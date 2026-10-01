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

# One build, both architectures. SwiftPM emits a universal binary directly.
#
# The obvious-looking alternative — building each --triple separately and
# joining them with lipo — does NOT work here: --show-bin-path returns the
# same directory for every triple, so the second build overwrites the first
# and lipo is handed the same file twice. (lipo catches that and fails, which
# is how it was found; nothing falsely universal was produced.)
echo "▸ building universal binary"
swift build -c release --arch arm64 --arch x86_64 --package-path "$ROOT"
BIN="$(swift build -c release --arch arm64 --arch x86_64 --package-path "$ROOT" --show-bin-path)"
cp "$BIN/NativeVoice" "$APP/Contents/MacOS/NativeVoice"

# Read the architectures back out of the binary that was actually produced,
# rather than trusting the build to have done what was asked. A package that
# claimed to be universal and was not has already shipped once in this
# project's predecessor.
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

# The icon is generated rather than committed as a binary, so that changing it
# is a diff somebody can read. Design/make-icon.swift draws it; this step only
# refuses to ship without one, because a missing icon is most visible exactly
# where it matters least to us and most to the user: the Input Monitoring and
# Accessibility lists, where they decide whether to trust the thing.
ICON="$ROOT/Design/AppIcon.icns"
if [ ! -f "$ICON" ]; then
    echo "✗ $ICON missing — run: cd Design && swift make-icon.swift . && iconutil -c icns AppIcon.iconset -o AppIcon.icns" >&2
    exit 1
fi
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
echo "▸ icon: AppIcon.icns"

# Resource bundles produced by SwiftPM (String Catalog) sit next to the binary.
for b in "$BIN"/*.bundle; do
    [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done

# Signed with Developer ID when one is available, ad-hoc otherwise.
#
# This is not about distribution — notarization comes later. It is about the
# signature staying the same between builds. macOS ties Accessibility
# permission to the code signature, and an ad-hoc signature changes on every
# build, so the permission is revoked every time and has to be granted again
# before the app can see a key press. With a stable identity it is granted
# once.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
            | grep "Developer ID Application" | head -1 \
            | sed -E 's/.*"(.*)"/\1/')"

if [ -n "$IDENTITY" ]; then
    echo "▸ signing as: $IDENTITY"
    codesign --force --options runtime --sign "$IDENTITY" --timestamp "$APP"
else
    echo "▸ signing ad-hoc — no Developer ID found"
    echo "   Accessibility permission will be revoked on every rebuild."
    codesign --force --sign - --timestamp=none "$APP"
fi

echo "✓ $APP"
