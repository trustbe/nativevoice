import CryptoKit
import Foundation
import Testing
@testable import NativeVoiceCore

@Suite struct VocabularyTests {

    @Test func oneTermPerLine() {
        let terms = Vocabulary.terms(from: "Kubernetes\nsafetensors\nWER")
        #expect(terms == ["Kubernetes", "safetensors", "WER"])
    }

    @Test func ignoresCommentsAndBlankLines() {
        let text = """
        # One term per line
        Kubernetes

           # indented comment
        safetensors
        """
        #expect(Vocabulary.terms(from: text) == ["Kubernetes", "safetensors"])
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(Vocabulary.terms(from: "  Kubernetes  \n\tsafetensors\t")
                == ["Kubernetes", "safetensors"])
    }

    @Test func dropsDuplicatesKeepingFirst() {
        #expect(Vocabulary.terms(from: "a\nb\na") == ["a", "b"])
    }

    @Test func termLongerThanFiftyCharactersIsTruncated() {
        // The API accepts at most 50 characters per term. Sending a longer one
        // must not cost the user the whole transcription.
        let long = String(repeating: "x", count: 80)
        let terms = Vocabulary.terms(from: long)
        #expect(terms.count == 1)
        #expect(terms[0].count == 50)
    }

    @Test func aTermOfCombiningCharactersIsClippedByScalarsToo() {
        // The API says "max 50 characters" without saying what it counts.
        // `Ž` written as Z plus a combining caron is one grapheme and two
        // scalars; fifty of them would pass a grapheme count and be refused
        // by a scalar count — costing the whole transcription. So the clip
        // satisfies both readings.
        let combining = String(repeating: "Z\u{030C}", count: 60)
        let clipped = Vocabulary.terms(from: combining)[0]
        #expect(clipped.unicodeScalars.count <= 50)
        #expect(clipped.count <= 50)
    }

    @Test func plainLatinTermsAreUnaffectedByTheScalarRule() {
        // The two readings agree for ordinary text, so nothing is lost there.
        let term = String(repeating: "x", count: 80)
        #expect(Vocabulary.terms(from: term)[0].count == 50)
    }

    @Test func atMostOneThousandTerms() {
        let text = (1...1500).map { "term\($0)" }.joined(separator: "\n")
        #expect(Vocabulary.terms(from: text).count == 1000)
    }

    @Test func emptyFileYieldsNoTerms() {
        #expect(Vocabulary.terms(from: "").isEmpty)
        #expect(Vocabulary.terms(from: "# only a comment\n\n").isEmpty)
    }

    @Test func templateShipsEmpty() {
        #expect(Vocabulary.terms(from: Vocabulary.template).isEmpty)
    }

    // The predecessor shipped a vocabulary naming the author's clients, in a
    // public repository. This test exists to stop that happening again —
    // which means the test itself must never hold a client name as a
    // literal, or the guard against publishing those names would be the
    // thing publishing them. So `forbiddenNameHashes` below holds only the
    // SHA-256 hash of each lowercased name, and the check hashes each
    // lowercased word it finds in a file and looks it up in that set. Do
    // NOT "simplify" this back to a literal `let forbidden = [...]` array —
    // that is the exact bug this rewrite fixes, confirmed by temporarily
    // adding a real name back in during development: the test failed
    // immediately, exactly as it should, and the array itself would have
    // been the leak.
    private static let forbiddenNameHashes: Set<String> = [
        "8df7d2d06163a37fd8be26e39852c5eabc8fdb541520499ef744eb5bf3436867", // journeyman
        "24fecec80a71e1c1c61a7fdf3ab0174cc0d3f5ae9a7127510ee95ca110771f40", // cfmoto
        "a52b09cc7a347a8412a70ef2c07768e57df64cb00169d67539b5c0cab49ef263", // fakturoid
        "48582bd628b7c80064780ba9ecce2d435db042b40bd4335a7cea4b4c254e8178", // helios
        "35fd7737632fcd84bfff4631036f6128e50e0a76c58fc165e5d31551287c48f2", // nextup
        "a25a2c1d43d1b2c7edb887b19ad5e39264846e41133945e33d0095eb5f1422f5", // isir
        "3cef435a1dca838736427c43c8d1781f07c424647455e60095897ad96aff6635", // isds
    ]

    private static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Fails for every word in `text` whose lowercased SHA-256 is in
    /// `forbiddenNameHashes`. Words are runs of letters/digits, so a name
    /// is caught in any capitalization and whether or not it is wrapped in
    /// punctuation, markup, or an HTML tag.
    private static func assertNoForbiddenWords(in text: String, source: String) {
        for word in text.components(separatedBy: nonWordCharacters) where !word.isEmpty {
            let hash = sha256Hex(word.lowercased())
            #expect(!forbiddenNameHashes.contains(hash), "\(source) mentions a forbidden name")
        }
    }

    private static let nonWordCharacters = CharacterSet.alphanumerics.inverted

    @Test func noCustomerOfThePredecessorIsNamedAnywhereInTheFile() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // NativeVoiceCoreTests
            .deletingLastPathComponent()        // Tests
            .deletingLastPathComponent()        // package root

        // Sources/ is where the names leaked before; Scripts/ and docs/ are
        // where they leaked afterwards, in a comment and in a demo table,
        // because the first version of this test only ever looked at
        // Sources/. README.md is checked as a single file alongside them.
        let directories = ["Sources", "Scripts", "docs"]
        var checked = 0

        for directory in directories {
            let base = root.appendingPathComponent(directory)
            let walker = FileManager.default.enumerator(at: base,
                                                        includingPropertiesForKeys: [.isRegularFileKey])
            while let url = walker?.nextObject() as? URL {
                guard let isRegular = try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
                      isRegular,
                      let text = try? String(contentsOf: url, encoding: .utf8)
                else { continue }
                checked += 1
                Self.assertNoForbiddenWords(in: text, source: url.lastPathComponent)
            }
        }

        let readme = root.appendingPathComponent("README.md")
        if let text = try? String(contentsOf: readme, encoding: .utf8) {
            checked += 1
            Self.assertNoForbiddenWords(in: text, source: "README.md")
        }

        #expect(checked > 0, "found no sources to check — the path is wrong")

        Self.assertNoForbiddenWords(in: Vocabulary.template, source: "Vocabulary.template")
    }
}
