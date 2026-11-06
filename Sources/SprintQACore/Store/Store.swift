import Foundation
import Security

/// Where the widget keeps what survives a relaunch: the token in the
/// Keychain (this device only), the bubble's place and the person's choice to
/// hide it in UserDefaults.
public protocol SecretStore: Sendable {
    func get(_ key: String) -> String?
    func set(_ key: String, _ value: String?)
}

public struct KeychainStore: SecretStore {
    private let service: String

    public init(service: String = "com.hortensia.sprint-qa") {
        self.service = service
    }

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }

    public func get(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ key: String, _ value: String?) {
        SecItemDelete(query(key) as CFDictionary)
        guard let value else { return }
        var q = query(key)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
}

public final class MemoryStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    public init() {}
    public func get(_ key: String) -> String? { lock.withLock { values[key] } }
    public func set(_ key: String, _ value: String?) { lock.withLock { values[key] = value } }
}

// UserDefaults is documented thread-safe.
public struct WidgetStorage: @unchecked Sendable {
    private let secrets: SecretStore
    private let defaults: UserDefaults

    public init(secrets: SecretStore = KeychainStore(), defaults: UserDefaults = .standard) {
        self.secrets = secrets
        self.defaults = defaults
    }

    public var pat: String? {
        get { secrets.get("pat") }
        nonmutating set { secrets.set("pat", newValue) }
    }

    /// Names this device's token, so signing in on one device never revokes
    /// another's. Generated once.
    public var deviceId: String {
        if let id = secrets.get("device-id") { return id }
        let id = "ios_" + UUID().uuidString.lowercased()
        secrets.set("device-id", id)
        return id
    }

    public var hidden: Bool {
        get { defaults.bool(forKey: "sprint-qa-hidden") }
        nonmutating set { defaults.set(newValue, forKey: "sprint-qa-hidden") }
    }

    public var bubblePosition: (x: Double, y: Double)? {
        get {
            guard let p = defaults.array(forKey: "sprint-qa-bubble") as? [Double], p.count == 2 else { return nil }
            return (p[0], p[1])
        }
        nonmutating set { defaults.set(newValue.map { [$0.x, $0.y] }, forKey: "sprint-qa-bubble") }
    }
}
