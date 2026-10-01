import AppKit
import AVFoundation
import NativeVoiceCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum State { case idle, recording, transcribing }

    private var statusItem: NSStatusItem!
    private let recorder = Recorder()
    private let secrets = KeychainSecretStore()
    private lazy var transcriber: Transcriber = ElevenLabsClient(secrets: secrets)
    private let clipboardRestore = ClipboardRestore()

    private var tap: EventTap?
    private var tapIsRunning = false
    private var hold = HoldTracker(key: .default)
    private var state: State = .idle {
        didSet {
            updateStatusIcon()
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
        statusItem.menu = buildMenu()

        requestMicrophone()

        let tap = EventTap { [weak self] flags in
            Task { @MainActor in self?.handle(flags: flags) }
        }
        self.tap = tap
        tapIsRunning = tap.start()
        if !tapIsRunning {
            // Without this the menu bar icon is identical to a healthy idle
            // app, and the only hint lives in a log file nobody is reading.
            updateStatusIcon()
            statusItem.menu = buildMenu()
        }
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
        let hint: NSMenuItem
        if tapIsRunning {
            hint = NSMenuItem(
                title: String(localized: "Hold \(hold.key.menuTitle) and speak",
                              bundle: .module),
                action: nil, keyEquivalent: "")
            hint.isEnabled = false
        } else {
            // Naming the permission matters: Input Monitoring is what a
            // listen-only tap needs, and sending someone to Accessibility
            // instead wastes their evening.
            hint = NSMenuItem(
                title: String(localized: "Allow Input Monitoring to use the key",
                              bundle: .module),
                action: #selector(openInputMonitoringSettings), keyEquivalent: "")
            hint.target = self
        }
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit NativeVoice", bundle: .module),
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        return menu
    }

    @objc private func openInputMonitoringSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
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
        recorder.onLevel = { _ in }     // HUD arrives in plan 2
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
        armLimit(RecordingLimit.default)
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
        let language = Language.forSystem().code

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
                keyterms: vocabulary, removeFillers: false)
            appLog(String(format: "spoken %.1fs | peak %.0f dB | transcribe %.2fs",
                       spoken, peak, Date().timeIntervalSince(started)))

            await MainActor.run {
                self.state = .idle
                switch outcome {
                case .failure(let error):
                    appLog("error: \(error.userMessage)")
                case .text(let text) where text.isEmpty:
                    appLog(peak < -55 ? "empty transcript — the input was silent"
                                   : "empty transcript although there was sound")
                case .text(let text):
                    Paste.deliver(text, autoPaste: true, restore: self.clipboardRestore)
                }
            }
        }
    }

    private func loadVocabulary() -> [String] {
        let path = NSString(string: "~/.config/nativevoice/vocabulary.txt")
            .expandingTildeInPath
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            try? FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true)
            try? Vocabulary.template.write(toFile: path, atomically: true, encoding: .utf8)
            return []
        }
        return Vocabulary.terms(from: text)
    }
}
