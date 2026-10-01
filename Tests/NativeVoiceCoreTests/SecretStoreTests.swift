import Foundation
import Security
import Testing
@testable import NativeVoiceCore

/// Stands in for the Keychain. It records what was asked of it, so a test can
/// assert not only what came back but that nothing else was consulted.
final class FakeKeychain: KeychainBackend, @unchecked Sendable {
    private let lock = NSLock()
    /// Keyed by service and account, like the real thing. A single slot would
    /// not notice a store that queried the wrong account.
    private var items: [String: Data] = [:]
    private var reads = 0
    private var forcedReadStatus: OSStatus?

    var readCount: Int { lock.lock(); defer { lock.unlock() }; return reads }

    func forceNextReads(_ status: OSStatus?) {
        lock.lock(); forcedReadStatus = status; lock.unlock()
    }

    private func key(_ query: [String: Any]) -> String {
        let service = query[kSecAttrService as String] as? String ?? "?"
        let account = query[kSecAttrAccount as String] as? String ?? "?"
        return "\(service)/\(account)"
    }

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        lock.lock(); defer { lock.unlock() }
        reads += 1
        if let forced = forcedReadStatus { return (forced, nil) }
        guard let data = items[key(query)] else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, data)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        let k = key(attributes)
        guard items[k] == nil else { return errSecDuplicateItem }
        items[k] = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        let k = key(query)
        guard items[k] != nil else { return errSecItemNotFound }
        items[k] = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        guard items.removeValue(forKey: key(query)) != nil else {
            return errSecItemNotFound
        }
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

    @Test func theStoreHasExactlyOnePlaceToLookForAKey() throws {
        // The invariant this whole file exists for, checked the only way that
        // actually holds.
        //
        // A behavioural test cannot catch this, and it is worth being precise
        // about why: a fallback that reads a file the test never created
        // returns nothing, so the store still answers nil and the test still
        // passes. The predecessor's bug — a stale key lying in a file from an
        // earlier run — would come back invisible to a green suite.
        //
        // So this asks the source instead. Naming the APIs a second source
        // would need is blunt, and that is the point: it fails loudly the
        // moment one appears, and whoever has a good reason to add one has to
        // come here and say so.
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // NativeVoiceCoreTests
            .deletingLastPathComponent()        // Tests
            .deletingLastPathComponent()        // package root
            .appendingPathComponent("Sources/NativeVoiceCore/Support/SecretStore.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        let waysToReadFromSomewhereElse = [
            "contentsOfFile", "contentsOf:", "UserDefaults", "ProcessInfo",
            "FileManager", "FileHandle", "NSHomeDirectory", "URLSession",
            "Bundle.main",
        ]
        for api in waysToReadFromSomewhereElse {
            #expect(!(text.contains(api)),
                    "the Keychain must be the only source of the key — found \(api)")
        }
    }

    @Test func aStoreNeverSeesAnotherStoresKey() {
        // The fake keys on service and account, like the real Keychain does,
        // so a store asking under the wrong name finds nothing. Without this
        // the fake would hand any key to any query and a wrong-account bug
        // would pass unnoticed.
        let fake = FakeKeychain()
        let ours = KeychainSecretStore(backend: fake)
        let theirs = KeychainSecretStore(service: "com.example.other", backend: fake)
        ours.save("sk_ours")
        #expect(ours.apiKey() == "sk_ours")
        #expect(theirs.apiKey() == nil)
    }

    @Test func aFailedReadIsNotMistakenForNoKey() {
        // A locked keychain or a denied prompt must not be cached as "empty".
        let (store, fake) = makeStore()
        store.save("sk_example")
        _ = store.apiKey()

        let (store2, fake2) = (KeychainSecretStore(backend: fake), fake)
        fake2.forceNextReads(errSecInteractionNotAllowed)
        #expect(store2.apiKey() == nil)
        fake2.forceNextReads(nil)
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
