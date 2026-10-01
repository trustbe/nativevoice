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

    @Test func noCustomerOfThePredecessorIsNamedAnywhereInTheFile() throws {
        // The predecessor shipped a vocabulary naming the author's clients.
        // Checking only `template` is not enough — a name in a doc comment is
        // just as public once the repository is, and that is exactly where
        // one slipped through before this test was widened.
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // NativeVoiceCoreTests
            .deletingLastPathComponent()        // Tests
            .deletingLastPathComponent()        // package root
            .appendingPathComponent("Sources/NativeVoiceCore/Support/Vocabulary.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        let forbidden = ["Journeyman", "CFMOTO", "Fakturoid", "Helios",
                         "Nextup", "ISIR", "ISDS"]
        for name in forbidden {
            #expect(!(text.contains(name)), "Vocabulary.swift mentions \(name)")
            #expect(!(Vocabulary.template.contains(name)), "template mentions \(name)")
        }
    }
}
