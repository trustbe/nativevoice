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

# Two single-architecture builds joined with lipo, rather than
# `swift build --arch`. Separate triples are explicit about the deployment
# target, and the lipo result is checked below: a binary that claimed to be
# universal but was not has already shipped once in this project's
# predecessor.
SB=(swift build -c release --package-path "$ROOT")

# Each architecture is built, then the same command is repeated with
# --show-bin-path purely to learn where the product landed. The second call
# is a no-op against an up-to-date build, and asking the tool for the path
# beats hardcoding .build/<triple>/release, which is not a documented layout.
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
echo "   architectures: $ARCHS"
case "$ARCHS" in
    *arm64*) ;;
    *) echo "arm64 missing from the finished binary" >&2; exit 1 ;;
esac
case "$ARCHS" in
    *x86_64*) ;;
    *) echo "x86_64 missing from the finished binary" >&2; exit 1 ;;
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
