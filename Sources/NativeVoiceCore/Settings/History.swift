import Foundation

/// The last few transcripts, so text can be put back on the clipboard after
/// it was overwritten or pasted into the wrong window.
///
/// **Off by default, and deliberately.** Keeping history means dictated text —
/// passwords, addresses, anything else — sits in unencrypted preferences.
/// Whoever wants that can switch it on knowingly. It must not happen to
/// anyone by itself.
///
/// Only text is kept. Audio is discarded as soon as it has been transcribed,
/// and that does not change here.
public final class History {
    private let defaults: UserDefaults

    private enum Key {
        static let items = "historyItems"
        static let enabled = "historyEnabled"
        static let limit = "historyLimit"
    }

    /// How many entries can be kept. Offering a list rather than a number
    /// keeps the menu honest about what it will do.
    public static let limitChoices = [5, 10, 20, 50]
    public static let defaultLimit = 20

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set {
            defaults.set(newValue, forKey: Key.enabled)
            // Switching off has to delete, not just stop adding.
            if !newValue { clear() }
        }
    }

    public var limit: Int {
        get {
            let stored = defaults.integer(forKey: Key.limit)
            return Self.limitChoices.contains(stored) ? stored : Self.defaultLimit
        }
        set {
            // A value from outside the offered list is someone else's idea,
            // not a choice this app made. It is refused rather than stored.
            guard Self.limitChoices.contains(newValue) else { return }
            defaults.set(newValue, forKey: Key.limit)
            trim()
        }
    }

    /// Newest first.
    public var items: [String] {
        defaults.stringArray(forKey: Key.items) ?? []
    }

    public func record(_ text: String) {
        guard isEnabled else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var all = items
        all.insert(trimmed, at: 0)
        defaults.set(Array(all.prefix(limit)), forKey: Key.items)
    }

    public func clear() {
        defaults.removeObject(forKey: Key.items)
    }

    private func trim() {
        let all = items
        guard all.count > limit else { return }
        defaults.set(Array(all.prefix(limit)), forKey: Key.items)
    }

    /// Shortened for a menu row. A newline would break the row, so lines are
    /// joined with a space.
    public static func menuTitle(for text: String, max: Int = 48) -> String {
        let flat = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return flat.count <= max ? flat : String(flat.prefix(max - 1)) + "…"
    }
}
