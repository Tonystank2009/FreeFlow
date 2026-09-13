#!/bin/bash
#
# FreeFlow release: build -> sign -> notarize -> staple -> DMG.
#
# Produces a DMG that opens on any Mac with no Gatekeeper warning.
#
# One-time setup:
#   1. Xcode installed and selected:
#        sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
#   2. A "Developer ID Application" certificate in your login keychain
#        (Xcode > Settings > Accounts > Manage Certificates > + )
#   3. A notarytool keychain profile:
#        xcrun notarytool store-credentials FreeFlowNotary \
#          --apple-id "you@example.com" \
#          --team-id "YOURTEAMID" \
#          --password "app-specific-password"
#      (app-specific password from appleid.apple.com, not your Apple ID password)
#
# Usage:
#   ./scripts/release.sh              # full signed + notarized release
#   ./scripts/release.sh --no-notarize  # local signed build, skip notarization

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="FreeFlow"
SCHEME="FreeFlow"
CONFIGURATION="Release"
NOTARY_PROFILE="${FREEFLOW_NOTARY_PROFILE:-FreeFlowNotary}"

BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_STAGE="$BUILD_DIR/dmg"
DIST_DIR="$PROJECT_DIR/dist"

NOTARIZE=1
[ "${1:-}" = "--no-notarize" ] && NOTARIZE=0

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
ylw()  { printf '\033[33m%s\033[0m\n' "$*"; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

die() { red "error: $*"; exit 1; }

# ---------------------------------------------------------------- preflight

step "Preflight"

xcodebuild -version >/dev/null 2>&1 || die \
  "xcodebuild needs full Xcode, not just Command Line Tools.
  Install Xcode, then: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"

# Refuse to ship a build whose commerce config is still a placeholder — this is
# the difference between a DMG that can take money and one that cannot.
# Commerce config only has to be real when the paywall is switched on.
PAYWALL=$(grep -E 'static let isPaywallEnabled' Sources/FreeFlow/Licensing/Brand.swift \
  | grep -c 'true' || true)

if [ "$PAYWALL" != "0" ]; then
  # Match real assignments only, so prose mentioning the token doesn't trip
  # this. supportEmail is intentionally optional and excluded.
  PLACEHOLDERS=$(grep -nE '= *"REPLACE_ME' Sources/FreeFlow/Licensing/Brand.swift \
    | grep -v "REPLACE_ME_SUPPORT_EMAIL" || true)
  if [ -n "$PLACEHOLDERS" ]; then
    red "Paywall is enabled but Brand.swift still contains placeholders:"
    echo "$PLACEHOLDERS" | sed 's/^/    /'
    die "Fill these in before cutting a release (see docs/SETUP.md)."
  fi
  grn "  paywall          : enabled"
else
  ylw "  paywall          : disabled (shipping free)"
fi

SIGN_ID=$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" \
  | head -1 \
  | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p')

[ -n "$SIGN_ID" ] || die \
  "No 'Developer ID Application' certificate found in your keychain.
  An Apple Developer account alone is not enough — the certificate must be issued
  and installed: Xcode > Settings > Accounts > Manage Certificates > + >
  Developer ID Application.
  Found instead:
$(security find-identity -v -p codesigning | sed 's/^/    /')"

TEAM_ID=$(echo "$SIGN_ID" | sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p')
[ -n "$TEAM_ID" ] || die "Could not parse a Team ID out of: $SIGN_ID"

grn "  signing identity : $SIGN_ID"
grn "  team id          : $TEAM_ID"

if [ "$NOTARIZE" = "1" ]; then
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || die \
    "No notarytool profile named '$NOTARY_PROFILE'.
  Create one with:
    xcrun notarytool store-credentials $NOTARY_PROFILE \\
      --apple-id \"you@example.com\" --team-id \"$TEAM_ID\" \\
      --password \"app-specific-password\"
  Or run with --no-notarize to skip."
  grn "  notary profile   : $NOTARY_PROFILE"
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
BUILD_NUM=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist)
grn "  version          : $VERSION ($BUILD_NUM)"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# ---------------------------------------------------------------- archive

step "Building $CONFIGURATION archive"

xcodebuild archive \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_ID" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  FREEFLOW_TEAM_ID="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  | xcbeautify 2>/dev/null || xcodebuild archive \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_ID" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  FREEFLOW_TEAM_ID="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime"

[ -d "$ARCHIVE_PATH" ] || die "Archive was not produced."

# ---------------------------------------------------------------- export

step "Exporting Developer ID app"

cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -exportPath "$EXPORT_DIR"

APP_PATH="$EXPORT_DIR/$APP_NAME.app"
[ -d "$APP_PATH" ] || die "Export did not produce $APP_PATH"

# ---------------------------------------------------------------- verify sig

step "Verifying signature"

codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1 | sed 's/^/    /'

codesign -dv --verbose=4 "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier|flags" | sed 's/^/    /'

# Hardened runtime is mandatory for notarization.
codesign -d --verbose=4 "$APP_PATH" 2>&1 | grep -q "flags=.*runtime" \
  || die "Hardened runtime is not enabled on the exported app."
grn "  hardened runtime : enabled"

# ---------------------------------------------------------------- notarize app

if [ "$NOTARIZE" = "1" ]; then
  step "Notarizing app"

  APP_ZIP="$BUILD_DIR/$APP_NAME.zip"
  ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"

  xcrun notarytool submit "$APP_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    || die "Notarization failed. Inspect with:
    xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"

  xcrun stapler staple "$APP_PATH" || die "Stapling the app failed."
  grn "  app stapled"
fi

# ---------------------------------------------------------------- dmg

step "Building DMG"

rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
cp -R "$APP_PATH" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

# GPL-3 §6: the binary must be accompanied by, or offer, the source. Shipping
# the offer inside the DMG makes it impossible for a buyer to miss.
cp SOURCE-OFFER.txt "$DMG_STAGE/Source Code and Licence.txt" 2>/dev/null || true

DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH" >/dev/null

grn "  $DMG_PATH"

step "Signing DMG"
codesign --force --sign "$SIGN_ID" --timestamp "$DMG_PATH"

# ---------------------------------------------------------------- notarize dmg

if [ "$NOTARIZE" = "1" ]; then
  step "Notarizing DMG"

  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    || die "DMG notarization failed."

  xcrun stapler staple "$DMG_PATH" || die "Stapling the DMG failed."

  step "Final Gatekeeper check"
  spctl -a -vvv -t install "$DMG_PATH" 2>&1 | sed 's/^/    /'
  xcrun stapler validate "$DMG_PATH" 2>&1 | sed 's/^/    /'
fi

# ---------------------------------------------------------------- done

SIZE=$(du -h "$DMG_PATH" | cut -f1)
step "Done"
grn "  $DMG_PATH  ($SIZE)"
if [ "$NOTARIZE" = "1" ]; then
  grn "  Signed, notarized and stapled — opens with no Gatekeeper warning."
else
  ylw "  Signed but NOT notarized — macOS will warn on other Macs."
fi
echo
echo "Next:"
echo "  1. Test on a second Mac (or: xattr -w com.apple.quarantine ... to simulate)"
echo "  2. Publish the matching source tag — GPL-3 requires it:"
echo "       git tag v$VERSION && git push origin v$VERSION"
echo "  3. Attach the DMG to the GitHub release so the in-app updater finds it."
