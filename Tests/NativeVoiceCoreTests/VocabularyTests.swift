import Testing
@testable import NativeVoiceCore

@Suite struct VocabularyTests {

    @Test func oneTermPerLine() {
        let terms = Vocabulary.terms(from: "Journeyman\nsafetensors\nWER")
        #expect(terms == ["Journeyman", "safetensors", "WER"])
    }

    @Test func ignoresCommentsAndBlankLines() {
        let text = """
        # One term per line
        Journeyman

           # indented comment
        safetensors
        """
        #expect(Vocabulary.terms(from: text) == ["Journeyman", "safetensors"])
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(Vocabulary.terms(from: "  Journeyman  \n\tsafetensors\t")
                == ["Journeyman", "safetensors"])
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

    @Test func templateIsEmptyOfTermsAndNamesNoCustomer() {
        // The predecessor shipped a vocabulary naming the author's clients.
        #expect(Vocabulary.terms(from: Vocabulary.template).isEmpty)
        let forbidden = ["Journeyman", "CFMOTO", "Fakturoid", "Helios",
                         "Nextup", "ISIR", "ISDS"]
        for name in forbidden {
            #expect(!(Vocabulary.template.contains(name)), "template mentions \(name)")
        }
    }
}
