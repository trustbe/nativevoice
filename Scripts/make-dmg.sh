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
# Captured into a variable rather than piped straight into `grep -q`: with
# `pipefail` a pipe here raced codesign against grep closing early on match —
# grep was done by line 8 of 11, and if codesign was still writing lines 9-11
# it was killed by SIGPIPE (exit 141), which pipefail then reported as this
# script's failure. A signed app was refused about one run in four.
SIGNATURE="$(codesign -dv "$APP" 2>&1)"
if [[ "$SIGNATURE" != *"TeamIdentifier=5XJALC3SPQ"* ]]; then
    echo "✗ $APP is not signed by this developer — refusing to package it" >&2
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
