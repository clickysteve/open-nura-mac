#!/usr/bin/env bash
#
# Build, sign, notarise and staple opennura as a Developer ID app you can run
# on your own Mac (and hand to others) without Gatekeeper warnings.
#
# Run this ON YOUR MAC, from the repo root:  ./scripts/notarize.sh
#
# One-time setup (see docs/BUILD-AND-NOTARIZE.md for detail):
#   1. Paid Apple Developer account, with a "Developer ID Application"
#      certificate installed in your login keychain (Xcode > Settings >
#      Accounts > Manage Certificates > + Developer ID Application).
#   2. Set your Team ID in scripts/ExportOptions.plist and in DEVELOPMENT_TEAM
#      (Xcode target > Signing & Capabilities, or the project settings).
#   3. Store notary credentials once:
#        xcrun notarytool store-credentials opennura-notary \
#          --apple-id "you@example.com" \
#          --team-id  "YOURTEAMID" \
#          --password "app-specific-password"   # from appleid.apple.com
#
set -euo pipefail

PROJECT="opennura.xcodeproj"
SCHEME="opennura"
CONFIG="Release"
NOTARY_PROFILE="opennura-notary"     # must match the store-credentials name

BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/opennura.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/opennura.app"
ZIP="$BUILD_DIR/opennura.zip"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving ($CONFIG)…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  clean archive

echo "==> Exporting Developer ID app…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$EXPORT_DIR"

echo "==> Zipping for the notary service…"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Submitting to Apple's notary service (this can take a few minutes)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling the ticket…"
xcrun stapler staple "$APP"

echo "==> Verifying…"
xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP" || true
spctl --assess --type execute --verbose=2 "$APP" || true

echo ""
echo "Done. Your notarised app is at: $APP"
echo "Drag it to /Applications and it should open with no Gatekeeper warning."
