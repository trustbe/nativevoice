import Foundation
import Testing
@testable import NativeVoiceCore

@Suite struct PreferencesTests {

    /// Each test gets its own suite name so they cannot see each other's
    /// values, and so none of them touches the real app's settings.
    private func makePreferences() -> Preferences {
        let name = "nativevoice-tests-\(UUID().uuidString)"
        return Preferences(defaults: UserDefaults(suiteName: name)!)
    }

    @Test func languageDefaultsToTheSystemUntilSomethingIsChosen() {
        let preferences = makePreferences()
        #expect(!(preferences.hasChosenLanguage))
        #expect(preferences.language == Language.forSystem())
    }

    @Test func aChosenLanguageIsRemembered() {
        let preferences = makePreferences()
        preferences.language = Language.named("ces")!
        #expect(preferences.hasChosenLanguage)
        #expect(preferences.language.code == "ces")
    }

    @Test func aChosenLanguageSurvivesANewInstance() {
        let name = "nativevoice-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        Preferences(defaults: defaults).language = Language.named("pol")!
        #expect(Preferences(defaults: defaults).language.code == "pol")
    }

    @Test func anUnknownStoredLanguageFallsBackToTheSystem() {
        // A code that no longer exists — a tier change, or a hand-edited
        // defaults file. Freezing on it would transcribe in a language the
        // user cannot pick any more and cannot see why.
        let name = "nativevoice-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set("xyz", forKey: "languageCode")
        #expect(Preferences(defaults: defaults).language == Language.forSystem())
    }

    @Test func triggerKeyDefaultsToRightCommand() {
        #expect(makePreferences().triggerKey == .rightCommand)
    }

    @Test func aChosenTriggerKeyIsRemembered() {
        let preferences = makePreferences()
        preferences.triggerKey = .leftOption
        #expect(preferences.triggerKey == .leftOption)
    }

    @Test func anUnknownStoredTriggerKeyFallsBackToTheDefault() {
        let name = "nativevoice-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set("middleCommand", forKey: "triggerKey")
        #expect(Preferences(defaults: defaults).triggerKey == .rightCommand)
    }

    @Test func recordingLimitDefaultsToTwoMinutes() {
        #expect(makePreferences().recordingLimit == .twoMinutes)
    }

    @Test func noLimitIsARealChoiceAndSurvives() {
        // Zero is a deliberate choice, not an absent value. Reading it as
        // "unset" would quietly re-impose a cap the user turned off.
        let name = "nativevoice-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        Preferences(defaults: defaults).recordingLimit = RecordingLimit.none
        #expect(Preferences(defaults: defaults).recordingLimit == RecordingLimit.none)
    }

    @Test func anUnknownStoredLimitFallsBackToTheDefault() {
        let name = "nativevoice-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(999, forKey: "recordingLimitSeconds")
        #expect(Preferences(defaults: defaults).recordingLimit == .twoMinutes)
    }

    @Test func soundsAndPastingAreOnBeforeAnyoneChoosesAnything() {
        let preferences = makePreferences()
        #expect(preferences.playSounds)
        #expect(preferences.autoPaste)
    }

    @Test func fillerRemovalIsOffBeforeAnyoneChoosesIt() {
        // It changes what you said. Someone dictating a commit message or a
        // filing wants their own words back.
        #expect(!makePreferences().removeFillers)
    }

    @Test func soundsCanBeTurnedOff() {
        // The one that catches the real mistake: `defaults.bool(forKey:)`
        // cannot tell "off" from "never set", so a default of true written
        // that way ignores this.
        let preferences = makePreferences()
        preferences.playSounds = false
        #expect(!preferences.playSounds)
    }

    @Test func pastingCanBeTurnedOff() {
        let preferences = makePreferences()
        preferences.autoPaste = false
        #expect(!preferences.autoPaste)
    }

    @Test func togglesSurviveANewInstance() {
        let name = "nativevoice-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let first = Preferences(defaults: defaults)
        first.playSounds = false
        first.removeFillers = true
        let second = Preferences(defaults: defaults)
        #expect(!second.playSounds)
        #expect(second.removeFillers)
    }
}
