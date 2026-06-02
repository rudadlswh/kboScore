//
//  APNsDeviceTokenStore.swift
//  kboScore
//
//  Created by Codex on 4/24/26.
//

import Foundation
import Security

enum APNsDeviceTokenStore {
    private static let service = "com.chogm.kboScore.apns-device-token"
    private static let account = "apns-device-token"

    static func load() -> String? {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              token.isEmpty == false else {
            return nil
        }
        return token
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8), token.isEmpty == false else {
            return false
        }

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(baseQuery() as CFDictionary, updateAttributes as CFDictionary)
        if status == errSecSuccess {
            return true
        }
        if status != errSecItemNotFound {
            return false
        }

        var insertQuery = baseQuery()
        insertQuery[kSecValueData as String] = data
        insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(insertQuery as CFDictionary, nil) == errSecSuccess
    }

    static func loadOrMigrateLegacyValue(
        legacyDefaults: UserDefaults = .standard,
        legacyKey: String
    ) -> String? {
        if let token = load() {
            legacyDefaults.removeObject(forKey: legacyKey)
            return token
        }

        guard let legacyToken = legacyDefaults.string(forKey: legacyKey),
              legacyToken.isEmpty == false else {
            return nil
        }

        if save(legacyToken) {
            legacyDefaults.removeObject(forKey: legacyKey)
        }
        return legacyToken
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
