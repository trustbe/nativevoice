import Foundation
import Testing
@testable import NativeVoiceCore

/// The deferred block finishes on a different queue than the test, so the
/// result has to travel through something that tolerates concurrent access.
private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func set(_ value: T) { lock.lock(); stored = value; lock.unlock() }
}

@Suite struct ClipboardRestoreTests {

    @Test func restoresThePreviousStringAfterTheDelay() async throws {
        let restore = ClipboardRestore(delay: 0.05)
        let received = Box<String??>(nil)
        restore.schedule(previous: "old text") { received.set(.some($0)) }
        try await Task.sleep(for: .milliseconds(400))
        #expect(received.value ?? nil == "old text")
    }

    @Test func cancelPreventsTheRestore() async throws {
        // Clicking a history entry right after dictating must not have the
        // pending restore throw it straight back out of the clipboard.
        let restore = ClipboardRestore(delay: 0.1)
        let fired = Box(false)
        restore.schedule(previous: "old") { _ in fired.set(true) }
        restore.cancel()
        try await Task.sleep(for: .milliseconds(400))
        #expect(!(fired.value))
    }

    @Test func schedulingAgainReplacesThePendingRestore() async throws {
        let restore = ClipboardRestore(delay: 0.05)
        let values = Box<[String?]>([])
        restore.schedule(previous: "first") { v in values.set(values.value + [v]) }
        restore.schedule(previous: "second") { v in values.set(values.value + [v]) }
        try await Task.sleep(for: .milliseconds(400))
        #expect(values.value == ["second"])
    }

    @Test func nilPreviousIsPassedThroughAsNil() async throws {
        // The clipboard held an image or a file, so there is nothing to put
        // back. Turning that into an empty string would wipe it rather than
        // restore it.
        let restore = ClipboardRestore(delay: 0.05)
        let received = Box<String??>(nil)
        restore.schedule(previous: nil) { received.set(.some($0)) }
        try await Task.sleep(for: .milliseconds(400))
        #expect(received.value != nil)       // the block ran
        #expect((received.value ?? "not nil") == nil)
    }

    @Test func isPendingReflectsState() {
        let restore = ClipboardRestore(delay: 5)
        #expect(!(restore.isPending))
        restore.schedule(previous: "x") { _ in }
        #expect(restore.isPending)
        restore.cancel()
        #expect(!(restore.isPending))
    }
}
