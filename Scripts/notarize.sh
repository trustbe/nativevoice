#!/bin/bash
# Sends an artifact to Apple for notarization and, unless told not to,
# staples the ticket onto it.
#
#   Scripts/notarize.sh NativeVoice-v1.0.0.dmg
#   Scripts/notarize.sh --no-staple NativeVoice-v1.0.0-submission.zip
#
# `notarytool submit` only accepts a disk image, a signed flat installer
# package, or a zip ("SUPPORTED UPLOAD FILE FORMATS" in `man notarytool`) —
# never a bare .app. `stapler` only accepts a disk image, a code-signed
# bundle, or a flat installer package ("man stapler") — never a zip, because
# there is nowhere in a zip to put the ticket. So a .app is notarized by
# submitting a throwaway zip of it and then stapling the .app itself, not
# the zip that got it there — that is what --no-staple is for.

set -euo pipefail
cd "$(dirname "$0")/.."

STAPLE=1
if [ "${1:-}" = "--no-staple" ]; then
    STAPLE=0
    shift
fi

# Credentials are read from a file, not the keychain. A keychain profile
# proved unreliable on this machine: it vanished, and storing it again from a
# non-interactive shell does not work — the write fails silently because it is
# waiting on a dialog nobody is looking at.
CONF="$HOME/.config/apple-signing/notary.env"
if [ ! -f "$CONF" ]; then
    cat >&2 <<MSG
✗ missing $CONF

Create it with permissions 600 and the contents:
  NOTARY_KEY="\$HOME/.config/apple-signing/AuthKey_XXXXXXXXXX.p8"
  NOTARY_KEY_ID="XXXXXXXXXX"
  NOTARY_ISSUER="<uuid>"
MSG
    exit 1
fi
# shellcheck disable=SC1090
. "$CONF"

TARGET="${1:-}"
[ -n "$TARGET" ] && [ -f "$TARGET" ] || {
    echo "Usage: Scripts/notarize.sh [--no-staple] NativeVoice-v1.0.0.dmg" >&2; exit 1; }

echo "▸ submitting $TARGET"
xcrun notarytool submit "$TARGET" \
    --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" \
    --wait

if [ "$STAPLE" = 1 ]; then
    echo "▸ stapling"
    xcrun stapler staple "$TARGET"
    xcrun stapler validate "$TARGET"
    echo "✓ $TARGET is notarized and stapled"
else
    echo "✓ $TARGET is notarized — staple the real target directly, not this file"
fi
