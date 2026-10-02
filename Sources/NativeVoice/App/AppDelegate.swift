import AppKit
import AVFoundation
import NativeVoiceCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum State { case idle, recording, transcribing }

    private static let homepage = "https://github.com/trustbe/nativevoice"
    private static let donate = "https://buymeacoffee.com/jenicek666"
    private static let website = "https://nativevoice.trustbe.com"

    private var statusItem: NSStatusItem!
    private let recorder = Recorder()
    private let hud = HUD()
    private let secrets = KeychainSecretStore()
    private lazy var transcriber: Transcriber = ElevenLabsClient(secrets: secrets)
    private let clipboardRestore = ClipboardRestore()
    private let preferences = Preferences()
    private lazy var keyWindow = KeyWindow(secrets: secrets) { [weak self] in
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
    private var subscription: UsageStats.Subscription?
    private weak var periodMenuItem: NSMenuItem?
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

        // After the status item exists, so the dialogs arrive over an app the
        // user can already see rather than over nothing.
        requestPermissions()

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
        didFinishLaunching = true
    }

    // MARK: - Status item

    private func updateStatusIcon() {
        // Drawn rather than taken from SF Symbols, so the menu bar carries the
        // same mark as the app icon. See StatusIcon for why they had to differ
        // before and no longer do.
        let shape: StatusIcon.State
        if !tapIsRunning {
            // A deaf app must not look like a healthy idle one. This is the
            // only thing the user can see without opening a log file.
            shape = .deaf
        } else {
            switch state {
            case .idle:         shape = .idle
            case .recording:    shape = .recording
            case .transcribing: shape = .transcribing
            }
        }
        statusItem.button?.image = StatusIcon.image(for: shape)
    }

    private func rebuildMenu() {
        // Updated in place rather than replaced: this runs from inside
        // `menuWillOpen` too, and the menu the system is about to display is
        // already `statusItem.menu` by the time that delegate call happens.
        // Swapping in a different `NSMenu` instance there does not change
        // what gets shown for that opening — AppKit already captured the old
        // one — so the existing object's items are cleared and rebuilt
        // instead.
        let menu = statusItem.menu ?? {
            let menu = NSMenu()
            menu.delegate = self
            statusItem.menu = menu
            return menu
        }()
        populate(menu)
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Ordered the way a macOS menu is: how to use it at the top, the
        // things you do with it next, the settings you change after that, and
        // everything belonging to the app itself at the bottom with Quit last.
        //
        // The version, the usage figures and the API key used to sit third
        // from the top — above every row anyone actually opens this menu for.
        // They are account administration; they are now where that belongs.

        menu.addItem(hintItem())
        if !AXIsProcessTrusted() {
            menu.addItem(actionItem(
                String(localized: "Allow Accessibility to paste automatically",
                       bundle: .module),
                #selector(openAccessibilitySettings)))
        }
        menu.addItem(.separator())

        // What you do with it.
        if let transcript = lastTranscript {
            let item = actionItem(String(localized: "Copy Last Transcript", bundle: .module),
                                  #selector(copyLastTranscript))
            item.toolTip = transcript
            menu.addItem(item)
        }
        menu.addItem(historyItem())
        menu.addItem(.separator())

        // What you change.
        menu.addItem(choiceItem(
            String(localized: "Language", bundle: .module),
            Language.sortedForDisplay().map {
                ($0.name, $0.code as Any, $0 == preferences.language)
            },
            #selector(selectLanguage(_:))))

        menu.addItem(choiceItem(
            String(localized: "Trigger Key", bundle: .module),
            TriggerKey.allCases.map { ($0.menuTitle, $0.rawValue as Any, $0 == hold.key) },
            #selector(selectTriggerKey(_:))))

        menu.addItem(choiceItem(
            String(localized: "Max Recording Length", bundle: .module),
            RecordingLimit.allCases.map {
                ($0.menuTitle, $0.rawValue as Any, $0 == preferences.recordingLimit)
            },
            #selector(selectRecordingLimit(_:))))

        menu.addItem(actionItem(String(localized: "Edit vocabulary…", bundle: .module),
                                #selector(openVocabulary)))
        menu.addItem(.separator())

        // Switches, together, because they are read as a set.
        menu.addItem(toggleItem(String(localized: "Play sounds", bundle: .module),
                                #selector(togglePlaySounds(_:)), preferences.playSounds))
        menu.addItem(toggleItem(String(localized: "Paste automatically", bundle: .module),
                                #selector(toggleAutoPaste(_:)), preferences.autoPaste))
        menu.addItem(toggleItem(String(localized: "Remove filler words", bundle: .module),
                                #selector(toggleRemoveFillers(_:)), preferences.removeFillers))
        // Returns two rows when macOS is waiting for approval: the one that
        // opens Settings, and a real toggle, so it can still be switched off.
        for item in loginItem() { menu.addItem(item) }
        menu.addItem(.separator())

        // The app and the account.
        menu.addItem(accountItem())
        menu.addItem(actionItem(String(localized: "About NativeVoice…", bundle: .module),
                                #selector(showAbout)))
        menu.addItem(actionItem(String(localized: "Check for updates…", bundle: .module),
                                #selector(checkForUpdates)))
        menu.addItem(actionItem(String(localized: "Open log", bundle: .module),
                                #selector(openLog)))
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: String(localized: "Quit NativeVoice", bundle: .module),
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    /// Everything about the ElevenLabs account, under its own name.
    ///
    /// A submenu rather than four rows in the main one: these are read
    /// occasionally and the main menu is read constantly. Its own heading also
    /// settles whose credits these are — a bare "Today: 13 credits" in an
    /// app's menu reads as if the app were charging for something.
    private func accountItem() -> NSMenuItem {
        let parent = NSMenuItem(title: String(localized: "ElevenLabs account", bundle: .module),
                                action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let period = disabledItem(UsageStats.periodTitle(for: subscription))
        periodMenuItem = period
        submenu.addItem(period)

        submenu.addItem(.separator())
        submenu.addItem(keyStatusItem())
        submenu.addItem(actionItem(secrets.hasKey
            ? String(localized: "Change API key…", bundle: .module)
            : String(localized: "Set API key…", bundle: .module),
            #selector(openKeyWindow)))

        parent.submenu = submenu
        return parent
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

    private func indented(_ item: NSMenuItem) -> NSMenuItem {
        item.indentationLevel = 1
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

    /// Returns one row for "on" and "off", but two for "needs approval": the
    /// explanatory row stays, and underneath it a real toggle — bound to the
    /// same `toggleLoginItem(_:)` as the other two states — so the feature
    /// can be turned back off without a trip to System Settings.
    private func loginItem() -> [NSMenuItem] {
        switch LoginItemState.from(rawStatus: SMAppService.mainApp.status.rawValue) {
        case .needsApproval:
            return [
                actionItem(
                    String(localized: "Launch at Login — Approve in Settings…",
                          bundle: .module),
                    #selector(openLoginItemSettings)),
                toggleItem(String(localized: "Launch at login", bundle: .module),
                          #selector(toggleLoginItem(_:)), true),
            ]
        case .on:
            return [toggleItem(String(localized: "Launch at login", bundle: .module),
                              #selector(toggleLoginItem(_:)), true)]
        case .off:
            return [toggleItem(String(localized: "Launch at login", bundle: .module),
                              #selector(toggleLoginItem(_:)), false)]
        }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        refreshUsage()
        // Every status read in here — login item, Accessibility, the API
        // key — can go stale while the app sits in the background, so the
        // whole menu is rebuilt on every open rather than only when a menu
        // action changes something.
        rebuildMenu()
    }

    private func refreshUsage() {
        guard secrets.hasKey else { return }
        if let fetchedAt = usageFetchedAt,
           Date().timeIntervalSince(fetchedAt) < 600 { return }
        Task { [weak self] in
            guard let self else { return }
            let key = self.secrets.apiKey() ?? ""
            // Only the subscription. There was a second request, for daily
            // figures, and its numbers could not be squared with these: our
            // own log showed three recordings totalling twelve seconds on a
            // day it reported as 13, where the billing counter would put that
            // near 66. Rather than print a number in a unit nobody could
            // name, the request is gone.
            guard let subscription = await ElevenLabsClient.subscription(key: key)
            else { return }
            await MainActor.run {
                self.subscription = subscription
                // Stamped on success only: stamping before the request let
                // one failure (offline, a revoked key) pin the row at
                // "loading…" for a full ten minutes even after the network
                // came back.
                self.usageFetchedAt = Date()
                self.periodMenuItem?.title = UsageStats.periodTitle(for: self.subscription)
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
            action: #selector(openKeyWindow), keyEquivalent: ",")
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

    @objc private func openKeyWindow() { keyWindow.show() }

    @objc private func checkForUpdates() {
        Task { @MainActor in
            guard let release = await Updater.check() else {
                let alert = NSAlert()
                alert.messageText = String(
                    localized: "NativeVoice \(Updater.currentVersion) is up to date.",
                    bundle: .module)
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
                return
            }
            let alert = NSAlert()
            alert.messageText = String(localized: "Version \(release.version) is available.",
                                       bundle: .module)
            alert.informativeText = String(localized: """
                You are running \(Updater.currentVersion). Installing replaces this \
                copy and NativeVoice will quit; open it again afterwards.
                """, bundle: .module)
            alert.addButton(withTitle: String(localized: "Install", bundle: .module))
            alert.addButton(withTitle: String(localized: "Release notes", bundle: .module))
            alert.addButton(withTitle: String(localized: "Later", bundle: .module))
            NSApp.activate(ignoringOtherApps: true)
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                if let problem = await Updater.install(release) {
                    let failed = NSAlert()
                    failed.messageText = problem
                    failed.alertStyle = .warning
                    failed.runModal()
                } else {
                    // Relaunching the bundle we have just replaced from inside
                    // that same bundle is not something to attempt; quitting
                    // and saying so is honest and works.
                    let done = NSAlert()
                    done.messageText = String(
                        localized: "Version \(release.version) is installed.",
                        bundle: .module)
                    done.informativeText = String(
                        localized: "NativeVoice will now quit. Open it again to use it.",
                        bundle: .module)
                    done.runModal()
                    NSApp.terminate(nil)
                }
            case .alertSecondButtonReturn:
                NSWorkspace.shared.open(release.pageURL)
            default:
                break
            }
        }
    }

    @objc private func showAbout() {
        let credits = NSMutableAttributedString()

        let heading = NSMutableParagraphStyle()
        heading.alignment = .center
        heading.paragraphSpacing = 14      // air between the sentence and the links

        let link = NSMutableParagraphStyle()
        link.alignment = .center
        link.paragraphSpacing = 6          // and between the links themselves,
                                           // which otherwise read as one block

        func line(_ text: String, url: String?, style: NSParagraphStyle,
                  last: Bool = false) {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: style,
            ]
            if let url { attributes[.link] = url }
            credits.append(NSAttributedString(string: text, attributes: attributes))
            if !last {
                credits.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }

        line(String(localized: "Dictation that works in languages the big tools skip.",
                    bundle: .module), url: nil, style: heading)
        line(String(localized: "nativevoice.trustbe.com", bundle: .module),
             url: Self.website, style: link)
        line(String(localized: "Report an issue", bundle: .module),
             url: Self.homepage + "/issues", style: link)
        line(String(localized: "Buy me a coffee", bundle: .module),
             url: Self.donate, style: link, last: true)

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
        // A cap the user just shortened should apply to the recording
        // already in progress, not just the next one.
        if state == .recording { armLimit(preferences.recordingLimit) }
        // This also fires for a language or trigger-key change, not only a
        // key change — clearing here is cheap, and `refreshUsage` simply
        // fetches again on the next menu open, so telling those apart is not
        // worth the extra plumbing. What matters is that a key change can
        // never leave the previous account's figures on screen.
        subscription = nil
        usageFetchedAt = nil
        rebuildMenu()
    }

    @objc private func openInputMonitoringSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
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
        // A cap the user just shortened should apply to the recording
        // already in progress, not just the next one.
        if state == .recording { armLimit(preferences.recordingLimit) }
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
        // Cancel the pending restore first: it would overwrite this a moment
        // later, and the user would see the click do nothing. Same as
        // `copyLastTranscript`, below.
        clipboardRestore.cancel()
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
            // `.needsApproval` counts as "on" here too: it is what the extra
            // toggle row under "Approve in Settings…" is wired to, and its
            // whole point is letting that state be turned back off again.
            if LoginItemState.from(rawStatus: service.status.rawValue) == .off {
                try service.register()
            } else {
                try service.unregister()
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

    /// Asks for the microphone and calls back when the user has answered.
    ///
    /// The callback is what lets the next request wait its turn; see
    /// `requestPermissions`.
    private func requestMicrophone(then next: @escaping @MainActor () -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        appLog("microphone authorization: \(status.rawValue)")
        guard status == .notDetermined else { next(); return }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            appLog("microphone access \(granted ? "granted" : "denied")")
            Task { @MainActor in next() }
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
            // Without this the user holds, speaks, releases, and nothing at
            // all happens — no HUD, no sound. Reachable whenever the audio
            // device is missing or changed, such as AirPods disconnecting
            // mid-session.
            hud.showError(String(localized: "Could not start recording — check the microphone",
                                 bundle: .module))
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
                // Setting `state` above can, through its own `didSet`,
                // synchronously start the *next* recording right here — that
                // is what a hold for sentence two that arrived while this
                // one was still transcribing is waiting for. When that
                // happens `state` is no longer `.idle` by the time execution
                // reaches here, and showing an error HUD for sentence one
                // would overwrite the HUD the recording just put up. So the
                // ordinary case (still `.idle`) is unaffected, and the
                // overlapping case simply skips the error display.
                switch outcome {
                case .failure(let error):
                    appLog("error: \(error.userMessage)")
                    if self.state == .idle { self.hud.showError(error.userMessage) }
                case .text(let text) where text.isEmpty:
                    let silent = LevelAdvice.of(peakDecibels: Double(peak)) == .silent
                    appLog(silent ? "empty transcript — the input was silent"
                                  : "empty transcript although there was sound")
                    if self.state == .idle {
                        self.hud.showError(silent
                            ? String(localized: "Nothing was heard.", bundle: .module)
                            : String(localized: "Nothing was recognized.", bundle: .module))
                    }
                case .text(let text):
                    self.lastTranscript = text
                    self.history.record(text)
                    self.rebuildMenu()
                    Sounds.done(enabled: self.preferences.playSounds)
                    Paste.deliver(text, autoPaste: self.preferences.autoPaste,
                                  restore: self.clipboardRestore)
                    self.warnAboutQuietInput(peak: peak)
                }
            }
        }
    }

    /// Says so, once, when the microphone is audible but too quiet to trust.
    ///
    /// Once per launch and no more. The text arrived, so this is a remark and
    /// not a failure, and a remark that repeats after every sentence is a
    /// remark people learn to dismiss without reading. It waits 1.5 s so it
    /// lands after the paste rather than on top of it.
    private var hasWarnedAboutLevel = false
    private var didFinishLaunching = false

    private func warnAboutQuietInput(peak: Float) {
        guard !hasWarnedAboutLevel,
              let message = LevelAdvice.message(forPeakDecibels: Double(peak))
        else { return }
        hasWarnedAboutLevel = true
        appLog(String(format: "input is quiet — peak %.0f dB", peak))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.state == .idle else { return }
            self.hud.showError(message)
        }
    }

    /// Asks for everything the app needs, rather than telling the user to go
    /// and find it.
    ///
    /// All three have a request API; two of them were only ever *checked*
    /// here, which is why the menu ended up explaining where System Settings
    /// is. `CGPreflightListenEventAccess` and `AXIsProcessTrusted` answer the
    /// question; `CGRequestListenEventAccess` and the `kAXTrustedCheckOption`
    /// prompt ask it.
    ///
    /// **One at a time, and each only after the last is answered.** Fired
    /// together they collide: measured on a freshly reset install, all three
    /// went out in the same runloop tick and the microphone came back
    /// `denied` within the same second, with no dialog ever shown. The
    /// microphone is first because it is the only one whose answer arrives in
    /// a callback, so it is the only one that can sequence the others.
    ///
    /// Only what is missing is asked for: macOS shows each of these once per
    /// app, and asking again when it is already granted does nothing except
    /// look broken.
    private func requestPermissions() {
        requestMicrophone { [weak self] in
            self?.requestInputMonitoring()
        }
    }

    private func requestInputMonitoring() {
        guard !CGPreflightListenEventAccess() else { requestAccessibility(); return }
        appLog("input monitoring: asking")
        // Returns the current status rather than waiting: the dialog it raises
        // offers to open System Settings and the user may take a while.
        // applicationDidBecomeActive picks the answer up.
        _ = CGRequestListenEventAccess()
        // Half a second so the next dialog does not land on top of this one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.requestAccessibility()
        }
    }

    private func requestAccessibility() {
        guard !AXIsProcessTrusted() else { return }
        appLog("accessibility: asking")
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    /// Picks up permissions granted while the app was running.
    ///
    /// Accessibility starts working immediately, so the menu and the icon just
    /// need rebuilding. Input Monitoring does not: macOS hands it to a freshly
    /// started process only, so a tap created before the grant stays deaf
    /// forever and the app looks broken while the checkbox says it is allowed.
    /// That is the one case worth interrupting someone for.
    func applicationDidBecomeActive(_ notification: Notification) {
        guard didFinishLaunching else { return }
        let canListen = CGPreflightListenEventAccess()
        defer { updateStatusIcon(); rebuildMenu() }

        guard canListen, !tapIsRunning, !hasOfferedRestart else { return }
        hasOfferedRestart = true

        let alert = NSAlert()
        alert.messageText = String(localized: "Input Monitoring is allowed now.",
                                   bundle: .module)
        alert.informativeText = String(localized: """
            macOS only hands this permission to a freshly started process, so \
            NativeVoice has to restart before it can hear the trigger key.
            """, bundle: .module)
        alert.addButton(withTitle: String(localized: "Restart now", bundle: .module))
        alert.addButton(withTitle: String(localized: "Later", bundle: .module))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        relaunch()
    }

    private var hasOfferedRestart = false

    private func relaunch() {
        // The new instance is started before this one quits, so there is no
        // window in which the app is simply gone.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                           configuration: configuration) { _, error in
            if let error { appLog("relaunch failed: \(error.localizedDescription)") }
            DispatchQueue.main.async { NSApp.terminate(nil) }
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
