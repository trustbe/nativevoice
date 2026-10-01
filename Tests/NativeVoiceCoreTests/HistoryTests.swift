import Foundation
import Testing
@testable import NativeVoiceCore

@Suite struct HistoryTests {

    private func makeHistory() -> History {
        History(defaults: UserDefaults(suiteName: "nativevoice-tests-\(UUID().uuidString)")!)
    }

    @Test func nothingIsRememberedUntilItIsSwitchedOn() {
        let history = makeHistory()
        #expect(!history.isEnabled)
        history.record("something private")
        #expect(history.items.isEmpty)
    }

    @Test func newestComesFirst() {
        let history = makeHistory()
        history.isEnabled = true
        history.record("first")
        history.record("second")
        #expect(history.items == ["second", "first"])
    }

    @Test func blankTextIsNotWorthRemembering() {
        let history = makeHistory()
        history.isEnabled = true
        history.record("   \n  ")
        #expect(history.items.isEmpty)
    }

    @Test func textIsStoredTrimmed() {
        let history = makeHistory()
        history.isEnabled = true
        history.record("  hello  ")
        #expect(history.items == ["hello"])
    }

    @Test func theOldestFallOffAtTheLimit() {
        let history = makeHistory()
        history.isEnabled = true
        history.limit = 5
        for index in 1...7 { history.record("line \(index)") }
        #expect(history.items.count == 5)
        #expect(history.items.first == "line 7")
        #expect(history.items.last == "line 3")
    }

    @Test func loweringTheLimitTrimsWhatIsAlreadyThere() {
        let history = makeHistory()
        history.isEnabled = true
        history.limit = 20
        for index in 1...12 { history.record("line \(index)") }
        history.limit = 5
        #expect(history.items.count == 5)
    }

    @Test func switchingOffDeletesWhatWasStored() {
        // A toggle that only stops adding, and leaves the old entries lying
        // in unencrypted preferences, promises something it does not do.
        let history = makeHistory()
        history.isEnabled = true
        history.record("a password, probably")
        history.isEnabled = false
        #expect(history.items.isEmpty)
    }

    @Test func aLimitThatIsNotOnOfferIsRefused() {
        // Review Focus 2: a hand-edited preferences file, or a list that
        // changed between versions, must not freeze the menu or store junk.
        let history = makeHistory()
        history.limit = 7
        #expect(history.limit == History.defaultLimit)
    }

    @Test func aStoredLimitOutsideTheChoicesFallsBack() {
        let defaults = UserDefaults(suiteName: "nativevoice-tests-\(UUID().uuidString)")!
        defaults.set(999, forKey: "historyLimit")
        #expect(History(defaults: defaults).limit == History.defaultLimit)
    }

    @Test func aMenuTitleIsOneLine() {
        let title = History.menuTitle(for: "first line\n\nsecond line")
        #expect(title == "first line second line")
    }

    @Test func aLongMenuTitleIsCut() {
        let title = History.menuTitle(for: String(repeating: "a", count: 80), max: 10)
        #expect(title.count == 10)
        #expect(title.hasSuffix("…"))
    }
}
