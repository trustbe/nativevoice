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
    /// The plan's quota for the current billing period.
    ///
    /// A separate endpoint from the daily statistics, and necessarily so: the
    /// buckets can be summed over the last N days, but a billing period does
    /// not begin N days ago, and the number on the bill is this one.
    static func subscription(key: String) async -> UsageStats.Subscription? {
        guard !key.isEmpty,
              let url = URL(string: "https://api.elevenlabs.io/v1/user/subscription")
        else { return nil }
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let code = (response as? HTTPURLResponse)?.statusCode,
               !(200..<300).contains(code) {
                appLog("subscription: HTTP \(code)")
                return nil
            }
            return UsageStats.subscription(from: data)
        } catch {
            appLog("subscription: \(error.localizedDescription)")
            return nil
        }
    }

    static func usage(key: String) async -> UsageStats.Snapshot? {
        guard !key.isEmpty else { return nil }

        // start_unix and end_unix are required and are MILLISECONDS, not
        // seconds — omitting them is an HTTP 422, which is how this was found.
        // breakdown_type=product_type is what makes the response carry an
        // "STT" series; the other breakdowns group by something else and the
        // parser finds nothing.
        let now = Date()
        let from = now.addingTimeInterval(-2000 * 86_400)
        func milliseconds(_ date: Date) -> Int { Int(date.timeIntervalSince1970 * 1000) }

        guard let url = URL(string: "https://api.elevenlabs.io/v1/usage/character-stats"
                                  + "?start_unix=\(milliseconds(from))"
                                  + "&end_unix=\(milliseconds(now))"
                                  + "&breakdown_type=product_type")
        else { return nil }
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let code = (response as? HTTPURLResponse)?.statusCode,
               !(200..<300).contains(code) {
                appLog("usage: HTTP \(code) — \(url.query ?? "no query")")
                return nil
            }
            return UsageStats.snapshot(from: data)
        } catch {
            appLog("usage: \(error.localizedDescription)")
            return nil
        }
    }
}
