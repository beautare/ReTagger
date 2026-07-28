//
//  KeychainStore.swift
//  ReTagger
//
//  登录凭据等敏感信息的 Keychain 存取工具
//

import Foundation
import Security
import OSLog

/// 基于 Keychain（kSecClassGenericPassword）的字符串存取工具，
/// 用于替代 UserDefaults 保存登录 token 等敏感凭据。
///
/// 统一走 data protection keychain（`kSecUseDataProtectionKeychain`）：访问授权由签名中的
/// keychain access group 决定，而非 login keychain 的 ACL 校验，因此换渠道（App Store /
/// 直发 DMG）、换开发者证书都不会再弹出"允许访问钥匙串"对话框。access group 两个渠道取值一致
/// （App Store 由 `com.apple.application-identifier` 提供，直发由 ReTagger-Direct.entitlements
/// 的 `keychain-access-groups` 提供），凭据可跨渠道沿用。
enum KeychainStore {
    private static let service = "vip.retagger.credentials"

    static func string(forKey key: String) -> String? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    static func setString(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        let query = baseQuery(forKey: key)
        let update: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            if addStatus != errSecSuccess {
                Logger.auth.error("Keychain 写入失败：\(addStatus)")
            }
        } else if status != errSecSuccess {
            Logger.auth.error("Keychain 更新失败：\(status)")
        }
    }

    static func removeValue(forKey key: String) {
        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Logger.auth.error("Keychain 删除失败：\(status)")
        }
    }

    private static func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]
    }
}
