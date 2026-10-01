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

    @Test func noCustomerOfThePredecessorIsNamedAnywhereInTheFile() throws {
        // The predecessor shipped a vocabulary naming the author's clients.
        // Checking only `template` is not enough — a name in a doc comment is
        // just as public once the repository is, and that is exactly where
        // one slipped through before this test was widened.
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // NativeVoiceCoreTests
            .deletingLastPathComponent()        // Tests
            .deletingLastPathComponent()        // package root
            .appendingPathComponent("Sources")

        let forbidden = ["Journeyman", "CFMOTO", "Fakturoid", "Helios",
                         "Nextup", "ISIR", "ISDS"]

        // Every source file, not just this module's: a name in any of them is
        // equally public once the repository is.
        let walker = FileManager.default.enumerator(at: sources,
                                                    includingPropertiesForKeys: nil)
        var checked = 0
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            checked += 1
            for name in forbidden {
                #expect(!(text.contains(name)),
                        "\(url.lastPathComponent) mentions \(name)")
            }
        }
        #expect(checked > 0, "found no sources to check — the path is wrong")

        for name in forbidden {
            #expect(!(Vocabulary.template.contains(name)), "template mentions \(name)")
        }
    }
}
