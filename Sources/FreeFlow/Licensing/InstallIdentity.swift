//
//  InstallIdentity.swift
//  FreeFlow
//
//  A stable, anonymous identifier for this install, used only to anchor the
//  free formatting trial.
//

import Foundation
import Security

/// Identifies an install so a 14-day trial can start once and not restart.
///
/// Stored in the Keychain rather than UserDefaults because the Keychain
/// survives deleting and reinstalling the app — otherwise the trial resets on
/// every reinstall. It is a random UUID: it says nothing about the machine or
/// the person, and it is never sent anywhere except FreeFlow's own formatting
/// endpoint.
enum InstallIdentity {
    private static let service = "com.freeflowapp.install"
    private static let account = "trial-id"

    static var current: String {
        if let existing = self.read() { return existing }
        let fresh = UUID().uuidString
        self.write(fresh)
        return fresh
    }

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    private static func write(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { current, _ in current }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }
}
