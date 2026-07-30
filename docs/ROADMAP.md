# Improvement analysis / roadmap

An assessment of where the app could go next, grouped by area and rough effort.
Items marked (HW) need a physical Nuraphone to validate.

## Functionality (highest user value)

The GAIA command set is already defined in `GaiaConstants.swift`; several
opcodes are wired in the manager but have no UI, so these are mostly
surfacing-work rather than new protocol work.

- **ANC level control (HW).** `cmdGetAncLevel` / `cmdSetAncLevel` exist and
  `setAncLevel` is implemented, but there is no slider. Add one next to the ANC
  toggle.
- **Button configuration UI (HW).** `NuraButtonConfiguration` and
  `setButtonConfiguration` exist with no editor. Add a screen to remap
  tap/double-tap/hold.
- **Dial configuration UI (HW).** Same story via `NuraDialConfiguration` /
  `setDialConfiguration`.
- **Voice-prompt gain and deep-sleep timeout (HW).** Opcodes exist
  (`cmdSetVoicePromptGain`, `cmdGetDeepSleepTimeout`); expose read/write.
- **Auto battery refresh.** Battery is read once at connect. Poll on a timer or
  refresh from indications so it stays current.
- **Auto-reconnect.** Remember the last device and offer to reconnect on launch
  instead of requiring a manual Connect each time.
- **Pre-flight for recovery (HW).** Detect an active audio connection before
  recovery and show a prominent "disconnect audio first" banner with a retry
  button, rather than relying on the log hint.

## Reliability / correctness

- **Retry on transient backend 5xx.** Add a small bounded retry with backoff to
  `NuraApiClient` for 5xx / network blips during the multi-step recovery.
- **Unify on async/await in the transport.** The transports use
  completion-handler callbacks bridged to continuations. Converting the
  transport protocol to `async` would remove the Timer-based polling and the
  manual pending-callback bookkeeping, and clears the Swift 6 concurrency
  warnings. Larger refactor; do behind tests.
- **Structured connection state.** The `NuraDeviceManager` state machine is a
  chain of nested callbacks (startup reads). An explicit state enum + async
  sequence would be easier to extend and test.

## Performance

Data volumes here are tiny (small GAIA frames, infrequent), so nothing is a real
bottleneck today. The notes below are correctness/quality wins more than speed.

- **Consider CryptoKit for AES-GCM (HW).** `AES128` is a pure-Swift,
  allocation-heavy reference implementation and `GCM`/GHASH is a bit-at-a-time
  software loop. Apple's CryptoKit gives hardware-accelerated, constant-time
  AES-GCM. The session and handshake use an explicit-J0 / GMAC-only pattern, so
  a swap needs careful matching against the device and must be validated on
  hardware, but it would delete a lot of hand-rolled crypto.
- **Batch config writes during recovery.** Recovery calls `save()` after each
  backend step, each of which now touches the Keychain and rewrites the file.
  Writing once at the end (persisting the recovered key) would cut redundant
  I/O. Minor.

## UX / polish

- **First-run onboarding** explaining the paired-not-connected recovery flow.
- **Recovery shown as discrete steps** (session start → relay → key saved)
  rather than a single status string.
- **Accessibility**: labels on the custom immersion buttons, Dynamic Type
  checks, VoiceOver pass.
- **Menu-bar extra** for quick ANC / immersion toggles without opening the app.
- **Localization** of user-facing strings (currently English only).

## Testing / project

- **Expand the test package** with more msgpack edge cases and a GHASH/GCM
  known-answer test (RFC 5288 / NIST vectors) to lock the crypto down.
- **CI** running `swift test` on push.
- **Device-info decoder fuzzing** for the BLE/RFCOMM framing on random input.

## Explicitly out of scope (by decision)

- Support for other Nura devices (Buds / True). This fork targets the Nuraphone
  only.
