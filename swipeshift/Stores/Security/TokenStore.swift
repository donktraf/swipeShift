//
//  TokenStore.swift
//  swipeShift
//
//  Created by DON on 03.01.26.
//

import Foundation
import Security

final class TokenStore {
    static let shared = TokenStore()
    private init() {}

    private let service = Bundle.main.bundleIdentifier ?? "swipeshift"
    private let account = "auth_token"

    func saveToken(_ token: String) {
        #if DEBUG
        if DebugLaunch.bypassesKeychain { return } // Debug-Launch: nie in den Keychain schreiben
        #endif
        let data = Data(token.utf8)

        // Delete old item first (simplest, reliable)
        deleteToken()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // optional: only this device
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("🔐 Keychain saveToken failed:", status)
        }
    }

    func getToken() -> String? {
        #if DEBUG
        if DebugLaunch.bypassesKeychain { return DebugLaunch.token } // SS_DEBUG_TOKEN statt Keychain
        #endif
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return token
    }

    // MARK: Ausstehende Push-Abmeldungen (JSON; enthaelt alte Auth-Token → ebenfalls im Keychain)

    private let pendingUnregisterAccount = "pending_push_unregister"

    func savePendingUnregisterData(_ data: Data) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: pendingUnregisterAccount
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    func loadPendingUnregisterData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: pendingUnregisterAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    func deletePendingUnregisterData() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: pendingUnregisterAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    func deleteToken() {
        #if DEBUG
        if DebugLaunch.bypassesKeychain { return }
        #endif
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
