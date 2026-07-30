#if os(macOS)
import Foundation
@preconcurrency import IOBluetooth

/// Classic Bluetooth (BR/EDR) RFCOMM/SPP transport for the nuraphone on macOS.
///
/// The nuraphone exposes its GAIA control channel over classic Bluetooth SPP
/// (the "CSR GAIA" service, UUID 0x1101), not Bluetooth LE, so on macOS this is
/// the transport that actually reaches the device while it's connected for
/// audio. Uses Apple's IOBluetooth framework.
@MainActor
final class ClassicBTTransport: NSObject, NuraTransport {
    weak var delegate: NuraTransportDelegate?
    var autoResetOnConnect = false

    private(set) var phase: ConnectionPhase = .idle {
        didSet {
            // Any move out of .connecting (handshaking, failed, idle) ends the
            // connect attempt, so the SDP/RFCOMM watchdog is no longer needed.
            if phase != .connecting {
                connectTimer?.invalidate()
                connectTimer = nil
            }
            delegate?.transportDidUpdatePhase(phase)
        }
    }

    private var inquiry: IOBluetoothDeviceInquiry?
    private var rfcommChannel: IOBluetoothRFCOMMChannel?
    private var frameBuffer = RFCOMMFrameBuffer()
    private var targetDevice: IOBluetoothDevice?

    private var pendingAck: UInt16 = 0
    private var pendingMinLen: Int = 0
    private var pendingCompletion: ((Result<[UInt8], Error>) -> Void)?
    private var pendingRawCompletion: ((Result<GaiaResponse, Error>) -> Void)?
    private var timeoutTimer: Timer?
    private var connectTimer: Timer?
    private var connectAttempt = 0
    private let maxConnectAttempts = 4

    private static let sppUUID = IOBluetoothSDPUUID(uuid16: 0x1101)

    private func freshNuraDevice() -> IOBluetoothDevice? {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return nil }
        let nura = paired.filter { ($0.name ?? "").lowercased().contains("nura") }
        return nura.first(where: { !($0.name ?? "").lowercased().contains("[le]") }) ?? nura.first
    }

    func scan() {
        guard phase.isIdle else { return }
        // Defensive: release any channel left over from a prior connection, so
        // we don't try to reopen an already-registered RFCOMM channel id.
        if let stale = rfcommChannel {
            stale.close()
            rfcommChannel = nil
        }
        connectAttempt = 0
        phase = .scanning
        delegate?.transportDidLog("Classic BT: Looking for paired Nura devices...")

        if let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            let nuraDevices = paired.filter { ($0.name ?? "").lowercased().contains("nura") }
            // Prefer the Classic BR/EDR entry. The LE entry ("... [LE]") has no
            // RFCOMM/SPP service record, so a Classic SDP query against it never
            // completes and the connection hangs.
            if let device = nuraDevices.first(where: { !($0.name ?? "").lowercased().contains("[le]") }) {
                delegate?.transportDidLog("Found paired device: \"\(device.name ?? "")\"")
                // Refuse to open the control channel while the headphones are
                // connected for audio. Observed behaviour (fw 606): the
                // nuraphone advertises GAIA on more than one RFCOMM channel, and
                // while audio holds the link macOS's SDP keeps surfacing a
                // channel that never finishes opening (e.g. 15), while the
                // channel that actually works (e.g. 1) only appears
                // intermittently on re-query. The result is an unreliable stall
                // loop. Connecting with audio disconnected reliably resolves the
                // working channel. Live control while audio plays is fine ONCE a
                // session is established; it's only the initial handshake that is
                // unreliable during audio, so we gate the connect, not the use.
                if device.isConnected() {
                    if autoResetOnConnect {
                        // Disconnect just this device's link (the equivalent of
                        // toggling it off in Bluetooth settings, but targeted so
                        // it doesn't touch the keyboard/mouse), then connect once
                        // it has settled into the paired-but-not-connected state
                        // where channel resolution is reliable.
                        delegate?.transportDidLog("Nuraphone is connected for audio; disconnecting that link first for a clean control connection...")
                        targetDevice = device
                        phase = .connecting
                        _ = device.closeConnection()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                            MainActor.assumeIsolated {
                                guard let self, self.targetDevice != nil, self.phase == .connecting else { return }
                                self.performSDPQueryAndConnect(device)
                            }
                        }
                        return
                    }
                    delegate?.transportDidLog("Refusing to connect: nuraphone is connected for audio. Turn on \"Disconnect audio automatically\", or disconnect it in macOS Bluetooth (keep it paired), then connect.")
                    phase = .failed("Disconnect the nuraphone's audio first (keep it paired), then connect")
                    return
                }
                targetDevice = device
                performSDPQueryAndConnect(device)
                return
            }
            if let le = nuraDevices.first {
                delegate?.transportDidLog("Only an LE entry is paired: \"\(le.name ?? "")\"")
                phase = .failed("Only an LE entry is paired — pair the nuraphone as an audio device for Classic Bluetooth")
                return
            }
        }

        delegate?.transportDidLog("No paired Nura device found, starting inquiry...")
        guard let inq = IOBluetoothDeviceInquiry(delegate: self) else {
            delegate?.transportDidLog("Failed to create device inquiry")
            phase = .failed("Inquiry failed")
            return
        }
        inq.inquiryLength = 15
        inquiry = inq
        inq.start()
    }

    func stopScan() {
        inquiry?.stop()
        inquiry = nil
    }

    func disconnect() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        failPending(NuraError.notReady)
        rfcommChannel?.close()
        rfcommChannel = nil
        targetDevice = nil
        inquiry?.stop()
        inquiry = nil
        phase = .idle
    }

    func sendFrame(
        _ frame: GaiaFrame,
        expectedAck: UInt16,
        minResponseLen: Int,
        completion: @escaping (Result<[UInt8], Error>) -> Void
    ) {
        guard let channel = rfcommChannel else {
            completion(.failure(NuraError.notReady))
            return
        }
        guard pendingCompletion == nil, pendingRawCompletion == nil else {
            completion(.failure(NuraError.busy))
            return
        }

        pendingAck = expectedAck
        pendingMinLen = minResponseLen
        pendingCompletion = completion

        if !writeFrame(frame, on: channel) {
            let cb = pendingCompletion
            pendingCompletion = nil
            pendingAck = 0
            cb?(.failure(NuraError.malformed("RFCOMM write failed")))
            return
        }
        startTimeout()
    }

    func sendRawFrameCapturingResponse(
        commandId: UInt16,
        payload: [UInt8],
        completion: @escaping (Result<GaiaResponse, Error>) -> Void
    ) {
        guard let channel = rfcommChannel else {
            completion(.failure(NuraError.notReady))
            return
        }
        guard pendingCompletion == nil, pendingRawCompletion == nil else {
            completion(.failure(NuraError.busy))
            return
        }

        pendingRawCompletion = completion
        pendingAck = 0
        pendingMinLen = 0

        if !writeFrame(GaiaFrame(commandId: commandId, payload: payload), on: channel) {
            pendingRawCompletion = nil
            completion(.failure(NuraError.malformed("RFCOMM write failed")))
            return
        }
        startTimeout()
    }

    // MARK: - Internal

    private func writeFrame(_ frame: GaiaFrame, on channel: IOBluetoothRFCOMMChannel) -> Bool {
        var bytes = [UInt8](frame.rfcommData)
        let result = channel.writeAsync(&bytes, length: UInt16(bytes.count), refcon: nil)
        if result != kIOReturnSuccess {
            delegate?.transportDidLog(String(format: "RFCOMM write failed: 0x%08x", result))
            return false
        }
        return true
    }

    private func failPending(_ error: Error) {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        pendingAck = 0
        if let cb = pendingCompletion {
            pendingCompletion = nil
            cb(.failure(error))
            return
        }
        if let cb = pendingRawCompletion {
            pendingRawCompletion = nil
            cb(.failure(error))
        }
    }

    // MARK: - Connect

    private func performSDPQueryAndConnect(_ device: IOBluetoothDevice) {
        phase = .connecting
        startConnectTimeout()

        // macOS's IOBluetooth must discover the RFCOMM channel through a live SDP
        // query before the channel can be opened — opening a cached channel
        // number directly fails with "No known channel cid N". Use the
        // *unfiltered* performSDPQuery; the uuids:-filtered variant never
        // delivers its completion callback. The channel is opened in
        // sdpQueryComplete, once the query has registered it with the coordinator.
        delegate?.transportDidLog("Performing SDP query...")
        let result = device.performSDPQuery(self)
        if result != kIOReturnSuccess {
            delegate?.transportDidLog(String(format: "SDP query failed to start: 0x%08x", result))
            phase = .failed("SDP query failed")
        }
    }

    /// Resolves the GAIA RFCOMM channel from the device's SDP records.
    ///
    /// We must NOT just take the first RFCOMM record or the plain SPP lookup:
    /// when the nuraphone is connected for audio, macOS's cached SDP can hand
    /// back the headset (HFP/HSP) channel (often channel 1) instead of the GAIA
    /// control channel (a higher channel, e.g. 14). Opening the headset channel
    /// fails with "No known channel cid 1". So we enumerate every record and
    /// pick the GAIA one deliberately.
    private func gaiaChannelID(for device: IOBluetoothDevice) -> BluetoothRFCOMMChannelID? {
        // Only ever return a channel we can positively identify as GAIA, never a
        // guess. The nuraphone advertises "CSR GAIA" (legitimately on RFCOMM
        // channel 1). Writing control frames to any other channel is unsafe, so
        // if we can't find the GAIA record we refuse rather than guess.
        for record in (device.services as? [IOBluetoothSDPServiceRecord]) ?? [] {
            var channel: BluetoothRFCOMMChannelID = 0
            guard record.getRFCOMMChannelID(&channel) == kIOReturnSuccess, channel != 0 else { continue }
            if (record.getServiceName() ?? "").lowercased().contains("gaia") {
                delegate?.transportDidLog("GAIA service on channel \(channel)")
                return channel
            }
        }
        // The SPP (0x1101) record is the GAIA service on the nuraphone.
        if let record = device.getServiceRecord(for: Self.sppUUID) {
            var channel: BluetoothRFCOMMChannelID = 0
            if record.getRFCOMMChannelID(&channel) == kIOReturnSuccess, channel != 0 {
                delegate?.transportDidLog("Using SPP/GAIA channel \(channel)")
                return channel
            }
        }
        delegate?.transportDidLog("No GAIA service record found — not opening any channel")
        return nil
    }

    private func openRFCOMMChannel(on device: IOBluetoothDevice) {
        guard let channelID = gaiaChannelID(for: device) else {
            delegate?.transportDidLog("No GAIA (CSR GAIA / SPP) service record on device")
            phase = .failed("GAIA service not found")
            return
        }
        delegate?.transportDidLog("Opening RFCOMM channel \(channelID) to \(device.name ?? "device")...")

        var channel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(
            &channel,
            withChannelID: channelID,
            delegate: self
        )

        if result != kIOReturnSuccess {
            delegate?.transportDidLog(String(format: "Failed to open RFCOMM channel: 0x%08x", result))
            phase = .failed("RFCOMM open failed")
            return
        }

        rfcommChannel = channel
        delegate?.transportDidLog("RFCOMM channel opening (async)...")
    }

    private func startConnectTimeout() {
        connectTimer?.invalidate()
        connectTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            // The timer fires on the main run loop, so we're already on the main
            // actor. assumeIsolated runs synchronously in that isolation, which
            // avoids the concurrent Task that tripped the captured-self warning.
            MainActor.assumeIsolated {
                guard let self, self.phase == .connecting else { return }

                // macOS's RFCOMM coordinator can leave channel id 1 half-open
                // after a prior connection, so the first open attempt stalls.
                // Tear down and retry with a fresh device handle a few times.
                self.rfcommChannel?.close()
                self.rfcommChannel = nil

                if self.connectAttempt < self.maxConnectAttempts, let device = self.freshNuraDevice() {
                    self.connectAttempt += 1
                    self.delegate?.transportDidLog("Channel open stalled, retrying (\(self.connectAttempt)/\(self.maxConnectAttempts))...")
                    self.targetDevice = device
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self, self.phase == .connecting else { return }
                            self.performSDPQueryAndConnect(device)
                        }
                    }
                } else {
                    let audioHeld = self.targetDevice?.isConnected() ?? false
                    self.delegate?.transportDidLog("Connection timed out (SDP/RFCOMM)")
                    self.targetDevice = nil
                    self.phase = .failed(audioHeld
                        ? "Timed out - disconnect the nuraphone's audio in macOS Bluetooth, then retry"
                        : "Connection timed out - try again")
                }
            }
        }
    }

    private func startTimeout() {
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.pendingCompletion != nil || self.pendingRawCompletion != nil else { return }
                self.delegate?.transportDidLog("Command timed out")
                self.failPending(NuraError.timeout)
            }
        }
    }

    private func processReceivedData() {
        while let frameBytes = frameBuffer.tryReadFrame() {
            do {
                let response = try GaiaResponse.fromRFCOMM(frameBytes)
                guard response.vendorId == gaiaVendor else {
                    delegate?.transportDidLog(String(format: "  Ignoring non-Nura vendor: 0x%04x", response.vendorId))
                    continue
                }

                if response.rawCommandId == cmdEventNotification {
                    delegate?.transportDidReceiveIndication(response)
                    continue
                }

                delegate?.transportDidLog(
                    String(
                        format: "<- GAIA cmd=0x%04x (%d bytes) payload=%@",
                        response.rawCommandId, response.payload.count, hexStr(Data(response.payload))
                    )
                )

                // Provisioning relay: hand back the next non-indication frame as-is.
                if pendingRawCompletion != nil {
                    timeoutTimer?.invalidate()
                    timeoutTimer = nil
                    let cb = pendingRawCompletion
                    pendingRawCompletion = nil
                    pendingAck = 0
                    cb?(.success(response))
                    continue
                }

                if response.rawCommandId == pendingAck {
                    if response.payload.count < pendingMinLen {
                        delegate?.transportDidLog(
                            String(
                                format: "  (ignoring: only %d byte(s), need >=%d)",
                                response.payload.count, pendingMinLen
                            )
                        )
                        continue
                    }
                    timeoutTimer?.invalidate()
                    timeoutTimer = nil
                    let cb = pendingCompletion
                    pendingCompletion = nil
                    pendingAck = 0
                    cb?(.success(response.payload))
                }
            } catch {
                delegate?.transportDidLog("Malformed RFCOMM frame: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - IOBluetoothDeviceAsyncCallbacks (SDP query completion)

extension ClassicBTTransport: IOBluetoothDeviceAsyncCallbacks {
    nonisolated func remoteNameRequestComplete(_ device: IOBluetoothDevice, status: IOReturn) {}

    nonisolated func connectionComplete(_ device: IOBluetoothDevice, status: IOReturn) {}

    nonisolated func sdpQueryComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if status == kIOReturnSuccess {
                self.delegate?.transportDidLog("SDP query complete")
            } else {
                self.delegate?.transportDidLog(String(format: "SDP query returned 0x%08x; attempting open anyway", status))
            }
            self.openRFCOMMChannel(on: device)
        }
    }
}

// MARK: - IOBluetoothDeviceInquiryDelegate

extension ClassicBTTransport: IOBluetoothDeviceInquiryDelegate {

    nonisolated func deviceInquiryDeviceFound(
        _ sender: IOBluetoothDeviceInquiry,
        device: IOBluetoothDevice
    ) {
        let name = device.name ?? ""
        guard name.lowercased().contains("nura") else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            sender.stop()
            self.inquiry = nil
            self.targetDevice = device
            self.delegate?.transportDidLog("Inquiry found: \"\(name)\"")
            self.performSDPQueryAndConnect(device)
        }
    }

    nonisolated func deviceInquiryComplete(
        _ sender: IOBluetoothDeviceInquiry,
        error: IOReturn,
        aborted: Bool
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.inquiry = nil
            if !aborted, case .scanning = self.phase {
                self.delegate?.transportDidLog("Inquiry complete, no Nura device found")
                self.phase = .failed("No device found")
            }
        }
    }
}

// MARK: - IOBluetoothRFCOMMChannelDelegate

extension ClassicBTTransport: IOBluetoothRFCOMMChannelDelegate {

    nonisolated func rfcommChannelOpenComplete(
        _ rfcommChannel: IOBluetoothRFCOMMChannel,
        status error: IOReturn
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if error == kIOReturnSuccess {
                self.delegate?.transportDidLog("RFCOMM channel opened successfully")
                self.phase = .handshaking
            } else {
                self.delegate?.transportDidLog(String(format: "RFCOMM open failed: 0x%08x", error))
                self.rfcommChannel = nil
                self.phase = .failed("RFCOMM open failed")
            }
        }
    }

    nonisolated func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel,
        data dataPointer: UnsafeMutableRawPointer,
        length dataLength: Int
    ) {
        let dataCopy = Data(bytes: dataPointer, count: dataLength)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.frameBuffer.append(dataCopy)
            self.processReceivedData()
        }
    }

    nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.transportDidLog("RFCOMM channel closed")
            self.rfcommChannel = nil
            self.targetDevice = nil
            self.failPending(NuraError.notReady)
            self.phase = .failed("Disconnected")
        }
    }

    nonisolated func rfcommChannelWriteComplete(
        _ rfcommChannel: IOBluetoothRFCOMMChannel,
        refcon: UnsafeMutableRawPointer?,
        status error: IOReturn
    ) {
        guard error != kIOReturnSuccess else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.transportDidLog(String(format: "RFCOMM write error: 0x%08x", error))
        }
    }
}
#endif
