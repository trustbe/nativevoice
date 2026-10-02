import Foundation

/// When an automatic update check is due.
///
/// Kept as a decision over values so the awkward parts — a clock that went
/// backwards, a first run with nothing recorded — are settled somewhere a
/// test can reach, rather than inside a timer nobody can step through.
public enum UpdateSchedule {

    /// Six hours. Often enough that a fix lands the same day, rarely enough
    /// that it is not a background process hammering a public API.
    public static let interval: TimeInterval = 6 * 3600

    /// A pause after launch before the first check. Starting the app should
    /// not wait on a network request, and somebody who has just opened it is
    /// about to use it, not about to want it restarted.
    public static let delayAfterLaunch: TimeInterval = 120

    public static func isDue(lastCheck: Date?, now: Date = Date()) -> Bool {
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        // A negative interval means the clock moved backwards — a timezone
        // change, an NTP correction, a laptop waking in another country.
        // Treating it as "not due yet" would park the check until the stored
        // date came round again, which could be never.
        guard elapsed >= 0 else { return true }
        return elapsed >= interval
    }
}
