import Foundation
import Testing
@testable import NativeVoiceCore

@Suite struct LogDestinationTests {

    private let home = "/Users/someone"
    private let appBundle = "/Applications/NativeVoice.app"
    private let toolchain = "/Library/Developer/Toolchains/x.xctoolchain/usr/libexec"

    @Test func theShippedAppWritesToTheUsersLogFolder() {
        let path = Log.defaultPath(environment: [:], home: home, bundlePath: appBundle)
        #expect(path == "/Users/someone/Library/Logs/NativeVoice.log")
    }

    @Test func anythingNotRunningFromAnAppBundleGetsAScratchFile() {
        // Measured: during `swift test` the bundle path points into the
        // toolchain, not into a .app. Detecting test runs by name would only
        // ever cover the invocations somebody thought of; asking whether this
        // is the shipped app covers the rest by default.
        let path = Log.defaultPath(environment: [:], home: home, bundlePath: toolchain)
        #expect(!(path.hasPrefix(home)))
        #expect(path.hasSuffix("nativevoice-scratch.log"))
    }

    @Test func aBareSwiftTestCannotReachTheUsersLog() {
        // The failure this exists to prevent: parser tests logged HTTP 401 and
        // 502 into the user's own log in the middle of a real dictation, and
        // the lines looked exactly like failures of the running app.
        let path = Log.defaultPath(environment: [:], home: home, bundlePath: toolchain)
        #expect(path != home + "/Library/Logs/NativeVoice.log")
    }

    @Test func anExplicitOverrideWinsEvenForTheApp() {
        let path = Log.defaultPath(environment: ["NATIVEVOICE_LOG": "/tmp/t.log"],
                                   home: home, bundlePath: appBundle)
        #expect(path == "/tmp/t.log")
    }

    @Test func anEmptyOverrideIsIgnored() {
        let path = Log.defaultPath(environment: ["NATIVEVOICE_LOG": "  "],
                                   home: home, bundlePath: appBundle)
        #expect(path == "/Users/someone/Library/Logs/NativeVoice.log")
    }
}
