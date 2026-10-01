import Foundation

/// Builds the multipart request. Pure: no network, no file system, so every
/// byte that leaves this machine can be asserted on in a test.
///
/// The key travels in a header. It must never reach a URL, a query string or
/// a process argument — `ps -ww` shows arguments to every user on the machine,
/// which is why the predecessor had to pipe them into `curl` instead. Here the
/// key does not leave the process at all.
public struct ElevenLabsRequest {
    public static let endpoint = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
    public static let model = "scribe_v2"

    public static func build(audio: Data,
                             filename: String,
                             language: String,
                             keyterms: [String],
                             removeFillers: Bool,
                             apiKey: String,
                             boundary: String = "nativevoice-\(UUID().uuidString)") -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }

        field("model_id", model)
        field("language_code", language)
        if removeFillers { field("no_verbatim", "true") }
        for term in keyterms { field("keyterms", term) }

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(audio)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        request.httpBody = body
        return request
    }
}

private extension Data {
    mutating func append(_ text: String) {
        if let d = text.data(using: .utf8) { append(d) }
    }
}
