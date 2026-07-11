//
//  AppModelPersistenceStore.swift
//  kboScore
//  기능 설명: 앱 설정과 로컬 사용자 상태를 영구 저장소에 읽고 쓰는 기능을 담당합니다.
//  여러 화면과 시스템 기능이 같은 경기 데이터를 보도록 앱 전역 상태와 부수 효과를 한곳에서 조정합니다.
//  비동기 새로고침, 캐시, 알림, 위젯 갱신이 동시에 발생할 수 있어 중복 실행과 오래된 응답을 방어합니다.
//  TODO : 상태 전이를 더 작은 도메인 서비스로 나누고 관찰 가능한 부수 효과를 테스트로 고정합니다.
//
//  Created by Codex on 5/14/26.
//

import Foundation

// AppModelPersistenceStore 열거형는 AppModelPersistenceStore 타입의 역할과 값을 정의합니다.
enum AppModelPersistenceStore {
    private static let settingsStorageKey = "kbo_live_app_settings"
    private static let deviceTokenStorageKey = "kbo_live_apns_device_token"
    private static let notificationHistoryStorageKey = "kbo_live_notification_history"
    private static let attendedGamesStorageKey = "kbo_live_attended_game_keys"
    private static let cancellationNotificationStorageKey = "kbo_live_cancellation_notification_keys"
    private static let onboardingCompletionStorageKey = "kbo_live_onboarding_completed"

    // saveSettings 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    static func saveSettings(_ settings: AppSettings) {
        guard let encoded = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(encoded, forKey: settingsStorageKey)
    }

    // loadSettings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    static func loadSettings() -> AppSettings? {
        guard let data = UserDefaults.standard.data(forKey: settingsStorageKey) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    // saveDeviceToken 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    static func saveDeviceToken(_ token: String) {
        _ = APNsDeviceTokenStore.save(token)
        UserDefaults.standard.removeObject(forKey: deviceTokenStorageKey)
    }

    // loadDeviceToken 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    static func loadDeviceToken() -> String? {
        APNsDeviceTokenStore.loadOrMigrateLegacyValue(legacyKey: deviceTokenStorageKey)
    }

    // saveNotificationHistory 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    static func saveNotificationHistory(_ notifications: [NotificationItem]) {
        guard let encoded = try? JSONEncoder().encode(notifications) else { return }
        UserDefaults.standard.set(encoded, forKey: notificationHistoryStorageKey)
    }

    // loadNotificationHistory 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    static func loadNotificationHistory() -> [NotificationItem] {
        guard let data = UserDefaults.standard.data(forKey: notificationHistoryStorageKey),
              let decoded = try? JSONDecoder().decode([NotificationItem].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.sentAt > $1.sentAt }
    }

    // saveAttendedGameKeys 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    static func saveAttendedGameKeys(_ attendedGameKeys: Set<String>) {
        guard let encoded = try? JSONEncoder().encode(Array(attendedGameKeys).sorted()) else { return }
        UserDefaults.standard.set(encoded, forKey: attendedGamesStorageKey)
    }

    // loadAttendedGameKeys 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    static func loadAttendedGameKeys() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: attendedGamesStorageKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(decoded)
    }

    // saveCancellationNotificationKeys 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    static func saveCancellationNotificationKeys(_ notifiedCancellationKeys: Set<String>) {
        guard let encoded = try? JSONEncoder().encode(Array(notifiedCancellationKeys).sorted()) else { return }
        UserDefaults.standard.set(encoded, forKey: cancellationNotificationStorageKey)
    }

    // loadCancellationNotificationKeys 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    static func loadCancellationNotificationKeys() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: cancellationNotificationStorageKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(decoded)
    }

    // saveOnboardingCompletion 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    static func saveOnboardingCompletion(_ hasCompletedOnboarding: Bool) {
        UserDefaults.standard.set(hasCompletedOnboarding, forKey: onboardingCompletionStorageKey)
    }

    // loadOnboardingCompletion 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    static func loadOnboardingCompletion() -> Bool? {
        guard UserDefaults.standard.object(forKey: onboardingCompletionStorageKey) != nil else {
            return nil
        }
        return UserDefaults.standard.bool(forKey: onboardingCompletionStorageKey)
    }
}
