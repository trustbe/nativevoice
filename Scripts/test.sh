#!/bin/bash
# Runs the test suite.
#
# One command, identical locally and in CI, so a green build here means the
# same thing as a green build there.
#
# The tests use swift-testing (`import Testing`), not XCTest. Both ship with
# Xcode and the two can coexist in one target, but swift-testing also works
# on a machine that only has the Command Line Tools — where XCTest.framework
# is absent entirely. Choosing it costs nothing and removes a dependency on
# a full Xcode install.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec swift test --package-path "$ROOT" "$@"
