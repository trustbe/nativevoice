import Foundation

/// The settings the user can change, and what they are before anyone has.
///
/// `UserDefaults` is injected so tests can use a throwaway suite. A test that
/// wrote into the real domain would change the settings of the app running on
/// the same machine — which, on a developer's own Mac, is the app they are
/// about to try the change in.
public final class Preferences {
    private let defaults: UserDefaults

    private enum Key {
        static let language = "languageCode"
        static let triggerKey = "triggerKey"
        static let recordingLimit = "recordingLimitSeconds"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether a language was ever chosen explicitly. The menu uses it to tell
    /// "English because the system is English" from "English because I picked
    /// it" — the first should follow the system if that changes, the second
    /// should not.
    public var hasChosenLanguage: Bool {
        defaults.string(forKey: Key.language) != nil
    }

    public var language: Language {
        get {
            // An unknown stored code falls back rather than freezing. A tier
            // change or a hand-edited defaults file would otherwise leave the
            // app transcribing in a language the user can no longer pick and
            // cannot see the reason for.
            guard let code = defaults.string(forKey: Key.language),
                  let known = Language.named(code) else {
                return Language.forSystem()
            }
            return known
        }
        set { defaults.set(newValue.code, forKey: Key.language) }
    }

    public var triggerKey: TriggerKey {
        get {
            guard let raw = defaults.string(forKey: Key.triggerKey),
                  let key = TriggerKey(rawValue: raw) else { return .default }
            return key
        }
        set { defaults.set(newValue.rawValue, forKey: Key.triggerKey) }
    }

    public var recordingLimit: RecordingLimit {
        get {
            // Zero means "no limit" and is a real choice, so absence has to be
            // distinguished from a stored zero.
            guard defaults.object(forKey: Key.recordingLimit) != nil else {
                return .default
            }
            return RecordingLimit(storedSeconds: defaults.integer(forKey: Key.recordingLimit))
        }
        set { defaults.set(newValue.rawValue, forKey: Key.recordingLimit) }
    }
}
