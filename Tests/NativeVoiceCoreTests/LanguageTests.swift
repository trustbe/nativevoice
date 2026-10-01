import Testing
@testable import NativeVoiceCore

@Suite struct LanguageTests {

    @Test func offersTheWholeTopAccuracyTier() {
        // 36 languages, the tier ElevenLabs places at 5% WER or better.
        #expect(Language.all.count == 36)
    }

    @Test func keepsTheSmallLanguagesTheProjectExistsFor() {
        // Dropping these would contradict the point of the project: Scribe
        // rates them as accurately as English, and that is the documented
        // difference from every other tool.
        let required = ["bel", "bos", "mkd", "isl", "glg", "lav", "est",
                        "kan", "mal", "ces", "slk", "ukr"]
        for code in required {
            #expect(Language.named(code) != nil, "missing \(code)")
        }
    }

    @Test func codesAreThreeLetterAndUnique() {
        let codes = Language.all.map(\.code)
        #expect(Set(codes).count == codes.count, "duplicate language code")
        for code in codes { #expect(code.count == 3, "not ISO-639-3: \(code)") }
    }

    @Test func everyLanguageHasAName() {
        for language in Language.all {
            #expect(!(language.name.isEmpty), "no name for \(language.code)")
        }
    }

    @Test func systemLanguageIsMatchedFromATwoLetterTag() {
        #expect(Language.forSystem(preferred: ["cs-CZ"]).code == "ces")
        #expect(Language.forSystem(preferred: ["pl"]).code == "pol")
        #expect(Language.forSystem(preferred: ["pt-BR"]).code == "por")
    }

    @Test func unsupportedSystemLanguageFallsBackToEnglish() {
        // Hebrew, Thai and Arabic are not in the top tier. The app must pick
        // English rather than nothing — a user whose system is in an
        // unsupported language still has to be able to dictate.
        #expect(Language.forSystem(preferred: ["he-IL"]).code == "eng")
        #expect(Language.forSystem(preferred: ["th"]).code == "eng")
        #expect(Language.forSystem(preferred: []).code == "eng")
        #expect(Language.forSystem(preferred: ["zz-ZZ"]).code == "eng")
    }

    @Test func firstSupportedPreferenceWins() {
        #expect(Language.forSystem(preferred: ["he-IL", "cs-CZ", "pl"]).code == "ces")
    }

    @Test func displayOrderIsAlphabeticalWithoutFavourites() {
        // No "popular" languages pinned on top. Privileging the big ones
        // would undercut what the project is for.
        let names = Language.sortedForDisplay().map(\.name)
        #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }
}
