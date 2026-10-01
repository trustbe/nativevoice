import Foundation
import Testing
@testable import NativeVoiceCore

@Suite struct ElevenLabsTests {

    private let boundary = "TESTBOUNDARY"

    private func build(language: String = "ces",
                       keyterms: [String] = [],
                       removeFillers: Bool = false,
                       apiKey: String = "sk_test") -> URLRequest {
        ElevenLabsRequest.build(audio: Data("RIFFfake".utf8),
                                filename: "speech.wav",
                                language: language,
                                keyterms: keyterms,
                                removeFillers: removeFillers,
                                apiKey: apiKey,
                                boundary: boundary)
    }

    private func body(_ request: URLRequest) -> String {
        String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
    }

    // MARK: - Request

    @Test func postsToTheSpeechToTextEndpoint() {
        let r = build()
        #expect(r.httpMethod == "POST")
        #expect(r.url?.absoluteString
                == "https://api.elevenlabs.io/v1/speech-to-text")
    }

    @Test func carriesTheKeyInAHeaderAndNowhereElse() {
        // The key must never end up in a URL, a query string or a process
        // argument. `ps -ww` shows arguments to every user on the machine.
        let r = build(apiKey: "sk_secret")
        #expect(r.value(forHTTPHeaderField: "xi-api-key") == "sk_secret")
        #expect(!(r.url!.absoluteString.contains("sk_secret")))
        #expect(!(body(r)).contains("sk_secret"))
    }

    @Test func sendsModelAndLanguage() {
        let b = body(build(language: "mkd"))
        #expect(b.contains("name=\"model_id\"\r\n\r\nscribe_v2"))
        #expect(b.contains("name=\"language_code\"\r\n\r\nmkd"))
    }

    @Test func sendsOneFieldPerKeyterm() {
        let b = body(build(keyterms: ["Kubernetes", "safetensors"]))
        #expect(b.contains("name=\"keyterms\"\r\n\r\nKubernetes"))
        #expect(b.contains("name=\"keyterms\"\r\n\r\nsafetensors"))
    }

    @Test func omitsKeytermsWhenThereAreNone() {
        #expect(!(body(build(keyterms: []))).contains("keyterms"))
    }

    @Test func fillerRemovalIsOptOut() {
        #expect(!(body(build(removeFillers: false))).contains("no_verbatim"))
        #expect(body(build(removeFillers: true))
            .contains("name=\"no_verbatim\"\r\n\r\ntrue"))
    }

    @Test func aFilenameWithAQuoteCannotBreakTheHeader() {
        // The filename lands inside a quoted header value. A quote or a
        // backslash in it would end that value early and corrupt the part.
        let r = ElevenLabsRequest.build(audio: Data("RIFFfake".utf8),
                                        filename: "we\"ird\\name\n.wav",
                                        language: "ces", keyterms: [],
                                        removeFillers: false,
                                        apiKey: "sk_test", boundary: boundary)
        let b = String(data: r.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(b.contains("filename=\"weirdname.wav\""))
        // Exactly one Content-Disposition line for the file part, not two.
        #expect(b.components(separatedBy: "name=\"file\"").count == 2)
    }

    @Test func bodyIsWellFormedMultipart() {
        let r = build(keyterms: ["a"])
        #expect(r.value(forHTTPHeaderField: "Content-Type")
                == "multipart/form-data; boundary=\(boundary)")
        let b = body(r)
        #expect(b.hasPrefix("--\(boundary)\r\n"))
        #expect(b.hasSuffix("--\(boundary)--\r\n"))
        #expect(b.contains(
            "name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav"))
    }

    // MARK: - Response

    @Test func parsesTranscript() {
        let data = Data(#"{"text":"toto je zkouška"}"#.utf8)
        guard case .text(let t) = ElevenLabsResponse.parse(data: data, httpStatus: 200) else {
            Issue.record("expected text"); return
        }
        #expect(t == "toto je zkouška")
    }

    @Test func emptyTranscriptIsStillASuccess() {
        // Silence is not an error of the request. The caller decides what to
        // tell the user, because only it knows the measured input level.
        let data = Data(#"{"text":""}"#.utf8)
        guard case .text(let t) = ElevenLabsResponse.parse(data: data, httpStatus: 200) else {
            Issue.record("expected text"); return
        }
        #expect(t == "")
    }

    @Test func emptyBodyMeansUnreachable() {
        guard case .failure(let e) = ElevenLabsResponse.parse(data: Data(), httpStatus: 0) else {
            Issue.record("expected failure"); return
        }
        #expect(e == .unreachable)
    }

    @Test func nonJSONBodyMeansBadResponse() {
        let data = Data("<html>502 Bad Gateway</html>".utf8)
        guard case .failure(let e) = ElevenLabsResponse.parse(data: data, httpStatus: 502) else {
            Issue.record("expected failure"); return
        }
        #expect(e == .badResponse)
    }

    @Test func serverMessageIsSurfacedFromDetailObject() {
        let data = Data(#"{"detail":{"message":"Invalid API key"}}"#.utf8)
        guard case .failure(let e) = ElevenLabsResponse.parse(data: data, httpStatus: 401) else {
            Issue.record("expected failure"); return
        }
        #expect(e == .server("Invalid API key"))
    }

    @Test func serverMessageIsSurfacedFromDetailString() {
        let data = Data(#"{"detail":"quota exceeded"}"#.utf8)
        guard case .failure(let e) = ElevenLabsResponse.parse(data: data, httpStatus: 429) else {
            Issue.record("expected failure"); return
        }
        #expect(e == .server("quota exceeded"))
    }

    @Test func jSONWithoutTextOrDetailMeansBadResponse() {
        let data = Data(#"{"unexpected":1}"#.utf8)
        guard case .failure(let e) = ElevenLabsResponse.parse(data: data, httpStatus: 200) else {
            Issue.record("expected failure"); return
        }
        #expect(e == .badResponse)
    }

    @Test func longServerMessageIsShortenedForTheHUD() {
        let long = String(repeating: "e", count: 300)
        let data = Data(#"{"detail":"\#(long)"}"#.utf8)
        guard case .failure(.server(let message)) =
                ElevenLabsResponse.parse(data: data, httpStatus: 400) else {
            Issue.record("expected server failure"); return
        }
        // `<=` alone would also pass if the code over-truncated to ten
        // characters, so the exact length is asserted.
        #expect(message.count == 90)
    }

    @Test func everyErrorHasANonEmptyUserMessage() {
        let all: [TranscriptionError] = [.noAPIKey, .unreachable, .badResponse,
                                         .server("boom")]
        for e in all { #expect(!(e.userMessage.isEmpty), "\(e)") }
    }

    @Test func unparseableBodyNeverLeaksDictatedWordsToTheLog() throws {
        // A truncated *success* response: it starts exactly like a real one,
        // `{"language_code":"cs","text":"…`, but the cut-off means it is not
        // valid JSON, so `parse` falls into its failure-logging path. Real
        // spoken words sit right at the front of the body, and the log must
        // never show them — History is off by default for exactly this
        // reason, and a log line would quietly defeat that.
        let fm = FileManager.default
        let path = Log.defaultPath()
        var before = 0
        if let attrs = try? fm.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int {
            before = size
        }

        let data = Data(#"{"language_code":"cs","text":"tajneSlovo odhaleno"#.utf8)
        _ = ElevenLabsResponse.parse(data: data, httpStatus: 200)
        Log.shared.drain()

        let fullData = fm.contents(atPath: path) ?? Data()
        let appendedData = fullData.count > before ? fullData.suffix(from: before) : Data()
        let appended = String(decoding: appendedData, as: UTF8.self)

        #expect(!appended.contains("tajneSlovo"))
        #expect(!appended.contains("odhaleno"))
        // The length and status are still worth having for diagnosis.
        #expect(appended.contains("\(data.count)"))
        #expect(appended.contains("200"))
    }
}
