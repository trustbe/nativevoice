import AppKit

/// The menu bar mark: the same bars as the app icon, drawn small.
///
/// This used to be `mic`, `mic.fill` and `mic.slash` from SF Symbols. Those
/// are fine inside an interface and they are what Apple's licence allows —
/// but the app icon cannot use them, so the app had two different marks and
/// no way to recognise one from the other. One identity is worth more than
/// the convenience of a ready-made glyph.
///
/// Drawn as a template image, so macOS inverts it for a dark menu bar and for
/// the highlight when the menu is open, exactly as the symbols did.
enum StatusIcon {

    enum State { case idle, recording, transcribing, deaf }

    static func image(for state: State) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return true }
            draw(state, in: context, size: size)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description(for: state)
        return image
    }

    private static func description(for state: State) -> String {
        switch state {
        case .idle:         return String(localized: "NativeVoice", bundle: .module)
        case .recording:    return String(localized: "NativeVoice — recording", bundle: .module)
        case .transcribing: return String(localized: "NativeVoice — transcribing", bundle: .module)
        case .deaf:         return String(localized: "NativeVoice — needs permission", bundle: .module)
        }
    }

    private static func draw(_ state: State, in context: CGContext, size: NSSize) {
        // Five bars, same silhouette as the app icon. Idle shows them at rest;
        // recording raises the middle three so the shape reads as "listening"
        // at a glance, without animating anything in the menu bar.
        let heights: [CGFloat]
        switch state {
        case .recording:    heights = [0.45, 0.80, 1.00, 0.80, 0.45]
        case .transcribing: heights = [0.70, 0.45, 0.80, 0.45, 0.70]
        default:            heights = [0.34, 0.60, 0.88, 0.60, 0.34]
        }

        let barWidth: CGFloat = 1.9
        let gap: CGFloat = 1.5
        let tallest = size.height * 0.62
        let total = barWidth * CGFloat(heights.count) + gap * CGFloat(heights.count - 1)
        var x = (size.width - total) / 2
        let middle = size.height / 2

        // A deaf app is drawn faint, so it cannot be mistaken for a healthy
        // idle one at a glance — that difference is the only thing visible
        // without opening a menu or a log.
        context.setFillColor(NSColor.black.withAlphaComponent(state == .deaf ? 0.4 : 1).cgColor)

        for factor in heights {
            let height = tallest * factor
            let bar = CGRect(x: x, y: middle - height / 2, width: barWidth, height: height)
            context.addPath(CGPath(roundedRect: bar,
                                   cornerWidth: barWidth / 2, cornerHeight: barWidth / 2,
                                   transform: nil))
            context.fillPath()
            x += barWidth + gap
        }

        guard state == .deaf else { return }

        // The slash is cut out rather than drawn over, so it stays visible
        // whichever way macOS inverts the template.
        context.setBlendMode(.clear)
        context.setLineWidth(2.6)
        context.move(to: CGPoint(x: 2.5, y: 3.0))
        context.addLine(to: CGPoint(x: size.width - 2.5, y: size.height - 3.0))
        context.strokePath()

        context.setBlendMode(.normal)
        context.setFillColor(NSColor.black.cgColor)
        context.setLineWidth(1.3)
        context.setStrokeColor(NSColor.black.cgColor)
        context.move(to: CGPoint(x: 2.5, y: 3.0))
        context.addLine(to: CGPoint(x: size.width - 2.5, y: size.height - 3.0))
        context.strokePath()
    }
}
