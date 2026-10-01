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

# Two single-architecture builds joined with lipo. `swift build --arch`
# always routes through XCBuild, which cannot initialize without a full
# Xcode.app — on a Command Line Tools machine it fails outright. Building
# each triple separately uses the native build system, which works.
SB=(swift build -c release --build-system native --package-path "$ROOT")

echo "▸ building arm64"
"${SB[@]}" --triple arm64-apple-macosx13.0
ARM="$("${SB[@]}" --triple arm64-apple-macosx13.0 --show-bin-path)"

echo "▸ building x86_64"
"${SB[@]}" --triple x86_64-apple-macosx13.0
X86="$("${SB[@]}" --triple x86_64-apple-macosx13.0 --show-bin-path)"

echo "▸ joining into a universal binary"
lipo -create "$ARM/NativeVoice" "$X86/NativeVoice" \
     -output "$APP/Contents/MacOS/NativeVoice"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/NativeVoice")"
echo "   architektury: $ARCHS"
case "$ARCHS" in
    *arm64*) ;;
    *) echo "arm64 chybi v hotove binarce" >&2; exit 1 ;;
esac
case "$ARCHS" in
    *x86_64*) ;;
    *) echo "x86_64 chybi v hotove binarce" >&2; exit 1 ;;
esac

echo "▸ Info.plist ($VERSION / $BUILD)"
cp "$ROOT/Sources/NativeVoice/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

# Resource bundles produced by SwiftPM (String Catalog) sit next to the binary.
for b in "$ARM"/*.bundle; do
    [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done

echo "▸ signing ad-hoc (Developer ID comes in plan 3)"
codesign --force --sign - --timestamp=none "$APP"

echo "✓ $APP"
