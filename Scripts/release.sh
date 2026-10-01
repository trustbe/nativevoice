#!/bin/bash
# Builds, signs, notarizes and publishes a release.
#
#   Scripts/release.sh 1.0.0 <build-number>
#
# Signing uses the certificate in this Mac's keychain. The private key never
# leaves the computer and is never uploaded anywhere.

set -euo pipefail
cd "$(dirname "$0")/.."

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
ZIP="NativeVoice-$TAG.zip"

echo "▸ zipping"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

./Scripts/make-dmg.sh "$TAG" "$APP"
./Scripts/notarize.sh "NativeVoice-$TAG.dmg"
# The zip is what the updater installs, so it is notarized too — Gatekeeper
# checks a bundle that arrived by download regardless of what carried it.
./Scripts/notarize.sh "$ZIP"

echo "▸ tagging $TAG"
git tag -a "$TAG" -m "NativeVoice $VERSION"
git push origin "$TAG"

echo "▸ publishing"
gh release create "$TAG" "NativeVoice-$TAG.dmg" "$ZIP" \
    --title "NativeVoice $VERSION" --generate-notes
echo "✓ $TAG published"
