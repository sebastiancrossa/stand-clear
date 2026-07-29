#!/usr/bin/env bash
# Writes dist/release/appcast.xml for the just-built Stand Clear DMG.
#
# Usage:
#   ./Scripts/write-appcast.sh <release-version> <build-number> <dmg-path> [prerelease]
#
# Env:
#   SPARKLE_ACCOUNT   Keychain account for EdDSA keys (default: standclear)
#   SPARKLE_BIN       Path to Sparkle bin dir (default: .build/artifacts/.../bin)
#   REPO_SLUG         GitHub owner/repo (default: sebastiancrossa/stand-clear)
#   APPCAST_FEED_URL  Live feed URL to merge/guard against (default: …/latest/download/appcast.xml)

set -euo pipefail

readonly RELEASE_VERSION="${1:-}"
readonly BUILD_NUMBER="${2:-}"
readonly DMG_PATH="${3:-}"
readonly PRERELEASE="${4:-}"

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly OUTPUT_DIR="$REPO_ROOT/dist/release"
readonly APPCAST_PATH="$OUTPUT_DIR/appcast.xml"
readonly REPO_SLUG="${REPO_SLUG:-sebastiancrossa/stand-clear}"
readonly SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-standclear}"
readonly SPARKLE_BIN="${SPARKLE_BIN:-$REPO_ROOT/.build/artifacts/sparkle/Sparkle/bin}"
readonly SIGN_UPDATE="$SPARKLE_BIN/sign_update"
readonly APPCAST_FEED_URL="${APPCAST_FEED_URL:-https://github.com/$REPO_SLUG/releases/latest/download/appcast.xml}"
readonly RELEASE_NOTES_FILE="$REPO_ROOT/docs/release-notes/${RELEASE_VERSION}.html"

die() {
    echo "error: $*" >&2
    exit 1
}

xml_escape() {
    local value="$1"
    value="${value//&/&amp;}"
    value="${value//</&lt;}"
    value="${value//>/&gt;}"
    value="${value//\"/&quot;}"
    value="${value//\'/&apos;}"
    printf '%s' "$value"
}

[[ -n "$RELEASE_VERSION" ]] || die "RELEASE_VERSION is required"
[[ -n "$BUILD_NUMBER" ]] || die "BUILD_NUMBER is required"
[[ -f "$DMG_PATH" ]] || die "DMG not found at $DMG_PATH"
[[ -x "$SIGN_UPDATE" ]] || die "sign_update not found at $SIGN_UPDATE (run swift package resolve)"

if [[ -n "$PRERELEASE" ]]; then
    readonly TAG="v${RELEASE_VERSION}-${PRERELEASE}"
    readonly ARTIFACT_LABEL="${RELEASE_VERSION}-${PRERELEASE}"
else
    readonly TAG="v${RELEASE_VERSION}"
    readonly ARTIFACT_LABEL="$RELEASE_VERSION"
fi

readonly DMG_BASENAME="StandClear-${ARTIFACT_LABEL}-macos-arm64.dmg"
readonly ENCLOSURE_URL="https://github.com/${REPO_SLUG}/releases/download/${TAG}/${DMG_BASENAME}"
readonly RELEASE_PAGE_URL="https://github.com/${REPO_SLUG}/releases/tag/${TAG}"

mkdir -p "$OUTPUT_DIR"

echo "Signing update archive with Sparkle EdDSA key (account: $SPARKLE_ACCOUNT)"
SIGN_OUTPUT="$("$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" "$DMG_PATH")"
# Example: sparkle:edSignature="…" length="12345"
ED_SIGNATURE="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<< "$SIGN_OUTPUT" | head -n 1)"
LENGTH="$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' <<< "$SIGN_OUTPUT" | head -n 1)"
[[ -n "$ED_SIGNATURE" ]] || die "sign_update did not produce sparkle:edSignature (output: $SIGN_OUTPUT)"
[[ -n "$LENGTH" ]] || die "sign_update did not produce length (output: $SIGN_OUTPUT)"

ACTUAL_LENGTH="$(/usr/bin/stat -f%z "$DMG_PATH")"
[[ "$LENGTH" == "$ACTUAL_LENGTH" ]] || die "signed length ($LENGTH) does not match DMG size ($ACTUAL_LENGTH)"

LIVE_APPCAST="$(mktemp "${TMPDIR:-/tmp}/standclear-appcast.XXXXXX.xml")"
trap 'rm -f "$LIVE_APPCAST"' EXIT

HTTP_STATUS="$(curl -fsSL -o "$LIVE_APPCAST" -w '%{http_code}' "$APPCAST_FEED_URL" || true)"
PRIOR_ITEMS=""
if [[ "$HTTP_STATUS" == "200" ]]; then
    PUBLISHED_VERSION="$(
        /usr/bin/sed -n 's/.*<sparkle:version>\([^<]*\)<\/sparkle:version>.*/\1/p' "$LIVE_APPCAST" \
            | /usr/bin/head -n 1
    )"
    if [[ -n "$PUBLISHED_VERSION" ]]; then
        if ! [[ "$PUBLISHED_VERSION" =~ ^[0-9]+$ ]]; then
            die "live appcast sparkle:version is not an integer: $PUBLISHED_VERSION"
        fi
        if (( BUILD_NUMBER <= PUBLISHED_VERSION )); then
            die "BUILD_NUMBER ($BUILD_NUMBER) must exceed published sparkle:version ($PUBLISHED_VERSION)"
        fi
    fi
    # Preserve existing <item>…</item> blocks so historical enclosures keep resolving.
    PRIOR_ITEMS="$(
        /usr/bin/awk '
            /<item>/ { capturing = 1 }
            capturing { print }
            /<\/item>/ { capturing = 0 }
        ' "$LIVE_APPCAST"
    )"
elif [[ "$HTTP_STATUS" == "404" ]]; then
    echo "No live appcast yet (HTTP 404); writing first item"
else
    die "failed to fetch live appcast (HTTP $HTTP_STATUS) from $APPCAST_FEED_URL"
fi

PUB_DATE="$(/bin/date -u '+%a, %d %b %Y %H:%M:%S +0000')"
TITLE="$(xml_escape "Stand Clear ${ARTIFACT_LABEL}")"
DESCRIPTION_BLOCK=""
if [[ -f "$RELEASE_NOTES_FILE" ]]; then
    NOTES="$(cat "$RELEASE_NOTES_FILE")"
    DESCRIPTION_BLOCK="
        <description><![CDATA[
${NOTES}
        ]]></description>"
else
    NOTES_LINK="$(xml_escape "$RELEASE_PAGE_URL")"
    DESCRIPTION_BLOCK="
        <sparkle:releaseNotesLink>${NOTES_LINK}</sparkle:releaseNotesLink>"
fi

NEW_ITEM="        <item>
            <title>${TITLE}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
            <sparkle:shortVersionString>${RELEASE_VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>${DESCRIPTION_BLOCK}
            <enclosure
                url=\"$(xml_escape "$ENCLOSURE_URL")\"
                sparkle:edSignature=\"${ED_SIGNATURE}\"
                length=\"${LENGTH}\"
                type=\"application/octet-stream\" />
        </item>"

{
    cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Stand Clear</title>
        <link>https://github.com/${REPO_SLUG}</link>
        <description>Stand Clear updates</description>
        <language>en</language>
${NEW_ITEM}
EOF
    if [[ -n "$PRIOR_ITEMS" ]]; then
        printf '%s\n' "$PRIOR_ITEMS"
    fi
    cat <<'EOF'
    </channel>
</rss>
EOF
} > "$APPCAST_PATH"

echo "Wrote $APPCAST_PATH"
echo "  version=$RELEASE_VERSION build=$BUILD_NUMBER length=$LENGTH"
echo "  enclosure=$ENCLOSURE_URL"
