import Testing
@testable import NativeVoiceCore

@Suite struct SecretStoreTests {

    // The real Keychain is not touched here. Tests against the login keychain
    // raise an authorization dialog, which would hang CI and, worse, train
    // the developer to click Allow on prompts they did not read.
    private func makeStore() -> InMemorySecretStore { InMemorySecretStore() }

    @Test func startsEmpty() {
        #expect(makeStore().apiKey() == nil)
        #expect(!(makeStore()).hasKey)
    }

    @Test func savesAndReadsBack() {
        let s = makeStore()
        #expect(s.save("sk_example"))
        #expect(s.apiKey() == "sk_example")
        #expect(s.hasKey)
    }

    @Test func trimsSurroundingWhitespace() {
        let s = makeStore()
        s.save("  sk_example\n")
        #expect(s.apiKey() == "sk_example")
    }

    @Test func emptyStringRemovesTheKey() {
        let s = makeStore()
        s.save("sk_example")
        #expect(s.save(""))
        #expect(s.apiKey() == nil)
        #expect(!(s.hasKey))
    }

    @Test func whitespaceOnlyAlsoRemovesTheKey() {
        let s = makeStore()
        s.save("sk_example")
        s.save("   \n ")
        #expect(s.apiKey() == nil)
    }

    @Test func deleteIsIdempotent() {
        let s = makeStore()
        #expect(s.delete())
        #expect(s.delete())
        #expect(s.apiKey() == nil)
    }

    @Test func deletedKeyStaysDeleted() {
        // The predecessor read a plain file as a fallback and a deleted key
        // silently came back. There is no fallback source here at all, and
        // this test exists to keep it that way.
        let s = makeStore()
        s.save("sk_example")
        s.delete()
        #expect(s.apiKey() == nil)
        #expect(s.apiKey() == nil)
    }
}
