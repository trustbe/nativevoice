import Foundation
import Testing
@testable import NativeVoiceCore

@Suite struct UsageStatsTests {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    /// `time` holds bucket timestamps in milliseconds.
    private func payload(times: [Double], stt: [Double]) -> Data {
        let object: [String: Any] = ["time": times, "usage": ["STT": stt]]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    private func ms(daysAgo: Double) -> Double {
        (now.timeIntervalSince1970 - daysAgo * 86_400) * 1000
    }

    @Test func rubbishIsNotASnapshot() {
        #expect(UsageStats.snapshot(from: Data("not json".utf8)) == nil)
    }

    @Test func aPayloadWithoutTimesIsNotASnapshot() {
        let data = try! JSONSerialization.data(withJSONObject: ["usage": ["STT": [1.0]]])
        #expect(UsageStats.snapshot(from: data) == nil)
    }

    @Test func bucketsAreSortedIntoTodayThisWeekAndEverything() {
        let data = payload(times: [ms(daysAgo: 0.5), ms(daysAgo: 3), ms(daysAgo: 40)],
                           stt: [10, 20, 30])
        let snapshot = UsageStats.snapshot(from: data, now: now)
        #expect(snapshot == UsageStats.Snapshot(today: 10, week: 30, total: 60))
    }

    @Test func anEmptySeriesIsZeroesRatherThanNothing() {
        let snapshot = UsageStats.snapshot(from: payload(times: [], stt: []), now: now)
        #expect(snapshot == UsageStats.Snapshot(today: 0, week: 0, total: 0))
    }

    @Test func aMissingSTTSeriesIsZeroes() {
        let data = try! JSONSerialization.data(
            withJSONObject: ["time": [ms(daysAgo: 1)], "usage": ["TTS": [99.0]]])
        #expect(UsageStats.snapshot(from: data, now: now)
                == UsageStats.Snapshot(today: 0, week: 0, total: 0))
    }

    @Test func moreTimestampsThanNumbersDoesNotCrash() {
        // Review Focus 1. The version this was ported from walked `time` and
        // indexed into the series, so one extra timestamp took the process
        // down. Only the overlap counts.
        let data = payload(times: [ms(daysAgo: 0.1), ms(daysAgo: 0.2), ms(daysAgo: 0.3)],
                           stt: [5, 5])
        #expect(UsageStats.snapshot(from: data, now: now)
                == UsageStats.Snapshot(today: 10, week: 10, total: 10))
    }

    @Test func moreNumbersThanTimestampsDoesNotCrash() {
        let data = payload(times: [ms(daysAgo: 0.1)], stt: [5, 5, 5])
        #expect(UsageStats.snapshot(from: data, now: now)
                == UsageStats.Snapshot(today: 5, week: 5, total: 5))
    }

    @Test func aSnapshotWeDoNotHaveYetSaysSo() {
        #expect(UsageStats.todayTitle(for: nil).contains("…"))
    }

    @Test func largeNumbersAreGroupedToStayReadable() {
        let title = UsageStats.todayTitle(
            for: UsageStats.Snapshot(today: 1234, week: 56789, total: 1_234_567))
        #expect(!title.contains("1234"))
        #expect(title.lowercased().contains("today"))
    }
}

@Suite struct SubscriptionTests {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func payload(used: Int, limit: Int, reset: Double?) -> Data {
        var object: [String: Any] = ["character_count": used, "character_limit": limit]
        if let reset { object["next_character_count_reset_unix"] = reset }
        return try! JSONSerialization.data(withJSONObject: object)
    }

    @Test func readsTheQuota() {
        let plan = UsageStats.subscription(from: payload(used: 4230, limit: 10000, reset: nil))
        #expect(plan?.used == 4230)
        #expect(plan?.limit == 10000)
        #expect(plan?.resetsAt == nil)
    }

    @Test func readsTheResetDate() {
        let plan = UsageStats.subscription(from: payload(used: 1, limit: 2, reset: 1_500_000))
        #expect(plan?.resetsAt == Date(timeIntervalSince1970: 1_500_000))
    }

    @Test func aPayloadWithoutAQuotaIsNotASubscription() {
        #expect(UsageStats.subscription(from: Data("{}".utf8)) == nil)
        #expect(UsageStats.subscription(from: Data("not json".utf8)) == nil)
    }

    @Test func aPlanThatDoesNotResetSaysOnlyWhatItHasUsed() {
        // next_character_count_reset_unix is nullable, and absent on plans
        // that never reset. The row must not invent a date for them.
        let title = UsageStats.periodTitle(
            for: UsageStats.Subscription(used: 4230, limit: 10000, resetsAt: nil), now: now)
        #expect(title.contains("4,230") || title.contains("4 230"))
        #expect(!title.lowercased().contains("reset"))
    }

    @Test func aResetInTheFutureIsCountedInWholeDays() {
        let plan = UsageStats.Subscription(used: 1, limit: 2,
                                           resetsAt: now.addingTimeInterval(12 * 86_400))
        #expect(UsageStats.periodTitle(for: plan, now: now).contains("12"))
    }

    @Test func aResetLaterTodayDoesNotReadAsAWholeDay() {
        // Rounded up, so a reset four minutes away never says "in 0 days".
        let plan = UsageStats.Subscription(used: 1, limit: 2,
                                           resetsAt: now.addingTimeInterval(240))
        #expect(UsageStats.periodTitle(for: plan, now: now).contains("tomorrow"))
    }

    @Test func aResetAlreadyPastIsIgnoredRatherThanShownAsNegative() {
        // The server's timestamp can be behind a clock that has drifted, and
        // "resets in -3 days" is worse than saying nothing about it.
        let plan = UsageStats.Subscription(used: 1, limit: 2,
                                           resetsAt: now.addingTimeInterval(-3 * 86_400))
        let title = UsageStats.periodTitle(for: plan, now: now)
        #expect(!title.contains("-"))
        #expect(!title.lowercased().contains("reset"))
    }

    @Test func nothingFetchedYetSaysSo() {
        #expect(UsageStats.periodTitle(for: nil, now: now).contains("…"))
        #expect(UsageStats.todayTitle(for: nil).contains("…"))
    }

    @Test func largeNumbersAreGrouped() {
        let title = UsageStats.todayTitle(
            for: UsageStats.Snapshot(today: 123456, week: 0, total: 0))
        #expect(!title.contains("123456"))
    }
}
