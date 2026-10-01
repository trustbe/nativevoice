import Foundation

/// Longest a single recording may run.
///
/// Not a cost control. Recording stops when the key is released, and release
/// is learned from a tap event. If that one event never arrives — the system
/// disabled the tap, the machine slept with the key held — nothing stops the
/// recording and it runs until somebody notices. A multi-minute file would
/// then be uploaded and paid for.
///
/// On reaching the cap the recording is **closed and transcribed, not
/// discarded**. Throwing it away would throw away what the user actually said.
public enum RecordingLimit: Int, CaseIterable, Equatable {
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600
    case none = 0

    /// Two minutes by default: continuous dictation longer than that is rare,
    /// while a stuck recording is exactly what the cap is for.
    public static let `default` = RecordingLimit.twoMinutes

    public var seconds: TimeInterval? { self == .none ? nil : TimeInterval(rawValue) }

    /// Zero is a real choice ("no limit"), so it must not be read as "unset".
    public init(storedSeconds: Int) {
        self = RecordingLimit(rawValue: storedSeconds) ?? .default
    }
}
