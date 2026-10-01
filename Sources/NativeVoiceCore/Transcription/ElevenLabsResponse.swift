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
            appLog("unparseable response (HTTP \(httpStatus)): "
                + String(decoding: data.prefix(300), as: UTF8.self))
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

        appLog("no transcript in response (HTTP \(httpStatus)): "
            + String(decoding: data.prefix(300), as: UTF8.self))

        guard let detail, !detail.isEmpty else { return .failure(.badResponse) }
        return .failure(.server(String(detail.prefix(maxServerMessage))))
    }
}
