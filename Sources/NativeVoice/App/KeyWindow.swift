import AppKit
import NativeVoiceCore

/// The one window this app has, and it holds one thing.
///
/// It used to be a Settings window carrying the language, the trigger key and
/// the recording cap as well — all three of which are in the menu, where they
/// are one click away instead of three. Somebody who opened it to paste a key
/// had to read past settings they had not come for, and a change made in one
/// place looked like it had not taken in the other.
///
/// Everything the app does is now in the menu. This is here because a long
/// secret has to be pasted somewhere, and a menu cannot take one.
@MainActor
final class KeyWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let secrets: SecretStore
    private let onChange: () -> Void

    private let field = NSTextField()
    private let status = NSTextField(labelWithString: "")
    private let counter = NSTextField(labelWithString: "")
    private var removeButton: NSButton?

    private static let keysPage = "https://elevenlabs.io/app/settings/api-keys"

    init(secrets: SecretStore, onChange: @escaping () -> Void) {
        self.secrets = secrets
        self.onChange = onChange
        super.init()
    }

    func show() {
        if window == nil { build() }
        refresh()
        // Order matters. Activating after ordering front leaves the window up
        // with another app's menu bar above it, which on a menu bar app is
        // indistinguishable from the app having no menus at all.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(field)
    }

    private func build() {
        let w = EscapableWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 220),
                                styleMask: [.titled, .closable],
                                backing: .buffered, defer: false)
        w.title = String(localized: "ElevenLabs API Key", bundle: .module)
        w.isReleasedWhenClosed = false
        w.delegate = self

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 22, bottom: 22, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let intro = NSTextField(wrappingLabelWithString: String(
            localized: """
            NativeVoice sends your audio to ElevenLabs to be transcribed, using \
            your key. They bill you directly for what you dictate.
            """, bundle: .module))
        intro.font = .systemFont(ofSize: 12)
        intro.textColor = .secondaryLabelColor
        // Matched to the row below it, and pinned, so the window takes its
        // width from the field rather than from however this sentence happens
        // to wrap — at 416 it was running off the right edge.
        intro.preferredMaxLayoutWidth = 392
        intro.widthAnchor.constraint(equalToConstant: 392).isActive = true
        stack.addArrangedSubview(intro)

        field.placeholderString = "sk_…"
        field.target = self
        field.action = #selector(saveKey)
        field.delegate = self
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        let save = NSButton(title: String(localized: "Save", bundle: .module),
                            target: self, action: #selector(saveKey))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"

        let row = NSStackView(views: [field, save])
        row.orientation = .horizontal
        row.spacing = 8
        field.widthAnchor.constraint(equalToConstant: 320).isActive = true
        stack.addArrangedSubview(row)

        // What you pasted, counted. A key is 50-odd opaque characters and a
        // field 320 points wide cannot show all of one — without this there is
        // no way to tell a whole key from one that lost its tail to a bad copy.
        counter.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        counter.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(counter)

        status.font = .boldSystemFont(ofSize: 11)
        stack.addArrangedSubview(status)

        let remove = NSButton(title: String(localized: "Remove key", bundle: .module),
                              target: self, action: #selector(removeKey))
        remove.bezelStyle = .inline
        remove.controlSize = .small
        removeButton = remove
        stack.addArrangedSubview(remove)

        stack.addArrangedSubview(LinkButton(
            title: String(localized: "How to get a key", bundle: .module),
            url: Self.keysPage))

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        w.contentView = content
        w.setContentSize(content.fittingSize)
        window = w
    }

    private func refresh() {
        // The field is never filled with the stored key. Showing a secret
        // because somebody opened a window is not a thing to do, and an app
        // whose argument is that you can audit what happens to your key should
        // not put it on screen unasked.
        field.stringValue = ""
        updateCounter()

        if secrets.hasKey {
            status.stringValue = String(
                localized: "\u{2713} A key is stored. Paste a new one to replace it.",
                bundle: .module)
            status.textColor = .systemGreen
        } else {
            status.stringValue = String(
                localized: "No key yet. Dictation will not work until one is set.",
                bundle: .module)
            status.textColor = .secondaryLabelColor
        }
        removeButton?.isHidden = !secrets.hasKey
    }

    private func updateCounter() {
        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { counter.stringValue = " "; return }
        counter.stringValue = String(
            localized: "\(typed.count) characters pasted", bundle: .module)
    }

    @objc private func saveKey() {
        let entered = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entered.isEmpty else { return }     // Remove has its own button
        if secrets.save(entered) {
            appLog("API key saved")
        } else {
            appLog("API key could not be saved")
        }
        field.stringValue = ""
        refresh()
        onChange()
    }

    @objc private func removeKey() {
        // A button of its own. Removing by clearing a field and pressing
        // Return is a thing you have to be told, and nobody reads the thing
        // that tells you.
        secrets.delete()
        appLog("API key removed")
        field.stringValue = ""
        refresh()
        onChange()
    }

    func windowWillClose(_ notification: Notification) {
        // Nothing should outlive the window holding a half-typed secret.
        field.stringValue = ""
        // Back to being a menu bar app: no Dock icon, no menu bar of its own.
        NSApp.setActivationPolicy(.accessory)
    }
}

extension KeyWindow: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        updateCounter()
    }
}

/// A window that closes on Escape.
///
/// `NSWindow` routes Escape to `cancelOperation(_:)` and does nothing with it
/// unless something answers. Every other window on the Mac shuts on Escape, so
/// one that does not feels stuck.
final class EscapableWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}

/// A link that looks and behaves like one.
///
/// As an `NSTextField` with a `.link` attribute it opened the page when
/// clicked, but drew in the same grey as the text above it and left the
/// pointer an arrow, so nothing said it could be clicked. `resetCursorRects`
/// is what puts the pointing hand there; a text field never gets one.
final class LinkButton: NSButton {
    private let url: URL?

    init(title: String, url: String) {
        self.url = URL(string: url)
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .inline
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        target = self
        action = #selector(open)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    @objc private func open() {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
