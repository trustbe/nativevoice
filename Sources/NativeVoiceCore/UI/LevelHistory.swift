import Foundation

/// A sliding window of input levels, normalized for drawing.
///
/// The arithmetic lives here, away from AppKit, because it is the part that
/// can be wrong in ways nobody notices: a meter stuck at zero looks exactly
/// like a quiet room, and a meter stuck at one looks exactly like shouting.
public struct LevelHistory {
    /// Below this the input is treated as silence.
    public static let floorDecibels: Float = -72
    /// The quietest the ceiling is allowed to fall to. Without a limit, a long
    /// silence would drag it down until room tone filled the whole graph.
    public static let ceilingFloor: Float = -50
    /// How fast the ceiling drifts back down, in dB per sample.
    public static let ceilingDecay: Float = 0.06

    private var samples: [Double]
    private var ceiling: Float = -38
    private var lastDecibels: Float = -200

    public init(samples count: Int = 72) {
        samples = Array(repeating: 0, count: max(2, count))
    }

    public var values: [Double] { samples }

    /// True while nothing above the floor has arrived. The panel shows a flat
    /// line rather than hiding, so the caller has to be able to tell the
    /// difference between "quiet" and "nothing at all".
    public var isSilent: Bool { lastDecibels < Self.floorDecibels + 3 }

    public mutating func push(decibels: Float) {
        lastDecibels = decibels

        // The ceiling tracks recent peaks so that speech on a quiet microphone
        // still fills the graph. A fixed ceiling would flatten it to nothing,
        // and a user with a quiet input would conclude they were not heard —
        // when in fact they were, faintly.
        if decibels > ceiling {
            ceiling = decibels
        } else {
            ceiling = max(Self.ceilingFloor, ceiling - Self.ceilingDecay)
        }

        let span = max(6, ceiling - Self.floorDecibels)
        let normalized = (decibels - Self.floorDecibels) / span
        samples.removeFirst()
        samples.append(Double(min(1, max(0, normalized))))
    }

    public mutating func reset() {
        samples = Array(repeating: 0, count: samples.count)
        ceiling = -38
        lastDecibels = -200
    }
}
