# How key recovery works

The goal is to obtain a Nuraphone's long-lived per-device key (`app_enc.key`),
the 16-byte AES key that encrypts all local control commands. The official app
gets it from Nura's backend during setup; this reproduces that exchange.

The flow is a Swift re-implementation of the sequence reverse-engineered in
[Nura-Windows](https://github.com/CallumCarmicheal/Nura-Windows) (Apache 2.0).

## The exchange

All backend calls use msgpack encoded in a `multipart/form-data` body with an
`Accept: application/msgpack` header. Auth is carried in rotating
`access-token` / `client` / `uid` headers. Base URL is
`https://api-p3.nuraphone.com/` with `api-p1` as a 404 fallback.

1. **`app/session`** — start an app session (spoofing the Android app context:
   version, device model, etc.). Yields an app-session id (`asid`).
2. **`auth/login_via_email`** then **`auth/login_via_email_verify`** — email a
   one-time code and verify it. Establishes the authenticated session.
3. **`auth/validate_token`** — resume/validate; yields the user-session id
   (`usid`).
4. **`end_to_end/session/start`** — begin provisioning for a specific serial and
   firmware. The response is a list of *actions*: a session id, a `finalEvent`
   naming the next endpoint, and *packets* to send to the headphones.
5. **Relay loop** — for the packets in the current response, send each to the
   headphones over Bluetooth (GAIA) and collect the device's replies, then POST
   them to the `finalEvent` endpoint (`session/start_1`, `_2`, …). Repeat until
   there is no further `finalEvent`.
6. Somewhere in these responses the backend releases **`app_enc.key`**. It is
   saved (base64) as the device key.

## Packet relay detail

Response actions of type `u` are server frames relayed verbatim; the device's
reply is packaged as `{e:false, a:false, m:false, b: vendor+rawCommandId+payload}`.
Type `r` actions are server-encrypted GAIA run packets; the command id is
derived from the action's `a`/`m` flags, and the reply is packaged as
`{e:true, a:<authenticated?>, m:<bulk?>, b: payload-without-status}`, where the
`a`/`m` classification uses fixed command-id sets.

Over classic Bluetooth these are full GAIA frames; over BLE the header is
stripped to `commandId + payload` because the characteristic handles framing.

## Gotchas learned the hard way

- **Binary must be msgpack `bin`, not an array.** A `[UInt8]` will silently
  bridge to `[Any?]` in Swift; if the encoder matches the array case first, the
  bytes go out as an array of integers and the backend rejects
  `session/start_1` with HTTP 500. Binary is matched before arrays in
  `MessagePackLite`.
- **Length fields are clamped.** Array/map counts in responses are clamped to
  the bytes remaining so a malformed/huge count cannot hang or OOM the parser.
- **The device must be reachable over classic Bluetooth**, which on the
  Nuraphone means paired-but-not-connected for best results (see Troubleshooting).
