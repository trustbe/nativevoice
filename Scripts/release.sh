#!/bin/bash
# Builds, signs, notarizes and publishes a release.
#
#   Scripts/release.sh 1.0.0 <build-number>
#
# Signing uses the certificate in this Mac's keychain. The private key never
# leaves the computer and is never uploaded anywhere.

set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/team-id.sh

VERSION="${1:-}"
BUILD="${2:-}"
if [ -z "$VERSION" ] || [ -z "$BUILD" ]; then
    echo "Usage: Scripts/release.sh 1.0.0 29" >&2
    exit 1
fi
TAG="v$VERSION"

if [ -n "$(git status --porcelain)" ]; then
    echo "✗ working tree is dirty — commit first" >&2
    exit 1
fi

./Scripts/test.sh
./Scripts/build-app.sh "$VERSION" "$BUILD"

APP=".build/app/NativeVoice.app"

# Review Focus 3d: build-app.sh falls back to signing ad hoc, and exits 0,
# whenever no Developer ID is in the keychain. An ad-hoc-signed app fails
# the one real verification every other step here relies on (the updater,
# and make-dmg.sh above it), so letting it through would only surface as a
# published release that users' copies of the app refuse to update to.
# Refuse before spending any time notarizing it.
if ! verify_signed_by_us "$APP" >/dev/null 2>&1; then
    echo "✗ $APP is not signed by $TEAM_ID — build-app.sh fell back to ad-hoc" \
         "signing (no \"Developer ID Application\" identity found in the" \
         "keychain). Install the certificate and re-run." >&2
    exit 1
fi

# The app is notarized and stapled on its own, before either artifact that
# carries it is built, so the DMG and the zip below both package an app that
# already has its ticket attached.
#
# notarytool cannot take the .app directly (it wants a disk image, a flat
# package, or a zip — see Scripts/notarize.sh), so a throwaway zip is made
# just to submit it; the staple then goes onto the app itself, not that zip.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
SUBMIT_ZIP="$STAGE/NativeVoice-submission.zip"

echo "▸ zipping the app for submission"
ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"

echo "▸ notarizing the app"
./Scripts/notarize.sh --no-staple "$SUBMIT_ZIP"

echo "▸ stapling the app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# Built from the now-stapled app, so both carry a real ticket onward.
./Scripts/make-dmg.sh "$TAG" "$APP"
./Scripts/notarize.sh "NativeVoice-$TAG.dmg"

echo "▸ zipping"
ZIP="NativeVoice-$TAG.zip"
rm -f "$ZIP"
# This is what the updater installs. It is built from the app that was
# already notarized and stapled above, so the ticket travels inside it and
# Gatekeeper can check it offline — there is no separate "notarize the zip"
# step, and there cannot be a "staple the zip" step: stapler has nowhere in
# a zip to put a ticket (see Scripts/notarize.sh). A previous version of
# this comment claimed the zip "is notarized too"; it never was, and did
# not need to be once the app inside it already carries its own ticket.
ditto -c -k --keepParent "$APP" "$ZIP"

# `gh release create <tag>` creates the tag itself, from the current default
# branch, if it doesn't already exist — so the tag now comes into being only
# together with the assets that justify it. A separate `git tag` + `git push`
# before this point used to let a failed `gh release create` leave a tag on
# the remote with no binaries behind it, which then made every re-run die on
# "tag already exists" before it could try again.
echo "▸ publishing"
gh release create "$TAG" "NativeVoice-$TAG.dmg" "$ZIP" \
    --title "NativeVoice $VERSION" --generate-notes
echo "✓ $TAG published"
