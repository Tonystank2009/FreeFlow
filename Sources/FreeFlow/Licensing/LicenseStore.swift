//
//  LicenseStore.swift
//  FreeFlow
//
//  Keychain persistence for the activated licence, plus the free-dictation
//  counter that gates the trial.
//

import Foundation
import Security

struct LicenseRecord: Codable, Equatable {
    var licenseKey: String
    var instanceID: String
    var licenseKeyID: String
    var productID: String
    var customerEmail: String?
    var activatedAt: Date
    /// Last time Dodo affirmatively told us this licence is still good.
    var lastValidatedAt: Date

    /// Shown in Settings so the user can confirm which key is installed
    /// without exposing the whole thing over a shoulder or in a screenshot.
    var maskedKey: String {
        let cleaned = self.licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > 8 else { return String(repeating: "•", count: max(cleaned.count, 4)) }
        return "\(cleaned.prefix(4))••••••••\(cleaned.suffix(4))"
    }
}

// MARK: - Keychain-backed licence storage

enum LicenseStore {
    private static let service = "com.freeflowapp.license"
    private static let account = "activation"

    static func load() -> LicenseRecord? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }

        return try? JSONDecoder().decode(LicenseRecord.self, from: data)
    }

    static func save(_ record: LicenseRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // Licences should survive reboot but never sync to iCloud.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { current, _ in current }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Account session storage

/// Keychain-backed storage for the Supabase session and the last known
/// entitlement.
///
/// The entitlement is cached deliberately: once someone has paid, FreeFlow must
/// keep working on a plane, behind a firewall, or if Supabase is down. The
/// cache is only ever cleared by an explicit sign-out or by the server actively
/// saying the entitlement is gone.
enum AccountStore {
    private static let service = "com.freeflowapp.account"
    private static let sessionAccount = "supabase-session"
    private static let entitlementAccount = "entitlement-cache"

    // Session

    static func loadSession() -> SupabaseSession? {
        self.read(account: self.sessionAccount).flatMap {
            try? JSONDecoder().decode(SupabaseSession.self, from: $0)
        }
    }

    static func saveSession(_ session: SupabaseSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        self.write(data, account: self.sessionAccount)
    }

    static func clearSession() {
        self.delete(account: self.sessionAccount)
    }

    // Cached entitlement

    static func loadEntitlement() -> Entitlement? {
        self.read(account: self.entitlementAccount).flatMap {
            try? JSONDecoder().decode(Entitlement.self, from: $0)
        }
    }

    static func saveEntitlement(_ entitlement: Entitlement) {
        guard let data = try? JSONEncoder().encode(entitlement) else { return }
        self.write(data, account: self.entitlementAccount)
    }

    static func clearEntitlement() {
        self.delete(account: self.entitlementAccount)
    }

    static func clearAll() {
        self.clearSession()
        self.clearEntitlement()
    }

    // MARK: Keychain primitives

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read(account: String) -> Data? {
        var query = self.baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func write(_ data: Data, account: String) {
        let query = self.baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { current, _ in current }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    private static func delete(account: String) {
        SecItemDelete(self.baseQuery(account: account) as CFDictionary)
    }
}

// MARK: - Trial counter

/// Counts completed dictations before the paywall.
///
/// Mirrored across UserDefaults and a file in Application Support, reading
/// whichever is higher. That stops an accidental `defaults delete` from
/// silently handing out another five, without pretending to be copy
/// protection — FreeFlow is GPL-3, so anyone who wants the counter gone can
/// simply delete the check and rebuild. The honest ask is the point.
enum TrialCounter {
    private static let defaultsKey = "FreeFlow_TrialDictationsUsed"

    private static var mirrorURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let directory = base.appendingPathComponent(Brand.appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(".trial", isDirectory: false)
    }

    static var used: Int {
        let fromDefaults = UserDefaults.standard.integer(forKey: self.defaultsKey)

        var fromMirror = 0
        if let url = mirrorURL,
           let text = try? String(contentsOf: url, encoding: .utf8),
           let parsed = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            fromMirror = parsed
        }

        return max(fromDefaults, fromMirror)
    }

    static func increment() {
        let next = self.used + 1
        UserDefaults.standard.set(next, forKey: self.defaultsKey)
        if let url = mirrorURL {
            try? String(next).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static var remaining: Int {
        max(0, Brand.Purchase.freeDictations - self.used)
    }

    /// Debug/support affordance — also what a refunded user would need.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: self.defaultsKey)
        if let url = mirrorURL { try? FileManager.default.removeItem(at: url) }
    }
}
