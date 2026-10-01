import Foundation

/// A transcription language.
///
/// The list is Scribe's top accuracy tier — the 36 languages the provider
/// places at 5% word error rate or better. It is **not narrowed**. Belarusian,
/// Bosnian, Macedonian, Icelandic, Galician, Latvian, Estonian, Kannada and
/// Malayalam are in it, which is precisely why this project exists: a small
/// language rated as accurately as English is the documented difference from
/// every other tool. Dropping them to keep the menu short would contradict
/// the product.
///
/// Tiers below this one (High to 10%, Good to 20%, Moderate to 50%) are not
/// offered. Dictation with one word in five wrong is not usable, and offering
/// it would promise something it cannot carry.
public struct Language: Equatable, Hashable {
    /// ISO-639-3. The API accepts both 639-1 and 639-3; the longer form is
    /// unambiguous.
    public let code: String
    /// Shown in the menu, localized by the system where a translation exists.
    public var name: String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized
            ?? fallbackName
    }
    private let fallbackName: String

    init(_ code: String, _ fallbackName: String) {
        self.code = code
        self.fallbackName = fallbackName
    }

    public static let all: [Language] = [
        Language("bel", "Belarusian"),   Language("bos", "Bosnian"),
        Language("bul", "Bulgarian"),    Language("cat", "Catalan"),
        Language("hrv", "Croatian"),     Language("ces", "Czech"),
        Language("dan", "Danish"),       Language("nld", "Dutch"),
        Language("eng", "English"),      Language("est", "Estonian"),
        Language("fin", "Finnish"),      Language("fra", "French"),
        Language("glg", "Galician"),     Language("deu", "German"),
        Language("ell", "Greek"),        Language("hun", "Hungarian"),
        Language("isl", "Icelandic"),    Language("ind", "Indonesian"),
        Language("ita", "Italian"),      Language("jpn", "Japanese"),
        Language("kan", "Kannada"),      Language("lav", "Latvian"),
        Language("mkd", "Macedonian"),   Language("msa", "Malay"),
        Language("mal", "Malayalam"),    Language("nor", "Norwegian"),
        Language("pol", "Polish"),       Language("por", "Portuguese"),
        Language("ron", "Romanian"),     Language("rus", "Russian"),
        Language("slk", "Slovak"),       Language("spa", "Spanish"),
        Language("swe", "Swedish"),      Language("tur", "Turkish"),
        Language("ukr", "Ukrainian"),    Language("vie", "Vietnamese"),
    ]

    public static let english = Language("eng", "English")

    public static func named(_ code: String) -> Language? {
        all.first { $0.code == code }
    }

    /// Alphabetical by display name, with **no favourites pinned on top**.
    /// Putting the big languages first would weaken what the list says.
    public static func sortedForDisplay() -> [Language] {
        all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// First preferred system language that Scribe transcribes well.
    ///
    /// Falls back to English, never to nothing: a user whose system runs in
    /// Hebrew or Thai — neither is in the top tier — still has to be able to
    /// dictate the moment the app starts.
    public static func forSystem(preferred: [String] = Locale.preferredLanguages) -> Language {
        for tag in preferred {
            guard let short = tag.split(separator: "-").first.map(String.init) else { continue }
            if let match = all.first(where: {
                Locale(identifier: $0.code).language.languageCode?.identifier == short
                    || $0.code == short
            }) {
                return match
            }
        }
        return english
    }
}
