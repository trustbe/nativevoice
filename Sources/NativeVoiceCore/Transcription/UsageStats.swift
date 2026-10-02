import Foundation

/// How much has been transcribed, from ElevenLabs' own accounting.
///
/// Parsing is kept apart from fetching so the arithmetic can be tested
/// without a network or a key.
public enum UsageStats {

    public struct Snapshot: Equatable, Sendable {
        public let today: Int
        public let week: Int
        public let total: Int

        public init(today: Int, week: Int, total: Int) {
            self.today = today
            self.week = week
            self.total = total
        }
    }

    /// `time` is a list of bucket timestamps in milliseconds; `usage.STT` is
    /// the figure for each bucket.
    ///
    /// The two lists are trusted only as far as the shorter one. The version
    /// this was ported from walked `time` and indexed into the series, which
    /// takes the process down the first time the server answers with one more
    /// timestamp than it has numbers.
    public static func snapshot(from json: Data, now: Date = Date()) -> Snapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let times = object["time"] as? [Double],
              let usage = object["usage"] as? [String: [Double]]
        else { return nil }

        let series = usage["STT"] ?? []
        let overlap = min(times.count, series.count)
        let nowMilliseconds = now.timeIntervalSince1970 * 1000

        func sum(withinDays days: Double?) -> Int {
            var total = 0.0
            for index in 0..<overlap {
                if let days, times[index] < nowMilliseconds - days * 86_400_000 { continue }
                total += series[index]
            }
            return Int(total)
        }

        return Snapshot(today: sum(withinDays: 1),
                        week: sum(withinDays: 7),
                        total: sum(withinDays: nil))
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

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

    static func grouped(_ value: Int) -> String {
        formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// The first usage row: what today has cost.
    public static func todayTitle(for snapshot: Snapshot?) -> String {
        guard let snapshot else {
            return String(localized: "Today: loading…", bundle: .module)
        }
        return String(localized: "Today: \(grouped(snapshot.today)) credits", bundle: .module)
    }

    /// The second: the billing period, against its limit, which is the only
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
