#!/bin/bash
# Builds a universal .app from the SwiftPM product.
#
# Version arguments are mandatory and validated: CFBundleVersion must be
# digits and periods only with a first integer above zero (Apple's rule),
# and a build that silently carried the wrong version has bitten this
# project's predecessor more than once.
set -euo pipefail

VERSION="${1:-}"
BUILD="${2:-}"
[ -n "$VERSION" ] && [ -n "$BUILD" ] || {
    echo "usage: $0 <short-version> <build-number>   e.g. $0 0.1.0 7" >&2
    exit 2
}
[[ "$BUILD" =~ ^[1-9][0-9]*(\.[0-9]+)*$ ]] || {
    echo "build number must be digits and periods, first integer > 0: got '$BUILD'" >&2
    exit 2
}

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.build/app"
APP="$OUT/NativeVoice.app"

rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ building universal binary"
swift build -c release --arch arm64 --arch x86_64 --package-path "$ROOT"
BIN="$(swift build -c release --arch arm64 --arch x86_64 --package-path "$ROOT" --show-bin-path)"
cp "$BIN/NativeVoice" "$APP/Contents/MacOS/NativeVoice"

echo "▸ Info.plist ($VERSION / $BUILD)"
cp "$ROOT/Sources/NativeVoice/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

# Resource bundles produced by SwiftPM (String Catalog) sit next to the binary.
for b in "$BIN"/*.bundle; do
    [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done

echo "▸ signing ad-hoc (Developer ID comes in plan 3)"
codesign --force --sign - --timestamp=none "$APP"

echo "✓ $APP"
