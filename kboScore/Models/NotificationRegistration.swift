//
//  NotificationRegistration.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import Foundation

enum NotificationAlertType: String, Codable, CaseIterable, Sendable {
    case gameStart
    case scoreChange
    case leadChange
    case gameEnd
    case rainDelay
}

struct NotificationRegistrationQuietHours: Codable, Equatable, Sendable {
    let startHour: Int
    let endHour: Int

    nonisolated init(startHour: Int, endHour: Int) {
        self.startHour = startHour
        self.endHour = endHour
    }
}

struct NotificationRegistrationPayload: Codable, Equatable, Sendable {
    let platform: String
    let environment: String
    let deviceToken: String
    let installationId: String
    let favoriteTeamID: String?
    let notificationsAuthorized: Bool
    let alertTypes: [NotificationAlertType]
    let quietHours: NotificationRegistrationQuietHours?

    private enum CodingKeys: String, CodingKey {
        case platform
        case environment
        case deviceToken
        case installationId
        case favoriteTeamID
        case notificationsAuthorized
        case alertTypes
        case quietHours
    }

    nonisolated init(
        platform: String = "ios",
        environment: String = NotificationRegistrationEnvironment.current,
        deviceToken: String,
        installationId: String = NotificationInstallationID.current,
        favoriteTeamID: String?,
        notificationsAuthorized: Bool,
        alertTypes: [NotificationAlertType],
        quietHours: NotificationRegistrationQuietHours?
    ) {
        self.platform = platform
        self.environment = environment
        self.deviceToken = deviceToken
        self.installationId = installationId
        self.favoriteTeamID = favoriteTeamID
        self.notificationsAuthorized = notificationsAuthorized
        self.alertTypes = alertTypes
        self.quietHours = quietHours
    }

    nonisolated init?(
        deviceToken: String?,
        settings: AppSettings,
        authorizationStatus: AppNotificationAuthorizationStatus
    ) {
        guard let deviceToken, deviceToken.isEmpty == false else { return nil }

        self.init(
            deviceToken: deviceToken,
            favoriteTeamID: settings.favoriteTeamID,
            notificationsAuthorized: authorizationStatus.allowsNotifications,
            alertTypes: NotificationAlertType.enabled(from: settings.notificationPreferences),
            quietHours: settings.quietHours.isEnabled
                ? NotificationRegistrationQuietHours(
                    startHour: settings.quietHours.startHour,
                    endHour: settings.quietHours.endHour
                )
                : nil
        )
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        platform = try container.decodeIfPresent(String.self, forKey: .platform) ?? "ios"
        environment = try container.decodeIfPresent(String.self, forKey: .environment) ?? NotificationRegistrationEnvironment.current
        deviceToken = try container.decode(String.self, forKey: .deviceToken)
        installationId = try container.decodeIfPresent(String.self, forKey: .installationId) ?? NotificationInstallationID.current
        favoriteTeamID = try container.decodeIfPresent(String.self, forKey: .favoriteTeamID)
        notificationsAuthorized = try container.decode(Bool.self, forKey: .notificationsAuthorized)
        alertTypes = try container.decode([NotificationAlertType].self, forKey: .alertTypes)
        quietHours = try container.decodeIfPresent(NotificationRegistrationQuietHours.self, forKey: .quietHours)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(platform, forKey: .platform)
        try container.encode(environment, forKey: .environment)
        try container.encode(deviceToken, forKey: .deviceToken)
        try container.encode(installationId, forKey: .installationId)
        try container.encodeIfPresent(favoriteTeamID, forKey: .favoriteTeamID)
        try container.encode(notificationsAuthorized, forKey: .notificationsAuthorized)
        try container.encode(alertTypes, forKey: .alertTypes)
        try container.encodeIfPresent(quietHours, forKey: .quietHours)
    }
}

enum NotificationInstallationID {
    nonisolated static var current: String {
        let storageKey = "notificationInstallationID"
        if let persisted = UserDefaults.standard.string(forKey: storageKey),
           persisted.isEmpty == false {
            return persisted
        }

        let generated = UUID().uuidString.lowercased()
        UserDefaults.standard.set(generated, forKey: storageKey)
        return generated
    }
}

enum NotificationRegistrationEnvironment {
    nonisolated static var current: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }
}

extension NotificationAlertType {
    nonisolated static func enabled(from preferences: NotificationPreferences) -> [NotificationAlertType] {
        var alertTypes: [NotificationAlertType] = []
        if preferences.gameStart { alertTypes.append(.gameStart) }
        if preferences.scoreChange { alertTypes.append(.scoreChange) }
        if preferences.leadChange { alertTypes.append(.leadChange) }
        if preferences.gameEnd { alertTypes.append(.gameEnd) }
        if preferences.rainDelay { alertTypes.append(.rainDelay) }
        return alertTypes
    }
}

enum NotificationRegistrationSyncStatus: String, Sendable {
    case idle = "대기"
    case waitingForToken = "토큰 대기"
    case skipped = "백엔드 미설정"
    case syncing = "동기화 중"
    case synced = "동기화 완료"
    case failed = "동기화 실패"
}
