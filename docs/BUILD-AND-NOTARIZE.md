# Building a notarised opennura for your own Mac

This produces a signed, notarised `opennura.app` that opens with no Gatekeeper
warning and keeps working across rebuilds (so macOS stops re-asking for Keychain
access every time, which happens with unsigned dev builds).

Everything here runs on your Mac. It can't be done in the cloud session: it
needs macOS, your Developer ID certificate, and your Apple credentials.

## What you need once

1. A paid Apple Developer account (99/year). The free tier can't create a
   Developer ID certificate or notarise.
2. A **Developer ID Application** certificate in your login keychain:
   Xcode > Settings > Accounts > (your Apple ID) > Manage Certificates >
   the "+" button > Developer ID Application.
3. Your **Team ID** (Apple Developer > Membership, a 10-character string).
4. An **app-specific password** for notarisation: appleid.apple.com >
   Sign-In and Security > App-Specific Passwords.

Then set the Team ID in two places:

- `scripts/ExportOptions.plist` -> `teamID`
- The Xcode target: select the project > target `opennura` > Signing &
  Capabilities > Team. (This sets `DEVELOPMENT_TEAM`, currently blank.)

And store your notary credentials once (the script reads them by name):

```sh
xcrun notarytool store-credentials opennura-notary \
  --apple-id "you@example.com" \
  --team-id  "YOURTEAMID" \
  --password "your-app-specific-password"
```

## The easy path (Xcode does it all)

1. Open `opennura.xcodeproj`.
2. Select the `opennura` scheme, and set the run destination to "My Mac".
3. Product > Archive.
4. In the Organizer that opens: Distribute App > **Direct Distribution**.
   Xcode signs with your Developer ID, uploads for notarisation, waits, and
   staples the ticket for you.
5. When it finishes, click Export and save `opennura.app`. Drag it to
   /Applications.

Hardened Runtime is already enabled in the project (required for
notarisation), so there's nothing else to toggle.

## The scripted path (one command)

After the one-time setup above:

```sh
./scripts/notarize.sh
```

It archives Release, exports a Developer ID app, submits it to Apple's notary
service, staples the ticket, and verifies. The finished app is at
`build/export/opennura.app`.

## Notes

- Bundle identifier is `org.jamesyoung.opennura`. You don't need to register it
  anywhere for Developer ID / notarisation. If you'd rather it carry your own
  name, change `PRODUCT_BUNDLE_IDENTIFIER` in the target's build settings before
  archiving.
- The app is not sandboxed (it needs raw classic-Bluetooth access, which the
  sandbox doesn't allow). Notarisation does not require the sandbox, only the
  Hardened Runtime, which is on.
- If macOS ever prompts for Bluetooth permission after enabling Hardened
  Runtime and the app can't see the headphones, add a usage string: target >
  Info > add `Privacy - Bluetooth Always Usage Description` with a short
  sentence. It hasn't been needed so far, so it's left out.
