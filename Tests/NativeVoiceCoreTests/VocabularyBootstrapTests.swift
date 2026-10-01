import Foundation
import Testing
@testable import NativeVoiceCore

@Suite struct VocabularyBootstrapTests {

    private func scratchDirectory() -> String {
        NSTemporaryDirectory() + "nativevoice-vocab-\(UUID().uuidString)"
    }

    @Test func aMissingFileIsCreatedFromTheTemplate() throws {
        // Review Focus 5: an "Edit vocabulary…" row that opens nothing is
        // worse than no row at all.
        let path = scratchDirectory() + "/vocabulary.txt"
        #expect(Vocabulary.ensureFile(at: path))
        let written = try String(contentsOfFile: path, encoding: .utf8)
        #expect(written == Vocabulary.template)
    }

    @Test func anExistingFileIsLeftAlone() throws {
        let path = scratchDirectory() + "/vocabulary.txt"
        #expect(Vocabulary.ensureFile(at: path))
        try "my own terms\n".write(toFile: path, atomically: true, encoding: .utf8)
        #expect(Vocabulary.ensureFile(at: path))
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "my own terms\n")
    }

    @Test func theDirectoryIsNotReadableByOtherAccounts() throws {
        // The file holds names, clients and places someone dictates about.
        let path = scratchDirectory() + "/vocabulary.txt"
        #expect(Vocabulary.ensureFile(at: path))
        let directory = (path as NSString).deletingLastPathComponent
        let mode = try FileManager.default
            .attributesOfItem(atPath: directory)[.posixPermissions] as? NSNumber
        #expect(mode?.int16Value == 0o700)
    }

    @Test func anUnwritablePathIsReportedRatherThanIgnored() {
        #expect(!Vocabulary.ensureFile(at: "/vocabulary-nobody-can-write.txt"))
    }
}
