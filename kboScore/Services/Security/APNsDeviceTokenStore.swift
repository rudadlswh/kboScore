//
//  APNsDeviceTokenStore.swift
//  kboScore
//  기능 설명: APNs 디바이스 토큰을 안전하게 저장하고 조회합니다.
//  APNs 디바이스 토큰을 안전하게 저장하고 조회합니다.을 명확히 분리해 변경 범위와 책임을 예측 가능하게 유지합니다.
//  입력 데이터 누락, 비동기 실행 순서, 플랫폼별 동작 차이를 고려해 방어적으로 처리합니다.
//  TODO : 반복되는 정책이나 화면 상태가 늘어나면 전용 모델과 테스트로 분리합니다.
//
//  Created by Codex on 4/24/26.
//

import Foundation
import Security

// APNsDeviceTokenStore 열거형는 APNsDeviceTokenStore 타입의 역할과 값을 정의합니다.
enum APNsDeviceTokenStore {
    private static let service = "com.chogm.kboScore.apns-device-token"
    private static let account = "apns-device-token"

    // load 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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

    // save 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
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

    // loadOrMigrateLegacyValue 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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

    // baseQuery 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
