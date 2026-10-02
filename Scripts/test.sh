#!/bin/bash
# Runs the test suite.
#
# One command, identical locally and in CI, so a green build here means the
# same thing as a green build there.
#
# The tests use swift-testing (`import Testing`), not XCTest. The two coexist
# in one target, and swift-testing does not need XCTest.framework, which the
# Command Line Tools alone do not provide.
#
# It does need Xcode 16 or newer. A CI image with Xcode 15 fails here with
# "no such module 'Testing'" after the build step has already passed, which
# reads as a test failure and is not one.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Keep a test run out of the log the user reads. Without this, a parser test
# logging an HTTP 401 lands in the middle of their real dictation and looks
# exactly like a failure of the running app.
export NATIVEVOICE_LOG="${TMPDIR:-/tmp}/nativevoice-tests.log"

exec swift test --package-path "$ROOT" "$@"
