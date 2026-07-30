# Changelog

## Unreleased (macOS key-recovery fork)

Fork of jamesy0ung/opennura adding Mac-only key recovery and hardening.

### Added
- Classic Bluetooth (RFCOMM/SPP) transport for macOS via IOBluetooth, so the
  Nuraphone's GAIA control channel is reachable on a Mac (it is not exposed
  over BLE).
- Backend key recovery: sign in with a Nura account and recover the per-device
  key over the Nura backend + Bluetooth relay, ported to Swift from the
  Nura-Windows reference (Apache 2.0). New files under `opennura/Auth/`.
- Sign-in and "Recover Device Key" UI; reveal/copy device key for backup.
- Keychain storage for the device key and account tokens, with migration from
  any legacy plaintext `config.json`.
- Unit-test package for the pure-logic core (`swift test`).
- README, architecture / key-recovery / troubleshooting docs, attribution and
  license files.
- Card-based control UI: noise control (Off/ANC/Passthrough), sound mode,
  immersion (−2…+4), and profiles.
- Per-profile controls: profile switching re-reads that profile's immersion and
  ANC; profile renaming (app-side); empty profile slots shown as such.
- Touch-button remapping (single/double tap), curated to the Nuraphone's
  supported functions per the reference capability map.
- Hearing-profile "signature" view and a comparison view overlaying profiles
  (firmware > 510).
- Global hotkeys (macOS, Carbon) with a Shortcuts settings tab, and a menu bar
  app for quick control.
- Optional automatic audio-link disconnect on connect, so a clean handshake no
  longer needs a manual trip to Bluetooth settings.
- App icon; Developer ID notarisation script and guide
  (`scripts/`, `docs/BUILD-AND-NOTARIZE.md`).

### Changed
- GAIA RFCOMM channel selection now picks the GAIA channel deliberately rather
  than trusting the first/cached SDP record, and warns when the device is held
  by an audio connection.
- Backend/network errors surface a clear "servers may be offline" message.
- Status badge and provisioning screen polish; on-screen guidance reflects the
  paired-but-not-connected recovery procedure.

### Safety
- Connect from the paired-but-not-connected state (the audio-connected state can
  resolve the wrong Bluetooth channel). Either the app drops the audio link
  itself (default) or it refuses and asks you to, rather than pushing frames at
  a device streaming audio. The loud-tone incident was traced to speculative
  reads on connect, which were removed; the startup read set is the
  upstream-proven one.
- Only open an RFCOMM channel positively identified as the GAIA service, never a
  guessed channel.
- Hearing-safety warnings in the README, troubleshooting doc, and app UI.

### Security
- Constant-time GCM authentication-tag comparison.
- msgpack length fields clamped to the bytes remaining (parser DoS hardening).
- Correct msgpack binary encoding for relayed byte payloads.
- `config.json` written with owner-only (0600) permissions in a 0700 directory.
