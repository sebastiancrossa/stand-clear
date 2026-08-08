#!/usr/bin/env bash
# Generate a dSYM for the Stand Clear binary and upload it to Sentry.
#
# Usage:
#   ./Scripts/upload-dsyms.sh <path-to-StandClear-binary-or-.app>
#
# Env (required):
#   SENTRY_AUTH_TOKEN   Org/user auth token with project:releases + org:read
#
# Env (optional):
#   SENTRY_ORG          default: zeroeval
#   SENTRY_PROJECT      default: apple-ios
#   SENTRY_CLI          path to sentry-cli (default: sentry-cli on PATH)

set -euo pipefail

readonly INPUT="${1:-}"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly SENTRY_ORG="${SENTRY_ORG:-zeroeval}"
readonly SENTRY_PROJECT="${SENTRY_PROJECT:-apple-ios}"
readonly SENTRY_CLI="${SENTRY_CLI:-sentry-cli}"
readonly OUTPUT_DIR="$REPO_ROOT/dist/dsyms"

die() {
    echo "error: $*" >&2
    exit 1
}

[[ -n "$INPUT" ]] || die "usage: $0 <path-to-StandClear-binary-or-.app>"
command -v "$SENTRY_CLI" >/dev/null 2>&1 || die "sentry-cli not found; install with: brew install getsentry/tools/sentry-cli"
# Prefer an exported token; otherwise use whatever `sentry-cli login` stored.
"$SENTRY_CLI" info >/dev/null 2>&1 \
    || die "sentry-cli is not authenticated; run: sentry-cli login (or export SENTRY_AUTH_TOKEN)"

BINARY=""
if [[ -d "$INPUT" && "$INPUT" == *.app ]]; then
    BINARY="$INPUT/Contents/MacOS/StandClear"
elif [[ -f "$INPUT" ]]; then
    BINARY="$INPUT"
else
    die "expected a StandClear.app bundle or executable, got: $INPUT"
fi

[[ -x "$BINARY" ]] || die "missing executable at $BINARY"

mkdir -p "$OUTPUT_DIR"
readonly DSYM_PATH="$OUTPUT_DIR/StandClear.dSYM"
rm -rf "$DSYM_PATH"

echo "Generating dSYM from $BINARY"
/usr/bin/dsymutil "$BINARY" -o "$DSYM_PATH"
[[ -d "$DSYM_PATH" ]] || die "dsymutil did not produce $DSYM_PATH"

BINARY_UUID="$(/usr/bin/dwarfdump --uuid "$BINARY" | /usr/bin/awk '/UUID:/ {print $2; exit}')"
DSYM_UUID="$(/usr/bin/dwarfdump --uuid "$DSYM_PATH" | /usr/bin/awk '/UUID:/ {print $2; exit}')"
[[ -n "$BINARY_UUID" && "$BINARY_UUID" == "$DSYM_UUID" ]] \
    || die "dSYM UUID ($DSYM_UUID) does not match binary UUID ($BINARY_UUID)"

echo "Uploading dSYM (UUID $DSYM_UUID) to Sentry org=$SENTRY_ORG project=$SENTRY_PROJECT"
"$SENTRY_CLI" debug-files upload \
    --wait \
    --org "$SENTRY_ORG" \
    --project "$SENTRY_PROJECT" \
    "$DSYM_PATH"

echo "Uploaded dSYM for Stand Clear to Sentry ($SENTRY_ORG/$SENTRY_PROJECT)"
