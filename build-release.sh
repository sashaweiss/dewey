#!/bin/bash
#
# build-release.sh
# dewey
#
# Builds dewey in Release, signs it for Developer ID distribution,
# notarizes it, and leaves a stapled dewey.app and a zip of it in dist/.
# Nothing is installed anywhere — copy the app where you want it.
#
# Notarizing needs credentials in the keychain. Run `xcrun notarytool
# store-credentials dewey` once and answer its prompts. Set
# NOTARY_PROFILE to use a profile stored under another name.
#
# Note that a Developer ID signature isn't the one Xcode's own builds
# carry, so the Screen Recording and Accessibility grants don't follow
# between them: an app installed from here asks for both again, and
# keeps them from then on.

set -euo pipefail

readonly PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT="$PROJECT_DIR/dewey.xcodeproj"
# Kept in the tree, but under its own subdirectory rather than in the
# Products and Intermediates.noindex that Xcode's own builds use: the
# archive action collects what it built through BUILD_DIR, and aiming
# SYMROOT at Xcode's location instead leaves it looking for a path that
# was never made.
readonly DERIVED_DATA="$PROJECT_DIR/DerivedData/Release"
readonly SCHEME="dewey"
readonly CONFIGURATION="Release"
readonly DIST_DIR="$PROJECT_DIR/dist"
readonly ARCHIVE_PATH="$DIST_DIR/dewey.xcarchive"
readonly APP_PATH="$DIST_DIR/dewey.app"
readonly NOTARY_PROFILE="${NOTARY_PROFILE:-dewey}"

log() {
    echo "==> $*"
}

fail() {
    echo "error: $*" >&2
    exit 1
}

# MARK: - Build

settings="$(
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$DERIVED_DATA" \
        -showBuildSettings 2>/dev/null
)"
team_id="$(sed -n 's/^ *DEVELOPMENT_TEAM = //p' <<<"$settings" | head -1)"
version="$(sed -n 's/^ *MARKETING_VERSION = //p' <<<"$settings" | head -1)"
[[ -n "$team_id" ]] || fail "the project has no DEVELOPMENT_TEAM to sign with"
[[ -n "$version" ]] || fail "the project has no MARKETING_VERSION to name the zip after"
readonly ZIP_PATH="$DIST_DIR/dewey-$version.zip"

# dist/ holds nothing but what the last run of this script put there.
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# The destination is the one xcodebuild picks anyway, but picking it
# here says so, rather than having it warn that it chose the first of
# four and leaving which one to the reader.
log "Archiving $SCHEME ($CONFIGURATION)"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    -quiet \
    archive

# Automatic signing picks the Developer ID identity from the export
# method, and -allowProvisioningUpdates fetches the profile that carries
# the enhanced-security entitlements.
export_options="$DIST_DIR/ExportOptions.plist"
cat > "$export_options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>$team_id</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>destination</key>
	<string>export</string>
</dict>
</plist>
PLIST

log "Exporting for Developer ID"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$export_options" \
    -exportPath "$DIST_DIR/export" \
    -allowProvisioningUpdates \
    -quiet

[[ -d "$DIST_DIR/export/dewey.app" ]] || fail "the export produced no dewey.app"
mv "$DIST_DIR/export/dewey.app" "$APP_PATH"
rm -rf "$DIST_DIR/export" "$export_options"

# MARK: - Notarize

# The notary service takes an archive, not a bundle, and this zip is
# made again once the ticket is stapled so what ships carries it.
zip_app() {
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
}

zip_app

# A rejection reports only "Invalid" here; `notarytool log`, with the
# submission id printed above, says what was actually wrong.
log "Notarizing $(basename "$ZIP_PATH") — this takes a few minutes"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait \
    || fail "notarization failed; for the reason, run: xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE"

# Stapling validates the ticket against the bundle as it goes, so a
# staple that reports success is the last word on the app being
# notarized. Nothing further to check.
log "Stapling the ticket"
xcrun stapler staple "$APP_PATH"
zip_app

log "Done: $APP_PATH"
log "Done: $ZIP_PATH"
