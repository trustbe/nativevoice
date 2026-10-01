import Foundation
import Security

/// Where the ElevenLabs API key lives.
///
/// A protocol, not a concrete type, for two reasons: tests must not touch the
/// user's login keychain (reading an item raises an authorization dialog), and
/// a reader auditing what happens to their key can see the whole surface in
/// one short file.
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

/// Keychain-backed store.
///
/// There is deliberately **no fallback source**. The predecessor also read a
/// plain file, and because the "already migrated" flag was only set on one
/// code path, deleting the key from the Keychain silently restored it from
/// that file. A key the user deleted must stay deleted.
public final class KeychainSecretStore: SecretStore {
    private let service: String
    private let account: String
    private let lock = NSLock()
    private var cache: String??     // nil = not read yet, .some(nil) = no key

    public init(service: String = "com.trustbe.nativevoice",
                account: String = "elevenlabs-api-key") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func apiKey() -> String? {
        lock.lock()
        if let cached = cache { lock.unlock(); return cached }
        lock.unlock()

        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var out: AnyObject?
        var result: String?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
           let data = out as? Data, let text = String(data: data, encoding: .utf8) {
            result = normalizedSecret(text)
        }

        lock.lock(); cache = .some(result); lock.unlock()
        return result
    }

    @discardableResult
    public func save(_ key: String) -> Bool {
        guard let value = normalizedSecret(key) else { return delete() }
        let data = Data(value.utf8)

        let update = SecItemUpdate(baseQuery as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        switch update {
        case errSecSuccess:
            invalidate(); return true
        case errSecItemNotFound:
            break
        default:
            // Falling through on every error made SecItemAdd report a
            // duplicate instead of the real cause, such as a denied dialog.
            appLog("keychain update failed: OSStatus \(update)")
            return false
        }

        var add = baseQuery
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            appLog("keychain add failed: OSStatus \(status)")
            return false
        }
        invalidate()
        return true
    }

    @discardableResult
    public func delete() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        invalidate()
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func invalidate() { lock.lock(); cache = nil; lock.unlock() }
}

/// Used by tests and by previews. Never reaches a shipping build path.
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
