import Foundation

/// What the ElevenLabs account has spent this billing period.
///
/// Parsing is kept apart from fetching so the arithmetic can be tested
/// without a network or a key.
///
/// There was a second source here, a daily breakdown, and its figures could
/// not be reconciled with these: our own log showed three recordings totalling
/// twelve seconds on a day it reported as 13, where this counter would put
/// that near 66. A number nobody can name the unit of is worse than no number,
/// so only the billing counter is read.
public enum UsageStats {

    /// The account's quota for the current billing period.
    ///
    /// This is the number the bill is based on, which is why it is read from
    /// the subscription rather than summed out of the daily buckets: those
    /// cover the last N days, and a billing period does not start N days ago.
    ///
    /// ElevenLabs' API calls the unit "characters" and its pricing page calls
    /// it credits. They are the same counter; the menu says credits, because
    /// that is the word on the page where the money is.
    public struct Subscription: Equatable, Sendable {
        public let used: Int
        public let limit: Int
        public let resetsAt: Date?

        public init(used: Int, limit: Int, resetsAt: Date?) {
            self.used = used
            self.limit = limit
            self.resetsAt = resetsAt
        }
    }

    public static func subscription(from json: Data) -> Subscription? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let used = object["character_count"] as? Int,
              let limit = object["character_limit"] as? Int
        else { return nil }
        // Nullable in the API, and absent on plans that do not reset.
        let reset = (object["next_character_count_reset_unix"] as? Double)
            .map { Date(timeIntervalSince1970: $0) }
        return Subscription(used: used, limit: limit, resetsAt: reset)
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    static func grouped(_ value: Int) -> String {
        formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// The usage row: the billing period against its limit, which is the only
    /// form in which a number of credits means anything.
    public static func periodTitle(for subscription: Subscription?,
                                   now: Date = Date()) -> String {
        guard let subscription else {
            return String(localized: "This billing period: loading…", bundle: .module)
        }
        let used = grouped(subscription.used)
        let limit = grouped(subscription.limit)

        guard let resetsAt = subscription.resetsAt, resetsAt > now else {
            return String(localized: "This billing period: \(used) of \(limit) credits",
                          bundle: .module)
        }
        // Rounded up, so "resets in 1 day" never means "in four minutes".
        let days = Int((resetsAt.timeIntervalSince(now) / 86_400).rounded(.up))
        if days <= 1 {
            return String(localized: "This billing period: \(used) of \(limit) credits · resets tomorrow",
                          bundle: .module)
        }
        return String(localized: "This billing period: \(used) of \(limit) credits · resets in \(days) days",
                      bundle: .module)
    }
}
