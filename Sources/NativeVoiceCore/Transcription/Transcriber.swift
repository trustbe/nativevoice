import Foundation

/// Why a transcription did not produce text.
///
/// Separate cases, not one catch-all. The predecessor reported every failure
/// as "Transcription failed — check the API key and connection", from which a
/// missing key could not be told apart from a dropped network.
public enum TranscriptionError: Equatable {
    case noAPIKey
    case unreachable
    case badResponse
    case server(String)

    /// Short enough for the HUD, specific enough to act on.
    public var userMessage: String {
        switch self {
        // `bundle: .module` is mandatory inside the library: without it the
        // lookup goes to the main bundle and silently returns the key.
        case .noAPIKey:
            return String(localized: "No API key. Add one in the menu.", bundle: .module)
        case .unreachable:
            return String(localized: "Could not reach the server.", bundle: .module)
        case .badResponse:
            return String(localized: "Unexpected reply from the server.", bundle: .module)
        case .server(let text): return text
        }
    }
}

public enum TranscriptionResult: Equatable {
    case text(String)
    case failure(TranscriptionError)
}

/// One engine. The app talks to this, never to a concrete client, so a second
/// engine is a new conformance rather than a rewrite — and so tests can run
/// the whole dictation loop without a network.
public protocol Transcriber {
    func transcribe(audio: URL,
                    language: String,
                    keyterms: [String],
                    removeFillers: Bool) async -> TranscriptionResult
}
