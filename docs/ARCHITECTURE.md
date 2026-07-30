# Architecture

A map of the code, for contributors.

## Layers

```
SwiftUI views ─► NuraDeviceManager ─► NuraTransport ─► headphones (GAIA)
                        │
                        └─► NuraProvisioningManager ─► NuraApiClient ─► Nura backend
                        │
                 NuraConfigStore ─► config.json (metadata) + Keychain (secrets)
```

### Transport (`opennura/Transport/`)
`NuraTransport` is a protocol with two implementations selected at runtime:

- `ClassicBTTransport` (macOS) — classic Bluetooth RFCOMM/SPP via IOBluetooth.
  This is the path that reaches the Nuraphone, because it does not advertise its
  GAIA control channel over BLE. It performs an SDP query, selects the GAIA
  RFCOMM channel (see Troubleshooting for the channel-selection nuance), and
  frames full GAIA packets.
- `BLETransport` (iOS, fallback) — CoreBluetooth. iOS cannot open RFCOMM to
  non-MFi devices, so BLE is the only option there.

Both expose `sendFrame` (normal request/response, matched on the ACK command id)
and `sendRawFrameCapturingResponse` (used by provisioning, which returns
whatever frame the device replies with).

### Protocol (`opennura/Protocol/`)
`GaiaFrame` / `GaiaResponse` encode and decode GAIA v1 frames in both the BLE
form (vendor+command+payload, framing handled by the characteristic) and the
RFCOMM form (full SOF/length header). `GaiaConstants` holds command opcodes,
the vendor id, and small decoders. `NuraResponseParsers` and
`HeadsetIndication` decode device-state payloads.

### Crypto (`opennura/Crypto/`)
`AES128` (encrypt-only, used for GCM keystream), `GCM` (explicit-J0 AES-GCM with
a constant-time tag compare), and `NuraSession` (the per-connection encrypted
channel: random nonce, direction-separated counters). The control handshake
challenges the device with the device key; a wrong key fails the GMAC check.

### Devices (`opennura/Devices/`)
`NuraDeviceManager` owns the transport and drives the connection state machine:
GetDeviceInfo → (control) key handshake → startup reads, or (provision) run the
recovery relay. `NuraDeviceState` / `NuraDeviceModels` hold observable state.

### Provisioning (`opennura/Auth/`)
`NuraProvisioningManager` runs the backend key-recovery flow, using a
transport-agnostic `sendFrame` closure for the Bluetooth relay. `NuraApiClient`
speaks the msgpack-over-multipart HTTP protocol. `MessagePackLite` is a small
msgpack encoder/decoder. `NuraSessionParsing` extracts session ids, the next
endpoint, packets, and the recovered key from responses. See
[KEY-RECOVERY.md](KEY-RECOVERY.md).

### Storage (`opennura/Configuration/`)
`NuraConfig` is the model. `NuraConfigStore` keeps non-secret metadata in
`config.json` and moves secrets (device keys, account tokens) into the Keychain
via `NuraKeychain`, migrating any legacy plaintext on load.

## Connection state machine (control mode)

```
idle → scanning → connecting → handshaking → ready
                                    │
             GetDeviceInfo ─► look up key by serial ─► crypto handshake ─► startup reads
```

In provision mode the handshake step is replaced by the recovery relay, after
which the recovered key is saved and a normal handshake proceeds.

## Safety model

Because the app writes to headphone hardware, several layers guard against
putting the device into a state that could produce a sudden loud sound:

1. **No auto-connect.** The app never connects on its own; it only talks to the
   headphones when the user explicitly taps Connect or Recover.
2. **Refuse while audio-connected.** `ClassicBTTransport` will not open the
   control channel while the Nuraphone is connected for audio, the state where
   macOS can hand back the wrong RFCOMM channel. The device must be paired but
   not connected.
3. **Positive channel identification.** Only a channel positively identified as
   the GAIA service ("CSR GAIA" / SPP 0x1101) is opened; the code never guesses
   a channel.
4. **Device-info gate.** The first exchange must decode as a plausible GAIA
   device-info reply; if not, the connection is torn down immediately with no
   further frames sent (`abortForSafety`).
5. **Crypto handshake gate.** Encrypted commands are only sent after the device
   GMAC verifies, so control traffic never goes to a channel that isn't the
   real, correctly-keyed device. Any handshake failure aborts and disconnects.
6. **Startup is read-only.** On connect the app only *reads* state; it issues no
   setting changes on its own. All writes are user-initiated and gated on a
   ready connection.

The ultimate backstop, documented for users, is simply not to wear the
headphones while connecting.
