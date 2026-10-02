import Foundation
import Testing
@testable import NativeVoiceCore

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
    }

    @Test func largeNumbersAreGrouped() {
        let title = UsageStats.periodTitle(
            for: UsageStats.Subscription(used: 123456, limit: 200000, resetsAt: nil), now: now)
        #expect(!title.contains("123456"))
    }
}
