import AppKit
import AVFoundation
import NativeVoiceCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum State { case idle, recording, transcribing }

    private static let homepage = "https://github.com/trustbe/nativevoice"
    private static let donate = "https://buymeacoffee.com/jenicek666"

    private var statusItem: NSStatusItem!
    private let recorder = Recorder()
    private let hud = HUD()
    private let secrets = KeychainSecretStore()
    private lazy var transcriber: Transcriber = ElevenLabsClient(secrets: secrets)
    private let clipboardRestore = ClipboardRestore()
    private let preferences = Preferences()
    private lazy var settings = SettingsWindow(
        preferences: preferences, secrets: secrets) { [weak self] in
            self?.applyPreferences()
        }

    /// The most recent transcript, kept so it can be recovered.
    ///
    /// Pasting goes into whatever is under the cursor. When nothing there
    /// takes text the ⌘V lands nowhere, and 1.2 s later the clipboard is
    /// restored and the transcript is gone — six seconds of speech for
    /// nothing. It happened on the first real use of the app.
    ///
    /// In memory only. Dictated text is not written anywhere; recovering it
    /// is worth a menu item, not a file on disk.
    private var lastTranscript: String?

    private var tap: EventTap?
    private var tapIsRunning = false
    private var hold = HoldTracker(key: .default)
    private let history = History()
    private var usageSnapshot: UsageStats.Snapshot?
    private weak var usageMenuItem: NSMenuItem?
    private var usageFetchedAt: Date?
    private var state: State = .idle {
        didSet {
            updateStatusIcon()
            switch state {
            case .recording:    hud.showRecording()
            case .transcribing: hud.showTranscribing()
            case .idle:         hud.hide()
            }
            // A hold that began while the previous utterance was still being
            // transcribed waits here rather than being thrown away.
            if state == .idle, startWhenIdle {
                startWhenIdle = false
                if hold.isHolding { startRecording() }
            }
        }
    }

    /// Set when the hold threshold passed but the app was still busy with the
    /// previous utterance. Dictating sentence after sentence is the normal way
    /// to use this app, and a network round trip routinely outlasts the 0.4 s
    /// threshold — so without this the second sentence is dropped in silence,
    /// which is how a dictation tool earns the reputation of "sometimes it
    /// just doesn't work".
    private var startWhenIdle = false

    /// A press shorter than this is a shortcut, not dictation. The tap does
    /// not see ordinary keys, so it cannot tell that ⌘C used the same key —
    /// the threshold is what keeps a quick shortcut from starting a recording.
    private let holdThreshold: TimeInterval = 0.4
    private var pendingStart: DispatchWorkItem?
    private var limitWork: DispatchWorkItem?
    private var audioURL: URL?
    private var startedAt = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.shared.rotateIfNeeded()
        Vocabulary.ensureFile(at: vocabularyPath())
        installEditMenu()
        appLog("launched from \(Bundle.main.bundlePath)")

        // Two different permissions, for two different jobs, and confusing
        // them cost a whole evening of diagnosis once:
        //
        //   Input Monitoring  lets the app *hear* the held key. A listen-only
        //                     tap is gated by this one, not by Accessibility.
        //   Accessibility     lets the app *press* ⌘V to paste the transcript.
        //
        // Either can be missing on its own, and each failure looks completely
        // different to the user, so they are reported separately.
        appLog("input monitoring: \(CGPreflightListenEventAccess())")
        appLog("accessibility (needed to paste): \(AXIsProcessTrusted())")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        rebuildMenu()

        requestMicrophone()

        let tap = EventTap { [weak self] flags in
            Task { @MainActor in self?.handle(flags: flags) }
        }
        self.tap = tap
        tapIsRunning = tap.start()
        hold.key = preferences.triggerKey
        // Rebuilt either way. The menu and the icon were first built before
        // the tap existed, when `tapIsRunning` was still false — so without
        // this the app offers to fix a permission that is already granted,
        // and wears the crossed-out microphone while working perfectly.
        updateStatusIcon()
        rebuildMenu()
    }

    // MARK: - Status item

    private func updateStatusIcon() {
        // SF Symbols as template images, not text glyphs: they adapt to a
        // light or dark menu bar and to the highlight when the menu is open.
        let name: String
        if !tapIsRunning {
            // A deaf app must not look like a healthy idle one. This is the
            // only thing the user can see without opening a log file.
            name = "mic.slash"
        } else {
            switch state {
            case .idle:         name = "mic"
            case .recording:    name = "mic.fill"
            case .transcribing: name = "waveform"
            }
        }
        let image = NSImage(systemSymbolName: name,
                            accessibilityDescription: String(localized: "NativeVoice", bundle: .module))
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(hintItem())
        menu.addItem(.separator())

        // In memory only, and the only way back to it while history is off:
        // see where `lastTranscript` is declared for why it is never written
        // to disk.
        if let transcript = lastTranscript {
            let item = actionItem(String(localized: "Copy Last Transcript", bundle: .module),
                                  #selector(copyLastTranscript))
            item.toolTip = transcript
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "?"
        menu.addItem(disabledItem(String(localized: "Version \(version)", bundle: .module)))

        let usage = disabledItem(UsageStats.menuTitle(for: usageSnapshot))
        usageMenuItem = usage
        menu.addItem(usage)

        menu.addItem(keyStatusItem())
        menu.addItem(actionItem(secrets.hasKey
            ? String(localized: "Change API key…", bundle: .module)
            : String(localized: "Set API key…", bundle: .module),
            #selector(openSettings)))
        menu.addItem(.separator())

        menu.addItem(choiceItem(
            String(localized: "Trigger Key", bundle: .module),
            TriggerKey.allCases.map { ($0.menuTitle, $0.rawValue as Any, $0 == hold.key) },
            #selector(selectTriggerKey(_:))))

        menu.addItem(choiceItem(
            String(localized: "Language", bundle: .module),
            Language.sortedForDisplay().map {
                ($0.name, $0.code as Any, $0 == preferences.language)
            },
            #selector(selectLanguage(_:))))

        menu.addItem(choiceItem(
            String(localized: "Max Recording Length", bundle: .module),
            RecordingLimit.allCases.map {
                ($0.menuTitle, $0.rawValue as Any, $0 == preferences.recordingLimit)
            },
            #selector(selectRecordingLimit(_:))))

        menu.addItem(historyItem())

        menu.addItem(toggleItem(String(localized: "Play sounds", bundle: .module),
                                #selector(togglePlaySounds(_:)), preferences.playSounds))
        menu.addItem(toggleItem(String(localized: "Paste automatically", bundle: .module),
                                #selector(toggleAutoPaste(_:)), preferences.autoPaste))
        menu.addItem(toggleItem(String(localized: "Remove filler words", bundle: .module),
                                #selector(toggleRemoveFillers(_:)), preferences.removeFillers))
        menu.addItem(.separator())

        menu.addItem(actionItem(String(localized: "Edit vocabulary…", bundle: .module),
                                #selector(openVocabulary)))
        menu.addItem(actionItem(String(localized: "Open log", bundle: .module),
                                #selector(openLog)))
        menu.addItem(actionItem(String(localized: "Settings…", bundle: .module),
                                #selector(openSettings), keyEquivalent: ","))
        menu.addItem(loginItem())
        menu.addItem(.separator())

        menu.addItem(actionItem(String(localized: "About NativeVoice…", bundle: .module),
                                #selector(showAbout)))
        menu.addItem(NSMenuItem(title: String(localized: "Quit NativeVoice", bundle: .module),
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        return menu
    }

    private func hintItem() -> NSMenuItem {
        guard tapIsRunning else {
            // Naming the permission matters: a listen-only tap needs Input
            // Monitoring, and sending someone to Accessibility instead wastes
            // their evening.
            return actionItem(
                String(localized: "Allow Input Monitoring to use the key", bundle: .module),
                #selector(openInputMonitoringSettings))
        }
        return disabledItem(String(localized: "Hold \(hold.key.menuTitle) and speak",
                                   bundle: .module))
    }

    /// Whether there is a key, said where it can be seen without opening
    /// anything. "Change API key…" implies a key exists, but only to someone
    /// who already knows that the other wording is "Set"; it answers the
    /// question by implication and that is not an answer.
    private func keyStatusItem() -> NSMenuItem {
        let item: NSMenuItem
        if secrets.hasKey {
            item = disabledItem(String(localized: "\u{2713} API key stored",
                                       bundle: .module))
            item.attributedTitle = NSAttributedString(
                string: item.title,
                attributes: [.foregroundColor: NSColor.systemGreen,
                             .font: NSFont.menuFont(ofSize: 0)])
        } else {
            item = disabledItem(String(localized: "No API key — dictation is off",
                                       bundle: .module))
        }
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector,
                            keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func toggleItem(_ title: String, _ action: Selector, _ isOn: Bool) -> NSMenuItem {
        let item = actionItem(title, action)
        item.state = isOn ? .on : .off
        return item
    }

    /// A submenu of mutually exclusive choices, one of them ticked.
    private func choiceItem(_ title: String,
                            _ choices: [(String, Any, Bool)],
                            _ action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (label, value, isCurrent) in choices {
            let item = actionItem(label, action)
            item.representedObject = value
            item.state = isCurrent ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func historyItem() -> NSMenuItem {
        let parent = NSMenuItem(title: String(localized: "History", bundle: .module),
                                action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        if history.isEnabled {
            let items = history.items
            if items.isEmpty {
                submenu.addItem(disabledItem(String(localized: "Nothing yet", bundle: .module)))
            } else {
                // What clicking one does has to be written down. A list of
                // past transcripts invites a click, and nothing about the row
                // says the click puts it on the clipboard rather than, say,
                // pasting it or deleting it.
                submenu.addItem(disabledItem(String(
                    localized: "Click one to copy it to the clipboard",
                    bundle: .module)))
                for text in items {
                    let item = actionItem(History.menuTitle(for: text),
                                          #selector(copyHistoryItem(_:)))
                    item.representedObject = text
                    item.toolTip = text
                    submenu.addItem(item)
                }
                submenu.addItem(.separator())
                submenu.addItem(actionItem(String(localized: "Clear", bundle: .module),
                                           #selector(clearHistory)))
            }
            submenu.addItem(.separator())
        }

        submenu.addItem(toggleItem(String(localized: "Remember Transcripts", bundle: .module),
                                   #selector(toggleHistory(_:)), history.isEnabled))

        if history.isEnabled {
            submenu.addItem(choiceItem(
                String(localized: "Keep", bundle: .module),
                History.limitChoices.map {
                    (String(localized: "\($0) transcripts", bundle: .module),
                     $0 as Any, $0 == history.limit)
                },
                #selector(selectHistoryLimit(_:))))
        } else {
            // Said plainly, because the switch is the thing that decides it.
            submenu.addItem(disabledItem(String(
                localized: "Transcripts are not stored while this is off.",
                bundle: .module)))
        }

        parent.submenu = submenu
        return parent
    }

    private func loginItem() -> NSMenuItem {
        switch LoginItemState.from(rawStatus: SMAppService.mainApp.status.rawValue) {
        case .needsApproval:
            return actionItem(
                String(localized: "Launch at Login — Approve in Settings…", bundle: .module),
                #selector(openLoginItemSettings))
        case .on:
            return toggleItem(String(localized: "Launch at login", bundle: .module),
                              #selector(toggleLoginItem(_:)), true)
        case .off:
            return toggleItem(String(localized: "Launch at login", bundle: .module),
                              #selector(toggleLoginItem(_:)), false)
        }
    }

    private func rebuildMenu() {
        statusItem?.menu = buildMenu()
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        refreshUsage()
    }

    private func refreshUsage() {
        guard secrets.hasKey else { return }
        if let fetchedAt = usageFetchedAt,
           Date().timeIntervalSince(fetchedAt) < 600 { return }
        usageFetchedAt = Date()
        Task { [weak self] in
            guard let self else { return }
            guard let snapshot = await ElevenLabsClient.usage(key: self.secrets.apiKey() ?? "")
            else { return }
            await MainActor.run {
                self.usageSnapshot = snapshot
                self.usageMenuItem?.title = UsageStats.menuTitle(for: snapshot)
            }
        }
    }

    /// Standard editing commands for the settings window.
    ///
    /// A menu bar app has no main menu, and macOS routes ⌘V through the Edit
    /// menu — so without one, paste silently does nothing. The API key is
    /// fifty characters and is shown once; nobody is going to retype it, and
    /// the settings window is useless without this.
    ///
    /// Nothing of this is ever displayed: the app stays an accessory and owns
    /// no menu bar. Only the shortcuts become live, and only while one of its
    /// windows is in front.
    private func installEditMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let name = String(localized: "NativeVoice", bundle: .module)
        appMenu.addItem(withTitle: String(localized: "About \(name)", bundle: .module),
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(
            withTitle: String(localized: "Settings…", bundle: .module),
            action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Hide \(name)", bundle: .module),
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Quit \(name)", bundle: .module),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: String(localized: "Edit", bundle: .module))
        edit.addItem(withTitle: String(localized: "Cut", bundle: .module),
                     action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: String(localized: "Copy", bundle: .module),
                     action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: String(localized: "Paste", bundle: .module),
                     action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: String(localized: "Select All", bundle: .module),
                     action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    @objc private func openSettings() { settings.show() }

    @objc private func showAbout() {
        let credits = NSMutableAttributedString()
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center

        func line(_ text: String, link: String?, breakAfter: Bool = true) {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: centered,
            ]
            if let link { attributes[.link] = link }
            credits.append(NSAttributedString(string: text, attributes: attributes))
            if breakAfter {
                credits.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }

        line(String(localized: "Dictation that works in languages the big tools skip.",
                    bundle: .module), link: nil)
        line("", link: nil)
        line(String(localized: "Report an issue", bundle: .module),
             link: Self.homepage + "/issues")
        line(String(localized: "Buy me a coffee", bundle: .module),
             link: Self.donate, breakAfter: false)

        // An accessory app's about panel opens behind everything unless the
        // app is brought forward first.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    /// Picks up a changed setting without a restart.
    private func applyPreferences() {
        // Changing the key mid-hold would leave the recording with no key-up
        // that maps to it, so the tracker is told plainly rather than left to
        // work it out.
        hold.key = preferences.triggerKey
        rebuildMenu()
    }

    @objc private func openInputMonitoringSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    @objc private func selectTriggerKey(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String,
              let key = TriggerKey(rawValue: raw) else { return }
        preferences.triggerKey = key
        hold = HoldTracker(key: key)
        rebuildMenu()
    }

    @objc private func selectLanguage(_ item: NSMenuItem) {
        guard let code = item.representedObject as? String,
              let language = Language.named(code) else { return }
        preferences.language = language
        rebuildMenu()
    }

    @objc private func selectRecordingLimit(_ item: NSMenuItem) {
        guard let seconds = item.representedObject as? Int else { return }
        preferences.recordingLimit = RecordingLimit(storedSeconds: seconds)
        rebuildMenu()
    }

    @objc private func togglePlaySounds(_ item: NSMenuItem) {
        preferences.playSounds.toggle()
        item.state = preferences.playSounds ? .on : .off
        // Switching it on should be audible at once, so the switch proves it.
        Sounds.confirm(enabled: preferences.playSounds)
    }

    @objc private func toggleAutoPaste(_ item: NSMenuItem) {
        preferences.autoPaste.toggle()
        item.state = preferences.autoPaste ? .on : .off
    }

    @objc private func toggleRemoveFillers(_ item: NSMenuItem) {
        preferences.removeFillers.toggle()
        item.state = preferences.removeFillers ? .on : .off
    }

    @objc private func toggleHistory(_ item: NSMenuItem) {
        history.isEnabled.toggle()
        rebuildMenu()
    }

    @objc private func selectHistoryLimit(_ item: NSMenuItem) {
        guard let limit = item.representedObject as? Int else { return }
        history.limit = limit
        rebuildMenu()
    }

    @objc private func copyHistoryItem(_ item: NSMenuItem) {
        guard let text = item.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func clearHistory() {
        history.clear()
        rebuildMenu()
    }

    @objc private func openVocabulary() {
        let path = vocabularyPath()
        guard Vocabulary.ensureFile(at: path) else {
            appLog("vocabulary: nothing to open at \(path)")
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: Log.defaultPath()))
    }

    @objc private func toggleLoginItem(_ item: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if LoginItemState.from(rawStatus: service.status.rawValue) == .on {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            appLog("launch at login: \(error.localizedDescription)")
        }
        rebuildMenu()
    }

    @objc private func openLoginItemSettings() {
        NSWorkspace.shared.open(URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
    }

    private func requestMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        appLog("microphone authorization: \(status.rawValue)")
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                appLog("microphone access \(granted ? "granted" : "denied")")
            }
        }
    }

    // MARK: - Key handling

    private func handle(flags: UInt64) {
        switch hold.update(flags: flags) {
        case .unchanged: return
        case .pressed:   pressed()
        case .released:  released()
        }
    }

    private func pressed() {
        appLog("\(hold.key.rawValue) pressed")
        recorder.onLevel = { [weak self] decibels in
            self?.hud.setLevel(decibels: decibels)
        }
        recorder.warmUp()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hold.isHolding else { return }
            guard self.state == .idle else {
                appLog("hold threshold passed while \(self.state) — "
                       + "recording will start as soon as the previous one finishes")
                self.startWhenIdle = true
                return
            }
            self.startRecording()
        }
        pendingStart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold, execute: work)
    }

    private func released() {
        appLog("\(hold.key.rawValue) released")
        pendingStart?.cancel(); pendingStart = nil
        limitWork?.cancel(); limitWork = nil
        // The key is up, so a deferred start has nothing left to record.
        startWhenIdle = false
        guard state == .recording else {
            recorder.stop()             // short press, nothing was written
            return
        }
        stopAndTranscribe()
    }

    // MARK: - Recording

    private func startRecording() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nativevoice-\(UUID().uuidString).wav")
        guard recorder.startWriting(to: url) else {
            recorder.stop()
            appLog("could not open the audio input")
            return
        }
        audioURL = url
        startedAt = Date()
        state = .recording
        Sounds.start(enabled: preferences.playSounds)
        armLimit(preferences.recordingLimit)
    }

    private func armLimit(_ limit: RecordingLimit) {
        limitWork?.cancel()
        guard let seconds = limit.seconds else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state == .recording else { return }
            appLog("recording limit \(Int(seconds))s reached — stopping")
            // The cap covers a lost key-release event. Leaving the tracker
            // latched would make the next genuine press read as "no change"
            // and be dropped, so the user would say a whole sentence into
            // nothing.
            self.hold.forceRelease()
            self.pendingStart?.cancel(); self.pendingStart = nil
            self.stopAndTranscribe()
        }
        limitWork = work
        // Subtracting the elapsed time matters when the limit is changed
        // mid-recording: scheduling from now would extend the recording
        // instead of shortening it.
        let remaining = max(0, seconds - Date().timeIntervalSince(startedAt))
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
    }

    private func stopAndTranscribe() {
        limitWork?.cancel(); limitWork = nil
        guard let url = audioURL else { return }
        audioURL = nil
        let spoken = Date().timeIntervalSince(startedAt)
        recorder.stop()
        state = .transcribing

        let peak = recorder.peakDecibels
        let vocabulary = loadVocabulary()
        let language = preferences.language.code

        Task { [weak self] in
            defer { try? FileManager.default.removeItem(at: url) }
            guard let self else { return }

            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            guard ((attributes?[.size] as? Int) ?? 0) > 2000 else {
                appLog("nothing was recorded")
                await MainActor.run { self.state = .idle }
                return
            }

            let started = Date()
            let outcome = await self.transcriber.transcribe(
                audio: url, language: language,
                keyterms: vocabulary, removeFillers: preferences.removeFillers)
            appLog(String(format: "spoken %.1fs | peak %.0f dB | transcribe %.2fs",
                       spoken, peak, Date().timeIntervalSince(started)))

            await MainActor.run {
                self.state = .idle
                switch outcome {
                case .failure(let error):
                    appLog("error: \(error.userMessage)")
                    self.hud.showError(error.userMessage)
                case .text(let text) where text.isEmpty:
                    appLog(peak < -55 ? "empty transcript — the input was silent"
                                   : "empty transcript although there was sound")
                    self.hud.showError(peak < -55
                        ? String(localized: "Nothing was heard.", bundle: .module)
                        : String(localized: "Nothing was recognized.", bundle: .module))
                case .text(let text):
                    self.lastTranscript = text
                    self.history.record(text)
                    self.rebuildMenu()
                    Sounds.done(enabled: self.preferences.playSounds)
                    Paste.deliver(text, autoPaste: self.preferences.autoPaste,
                                  restore: self.clipboardRestore)
                }
            }
        }
    }

    private func vocabularyPath() -> String {
        NSString(string: "~/.config/nativevoice/vocabulary.txt").expandingTildeInPath
    }

    private func loadVocabulary() -> [String] {
        let path = vocabularyPath()
        Vocabulary.ensureFile(at: path)
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return Vocabulary.terms(from: text)
    }

    @objc private func copyLastTranscript() {
        guard let transcript = lastTranscript else { return }
        // Cancel the pending restore first: it would overwrite this a moment
        // later, and the user would see the click do nothing.
        clipboardRestore.cancel()
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(transcript, forType: .string)
        appLog("last transcript copied to the clipboard")
    }
}
