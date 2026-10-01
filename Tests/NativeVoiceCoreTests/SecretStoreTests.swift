import Foundation
import Security
import Testing
@testable import NativeVoiceCore

/// Stands in for the Keychain. It records what was asked of it, so a test can
/// assert not only what came back but that nothing else was consulted.
final class FakeKeychain: KeychainBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?
    private(set) var readCount = 0
    /// Forced status for the next read, used to simulate a locked keychain.
    var readStatusOverride: OSStatus?

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        lock.lock(); defer { lock.unlock() }
        readCount += 1
        if let forced = readStatusOverride { return (forced, nil) }
        guard let stored else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, stored)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        guard stored == nil else { return errSecDuplicateItem }
        stored = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        guard stored != nil else { return errSecItemNotFound }
        stored = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        guard stored != nil else { return errSecItemNotFound }
        stored = nil
        return errSecSuccess
    }
}

/// These run against the real `KeychainSecretStore` with a stand-in backend.
/// They must never touch the real Keychain: reading an item there raises an
/// authorization dialog, which would hang the suite.
@Suite struct KeychainSecretStoreTests {

    private func makeStore() -> (KeychainSecretStore, FakeKeychain) {
        let fake = FakeKeychain()
        return (KeychainSecretStore(backend: fake), fake)
    }

    @Test func startsEmpty() {
        let (store, _) = makeStore()
        #expect(store.apiKey() == nil)
        #expect(!(store.hasKey))
    }

    @Test func savesAndReadsBack() {
        let (store, _) = makeStore()
        #expect(store.save("sk_example"))
        #expect(store.apiKey() == "sk_example")
        #expect(store.hasKey)
    }

    @Test func trimsSurroundingWhitespace() {
        let (store, _) = makeStore()
        store.save("  sk_example\n")
        #expect(store.apiKey() == "sk_example")
    }

    @Test func emptyStringRemovesTheKey() {
        let (store, _) = makeStore()
        store.save("sk_example")
        #expect(store.save(""))
        #expect(store.apiKey() == nil)
    }

    @Test func whitespaceOnlyAlsoRemovesTheKey() {
        let (store, _) = makeStore()
        store.save("sk_example")
        store.save("   \n ")
        #expect(store.apiKey() == nil)
    }

    @Test func deleteIsIdempotent() {
        let (store, _) = makeStore()
        #expect(store.delete())
        #expect(store.delete())
        #expect(store.apiKey() == nil)
    }

    @Test func aDeletedKeyStaysDeletedWithNoSecondPlaceToLook() {
        // The invariant the whole file exists for, asserted against the real
        // class. The predecessor read a plain file as a backup and a deleted
        // key silently came back. If anyone ever adds a second lookup path,
        // the store will stop agreeing with its only backend and this fails.
        let (store, fake) = makeStore()
        store.save("sk_example")
        #expect(store.apiKey() == "sk_example")
        store.delete()
        #expect(store.apiKey() == nil)
        #expect(store.apiKey() == nil)
        #expect(fake.readCount > 0)     // it really did ask the backend
    }

    @Test func aFailedReadIsNotMistakenForNoKey() {
        // A locked keychain or a denied prompt must not be cached as "empty".
        let (store, fake) = makeStore()
        store.save("sk_example")
        _ = store.apiKey()

        let (store2, fake2) = (KeychainSecretStore(backend: fake), fake)
        fake2.readStatusOverride = errSecInteractionNotAllowed
        #expect(store2.apiKey() == nil)
        fake2.readStatusOverride = nil
        // A fresh store must find the key again — the failure was transient
        // and must not have destroyed anything.
        let store3 = KeychainSecretStore(backend: fake2)
        #expect(store3.apiKey() == "sk_example")
    }

    @Test func readsAreCachedSoTheKeychainIsNotAskedRepeatedly() {
        // Each read of a real Keychain item can raise a dialog, so asking
        // once per call would be unusable.
        let (store, fake) = makeStore()
        store.save("sk_example")
        _ = store.apiKey()
        let afterFirst = fake.readCount
        _ = store.apiKey()
        _ = store.apiKey()
        #expect(fake.readCount == afterFirst)
    }

    @Test func aWriteInvalidatesTheCache() {
        let (store, _) = makeStore()
        store.save("first")
        #expect(store.apiKey() == "first")
        store.save("second")
        #expect(store.apiKey() == "second")
    }
}

/// The in-memory store is a stand-in for previews; these cover its own
/// contract so it cannot drift from the protocol it implements.
@Suite struct InMemorySecretStoreTests {

    @Test func startsEmptyAndRoundTrips() {
        let store = InMemorySecretStore()
        #expect(store.apiKey() == nil)
        store.save("  sk_example  ")
        #expect(store.apiKey() == "sk_example")
        store.save("")
        #expect(store.apiKey() == nil)
    }

    @Test func honoursAnInitialValue() {
        #expect(InMemorySecretStore(initial: "sk_x").apiKey() == "sk_x")
    }
}
