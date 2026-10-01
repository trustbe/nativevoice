import AppKit
import NativeVoiceCore

/// The two noises dictation makes: one when it starts listening, one when the
/// text has landed.
///
/// The instances are held for the life of the app. An `NSSound` created and
/// immediately dropped is deallocated before it finishes playing, so the
/// first press is silent and nobody can work out why.
@MainActor
enum Sounds {
    private static let cache: [String: NSSound] = {
        var sounds: [String: NSSound] = [:]
        for name in ["Tink", "Pop"] {
            if let sound = NSSound(named: name) {
                sounds[name] = sound
            } else {
                appLog("sound unavailable: \(name)")
            }
        }
        return sounds
    }()

    private static func play(_ name: String, enabled: Bool) {
        guard enabled, let sound = cache[name] else { return }
        // Still playing from the previous press: without rewinding, a quick
        // second dictation makes no sound at all.
        if sound.isPlaying { sound.stop() }
        sound.play()
    }

    static func start(enabled: Bool) { play("Tink", enabled: enabled) }
    static func done(enabled: Bool) { play("Pop", enabled: enabled) }

    /// Played when sounds are switched back on, so the switch proves itself.
    static func confirm(enabled: Bool) { play("Tink", enabled: enabled) }
}
