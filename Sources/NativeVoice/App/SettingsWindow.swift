import AppKit
import NativeVoiceCore

/// The settings, in a window of their own.
///
/// They could have gone in the menu, and in this project's predecessor they
/// did — where the menu grew to eight controls and stopped being a menu. The
/// guidelines are right about this one: a menu is for actions and state, and
/// settings belong behind ⌘,.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let preferences: Preferences
    private let secrets: SecretStore
    /// Called after anything changes, so the app can pick the new value up
    /// without waiting for a restart.
    private let onChange: () -> Void

    private let keyField = NSSecureTextField()
    private let keyStatus = NSTextField(labelWithString: "")
    private let languagePopUp = NSPopUpButton()
    private let triggerPopUp = NSPopUpButton()
    private let limitPopUp = NSPopUpButton()

    private let languages = Language.sortedForDisplay()

    init(preferences: Preferences, secrets: SecretStore, onChange: @escaping () -> Void) {
        self.preferences = preferences
        self.secrets = secrets
        self.onChange = onChange
        super.init()
    }

    func show() {
        if window == nil { build() }
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.center()
    }

    // MARK: - Building

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = String(localized: "NativeVoice Settings", bundle: .module)
        w.isReleasedWhenClosed = false
        w.delegate = self

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // API key
        stack.addArrangedSubview(heading(String(localized: "ElevenLabs API key",
                                                bundle: .module)))
        keyField.placeholderString = "sk_…"
        keyField.target = self
        keyField.action = #selector(saveKey)
        keyField.widthAnchor.constraint(equalToConstant: 420).isActive = true
        stack.addArrangedSubview(keyField)

        keyStatus.font = .systemFont(ofSize: 11)
        keyStatus.textColor = .secondaryLabelColor
        stack.addArrangedSubview(keyStatus)

        let links = NSTextField(labelWithString: "")
        links.attributedStringValue = keyLinks()
        links.isSelectable = true
        links.allowsEditingTextAttributes = true    // without this the link is dead
        stack.addArrangedSubview(links)

        stack.addArrangedSubview(separator())

        // Language
        stack.addArrangedSubview(heading(String(localized: "Transcription language",
                                                bundle: .module)))
        languagePopUp.target = self
        languagePopUp.action = #selector(chooseLanguage)
        for language in languages { languagePopUp.addItem(withTitle: language.name) }
        stack.addArrangedSubview(languagePopUp)

        // Trigger key
        stack.addArrangedSubview(heading(String(localized: "Trigger key", bundle: .module)))
        triggerPopUp.target = self
        triggerPopUp.action = #selector(chooseTriggerKey)
        for key in TriggerKey.allCases { triggerPopUp.addItem(withTitle: key.menuTitle) }
        stack.addArrangedSubview(triggerPopUp)

        // Recording limit
        stack.addArrangedSubview(heading(String(localized: "Maximum recording length",
                                                bundle: .module)))
        limitPopUp.target = self
        limitPopUp.action = #selector(chooseLimit)
        for limit in RecordingLimit.allCases { limitPopUp.addItem(withTitle: limit.menuTitle) }
        stack.addArrangedSubview(limitPopUp)

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
        ])
        w.contentView = content
        window = w
    }

    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 420).isActive = true
        return box
    }

    private func keyLinks() -> NSAttributedString {
        let out = NSMutableAttributedString()
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        attributes[.link] = "https://elevenlabs.io/app/settings/api-keys"
        out.append(NSAttributedString(
            string: String(localized: "Get a key", bundle: .module),
            attributes: attributes))
        return out
    }

    // MARK: - State

    private func refresh() {
        // The field is never filled with the stored key. Showing a secret
        // because the user opened a window is not a thing to do, and an app
        // whose argument is that you can audit what happens to your key should
        // not put it on screen unasked.
        keyField.stringValue = ""
        keyStatus.stringValue = secrets.hasKey
            ? String(localized: "A key is stored. Type a new one to replace it, or leave empty and press Return to remove it.",
                     bundle: .module)
            : String(localized: "No key yet. Dictation will not work until one is set.",
                     bundle: .module)

        if let index = languages.firstIndex(of: preferences.language) {
            languagePopUp.selectItem(at: index)
        }
        if let index = TriggerKey.allCases.firstIndex(of: preferences.triggerKey) {
            triggerPopUp.selectItem(at: index)
        }
        if let index = RecordingLimit.allCases.firstIndex(of: preferences.recordingLimit) {
            limitPopUp.selectItem(at: index)
        }
    }

    // MARK: - Actions

    @objc private func saveKey() {
        let entered = keyField.stringValue
        // Empty removes. There is no second place a removed key can come back
        // from, and that is deliberate.
        if secrets.save(entered) {
            appLog(entered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                   ? "API key removed" : "API key saved")
        } else {
            appLog("API key could not be saved")
        }
        keyField.stringValue = ""
        refresh()
        onChange()
    }

    @objc private func chooseLanguage() {
        let index = languagePopUp.indexOfSelectedItem
        guard languages.indices.contains(index) else { return }
        preferences.language = languages[index]
        appLog("transcription language: \(languages[index].code)")
        onChange()
    }

    @objc private func chooseTriggerKey() {
        let index = triggerPopUp.indexOfSelectedItem
        let all = TriggerKey.allCases
        guard all.indices.contains(index) else { return }
        preferences.triggerKey = all[index]
        appLog("trigger key: \(all[index].rawValue)")
        onChange()
    }

    @objc private func chooseLimit() {
        let index = limitPopUp.indexOfSelectedItem
        let all = RecordingLimit.allCases
        guard all.indices.contains(index) else { return }
        preferences.recordingLimit = all[index]
        appLog("maximum recording length: \(all[index].menuTitle)")
        onChange()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Nothing should outlive the window holding a half-typed secret.
        keyField.stringValue = ""
    }
}
