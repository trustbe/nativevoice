import Foundation
import NativeVoiceCore

/// Sends audio to ElevenLabs Scribe.
///
/// All the logic worth auditing — what is sent, how a reply is read — lives in
/// `NativeVoiceCore` and is covered by tests. This type is the thin part: read
/// the file, make the call.
struct ElevenLabsClient: Transcriber {
    let secrets: SecretStore
    let session: URLSession

    init(secrets: SecretStore, session: URLSession = .shared) {
        self.secrets = secrets
        self.session = session
    }

    func transcribe(audio url: URL,
                    language: String,
                    keyterms: [String],
                    removeFillers: Bool) async -> TranscriptionResult {
        guard let key = secrets.apiKey() else { return .failure(.noAPIKey) }
        guard let data = try? Data(contentsOf: url) else {
            appLog("recording could not be read back from \(url.path)")
            return .failure(.badResponse)
        }

        let request = ElevenLabsRequest.build(audio: data,
                                              filename: url.lastPathComponent,
                                              language: language,
                                              keyterms: keyterms,
                                              removeFillers: removeFillers,
                                              apiKey: key)
        do {
            let (body, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return ElevenLabsResponse.parse(data: body, httpStatus: status)
        } catch {
            appLog("request failed: \(error.localizedDescription)")
            return .failure(.unreachable)
        }
    }

    /// The account's own accounting. Fetched only when someone opens the menu:
    /// it costs a request, and nobody is looking at it the rest of the time.
    static func usage(key: String) async -> UsageStats.Snapshot? {
        guard !key.isEmpty,
              let url = URL(string: "https://api.elevenlabs.io/v1/usage/character-stats"
                                  + "?breakdown_type=request_queue")
        else { return nil }
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let code = (response as? HTTPURLResponse)?.statusCode,
               !(200..<300).contains(code) {
                appLog("usage: HTTP \(code)")
                return nil
            }
            return UsageStats.snapshot(from: data)
        } catch {
            appLog("usage: \(error.localizedDescription)")
            return nil
        }
    }
}
