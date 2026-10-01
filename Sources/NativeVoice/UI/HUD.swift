import Cocoa
import NativeVoiceCore

/// The floating panel in the middle of the screen, drawn after the system's
/// own HUD (the one for volume): squircle, blurred background, a large symbol
/// on top, the level curve below it, a quiet caption.
///
/// Rounding is done with `maskImage`, never `layer.cornerRadius`:
/// `NSVisualEffectView` draws its blur outside its own layer, so a corner
/// radius does not clip it and the corners show through white.
@MainActor
final class HUD {
    private var window: NSWindow?
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let meter = LevelGraphView()

    private let size = NSSize(width: 360, height: 156)
    private let radius: CGFloat = 26

    /// Visibility is kept here and never read back from `alphaValue`: while a
    /// fade is running the animator reports a different value than the model,
    /// so a show and a hide in quick succession skipped each other and the
    /// panel stayed on screen.
    private var isVisible = false

    /// A hide fades out over 0.22 s. If a show arrives during that, this
    /// counter is what stops the fade's completion handler from ordering the
    /// window out anyway — which is how the panel used to vanish in the middle
    /// of a recording.
    private var showGeneration = 0

    /// The error layout moves the icon up and gives the caption two lines,
    /// since the meter is hidden. The normal frames have to be remembered.
    private var iconHome = NSRect.zero
    private var labelHome = NSRect.zero
    private var errorDismiss: DispatchWorkItem?

    init() { build() }

    // MARK: - Building

    private func roundedMask() -> NSImage {
        let d = radius * 2 + 2
        let image = NSImage(size: NSSize(width: d, height: d), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: self.radius, yRadius: self.radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius,
                                       bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private func build() {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear

        // Window level, in the order they were tried:
        //   .floating    — invisible over a full-screen app
        //   .screenSaver — works over the system full screen (Chrome), but not
        //                  over terminals like Ghostty, which use their own
        //                  full screen and rise above the menu bar
        //   shielding    — the system shield layer, above everything else
        w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))

        // The panel must never take the keyboard: the transcript is pasted
        // into whatever is underneath, and a panel that stole focus would
        // break the one thing the app is for.
        w.ignoresMouseEvents = true
        w.hasShadow = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                .fullScreenAuxiliary, .ignoresCycle]
        w.alphaValue = 0
        w.appearance = NSAppearance(named: .darkAqua)

        let background: NSView
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            // Reduce Transparency is a request, not a preference to weigh.
            let solid = NSView(frame: NSRect(origin: .zero, size: size))
            solid.wantsLayer = true
            solid.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.92).cgColor
            solid.layer?.cornerRadius = radius
            background = solid
        } else {
            let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.maskImage = roundedMask()
            background = blur
        }

        // A gentle darkening for contrast on a light background. No outline —
        // the system HUD has none and carries itself with shadow and material.
        let tint = NSView(frame: background.bounds)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.22).cgColor
        tint.autoresizingMask = [.width, .height]

        icon.frame = NSRect(x: (size.width - 34) / 2, y: 112, width: 34, height: 30)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = .white

        meter.frame = NSRect(x: 0, y: 26, width: size.width, height: 76)

        label.frame = NSRect(x: 0, y: 92, width: size.width, height: 18)
        label.alignment = .center
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.55)
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false

        iconHome = icon.frame
        labelHome = label.frame

        tint.addSubview(icon)
        tint.addSubview(meter)
        tint.addSubview(label)
        background.addSubview(tint)
        w.contentView = background
        window = w
    }

    private func centre() {
        guard let window else { return }
        let screen = NSScreen.screens.first {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        guard let frame = screen?.frame else { return }
        window.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                      y: frame.midY - size.height / 2))
    }

    // MARK: - States

    func showRecording() {
        restoreLayout()
        setIcon("mic.fill", pointSize: 26, alpha: 1)
        setCaption(String(localized: "Listening", bundle: .module))
        meter.beginLive()
        show()
    }

    /// Input level, in dB, pushed continuously while recording.
    func setLevel(decibels: Float) {
        meter.push(decibels: decibels)
        // Saying it in words, because a flat line alone does not distinguish
        // "quiet room" from "microphone not working" — and a user spent an
        // evening on exactly that ambiguity.
        setCaption(meter.isSilent
                   ? String(localized: "Listening — hearing nothing", bundle: .module)
                   : String(localized: "Listening", bundle: .module))
    }

    func showTranscribing() {
        restoreLayout()
        setIcon("waveform", pointSize: 24, alpha: 0.85)
        setCaption(String(localized: "Transcribing", bundle: .module))
        meter.shimmer()
        show()
    }

    /// An error, shown where the user is already looking. A notification in
    /// the corner is easy to miss, and missing it means not knowing why
    /// nothing was pasted.
    func showError(_ text: String) {
        meter.stop()
        meter.isHidden = true

        icon.frame = NSRect(x: iconHome.minX, y: 96,
                            width: iconHome.width, height: iconHome.height)
        setIcon("exclamationmark.triangle.fill", pointSize: 24, alpha: 1)

        label.frame = NSRect(x: 16, y: 46, width: size.width - 32, height: 40)
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.9)
        setCaption(text)

        show()

        errorDismiss?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        errorDismiss = work
        // Long enough to read, scaled to the length of the message.
        let seconds = min(5.0, 2.2 + Double(text.count) / 22.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hide() {
        errorDismiss?.cancel()
        errorDismiss = nil
        meter.stop()
        guard let window, isVisible else { return }
        isVisible = false

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            window.alphaValue = 0
            window.orderOut(nil)
            return
        }

        let generation = showGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.showGeneration == generation else { return }
            window.orderOut(nil)
        }
    }

    // MARK: - Internals

    private func setCaption(_ text: String) {
        label.stringValue = text
        // VoiceOver reads the panel as one element; the caption is the whole
        // of what it has to say.
        window?.contentView?.setAccessibilityLabel(text)
    }

    private func setIcon(_ name: String, pointSize: CGFloat, alpha: CGFloat) {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize,
                                                        weight: .regular)
        icon.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        icon.contentTintColor = NSColor.white.withAlphaComponent(alpha)
    }

    /// Returns the layout after an error. Called before every normal state;
    /// without it the next recording would show the meter displaced and the
    /// caption on top of it.
    private func restoreLayout() {
        errorDismiss?.cancel()
        errorDismiss = nil
        guard meter.isHidden else { return }
        meter.isHidden = false
        icon.frame = iconHome
        label.frame = labelHome
        label.maximumNumberOfLines = 1
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.55)
    }

    private func show() {
        guard let window else { return }
        let wasHidden = !isVisible
        isVisible = true
        showGeneration &+= 1

        if wasHidden {
            centre()
            window.orderFrontRegardless()
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
               let layer = window.contentView?.layer {
                let pop = CASpringAnimation(keyPath: "transform.scale")
                pop.fromValue = 0.88
                pop.toValue = 1.0
                pop.damping = 18
                pop.stiffness = 320
                pop.mass = 1
                pop.duration = pop.settlingDuration
                layer.add(pop, forKey: "pop")
            }
        }

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            window.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }
}
