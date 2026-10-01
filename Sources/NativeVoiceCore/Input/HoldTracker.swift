import Foundation

/// Turns a stream of `flagsChanged` flag words into press and release events.
///
/// The held state is derived from the device bit in each event, never from a
/// counter this type increments on its own. With a counter, one lost event is
/// enough to invert everything: a *release* is then read as a *press*, and a
/// recording starts with no key held and nothing to stop it.
public struct HoldTracker {
    public enum Change: Equatable { case pressed, released, unchanged }

    public var key: TriggerKey {
        didSet {
            // Switching keys mid-hold would otherwise leave the old one
            // latched down forever.
            if key != oldValue { holding = false }
        }
    }
    private var holding = false

    public init(key: TriggerKey) { self.key = key }

    public var isHolding: Bool { holding }

    public mutating func update(flags: UInt64) -> Change {
        let down = key.isHeld(flags: flags)
        guard down != holding else { return .unchanged }
        holding = down
        return down ? .pressed : .released
    }

    /// Clears the held state without an event. Used when something other than
    /// a key release stopped the recording — the length cap — so that the next
    /// real press is not swallowed as "no change".
    public mutating func forceRelease() { holding = false }
}
