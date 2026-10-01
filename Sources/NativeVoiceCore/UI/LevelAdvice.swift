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
/// Working this out took three attempts and a look at the log. The app has
/// the number already, so it can say it the first time.
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

    /// What to tell someone, or nil when there is nothing worth saying.
    ///
    /// It names the number. "Too quiet" invites an argument about whether it
    /// really was; "peak −41 dB, healthy speech is around −12" does not, and
    /// it tells them whether their next attempt helped.
    public static func message(forPeakDecibels peak: Double) -> String? {
        guard of(peakDecibels: peak) == .tooQuiet else { return nil }
        return String(
            localized: """
                Heard you, but very quietly — peak \(Int(peak)) dB where speech \
                is usually around −12. Numbers are the first thing to go wrong \
                at this level. Raise the input volume in System Settings → Sound.
                """,
            bundle: .module)
    }
}
