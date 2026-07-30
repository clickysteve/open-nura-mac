# Troubleshooting

> **Hearing safety:** in bad Bluetooth states the device can emit a sudden loud
> tone. The Nuraphone disconnects when it isn't being worn, so keep it on your
> head but with the in-ear tips **out of your ears** while connecting or changing
> settings, and only seat the tips once things look stable. The app refuses to
> connect while the headphones are connected for audio, since that is the state
> most likely to misbehave — disconnect audio first (keep them paired).


## The app never finds my headphones / stuck on "Scanning"

On macOS the app uses **classic Bluetooth**, not BLE. Make sure the Nuraphone is
**paired** in Bluetooth settings. If you built an older BLE-only version, note
the Nuraphone does not advertise its control channel over BLE at all, so a BLE
scan will never see it even though other devices appear.

## Recovery stalls or "No known channel ... cid 1"

This is the most common issue and it has a reliable fix.

While the Nuraphone is **connected for audio**, macOS's SDP cache can hand back
the headset profile's RFCOMM channel (often channel 1) instead of the GAIA
control channel (a higher channel, e.g. 14). Opening the wrong channel fails.

Fix: in Bluetooth settings, **disconnect** the Nuraphone (but leave it
**paired**), then launch the app and hit Recover as the first action. The app
now also selects the GAIA channel deliberately and will warn in the log if the
device is still holding an audio connection, but paired-but-disconnected remains
the most reliable state.

If a connect attempt has already jammed the Bluetooth state, fully quit the app
(Cmd-Q) and relaunch; the first channel-open after launch is the clean one.

## "Couldn't reach Nura's servers"

Key recovery needs Nura's backend. If it is offline (the product is
discontinued) recovery cannot complete. If you already have your key, you can
enter it by hand in the Devices tab and skip recovery entirely.

## "Crypto: wrong key" when connecting

The stored key does not match the device. Re-run recovery, or re-enter the
correct 32-hex-character key. Keys are per-device; a key from another Nuraphone
will not work.

## Reading the log

The Device tab has a Logs section (Copy All to export). It shows each GAIA
command, the connection phase, and provisioning progress. It never logs the
device key, account tokens, or the session key. When reporting an issue, the log
lines around where it stalls are the useful part.
