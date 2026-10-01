import AppKit
import NativeVoiceCore

/// Delivers a transcript to wherever the cursor is.
enum Paste {
    /// Synthesizes ⌘V. Posting to the annotated session tap is what reaches
    /// the frontmost application.
    private static func pressCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let v: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }

    static func deliver(_ text: String, autoPaste: Bool, restore: ClipboardRestore) {
        let board = NSPasteboard.general
        let previous = autoPaste ? board.string(forType: .string) : nil

        board.clearContents()
        board.setString(text, forType: .string)
        guard autoPaste else { return }

        pressCommandV()

        // Put back what the user had. Without this, every dictation silently
        // destroys whatever they had copied.
        restore.schedule(previous: previous) { old in
            let board = NSPasteboard.general
            board.clearContents()
            if let old { board.setString(old, forType: .string) }
        }
    }
}
