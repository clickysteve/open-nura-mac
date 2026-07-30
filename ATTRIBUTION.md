# Attribution & provenance

This fork stands on two earlier projects. This file records who did what and
the licensing situation, so credit and obligations are clear.

## Upstreams

**OpenNura** — original macOS/iOS SwiftUI app
James Young (@jamesy0ung) — https://github.com/jamesy0ung/opennura
The app shell, the BLE transport, the GAIA protocol layer, the crypto
(AES-128 / GCM / session handshake), the device-state model, and the SwiftUI
control surface originate here. This fork restores and extends that work.

**Nura-Windows** — Windows SDK and reverse-engineering harness
Callum Carmicheal (@CallumCarmicheal) — https://github.com/CallumCarmicheal/Nura-Windows
Licensed under the Apache License 2.0.
The backend-assisted provisioning flow used to recover the per-device key was
worked out here first. The Swift implementation in this fork
(`opennura/Auth/*`) is a re-implementation derived from that project's C#
`NuraLib`: the `app/session` → `auth` → `end_to_end/session/start_N` sequence,
the GAIA relay packet framing, the authenticated/bulk command-id sets, the
Android app-context payload, and the msgpack-over-multipart transport.

## What this fork adds

- Classic Bluetooth (RFCOMM/SPP) transport for macOS via IOBluetooth,
  restored from OpenNura's own earlier history and hardened (GAIA channel
  selection, reconnect handling).
- A Swift port of the backend key-recovery flow, so the per-device key can be
  recovered on a Mac with no iOS or Windows device.
- A minimal msgpack implementation, session-response parsers, sign-in and
  "Recover Device Key" UI.
- Security hardening: Keychain storage for the device key and account tokens,
  constant-time GCM tag comparison, msgpack length-field clamping, restricted
  config-file permissions.
- A unit-test package for the pure-logic core (`swift test`).

Most of this fork's new code was written with the assistance of Claude.

## Licensing

- The project as a whole is licensed under the **GNU General Public License
  v3** (`LICENSE`), agreed with the original author.
- The provisioning code derived from **Nura-Windows** originates under the
  **Apache License 2.0**. Apache 2.0 is one-way compatible with GPLv3, so those
  portions are included here under GPLv3 while retaining Apache attribution
  (`NOTICE`, `LICENSE-APACHE`).
- GPLv3 was chosen over GPLv2 specifically because Apache 2.0 is **incompatible
  with GPLv2** but compatible with GPLv3, so GPLv3 is what lets the copyleft
  preference and the Apache-derived code coexist legally.
