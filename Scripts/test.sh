#!/bin/bash
# Runs the test suite.
#
# Two flags this machine cannot do without, both verified by measurement:
#
#   --build-system native   The default build system (XCBuild) cannot even
#                           initialize without a full Xcode.app — it fails
#                           with "Could not initialize build system". The
#                           native one works. It is deprecated upstream; when
#                           it goes away, Xcode becomes a requirement.
#
#   -F …/Developer/Frameworks   Testing.framework ships with the Command Line
#                           Tools but sits outside the default search path.
#                           XCTest.framework is not there at all, which is why
#                           the tests use swift-testing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks

exec swift test \
    --package-path "$ROOT" \
    --build-system native \
    -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
    "$@"
