import Foundation

public enum ElevenLabsResponse {
    /// Longest server message shown in the HUD. Beyond this it stops being a
    /// message and starts being a wall.
    static let maxServerMessage = 90

    public static func parse(data: Data, httpStatus: Int) -> TranscriptionResult {
        // An empty body means the connection never arrived anywhere. A server
        // that rejected the request would have sent one.
        guard !data.isEmpty else { return .failure(.unreachable) }

        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            appLog("unparseable response (HTTP \(httpStatus), \(data.count) bytes): "
                + redactedPreview(of: data))
            return .failure(.badResponse)
        }

        if let text = json["text"] as? String {
            if let seconds = json["audio_duration_secs"] as? Double {
                appLog(String(format: "API received %.2fs of audio", seconds))
            }
            return .text(text)
        }

        // The shape of an error body is not guaranteed anywhere, so it is read
        // defensively and falls back to a generic message.
        let detail = (json["detail"] as? [String: Any])?["message"] as? String
            ?? json["detail"] as? String
            ?? json["message"] as? String

        appLog("no transcript in response (HTTP \(httpStatus), \(data.count) bytes): "
            + redactedPreview(of: data))

        guard let detail, !detail.isEmpty else { return .failure(.badResponse) }
        return .failure(.server(String(detail.prefix(maxServerMessage))))
    }

    /// A body preview safe to put in the log.
    ///
    /// This only runs once parsing has already failed — the body is not
    /// known to be well-formed JSON — yet a *truncated success* response
    /// still starts `{"language_code":"cs","text":"…`, so dictated words can
    /// sit right at the front of it. History is off by default precisely to
    /// keep dictated text out of unencrypted storage, so this must not
    /// quietly reintroduce it through the log. Everything from the `"text"`
    /// key onward is cut before anything is logged — not merely capped in
    /// length, which a short enough message would still slip past — and
    /// what remains is bounded to a small prefix on top of that.
    private static func redactedPreview(of data: Data, maxBytes: Int = 60) -> String {
        let marker = Data(#""text""#.utf8)
        let bound = data.range(of: marker)?.lowerBound ?? data.endIndex
        let safe = data[data.startIndex..<bound].prefix(maxBytes)
        return String(decoding: safe, as: UTF8.self)
    }
}
