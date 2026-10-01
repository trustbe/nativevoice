import Foundation

/// What the Launch at Login row should show, worked out from the registration
/// status.
///
/// Kept as a mapping over the raw value so it can be tested without
/// registering anything on the machine running the tests.
public enum LoginItemState: Equatable, Sendable {
    case off
    case on
    /// Registered, but macOS is waiting for the person to confirm it in
    /// System Settings.
    case needsApproval

    /// `SMAppService.Status` raw values. An app that was never registered
    /// reports `notFound`, not `notRegistered` — measured with a throwaway
    /// bundle — so both have to land on `off`.
    public static func from(rawStatus: Int) -> LoginItemState {
        switch rawStatus {
        case 1:  return .on
        case 2:  return .needsApproval
        default: return .off
        }
    }
}
