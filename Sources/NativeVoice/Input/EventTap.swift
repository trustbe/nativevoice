import AppKit
import NativeVoiceCore

/// Watches modifier keys system-wide.
///
/// The mask is `flagsChanged` and nothing else. **`keyDown` must never be
/// added.** A version that included it coincided with every keyboard shortcut
/// in the system breaking; the mechanism was never proven, but the difference
/// was reproducible and the narrow mask has never repeated it.
final class EventTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var hasSeenAnEvent = false
    private let onChange: (UInt64) -> Void

    init(onChange: @escaping (UInt64) -> Void) {
        self.onChange = onChange
    }

    @discardableResult
    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        // userInfo must carry self. Passing nil left refcon nil in the
        // callback, so the branch that re-enables a timed-out tap could never
        // run and the app went deaf without saying so.
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
                me.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            appLog("event tap could not be created — Input Monitoring not granted")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        // Deliberately not "ready". A tap can be created and still deliver
        // nothing, and a log that claims readiness while the app is deaf is
        // worse than no log at all — it sends whoever is diagnosing it
        // somewhere else entirely.
        appLog("event tap created — waiting for the first event")
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            appLog("event tap re-enabled after \(type == .tapDisabledByTimeout ? "timeout" : "user input")")
            return
        }
        guard type == .flagsChanged else { return }
        if !hasSeenAnEvent {
            hasSeenAnEvent = true
            appLog("event tap is receiving events — ready")
        }
        onChange(event.flags.rawValue)
    }
}
