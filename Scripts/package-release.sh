#!/usr/bin/env bash

set -euo pipefail

readonly RELEASE_VERSION="${1:-}"
readonly PRERELEASE="${2:-}"
readonly BUILD_NUMBER="${3:-}"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly APP_NAME="StandClear"
readonly APP_DIR="$REPO_ROOT/dist/$APP_NAME.app"
readonly EXECUTABLE="$APP_DIR/Contents/MacOS/$APP_NAME"
readonly INFO_PLIST="$APP_DIR/Contents/Info.plist"
readonly RESOURCE_BUNDLE="$APP_DIR/Contents/Resources/StandClear_StandClearCore.bundle"
readonly APP_ICON="$APP_DIR/Contents/Resources/AppIcon.icns"
readonly SOURCE_ICON="$REPO_ROOT/Support/AppIcon.icns"
readonly ENTITLEMENTS="$REPO_ROOT/Support/StandClear.entitlements"
readonly OUTPUT_DIR="$REPO_ROOT/dist/release"
# The installer window and the artwork drawn behind it are one measurement: the
# background is positioned for icons at these exact coordinates, so the window size
# and the image size have to move together or the composition slides out of register.
#
# Finder counts its title bar inside these bounds but draws the background below it, so
# roughly 31pt of the image never appears, and a Mac set to always-on scroll bars loses
# another ~16pt at the bottom. The window is sized taller than the composition needs and
# the artwork keeps its lower band empty, which is why the height is 420 for a layout
# that reads as 560×373.
readonly DMG_WINDOW_WIDTH=560
readonly DMG_WINDOW_HEIGHT=420
readonly DMG_ICON_CENTER_Y=180
readonly DMG_BACKGROUND_1X="$REPO_ROOT/Support/dmg/background.png"
readonly DMG_BACKGROUND_2X="$REPO_ROOT/Support/dmg/background@2x.png"
readonly CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
readonly NOTARY_PROFILE="${NOTARY_PROFILE:-}"
readonly SENTRY_AUTH_TOKEN="${SENTRY_AUTH_TOKEN:-}"
readonly SENTRY_ORG="${SENTRY_ORG:-zeroeval}"
readonly SENTRY_PROJECT="${SENTRY_PROJECT:-apple-ios}"

if [[ -n "$PRERELEASE" ]]; then
    readonly ARTIFACT_LABEL="$RELEASE_VERSION-$PRERELEASE"
else
    readonly ARTIFACT_LABEL="$RELEASE_VERSION"
fi

readonly ARTIFACT_BASENAME="$APP_NAME-$ARTIFACT_LABEL-macos-arm64"
readonly STAGING_DIR="$OUTPUT_DIR/$ARTIFACT_BASENAME"
readonly DMG_PATH="$OUTPUT_DIR/$ARTIFACT_BASENAME.dmg"
readonly CHECKSUM_PATH="$DMG_PATH.sha256"

VERIFY_DIR=""
NOTARY_ZIP=""
DMG_MOUNT=""
BACKGROUND_DIR=""
BACKGROUND_TIFF=""
PACKAGE_SUCCEEDED=0
TEAM_ID=""

die() {
    echo "error: $*" >&2
    exit 1
}

readonly LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# Short-lived copies of the app register with LaunchServices under the real bundle ID.
# Left behind, those dead records accumulate and confuse services that resolve the
# bundle by identifier, so drop each copy before deleting it.
unregister_bundle() {
    local path="$1"
    [[ -d "$path" ]] || return 0
    "$LSREGISTER" -u "$path" >/dev/null 2>&1 || true
}

cleanup() {
    if [[ -n "$DMG_MOUNT" ]]; then
        unregister_bundle "$DMG_MOUNT/$APP_NAME.app"
        /usr/bin/hdiutil detach "$DMG_MOUNT" -quiet 2>/dev/null || true
        DMG_MOUNT=""
    fi
    if [[ -n "$VERIFY_DIR" && -d "$VERIFY_DIR" ]]; then
        unregister_bundle "$VERIFY_DIR/$APP_NAME.app"
        rm -rf "$VERIFY_DIR"
    fi
    if [[ -n "$NOTARY_ZIP" && -f "$NOTARY_ZIP" ]]; then
        rm -f "$NOTARY_ZIP"
    fi
    if [[ -n "$BACKGROUND_DIR" && -d "$BACKGROUND_DIR" ]]; then
        rm -rf "$BACKGROUND_DIR"
    fi
    if [[ -d "$STAGING_DIR" ]]; then
        unregister_bundle "$STAGING_DIR/$APP_NAME.app"
        rm -rf "$STAGING_DIR"
    fi
    if [[ "$PACKAGE_SUCCEEDED" -ne 1 ]]; then
        rm -f "$DMG_PATH" "$CHECKSUM_PATH" "$OUTPUT_DIR/appcast.xml"
    fi
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

parse_team_id() {
    local identity="$1"
    if [[ "$identity" =~ \(([A-Z0-9]{10})\)$ ]]; then
        TEAM_ID="${BASH_REMATCH[1]}"
    else
        die "CODESIGN_IDENTITY must end with a Team ID in parentheses, e.g. 'Developer ID Application: Name (AB12CD34EF)'"
    fi
}

verify_app() {
    local app_path="$1"
    local expect_notarized="${2:-0}"
    local executable_path="$app_path/Contents/MacOS/$APP_NAME"
    local plist_path="$app_path/Contents/Info.plist"
    local resource_bundle_path="$app_path/Contents/Resources/StandClear_StandClearCore.bundle"
    local icon_path="$app_path/Contents/Resources/AppIcon.icns"
    local sparkle_framework="$app_path/Contents/Frameworks/Sparkle.framework"
    local architectures
    local location_description
    local signature_details
    local gatekeeper_details
    local entitlements
    local otool_rpaths
    local sparkle_signature

    [[ -x "$executable_path" ]] || die "missing executable at $executable_path"
    [[ -f "$plist_path" ]] || die "missing Info.plist at $plist_path"
    [[ -d "$resource_bundle_path" ]] || die "missing resource bundle at $resource_bundle_path"
    [[ -f "$icon_path" ]] || die "missing app icon at $icon_path"
    [[ -d "$sparkle_framework" ]] || die "missing Sparkle.framework at $sparkle_framework"
    [[ ! -e "$sparkle_framework/XPCServices" ]] || die "Sparkle.framework still contains XPCServices; remove them for non-sandboxed builds"
    [[ ! -e "$sparkle_framework/Versions/B/XPCServices" ]] || die "Sparkle.framework Versions/B still contains XPCServices"

    architectures="$(/usr/bin/lipo -archs "$executable_path")"
    [[ "$architectures" == "arm64" ]] || die "expected arm64-only executable, found: $architectures"

    [[ "$(plist_value "$plist_path" CFBundleShortVersionString)" == "$RELEASE_VERSION" ]] || die "unexpected CFBundleShortVersionString"
    [[ "$(plist_value "$plist_path" CFBundleVersion)" == "$BUILD_NUMBER" ]] || die "unexpected CFBundleVersion"
    [[ "$(plist_value "$plist_path" CFBundleIdentifier)" == "com.sebastiancrossa.standclear" ]] || die "unexpected bundle identifier"
    [[ "$(plist_value "$plist_path" LSMinimumSystemVersion)" == "14.0" ]] || die "unexpected minimum macOS version"
    [[ "$(plist_value "$plist_path" LSUIElement)" == "true" ]] || die "app must remain menu-bar-only"
    [[ "$(plist_value "$plist_path" CFBundleIconFile)" == "AppIcon" ]] || die "unexpected app icon metadata"
    [[ "$(plist_value "$plist_path" SUFeedURL)" == "https://github.com/sebastiancrossa/stand-clear/releases/latest/download/appcast.xml" ]] \
        || die "unexpected SUFeedURL"
    [[ -n "$(plist_value "$plist_path" SUPublicEDKey)" ]] || die "missing SUPublicEDKey"
    [[ "$(plist_value "$plist_path" SUEnableAutomaticChecks)" == "true" ]] || die "SUEnableAutomaticChecks must be true"
    [[ "$(plist_value "$plist_path" SUAllowsAutomaticUpdates)" == "false" ]] || die "SUAllowsAutomaticUpdates must be false"
    [[ "$(plist_value "$plist_path" SUVerifyUpdateBeforeExtraction)" == "true" ]] || die "SUVerifyUpdateBeforeExtraction must be true"

    location_description="$(plist_value "$plist_path" NSLocationWhenInUseUsageDescription)"
    [[ -n "$location_description" ]] || die "missing location usage description"

    /usr/bin/codesign --verify --strict --verbose=2 "$app_path"
    signature_details="$(/usr/bin/codesign -dv --verbose=4 "$app_path" 2>&1)"
    /usr/bin/grep -q 'Authority=Developer ID Application' <<< "$signature_details" || die "app is not signed with Developer ID Application"
    /usr/bin/grep -q "^TeamIdentifier=$TEAM_ID$" <<< "$signature_details" || die "unexpected TeamIdentifier (expected $TEAM_ID)"
    /usr/bin/grep -q 'flags=.*runtime' <<< "$signature_details" || die "hardened runtime flag missing from signature"
    /usr/bin/grep -q '^Timestamp=' <<< "$signature_details" || die "secure timestamp missing from signature"

    sparkle_signature="$(/usr/bin/codesign -dv --verbose=4 "$sparkle_framework" 2>&1)"
    /usr/bin/grep -q "^TeamIdentifier=$TEAM_ID$" <<< "$sparkle_signature" || die "Sparkle.framework TeamIdentifier mismatch (expected $TEAM_ID)"
    /usr/bin/grep -q 'flags=.*runtime' <<< "$sparkle_signature" || die "Sparkle.framework missing hardened runtime"

    # Without this entitlement the hardened runtime blocks Core Location silently:
    # no authorization prompt is shown and the status stays notDetermined forever.
    entitlements="$(/usr/bin/codesign -d --entitlements - --xml "$app_path" 2>/dev/null || true)"
    /usr/bin/grep -q 'com.apple.security.personal-information.location' <<< "$entitlements" \
        || die "signature is missing com.apple.security.personal-information.location"

    otool_rpaths="$(/usr/bin/otool -l "$executable_path")"
    /usr/bin/grep -q '@executable_path/../Frameworks' <<< "$otool_rpaths" \
        || die "executable is missing @executable_path/../Frameworks rpath"

    if [[ "$expect_notarized" == "1" ]]; then
        /usr/bin/xcrun stapler validate "$app_path" || die "stapler validate failed for $app_path"
        gatekeeper_details="$(/usr/sbin/spctl --assess --type execute -vv "$app_path" 2>&1)" || die "Gatekeeper rejected $app_path: $gatekeeper_details"
        /usr/bin/grep -q 'source=Notarized Developer ID' <<< "$gatekeeper_details" || die "expected Notarized Developer ID assessment, got: $gatekeeper_details"
        echo "Verified notarized Developer ID signature for $app_path"
    else
        echo "Verified Developer ID signature for $app_path"
    fi
}

verify_appcast() {
    local appcast_path="$1"
    local dmg_path="$2"
    local ed_signature
    local length
    local actual_length
    local enclosure_url

    [[ -f "$appcast_path" ]] || die "missing appcast at $appcast_path"
    ed_signature="$(/usr/bin/sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$appcast_path" | /usr/bin/head -n 1)"
    length="$(/usr/bin/sed -n 's/.*length="\([0-9]*\)".*/\1/p' "$appcast_path" | /usr/bin/head -n 1)"
    enclosure_url="$(/usr/bin/sed -n 's/.*url="\([^"]*\)".*/\1/p' "$appcast_path" | /usr/bin/head -n 1)"
    [[ -n "$ed_signature" ]] || die "appcast missing sparkle:edSignature"
    [[ -n "$length" ]] || die "appcast missing length"
    [[ -n "$enclosure_url" ]] || die "appcast missing enclosure url"
    /usr/bin/grep -q "/releases/download/" <<< "$enclosure_url" \
        || die "appcast enclosure must point at a versioned release asset, not latest/download"
    actual_length="$(/usr/bin/stat -f%z "$dmg_path")"
    [[ "$length" == "$actual_length" ]] || die "appcast length ($length) does not match DMG size ($actual_length)"

    local sparkle_bin="$REPO_ROOT/.build/artifacts/sparkle/Sparkle/bin"
    local sign_update="$sparkle_bin/sign_update"
    [[ -x "$sign_update" ]] || die "sign_update not found at $sign_update"
    "$sign_update" --account "${SPARKLE_ACCOUNT:-standclear}" --verify "$dmg_path" "$ed_signature" \
        || die "appcast EdDSA signature does not verify against $dmg_path"
    echo "Verified appcast signature and length for $appcast_path"
}

notarize_and_staple_app() {
    NOTARY_ZIP="$(mktemp "${TMPDIR:-/tmp}/standclear-notary.XXXXXX.zip")"
    echo "Creating notarization zip for app bundle"
    /usr/bin/ditto -c -k --keepParent "$APP_DIR" "$NOTARY_ZIP"

    echo "Submitting app for notarization (profile: $NOTARY_PROFILE)"
    /usr/bin/xcrun notarytool submit "$NOTARY_ZIP" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    rm -f "$NOTARY_ZIP"
    NOTARY_ZIP=""

    echo "Stapling notarization ticket to app"
    /usr/bin/xcrun stapler staple "$APP_DIR"
    /usr/bin/xcrun stapler validate "$APP_DIR" || die "stapler validate failed after stapling app"
}

image_dimensions() {
    local path="$1"
    /usr/bin/sips -g pixelWidth -g pixelHeight "$path" 2>/dev/null \
        | /usr/bin/awk '/pixelWidth/ {w=$2} /pixelHeight/ {h=$2} END {print w "x" h}'
}

# Finder picks the matching representation out of a multi-resolution TIFF, so the
# installer window stays crisp on Retina instead of scaling the 1x art up. The pair of
# PNGs is what gets designed and reviewed; the TIFF only exists inside the DMG.
build_background() {
    local expected_1x="${DMG_WINDOW_WIDTH}x${DMG_WINDOW_HEIGHT}"
    local expected_2x="$((DMG_WINDOW_WIDTH * 2))x$((DMG_WINDOW_HEIGHT * 2))"
    local actual_1x
    local actual_2x

    actual_1x="$(image_dimensions "$DMG_BACKGROUND_1X")"
    actual_2x="$(image_dimensions "$DMG_BACKGROUND_2X")"
    [[ "$actual_1x" == "$expected_1x" ]] || die "DMG background must be $expected_1x, found $actual_1x in $DMG_BACKGROUND_1X"
    [[ "$actual_2x" == "$expected_2x" ]] || die "DMG background @2x must be $expected_2x, found $actual_2x in $DMG_BACKGROUND_2X"

    BACKGROUND_DIR="$(mktemp -d "${TMPDIR:-/tmp}/standclear-dmg-background.XXXXXX")"
    BACKGROUND_TIFF="$BACKGROUND_DIR/background.tiff"
    /usr/bin/tiffutil -cathidpicheck "$DMG_BACKGROUND_1X" "$DMG_BACKGROUND_2X" -out "$BACKGROUND_TIFF" >/dev/null \
        || die "tiffutil failed to combine the DMG background images"
    [[ -f "$BACKGROUND_TIFF" ]] || die "tiffutil did not produce $BACKGROUND_TIFF"
}

build_dmg() {
    command -v create-dmg >/dev/null 2>&1 || die "create-dmg not found; install with: brew install create-dmg"

    build_background

    rm -rf "$STAGING_DIR"
    mkdir -p "$OUTPUT_DIR" "$STAGING_DIR"
    /bin/cp -R "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"

    echo "Building notarized DMG at $DMG_PATH"
    create-dmg --overwrite \
        --volname "Stand Clear" \
        --volicon "$SOURCE_ICON" \
        --background "$BACKGROUND_TIFF" \
        --window-size "$DMG_WINDOW_WIDTH" "$DMG_WINDOW_HEIGHT" \
        --icon-size 128 \
        --icon "$APP_NAME.app" 150 "$DMG_ICON_CENTER_Y" \
        --hide-extension "$APP_NAME.app" \
        --app-drop-link 410 "$DMG_ICON_CENTER_Y" \
        --codesign "$CODESIGN_IDENTITY" \
        --notarize "$NOTARY_PROFILE" \
        "$DMG_PATH" \
        "$STAGING_DIR"

    [[ -f "$DMG_PATH" ]] || die "create-dmg did not produce $DMG_PATH"
}

verify_dmg() {
    local mounted_app
    local gatekeeper_details
    local attach_output

    echo "Validating stapled DMG"
    /usr/bin/xcrun stapler validate "$DMG_PATH" || die "stapler validate failed for DMG"

    gatekeeper_details="$(/usr/sbin/spctl --assess --type open --context context:primary-signature -vv "$DMG_PATH" 2>&1)" || die "Gatekeeper rejected DMG: $gatekeeper_details"
    echo "$gatekeeper_details"

    VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/standclear-release.XXXXXX")"
    attach_output="$(/usr/bin/hdiutil attach -nobrowse -readonly -mountroot "$VERIFY_DIR" "$DMG_PATH")"
    # With -mountroot, the volume appears as a subdirectory of VERIFY_DIR.
    DMG_MOUNT="$(/usr/bin/find "$VERIFY_DIR" -mindepth 1 -maxdepth 1 -type d | /usr/bin/head -n 1)"
    if [[ -z "$DMG_MOUNT" || ! -d "$DMG_MOUNT" ]]; then
        DMG_MOUNT="$(/usr/bin/awk '/[[:space:]]\// {print $NF; exit}' <<< "$attach_output")"
    fi
    [[ -n "$DMG_MOUNT" && -d "$DMG_MOUNT" ]] || die "failed to locate mounted DMG volume (hdiutil: $attach_output)"

    mounted_app="$DMG_MOUNT/$APP_NAME.app"
    [[ -d "$mounted_app" ]] || die "DMG is missing $APP_NAME.app"
    # A background that failed to copy leaves a plain white window rather than an error,
    # so the only way to notice is to look for it on the mounted volume.
    [[ -f "$DMG_MOUNT/.background/background.tiff" ]] || die "DMG is missing its window background"

    /bin/cp -R "$mounted_app" "$VERIFY_DIR/$APP_NAME.app"
    /usr/bin/hdiutil detach "$DMG_MOUNT" -quiet
    DMG_MOUNT=""

    verify_app "$VERIFY_DIR/$APP_NAME.app" 1
}

[[ -n "$CODESIGN_IDENTITY" ]] || die "CODESIGN_IDENTITY is required (example: 'Developer ID Application: Sebastian Crossa (AB12CD34EF)')"
[[ "$CODESIGN_IDENTITY" != "-" ]] || die "CODESIGN_IDENTITY must be a Developer ID Application identity, not ad-hoc (-)"
[[ -n "$NOTARY_PROFILE" ]] || die "NOTARY_PROFILE is required (example: standclear-notary). Store credentials with: xcrun notarytool store-credentials"
command -v sentry-cli >/dev/null 2>&1 || die "sentry-cli not found; install with: brew install getsentry/tools/sentry-cli"
# Accept either an exported token or one stored by `sentry-cli login` (~/.sentryclirc).
sentry-cli info >/dev/null 2>&1 \
    || die "sentry-cli is not authenticated; run: sentry-cli login (or export SENTRY_AUTH_TOKEN)"

parse_team_id "$CODESIGN_IDENTITY"

[[ -n "$RELEASE_VERSION" ]] || die "RELEASE_VERSION is required (example: 0.1.0)"
[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "RELEASE_VERSION must contain three numeric components (example: 0.1.0)"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || die "BUILD_NUMBER must be a positive integer"
[[ ${#BUILD_NUMBER} -le 4 ]] || die "BUILD_NUMBER must not exceed four digits"

if [[ -n "$PRERELEASE" ]]; then
    [[ "$PRERELEASE" =~ ^[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*$ ]] || die "PRERELEASE must use dot-separated alphanumeric or hyphenated identifiers"
fi

IFS='.' read -r release_major release_minor release_patch <<< "$RELEASE_VERSION"
for component in "$release_major" "$release_minor" "$release_patch"; do
    if [[ ${#component} -gt 1 && "$component" == 0* ]]; then
        die "RELEASE_VERSION components must not contain leading zeroes"
    fi
done

if [[ -n "$PRERELEASE" ]]; then
    IFS='.' read -r -a prerelease_identifiers <<< "$PRERELEASE"
    for identifier in "${prerelease_identifiers[@]}"; do
        if [[ "$identifier" =~ ^[0-9]+$ && ${#identifier} -gt 1 && "$identifier" == 0* ]]; then
            die "numeric PRERELEASE identifiers must not contain leading zeroes"
        fi
    done
fi

[[ -f "$SOURCE_ICON" ]] || die "missing source app icon at Support/AppIcon.icns"
[[ -f "$ENTITLEMENTS" ]] || die "missing entitlements at Support/StandClear.entitlements"
[[ -f "$DMG_BACKGROUND_1X" ]] || die "missing DMG background at Support/dmg/background.png"
[[ -f "$DMG_BACKGROUND_2X" ]] || die "missing DMG background at Support/dmg/background@2x.png"
[[ "$STAGING_DIR" == "$OUTPUT_DIR/"* ]] || die "refusing unsafe staging path"
[[ ! -e "$DMG_PATH" && ! -e "$CHECKSUM_PATH" ]] || die "release artifact already exists; use a new version or PRERELEASE and increment BUILD_NUMBER"

trap cleanup EXIT

cd "$REPO_ROOT"

echo "Running Swift tests"
/usr/bin/make test

echo "Building app bundle with Developer ID signing"
/usr/bin/make app CODESIGN_IDENTITY="$CODESIGN_IDENTITY"

[[ -x "$EXECUTABLE" ]] || die "app build did not produce $EXECUTABLE"
[[ -f "$INFO_PLIST" ]] || die "app build did not produce $INFO_PLIST"
[[ -d "$RESOURCE_BUNDLE" ]] || die "app build did not produce $RESOURCE_BUNDLE"
[[ -f "$APP_ICON" ]] || die "app build did not produce $APP_ICON"

# Version stamp invalidates the prior signature; re-sign afterward.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $RELEASE_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"
/usr/bin/codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$CODESIGN_IDENTITY" "$APP_DIR"

verify_app "$APP_DIR" 0
"$REPO_ROOT/Scripts/upload-dsyms.sh" "$APP_DIR"
notarize_and_staple_app
verify_app "$APP_DIR" 1
build_dmg
verify_dmg
"$REPO_ROOT/Scripts/write-appcast.sh" "$RELEASE_VERSION" "$BUILD_NUMBER" "$DMG_PATH" "$PRERELEASE"
verify_appcast "$OUTPUT_DIR/appcast.xml" "$DMG_PATH"

(
    cd "$OUTPUT_DIR"
    /usr/bin/shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$CHECKSUM_PATH")"
    /usr/bin/shasum -a 256 -c "$(basename "$CHECKSUM_PATH")"
)

PACKAGE_SUCCEEDED=1

# Stable filename used by the marketing site's Download button
# (…/releases/latest/download/StandClear-macos-arm64.dmg).
readonly STABLE_DMG_PATH="$OUTPUT_DIR/$APP_NAME-macos-arm64.dmg"
/bin/cp "$DMG_PATH" "$STABLE_DMG_PATH"

echo "Built release artifacts:"
echo "  $DMG_PATH"
echo "  $CHECKSUM_PATH"
echo "  $STABLE_DMG_PATH"
echo "  $OUTPUT_DIR/appcast.xml"
echo "Upload all four as GitHub release assets (tag v$ARTIFACT_LABEL)."
echo "Stand Clear is menu-bar-only: after install, look for the train icon in the menu bar (no Dock icon)."
