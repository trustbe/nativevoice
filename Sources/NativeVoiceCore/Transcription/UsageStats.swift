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

    /// The disabled row at the top of the menu. No unit is named: what the
    /// STT series counts is not established here, and a wrong unit is worse
    /// than none.
    public static func menuTitle(for snapshot: Snapshot?) -> String {
        guard let snapshot else {
            return String(localized: "Dictation: loading…", bundle: .module)
        }
        func grouped(_ value: Int) -> String {
            formatter.string(from: NSNumber(value: value)) ?? String(value)
        }
        return String(localized: """
            Dictation: \(grouped(snapshot.today)) today · \
            \(grouped(snapshot.week)) this week · \
            \(grouped(snapshot.total)) total
            """, bundle: .module)
    }
}
