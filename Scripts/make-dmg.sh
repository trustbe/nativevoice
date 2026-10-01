#!/bin/bash
# Builds a DMG with the app and a shortcut to Applications, so it can be
# dragged across.
#
#   Scripts/make-dmg.sh v1.0.0 [path/to/NativeVoice.app]

set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:-dev}"
APP="${2:-.build/app/NativeVoice.app}"
DMG="NativeVoice-$TAG.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

[ -d "$APP" ] || { echo "✗ $APP missing — run Scripts/build-app.sh first" >&2; exit 1; }

# Review Focus 5: an unsigned app inside a DMG is a download that fails at the
# user, days later, with a message that blames them. It fails here instead.
#
# This used to be `SIGNATURE="$(codesign -dv "$APP" 2>&1)"` followed by a
# substring match on the captured text. Two problems, both reproduced: under
# `set -e`, a command substitution takes the exit status of the command
# inside it, and `codesign -dv` exits non-zero on an *unsigned* app — so
# the one case this check exists to catch instead aborted the whole script
# before printing anything. And `-dv` is a display command, not a
# verification one, so a substring match on its output can be satisfied by
# an ad-hoc bundle whose `--identifier` echoes our team ID back on an
# unrelated line (see Scripts/team-id.sh). Using `verify_signed_by_us`
# inside an `if` avoids both: the condition of an `if` is exempt from
# `set -e`, and the predicate itself is a real verification, not a grep.
source "$(dirname "$0")/team-id.sh"
if ! verify_signed_by_us "$APP" >/dev/null 2>&1; then
    echo "✗ $APP is not signed by $TEAM_ID — refusing to package it" >&2
    exit 1
fi

echo "▸ staging"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "▸ building $DMG"
rm -f "$DMG"
hdiutil create -volname "NativeVoice" -srcfolder "$STAGE" \
               -ov -format UDZO -quiet "$DMG"
echo "✓ $DMG"
