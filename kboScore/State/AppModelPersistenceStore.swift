//
//  AppModelPersistenceStore.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

enum AppModelPersistenceStore {
    private static let settingsStorageKey = "kbo_live_app_settings"
    private static let deviceTokenStorageKey = "kbo_live_apns_device_token"
    private static let notificationHistoryStorageKey = "kbo_live_notification_history"
    private static let attendedGamesStorageKey = "kbo_live_attended_game_keys"
    private static let cancellationNotificationStorageKey = "kbo_live_cancellation_notification_keys"
    private static let onboardingCompletionStorageKey = "kbo_live_onboarding_completed"

    static func saveSettings(_ settings: AppSettings) {
        guard let encoded = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(encoded, forKey: settingsStorageKey)
    }

    static func loadSettings() -> AppSettings? {
        guard let data = UserDefaults.standard.data(forKey: settingsStorageKey) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    static func saveDeviceToken(_ token: String) {
        _ = APNsDeviceTokenStore.save(token)
        UserDefaults.standard.removeObject(forKey: deviceTokenStorageKey)
    }

    static func loadDeviceToken() -> String? {
        APNsDeviceTokenStore.loadOrMigrateLegacyValue(legacyKey: deviceTokenStorageKey)
    }

    static func saveNotificationHistory(_ notifications: [NotificationItem]) {
        guard let encoded = try? JSONEncoder().encode(notifications) else { return }
        UserDefaults.standard.set(encoded, forKey: notificationHistoryStorageKey)
    }

    static func loadNotificationHistory() -> [NotificationItem] {
        guard let data = UserDefaults.standard.data(forKey: notificationHistoryStorageKey),
              let decoded = try? JSONDecoder().decode([NotificationItem].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.sentAt > $1.sentAt }
    }

    static func saveAttendedGameKeys(_ attendedGameKeys: Set<String>) {
        guard let encoded = try? JSONEncoder().encode(Array(attendedGameKeys).sorted()) else { return }
        UserDefaults.standard.set(encoded, forKey: attendedGamesStorageKey)
    }

    static func loadAttendedGameKeys() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: attendedGamesStorageKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(decoded)
    }

    static func saveCancellationNotificationKeys(_ notifiedCancellationKeys: Set<String>) {
        guard let encoded = try? JSONEncoder().encode(Array(notifiedCancellationKeys).sorted()) else { return }
        UserDefaults.standard.set(encoded, forKey: cancellationNotificationStorageKey)
    }

    static func loadCancellationNotificationKeys() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: cancellationNotificationStorageKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(decoded)
    }

    static func saveOnboardingCompletion(_ hasCompletedOnboarding: Bool) {
        UserDefaults.standard.set(hasCompletedOnboarding, forKey: onboardingCompletionStorageKey)
    }

    static func loadOnboardingCompletion() -> Bool? {
        guard UserDefaults.standard.object(forKey: onboardingCompletionStorageKey) != nil else {
            return nil
        }
        return UserDefaults.standard.bool(forKey: onboardingCompletionStorageKey)
    }
}
