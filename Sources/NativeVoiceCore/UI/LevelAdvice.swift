import Foundation

/// Whether the microphone was loud enough to be worth trusting.
///
/// The thresholds are measured, not chosen. On 1 October 2026, the same
/// sentence was dictated three times on the same Mac:
///
/// - peak −41 dB: "paragraph one hundred and forty-two" came back as
///   "one hundred and sixty-two"
/// - peak −26 dB: correct
/// - peak −25 dB: correct
///
/// A quiet signal breaks numbers before it breaks words, which is the
/// dangerous way round: a mangled word is obviously wrong and a wrong digit
/// is not. Healthy speech peaks around −12 to −6 dB.
///
/// Used to decide whether a recording is worth a line in the log. There was
/// a panel too, raised after the transcript had landed; it is gone, because
/// the HUD's live meter says the same thing while you are still speaking and
/// can still do something about it.
public enum LevelAdvice: Equatable, Sendable {
    /// Nothing was there. Already handled as its own case by the caller.
    case silent
    /// Audible, but quiet enough that digits are unreliable.
    case tooQuiet
    case fine

    public static let silentBelow: Double = -55
    public static let quietBelow: Double = -35

    public static func of(peakDecibels: Double) -> LevelAdvice {
        if peakDecibels < silentBelow { return .silent }
        if peakDecibels < quietBelow { return .tooQuiet }
        return .fine
    }

}
