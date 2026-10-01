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
            if key != oldValue { holding = false; waitingForRelease = false }
        }
    }
    private var holding = false
    private var waitingForRelease = false

    public init(key: TriggerKey) { self.key = key }

    public var isHolding: Bool { holding }

    public mutating func update(flags: UInt64) -> Change {
        let down = key.isHeld(flags: flags)

        if waitingForRelease {
            // Nothing counts until the key is observably up again.
            if !down { waitingForRelease = false }
            return .unchanged
        }

        guard down != holding else { return .unchanged }
        holding = down
        return down ? .pressed : .released
    }

    /// Clears the held state without an event. Used when something other than
    /// a key release stopped the recording — the length cap — so that the next
    /// real press is not swallowed as "no change".
    ///
    /// Clearing alone is not enough. `flagsChanged` fires for *every* modifier,
    /// so the next time the user touches Shift while still holding the trigger
    /// key, the event would carry the trigger bit set, read as a fresh press,
    /// and start a recording the user never asked for. So the tracker also
    /// stops reporting presses until it has seen the key actually go up — which
    /// covers both cases: the key is still held (wait for the real release), or
    /// its release event was lost (the next event of any kind shows the bit
    /// clear).
    public mutating func forceRelease() {
        holding = false
        waitingForRelease = true
    }
}
