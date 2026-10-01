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
}
