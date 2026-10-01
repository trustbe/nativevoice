import Cocoa
import NativeVoiceCore

/// The oscilloscope: one continuous curve across the whole panel, mirrored
/// about the centre line. New values arrive on the right and the history
/// scrolls left. At rest it is a straight line — which is information, not
/// an error state.
final class LevelGraphView: NSView {
    private let baseline = CALayer()
    private let wave = CAShapeLayer()
    private let edgeMask = CAGradientLayer()

    private var history = LevelHistory(samples: 72)
    private var live = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        baseline.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
        layer?.addSublayer(baseline)

        wave.fillColor = NSColor.white.withAlphaComponent(0.95).cgColor
        wave.strokeColor = nil
        wave.lineJoin = .round
        layer?.addSublayer(wave)

        // The edges fade out so the curve does not end in a visible cut under
        // the panel's rounded corners.
        edgeMask.startPoint = CGPoint(x: 0, y: 0.5)
        edgeMask.endPoint = CGPoint(x: 1, y: 0.5)
        edgeMask.colors = [NSColor.clear.cgColor, NSColor.white.cgColor,
                           NSColor.white.cgColor, NSColor.clear.cgColor]
        edgeMask.locations = [0, 0.1, 0.9, 1]
        layer?.mask = edgeMask
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Layer geometry belongs here, not in `init`: the view is created with a
    /// zero frame and sized later. A mask of zero size covered the entire
    /// curve and nothing was visible at all.
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        baseline.frame = CGRect(x: 0, y: bounds.height / 2 - 0.5,
                                width: bounds.width, height: 1)
        wave.frame = bounds
        edgeMask.frame = bounds
        CATransaction.commit()
        redraw()
    }

    func beginLive() {
        live = true
        wave.removeAllAnimations()
        wave.opacity = 1
        history.reset()
        redraw()
    }

    func push(decibels: Float) {
        guard live else { return }
        history.push(decibels: decibels)
        redraw()
    }

    /// True while the input has stayed below the floor. The panel uses it to
    /// say so in words — a flat line alone is ambiguous between "quiet" and
    /// "not working", and that ambiguity cost a real user a whole evening.
    var isSilent: Bool { history.isSilent }

    private func redraw() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let samples = history.values
        guard samples.count > 1 else { return }

        let width = bounds.width
        let mid = bounds.height / 2
        let maxAmplitude = bounds.height / 2 - 2
        let dx = width / CGFloat(samples.count - 1)
        let minAmplitude: CGFloat = 1.0

        // A gentle lift for quiet passages. A full square root is too much
        // once the range is right — the curve then never settles.
        let amps = samples.map {
            max(minAmplitude, pow(CGFloat($0), 0.7) * maxAmplitude)
        }

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: mid + amps[0]))
        for i in 1..<samples.count {                      // upper outline
            let x = CGFloat(i) * dx
            let previousX = CGFloat(i - 1) * dx
            let cx = (previousX + x) / 2
            path.addCurve(to: CGPoint(x: x, y: mid + amps[i]),
                          control1: CGPoint(x: cx, y: mid + amps[i - 1]),
                          control2: CGPoint(x: cx, y: mid + amps[i]))
        }
        for i in stride(from: samples.count - 1, through: 1, by: -1) {  // mirror
            let x = CGFloat(i - 1) * dx
            let previousX = CGFloat(i) * dx
            let cx = (previousX + x) / 2
            path.addCurve(to: CGPoint(x: x, y: mid - amps[i - 1]),
                          control1: CGPoint(x: cx, y: mid - amps[i]),
                          control2: CGPoint(x: cx, y: mid - amps[i - 1]))
        }
        path.closeSubpath()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wave.path = path
        CATransaction.commit()
    }

    /// During transcription the curve goes quiet and only pulses.
    func shimmer() {
        live = false
        history.reset()
        redraw()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            wave.opacity = 0.6
            return
        }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.25
        pulse.toValue = 0.9
        pulse.duration = 0.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        wave.add(pulse, forKey: "shimmer")
    }

    func stop() {
        live = false
        wave.removeAllAnimations()
    }
}
