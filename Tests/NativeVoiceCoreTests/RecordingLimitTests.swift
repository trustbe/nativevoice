import Testing
@testable import NativeVoiceCore

@Suite struct RecordingLimitTests {

    @Test func defaultIsTwoMinutes() {
        #expect(RecordingLimit.default == .twoMinutes)
        #expect(RecordingLimit.default.seconds == 120)
    }

    @Test func noLimitMeansNoDeadline() {
        #expect(RecordingLimit.none.seconds == nil)
    }

    @Test func everyChoiceHasSecondsExceptNone() {
        for limit in RecordingLimit.allCases where limit != .none {
            #expect(limit.seconds != nil, "\(limit)")
            #expect(limit.seconds! > 0)
        }
    }

    @Test func unknownStoredValueFallsBackToTheDefault() {
        #expect(RecordingLimit(storedSeconds: 999) == .default)
        #expect(RecordingLimit(storedSeconds: -1) == .default)
    }

    @Test func storedZeroMeansNoLimitAndIsNotMistakenForMissing() {
        // Zero is a real choice here, not an absent one. Reading it as
        // "unset" would quietly re-impose a cap the user turned off.
        #expect(RecordingLimit(storedSeconds: 0) == RecordingLimit.none)
    }

    @Test func roundTripsThroughItsStoredValue() {
        for limit in RecordingLimit.allCases {
            #expect(RecordingLimit(storedSeconds: limit.rawValue) == limit)
        }
    }
}
