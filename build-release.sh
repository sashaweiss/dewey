#!/bin/bash
#
# build-release.sh
# dewey
#
# Builds dewey in Release and installs it to /Applications, replacing
# whatever's there. Quit a running dewey first — this won't do it for
# you, and won't start one afterwards.
#
# It installs to a fixed path on purpose. dewey's Screen Recording and
# Accessibility grants are keyed to its bundle identifier and code
# signature, so an app that keeps both — as this does, signing with the
# project's own team every time — keeps its permissions across builds.
# Running a copy from somewhere else means granting them again.

set -euo pipefail

readonly PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT="$PROJECT_DIR/dewey.xcodeproj"
# -derivedDataPath insists on a -scheme, and this project has no shared
# one, so the build locations are set directly instead. These are the
# ones Xcode itself uses with its build location set relative to the
# workspace, so the two share incremental state rather than fighting.
readonly SYMROOT="$PROJECT_DIR/DerivedData/Products"
readonly OBJROOT="$PROJECT_DIR/DerivedData/Intermediates.noindex"
readonly TARGET="dewey"
readonly CONFIGURATION="Release"
readonly INSTALL_PATH="/Applications/dewey.app"

log() {
    echo "==> $*"
}

fail() {
    echo "error: $*" >&2
    exit 1
}

# Replacing the bundle out from under a running dewey would leave it up
# and running the old code.
fail_if_running() {
    if pgrep -x "$TARGET" > /dev/null; then
        fail "dewey is running; quit it first (or: pkill -x $TARGET)"
    fi
}

# MARK: - Build

# Up front, rather than after a build that's about to go to waste.
fail_if_running

log "Building $TARGET ($CONFIGURATION)"
xcodebuild \
    -project "$PROJECT" \
    -target "$TARGET" \
    -configuration "$CONFIGURATION" \
    -quiet \
    SYMROOT="$SYMROOT" \
    OBJROOT="$OBJROOT" \
    build

# Ask where the product landed rather than assuming a layout, since that
# has moved between Xcode versions.
settings="$(
    xcodebuild \
        -project "$PROJECT" \
        -target "$TARGET" \
        -configuration "$CONFIGURATION" \
        SYMROOT="$SYMROOT" \
        OBJROOT="$OBJROOT" \
        -showBuildSettings 2>/dev/null
)"
products_dir="$(sed -n 's/^ *BUILT_PRODUCTS_DIR = //p' <<<"$settings" | head -1)"
product_name="$(sed -n 's/^ *FULL_PRODUCT_NAME = //p' <<<"$settings" | head -1)"
built_app="$products_dir/$product_name"

[[ -n "$products_dir" && -n "$product_name" ]] \
    || fail "couldn't read the build settings to find the app"
[[ -d "$built_app" ]] || fail "no app at $built_app"

# MARK: - Install

# Belt and braces around the rm below: nothing but a dewey bundle in
# /Applications should ever be on the end of this variable.
[[ "$INSTALL_PATH" == /Applications/dewey.app ]] \
    || fail "refusing to touch $INSTALL_PATH"
[[ -w "$(dirname "$INSTALL_PATH")" ]] \
    || fail "$(dirname "$INSTALL_PATH") isn't writable"

# Again, in case one was launched while the build ran.
fail_if_running

log "Installing to $INSTALL_PATH"
if [[ -e "$INSTALL_PATH" ]]; then
    [[ -d "$INSTALL_PATH/Contents" ]] || fail "$INSTALL_PATH isn't an app bundle"
    rm -rf "$INSTALL_PATH"
fi
# ditto rather than cp, which doesn't carry a bundle's signature intact.
ditto "$built_app" "$INSTALL_PATH"

log "Done: $INSTALL_PATH"
