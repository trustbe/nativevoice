import Foundation
import Testing
@testable import NativeVoiceCore

@Suite struct LevelHistoryTests {

    @Test func startsFlatAndSilent() {
        let history = LevelHistory(samples: 8)
        #expect(history.values.count == 8)
        #expect(history.values.allSatisfy { $0 == 0 })
        #expect(history.isSilent)
    }

    @Test func newestValueArrivesAtTheEnd() {
        var history = LevelHistory(samples: 4)
        history.push(decibels: -20)
        #expect(history.values.last! > 0)
        #expect(history.values.first! == 0)
    }

    @Test func historyScrollsAndKeepsItsLength() {
        var history = LevelHistory(samples: 4)
        for db in [Float(-60), -50, -40, -30, -20] { history.push(decibels: db) }
        #expect(history.values.count == 4)
        // Louder later, so the series must be increasing across the window.
        #expect(history.values == history.values.sorted())
    }

    @Test func silenceStaysNearZeroWithoutGoingNegative() {
        var history = LevelHistory(samples: 4)
        for _ in 0..<10 { history.push(decibels: -120) }
        #expect(history.values.allSatisfy { $0 >= 0 && $0 < 0.05 })
        #expect(history.isSilent)
    }

    @Test func loudInputIsClampedToOne() {
        var history = LevelHistory(samples: 4)
        for _ in 0..<10 { history.push(decibels: 20) }
        #expect(history.values.allSatisfy { $0 <= 1 })
        #expect(history.values.last! > 0.9)
    }

    @Test func aQuietMicrophoneStillMoves() {
        // The ceiling follows recent peaks, so speech on a quiet input is not
        // flattened to nothing. Measured on a real microphone at -69 dB once,
        // and a meter that showed a flat line there would be lying — it was
        // picking up something, just very little.
        var history = LevelHistory(samples: 16)
        for _ in 0..<40 { history.push(decibels: -62) }   // settle the ceiling
        for _ in 0..<8 { history.push(decibels: -52) }    // quiet speech
        #expect(history.values.last! > 0.15)
    }

    @Test func theCeilingDoesNotRunAwayAfterOneLoudPeak() {
        var history = LevelHistory(samples: 8)
        history.push(decibels: 0)                         // a door slam
        for _ in 0..<60 { history.push(decibels: -40) }   // back to speech
        #expect(history.values.last! > 0.2)
    }

    @Test func silenceIsReportedSeparatelyFromTheCurve() {
        // The panel shows a flat line for silence rather than hiding, so the
        // caller needs to know it is silence without inspecting the samples.
        var history = LevelHistory(samples: 4)
        for _ in 0..<10 { history.push(decibels: -70) }
        #expect(history.isSilent)
        history.push(decibels: -30)
        #expect(!(history.isSilent))
    }

    @Test func resetReturnsItToFlat() {
        var history = LevelHistory(samples: 4)
        for _ in 0..<10 { history.push(decibels: -10) }
        history.reset()
        #expect(history.values.allSatisfy { $0 == 0 })
        #expect(history.isSilent)
    }
}
