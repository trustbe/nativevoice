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
        static let playSounds = "playSounds"
        static let autoPaste = "autoPaste"
        static let removeFillers = "removeFillers"
        static let automaticUpdates = "automaticUpdates"
        static let lastUpdateCheck = "lastUpdateCheck"
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

    /// Two defaults that are not `false`, which is why they read through
    /// `object(forKey:)`: `bool(forKey:)` returns false for an unset key, and
    /// a dictation tool that ships silent and pastes nothing is the opposite
    /// of what someone installing it expects.
    public var playSounds: Bool {
        get { defaults.object(forKey: Key.playSounds) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.playSounds) }
    }

    public var autoPaste: Bool {
        get { defaults.object(forKey: Key.autoPaste) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoPaste) }
    }

    /// Off unless asked for. Filler removal edits what was said, and a tool
    /// that quietly rewrites your words has to be switched on knowingly.
    public var removeFillers: Bool {
        get { defaults.bool(forKey: Key.removeFillers) }
        set { defaults.set(newValue, forKey: Key.removeFillers) }
    }

    /// On unless switched off. An app that can update itself and does not is
    /// one more thing to remember, and the fixes it misses are the ones its
    /// user already hit.
    public var automaticUpdates: Bool {
        get { defaults.object(forKey: Key.automaticUpdates) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.automaticUpdates) }
    }

    public var lastUpdateCheck: Date? {
        get { defaults.object(forKey: Key.lastUpdateCheck) as? Date }
        set { defaults.set(newValue, forKey: Key.lastUpdateCheck) }
    }
}
