#!/bin/bash
# Sends a DMG or zip to Apple and staples the result onto it.
#
#   Scripts/notarize.sh NativeVoice-v1.0.0.dmg

set -euo pipefail
cd "$(dirname "$0")/.."

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
    echo "Usage: Scripts/notarize.sh NativeVoice-v1.0.0.dmg" >&2; exit 1; }

echo "▸ submitting $TARGET"
xcrun notarytool submit "$TARGET" \
    --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" \
    --wait

echo "▸ stapling"
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
echo "✓ $TARGET is notarized and stapled"
