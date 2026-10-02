import Foundation
import Testing
@testable import NativeVoiceCore

@Suite struct UpdateScheduleTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func theFirstCheckIsAlwaysDue() {
        #expect(UpdateSchedule.isDue(lastCheck: nil, now: now))
    }

    @Test func notDueAgainStraightAway() {
        #expect(!UpdateSchedule.isDue(lastCheck: now, now: now))
        #expect(!UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(-60), now: now))
    }

    @Test func dueOnceTheIntervalHasPassed() {
        let last = now.addingTimeInterval(-UpdateSchedule.interval)
        #expect(UpdateSchedule.isDue(lastCheck: last, now: now))
    }

    @Test func aClockThatWentBackwardsDoesNotParkTheCheckForever() {
        // A timezone change, an NTP correction, a laptop waking somewhere
        // else. Stored in the future, the elapsed time is negative, and
        // "not due yet" would hold until that date came round — possibly
        // never.
        let future = now.addingTimeInterval(400 * 86_400)
        #expect(UpdateSchedule.isDue(lastCheck: future, now: now))
    }

    @Test func theIntervalIsHoursRatherThanMinutes() {
        // Pinned deliberately: this is a public API being polled by every
        // copy of the app, and a careless edit here turns it into traffic.
        #expect(UpdateSchedule.interval >= 3600)
    }

    @Test func thereIsAPauseAfterLaunch() {
        // Starting the app must not wait on a network request, and somebody
        // who has just opened it is about to use it, not to be restarted.
        #expect(UpdateSchedule.delayAfterLaunch >= 60)
    }
}
