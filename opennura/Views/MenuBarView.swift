#if os(macOS)
import AppKit
import SwiftUI

/// Compact controls shown in the menu bar popover, for quick tweaks without
/// opening the main window.
struct MenuBarView: View {
    @ObservedObject var device: NuraDeviceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if device.phase.isReady {
                Divider()
                noiseRow
                soundRow
                immersionRow
                if hasProfiles { profileRow }
            } else {
                Divider()
                notConnected
            }

            Divider()
            HStack {
                if let battery = device.state.battery {
                    Label("\(battery.batteryPercentage)%", systemImage: battery.isCharging ? "bolt.fill" : "battery.100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "headphones")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.pink)
            VStack(alignment: .leading, spacing: 1) {
                Text("Nuraphone").font(.headline)
                Text(device.phase.label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if device.phase.isIdle {
                Button("Connect") { device.connect() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Button("Disconnect") { device.disconnect() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var notConnected: some View {
        Text("Connect with the nuraphone paired but its audio disconnected in macOS. Then you can resume audio and use these controls.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: Rows

    private var noiseRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Noise").font(.caption).foregroundStyle(.secondary)
            Picker("Noise", selection: Binding(
                get: { device.state.anc?.mode ?? .off },
                set: { device.setAncMode($0) }
            )) {
                ForEach(NuraAncMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var soundRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sound").font(.caption).foregroundStyle(.secondary)
            Picker("Sound", selection: Binding(
                get: { device.state.personalisationMode },
                set: { device.setSoundMode($0) }
            )) {
                ForEach(NuraPersonalisationMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var immersionRow: some View {
        HStack {
            Text("Immersion").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button {
                device.immersionStep(-1)
            } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
            Text(immersionLabel)
                .font(.callout.monospacedDigit())
                .frame(minWidth: 66)
                .multilineTextAlignment(.center)
            Button {
                device.immersionStep(1)
            } label: { Image(systemName: "plus.circle") }
                .buttonStyle(.borderless)
        }
    }

    private var profileRow: some View {
        HStack {
            Text("Profile").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button {
                device.cycleProfile(forward: false)
            } label: { Image(systemName: "chevron.left.circle") }
                .buttonStyle(.borderless)
            Text(device.displayProfileName(device.state.profileId ?? 0))
                .font(.callout)
                .lineLimit(1)
                .frame(minWidth: 90)
                .multilineTextAlignment(.center)
            Button {
                device.cycleProfile(forward: true)
            } label: { Image(systemName: "chevron.right.circle") }
                .buttonStyle(.borderless)
        }
    }

    // MARK: Helpers

    private var hasProfiles: Bool {
        [0, 1, 2].contains { device.isProfilePopulated($0) }
    }

    private var immersionLabel: String {
        let level = device.state.immersionLevel
        let sign = level > 0 ? "+" : ""
        return "\(sign)\(level)"
    }
}
#endif
