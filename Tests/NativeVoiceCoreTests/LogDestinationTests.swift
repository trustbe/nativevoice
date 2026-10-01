import Foundation
import Testing
@testable import NativeVoiceCore

@Suite struct LogDestinationTests {

    @Test func defaultsToTheUsersLogFolder() {
        let path = Log.defaultPath(environment: [:], home: "/Users/someone")
        #expect(path == "/Users/someone/Library/Logs/NativeVoice.log")
    }

    @Test func anOverrideWins() {
        // The test runner sets this so a test run cannot write into the log
        // the user is reading. A stray HTTP 401 from a parser test, landing
        // in the middle of a real dictation, once sent a diagnosis in
        // completely the wrong direction.
        let path = Log.defaultPath(environment: ["NATIVEVOICE_LOG": "/tmp/t.log"],
                                   home: "/Users/someone")
        #expect(path == "/tmp/t.log")
    }

    @Test func anEmptyOverrideIsIgnored() {
        let path = Log.defaultPath(environment: ["NATIVEVOICE_LOG": "  "],
                                   home: "/Users/someone")
        #expect(path == "/Users/someone/Library/Logs/NativeVoice.log")
    }
}
