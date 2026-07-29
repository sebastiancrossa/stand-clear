#!/usr/bin/env bash
#
# Put this Mac back into the state a brand-new user is in, so the onboarding
# pane can be exercised for real instead of reasoned about.
#
# Usage:
#   Scripts/reset-first-run.sh              # prefs + location permission
#   Scripts/reset-first-run.sh --prefs-only # leave the location grant alone
#   Scripts/reset-first-run.sh --launch     # reset, then open dist/StandClear.app

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly APP_NAME="StandClear"
readonly APP_DIR="$REPO_ROOT/dist/$APP_NAME.app"
readonly BUNDLE_ID="com.sebastiancrossa.standclear"

reset_location=1
launch_after=0

for arg in "$@"; do
    case "$arg" in
        --prefs-only) reset_location=0 ;;
        --launch) launch_after=1 ;;
        *) echo "error: unknown option $arg" >&2; exit 1 ;;
    esac
done

# cfprefsd holds the domain in memory and rewrites the plist on quit, so a
# running app would restore everything this script just deleted.
if pgrep -x "$APP_NAME" >/dev/null; then
    echo "Quitting ${APP_NAME}…"
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || killall "$APP_NAME"
    while pgrep -x "$APP_NAME" >/dev/null; do sleep 0.2; done
fi

# One domain covers everything the app remembers: line/direction selection, the
# onboarding version stamp, walk-time settings, and Sparkle's update state.
echo "Deleting preferences for ${BUNDLE_ID}…"
defaults delete "$BUNDLE_ID" 2>/dev/null || true
rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"
killall cfprefsd 2>/dev/null || true

if (( reset_location )); then
    # Onboarding's first real moment is the location prompt, and it only fires
    # again once the existing grant is gone.
    echo "Resetting Core Location permission…"
    tccutil reset CoreLocation "$BUNDLE_ID" || true
fi

# Launch-at-login lives with the system, not in the prefs domain, so an earlier
# run's "Open at login" would otherwise survive a wipe.
if [[ -d "$APP_DIR" ]]; then
    echo "Removing any login-item registration…"
    osascript -e 'tell application "System Events" to delete every login item whose name is "'"$APP_NAME"'"' 2>/dev/null || true
fi

echo "Done. Next launch will show the first-run pane."

if (( launch_after )); then
    if [[ ! -d "$APP_DIR" ]]; then
        echo "error: $APP_DIR not found; run 'make app' first" >&2
        exit 1
    fi
    echo "Launching ${APP_DIR}…"
    open "$APP_DIR"
fi
