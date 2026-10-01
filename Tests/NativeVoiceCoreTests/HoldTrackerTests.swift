import Testing
@testable import NativeVoiceCore

@Suite struct HoldTrackerTests {

    private let rightCommand: UInt64 = 0x10
    private let leftCommand: UInt64  = 0x08

    @Test func firstPressStartsAHold() {
        var tracker = HoldTracker(key: .rightCommand)
        #expect(tracker.update(flags: rightCommand) == .pressed)
    }

    @Test func releaseEndsTheHold() {
        var tracker = HoldTracker(key: .rightCommand)
        _ = tracker.update(flags: rightCommand)
        #expect(tracker.update(flags: 0) == .released)
    }

    @Test func repeatedSameStateIsIgnored() {
        // flagsChanged fires for every modifier, including ones we do not
        // care about. Only a change of our own key is an event.
        var tracker = HoldTracker(key: .rightCommand)
        _ = tracker.update(flags: rightCommand)
        #expect(tracker.update(flags: rightCommand | leftCommand) == .unchanged)
        #expect(tracker.update(flags: rightCommand) == .unchanged)
    }

    @Test func otherModifiersDoNotStartAHold() {
        var tracker = HoldTracker(key: .rightCommand)
        #expect(tracker.update(flags: leftCommand) == .unchanged)
    }

    @Test func forceReleaseMakesTheNextPressRegisterOnceTheKeyIsSeenUp() {
        // The recording-cap case. The cap exists because a release event can
        // go missing; if the tracker still believed the key was down, the next
        // genuine press would read as "no change" and be dropped — the user
        // would say a whole sentence into nothing.
        var tracker = HoldTracker(key: .rightCommand)
        _ = tracker.update(flags: rightCommand)
        tracker.forceRelease()
        _ = tracker.update(flags: 0)        // the release, now actually observed
        #expect(tracker.update(flags: rightCommand) == .pressed)
    }

    @Test func forceReleaseDoesNotTurnAnUnrelatedEventIntoAPress() {
        // `flagsChanged` fires for every modifier. Without this guard, touching
        // Shift while the trigger key is still physically held would carry the
        // trigger bit, read as a fresh press, and start a recording nobody
        // asked for.
        var tracker = HoldTracker(key: .rightCommand)
        _ = tracker.update(flags: rightCommand)
        tracker.forceRelease()
        let shiftWhileStillHolding = rightCommand | 0x2   // NX_DEVICELSHIFTKEYMASK
        #expect(tracker.update(flags: shiftWhileStillHolding) == .unchanged)
        #expect(tracker.update(flags: rightCommand) == .unchanged)
        // Only a real release re-arms it.
        _ = tracker.update(flags: 0)
        #expect(tracker.update(flags: rightCommand) == .pressed)
    }

    @Test func changingKeyWhileHeldDoesNotLeaveItStuck() {
        var tracker = HoldTracker(key: .rightCommand)
        _ = tracker.update(flags: rightCommand)
        tracker.key = .leftOption
        #expect(!(tracker.isHolding))
    }
}
