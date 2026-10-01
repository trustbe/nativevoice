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
        #expect(UsageStats.menuTitle(for: nil).contains("…"))
    }

    @Test func largeNumbersAreGroupedToStayReadable() {
        let title = UsageStats.menuTitle(
            for: UsageStats.Snapshot(today: 1234, week: 56789, total: 1_234_567))
        #expect(!title.contains("1234"))
        #expect(title.contains("today"))
    }
}
