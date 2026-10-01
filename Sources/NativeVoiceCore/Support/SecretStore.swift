import Foundation
import Security

/// Where the ElevenLabs API key is kept.
///
/// A protocol, not a concrete type, so a reader auditing what happens to
/// their key sees the whole surface in one short file.
public protocol SecretStore {
    func apiKey() -> String?
    @discardableResult func save(_ key: String) -> Bool
    @discardableResult func delete() -> Bool
}

public extension SecretStore {
    var hasKey: Bool { apiKey() != nil }
}

/// Normalizes what a user typed. Empty means "remove", not "store nothing".
func normalizedSecret(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

// MARK: - Keychain

/// The four Keychain operations this store needs.
///
/// It exists so the store's own logic can be tested. Reading a real Keychain
/// item raises an authorization dialog, which would hang a test suite and
/// teach the habit of clicking Allow on prompts nobody read — so no test may
/// touch the real Keychain. Without this seam the one invariant that matters
/// most here, *no fallback source*, could only be asserted against a stub
/// that was never capable of violating it.
public protocol KeychainBackend {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?)
    func add(_ attributes: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

/// The real thing. A thin pass-through, deliberately: everything worth
/// reviewing lives in `KeychainSecretStore`, where it can be tested.
public struct SystemKeychain: KeychainBackend {
    public init() {}

    public func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        return (status, out as? Data)
    }

    public func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    public func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

/// Keychain-backed store.
///
/// There is deliberately **no fallback source**. The predecessor project also
/// read a plain file, and because its "already migrated" flag was set on one
/// code path only, a key the user deleted from the Keychain silently came
/// back. A key the user deleted must stay deleted.
public final class KeychainSecretStore: SecretStore {
    private let service: String
    private let account: String
    private let backend: KeychainBackend

    private let lock = NSLock()
    private var cache: String??     // nil = not read yet, .some(nil) = no key
    /// Bumped by every write. A read that started before a write must not
    /// publish its now-stale result over the fresher state.
    private var generation: UInt64 = 0

    public init(service: String = "com.trustbe.nativevoice",
                account: String = "elevenlabs-api-key",
                backend: KeychainBackend = SystemKeychain()) {
        self.service = service
        self.account = account
        self.backend = backend
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func apiKey() -> String? {
        lock.lock()
        if let cached = cache { lock.unlock(); return cached }
        let startedAt = generation
        lock.unlock()

        // The query runs outside the lock on purpose: the Keychain can put up
        // an authorization dialog, and holding a lock across that would stall
        // every other thread behind a modal window.
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let (status, data) = backend.copyMatching(query)
        var result: String?
        switch status {
        case errSecSuccess:
            if let data, let text = String(data: data, encoding: .utf8) {
                result = normalizedSecret(text)
            } else {
                appLog("keychain returned an item that is not UTF-8 text")
            }
        case errSecItemNotFound:
            break   // No key yet. Expected, and not worth a log line.
        default:
            // Everything else is a real failure — a locked keychain, a denied
            // prompt, a damaged item. Reporting it as "no key configured"
            // without a trace would send the user looking in the wrong place.
            appLog("keychain read failed: OSStatus \(status)")
        }

        lock.lock()
        // Only publish if nothing was written while the query was in flight.
        // Without this check a save() that landed mid-read would be undone in
        // the cache and the stale value would persist until the next write.
        if generation == startedAt { cache = .some(result) }
        lock.unlock()
        return result
    }

    @discardableResult
    public func save(_ key: String) -> Bool {
        guard let value = normalizedSecret(key) else { return delete() }
        let data = Data(value.utf8)

        let updated = backend.update(baseQuery, [kSecValueData as String: data])
        switch updated {
        case errSecSuccess:
            invalidate(); return true
        case errSecItemNotFound:
            break           // Not there yet; fall through and add it.
        default:
            // Falling through on every error made the add below report a
            // duplicate instead of the real cause, such as a denied prompt.
            appLog("keychain update failed: OSStatus \(updated)")
            return false
        }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        let added = backend.add(attributes)
        guard added == errSecSuccess else {
            appLog("keychain add failed: OSStatus \(added)")
            return false
        }
        invalidate()
        return true
    }

    @discardableResult
    public func delete() -> Bool {
        let status = backend.delete(baseQuery)
        let ok = status == errSecSuccess || status == errSecItemNotFound
        if !ok { appLog("keychain delete failed: OSStatus \(status)") }
        invalidate()
        return ok
    }

    private func invalidate() {
        lock.lock()
        cache = nil
        generation &+= 1
        lock.unlock()
    }
}

// MARK: - In memory

/// For tests and SwiftUI previews.
///
/// It is `public` because previews live in the app target. Nothing in the
/// type system stops app code from using it by mistake, so whoever wires the
/// app together uses `KeychainSecretStore`; this one appears in no shipping
/// path.
public final class InMemorySecretStore: SecretStore {
    private let lock = NSLock()
    private var value: String?

    public init(initial: String? = nil) { self.value = initial }

    public func apiKey() -> String? { lock.lock(); defer { lock.unlock() }; return value }

    @discardableResult
    public func save(_ key: String) -> Bool {
        guard let normalized = normalizedSecret(key) else { return delete() }
        lock.lock(); value = normalized; lock.unlock()
        return true
    }

    @discardableResult
    public func delete() -> Bool {
        lock.lock(); value = nil; lock.unlock()
        return true
    }
}
