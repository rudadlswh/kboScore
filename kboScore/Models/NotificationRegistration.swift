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
    let gameStartEnabled: Bool
    let scoreChangeEnabled: Bool
    let leadChangeEnabled: Bool
    let gameEndEnabled: Bool
    let onBaseEnabled: Bool
    let inningChangeEnabled: Bool
    let favoriteTeamOnlyEnabled: Bool
    let muteWhenLosingEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case platform
        case environment
        case deviceToken
        case installationId
        case favoriteTeamID
        case notificationsAuthorized
        case alertTypes
        case quietHours
        case gameStartEnabled
        case scoreChangeEnabled
        case leadChangeEnabled
        case gameEndEnabled
        case onBaseEnabled
        case inningChangeEnabled
        case favoriteTeamOnlyEnabled
        case muteWhenLosingEnabled
    }

    nonisolated init(
        platform: String = "ios",
        environment: String = NotificationRegistrationEnvironment.current,
        deviceToken: String,
        installationId: String = NotificationInstallationID.current,
        favoriteTeamID: String?,
        notificationsAuthorized: Bool,
        alertTypes: [NotificationAlertType],
        quietHours: NotificationRegistrationQuietHours?,
        gameStartEnabled: Bool = true,
        scoreChangeEnabled: Bool = true,
        leadChangeEnabled: Bool = true,
        gameEndEnabled: Bool = true,
        onBaseEnabled: Bool = false,
        inningChangeEnabled: Bool = false,
        favoriteTeamOnlyEnabled: Bool = false,
        muteWhenLosingEnabled: Bool = false
    ) {
        self.platform = platform
        self.environment = environment
        self.deviceToken = deviceToken
        self.installationId = installationId
        self.favoriteTeamID = favoriteTeamID
        self.notificationsAuthorized = notificationsAuthorized
        self.alertTypes = alertTypes
        self.quietHours = quietHours
        self.gameStartEnabled = gameStartEnabled
        self.scoreChangeEnabled = scoreChangeEnabled
        self.leadChangeEnabled = leadChangeEnabled
        self.gameEndEnabled = gameEndEnabled
        self.onBaseEnabled = onBaseEnabled
        self.inningChangeEnabled = inningChangeEnabled
        self.favoriteTeamOnlyEnabled = favoriteTeamOnlyEnabled
        self.muteWhenLosingEnabled = muteWhenLosingEnabled
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
                : nil,
            gameStartEnabled: settings.notificationPreferences.gameStartEnabled,
            scoreChangeEnabled: settings.notificationPreferences.scoreChangeEnabled,
            leadChangeEnabled: settings.notificationPreferences.leadChangeEnabled,
            gameEndEnabled: settings.notificationPreferences.gameEndEnabled,
            onBaseEnabled: settings.notificationPreferences.onBaseEnabled,
            inningChangeEnabled: settings.notificationPreferences.inningChangeEnabled,
            favoriteTeamOnlyEnabled: settings.notificationPreferences.favoriteTeamOnlyEnabled,
            muteWhenLosingEnabled: settings.notificationPreferences.muteWhenLosingEnabled
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
        gameStartEnabled = try container.decodeIfPresent(Bool.self, forKey: .gameStartEnabled) ?? true
        scoreChangeEnabled = try container.decodeIfPresent(Bool.self, forKey: .scoreChangeEnabled) ?? true
        leadChangeEnabled = try container.decodeIfPresent(Bool.self, forKey: .leadChangeEnabled) ?? true
        gameEndEnabled = try container.decodeIfPresent(Bool.self, forKey: .gameEndEnabled) ?? true
        onBaseEnabled = try container.decodeIfPresent(Bool.self, forKey: .onBaseEnabled) ?? false
        inningChangeEnabled = try container.decodeIfPresent(Bool.self, forKey: .inningChangeEnabled) ?? false
        favoriteTeamOnlyEnabled = try container.decodeIfPresent(Bool.self, forKey: .favoriteTeamOnlyEnabled) ?? false
        muteWhenLosingEnabled = try container.decodeIfPresent(Bool.self, forKey: .muteWhenLosingEnabled) ?? false
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
        try container.encode(gameStartEnabled, forKey: .gameStartEnabled)
        try container.encode(scoreChangeEnabled, forKey: .scoreChangeEnabled)
        try container.encode(leadChangeEnabled, forKey: .leadChangeEnabled)
        try container.encode(gameEndEnabled, forKey: .gameEndEnabled)
        try container.encode(onBaseEnabled, forKey: .onBaseEnabled)
        try container.encode(inningChangeEnabled, forKey: .inningChangeEnabled)
        try container.encode(favoriteTeamOnlyEnabled, forKey: .favoriteTeamOnlyEnabled)
        try container.encode(muteWhenLosingEnabled, forKey: .muteWhenLosingEnabled)
    }
}

extension NotificationRegistrationPayload {
    nonisolated var debugBooleanDescription: String {
        [
            "gameStartEnabled=\(gameStartEnabled)",
            "scoreChangeEnabled=\(scoreChangeEnabled)",
            "leadChangeEnabled=\(leadChangeEnabled)",
            "gameEndEnabled=\(gameEndEnabled)",
            "onBaseEnabled=\(onBaseEnabled)",
            "inningChangeEnabled=\(inningChangeEnabled)",
            "favoriteTeamOnlyEnabled=\(favoriteTeamOnlyEnabled)",
            "muteWhenLosingEnabled=\(muteWhenLosingEnabled)"
        ].joined(separator: " ")
    }
}

struct NotificationRegistrationKey: Hashable, Sendable, CustomStringConvertible {
    let deviceToken: String
    let environment: String
    let favoriteTeamID: String?
    let notificationsEnabled: Bool
    let endpointDescription: String?
    let gameStartEnabled: Bool
    let scoreChangeEnabled: Bool
    let leadChangeEnabled: Bool
    let gameEndEnabled: Bool
    let onBaseEnabled: Bool
    let inningChangeEnabled: Bool
    let favoriteTeamOnlyEnabled: Bool
    let muteWhenLosingEnabled: Bool

    nonisolated init(
        deviceToken: String,
        environment: String,
        favoriteTeamID: String?,
        notificationsEnabled: Bool,
        endpointDescription: String?,
        gameStartEnabled: Bool = true,
        scoreChangeEnabled: Bool = true,
        leadChangeEnabled: Bool = true,
        gameEndEnabled: Bool = true,
        onBaseEnabled: Bool = false,
        inningChangeEnabled: Bool = false,
        favoriteTeamOnlyEnabled: Bool = false,
        muteWhenLosingEnabled: Bool = false
    ) {
        self.deviceToken = deviceToken
        self.environment = environment
        self.favoriteTeamID = favoriteTeamID
        self.notificationsEnabled = notificationsEnabled
        self.endpointDescription = endpointDescription
        self.gameStartEnabled = gameStartEnabled
        self.scoreChangeEnabled = scoreChangeEnabled
        self.leadChangeEnabled = leadChangeEnabled
        self.gameEndEnabled = gameEndEnabled
        self.onBaseEnabled = onBaseEnabled
        self.inningChangeEnabled = inningChangeEnabled
        self.favoriteTeamOnlyEnabled = favoriteTeamOnlyEnabled
        self.muteWhenLosingEnabled = muteWhenLosingEnabled
    }

    nonisolated init(
        payload: NotificationRegistrationPayload,
        endpointDescription: String?
    ) {
        self.init(
            deviceToken: payload.deviceToken,
            environment: payload.environment,
            favoriteTeamID: payload.favoriteTeamID,
            notificationsEnabled: payload.notificationsAuthorized,
            endpointDescription: endpointDescription,
            gameStartEnabled: payload.gameStartEnabled,
            scoreChangeEnabled: payload.scoreChangeEnabled,
            leadChangeEnabled: payload.leadChangeEnabled,
            gameEndEnabled: payload.gameEndEnabled,
            onBaseEnabled: payload.onBaseEnabled,
            inningChangeEnabled: payload.inningChangeEnabled,
            favoriteTeamOnlyEnabled: payload.favoriteTeamOnlyEnabled,
            muteWhenLosingEnabled: payload.muteWhenLosingEnabled
        )
    }

    nonisolated var description: String {
        [
            "tokenPrefix=\(deviceToken.prefix(12))",
            "environment=\(environment)",
            "favoriteTeamID=\(favoriteTeamID ?? "none")",
            "notificationsEnabled=\(notificationsEnabled)",
            "endpoint=\(endpointDescription ?? "missing")",
            "gameStartEnabled=\(gameStartEnabled)",
            "scoreChangeEnabled=\(scoreChangeEnabled)",
            "leadChangeEnabled=\(leadChangeEnabled)",
            "gameEndEnabled=\(gameEndEnabled)",
            "onBaseEnabled=\(onBaseEnabled)",
            "inningChangeEnabled=\(inningChangeEnabled)",
            "favoriteTeamOnlyEnabled=\(favoriteTeamOnlyEnabled)",
            "muteWhenLosingEnabled=\(muteWhenLosingEnabled)"
        ].joined(separator: " ")
    }
}

enum NotificationRegistrationStartDecision: Equatable, Sendable {
    case start(keyChanged: Bool)
    case skipInFlight
    case skipAlreadyRegistered
}

struct NotificationRegistrationDeduplicationState: Sendable {
    private(set) var inFlightRegistrationKeys: Set<NotificationRegistrationKey> = []
    private(set) var lastSuccessfulRegistrationKey: NotificationRegistrationKey?

    mutating func start(_ key: NotificationRegistrationKey, force: Bool = false) -> NotificationRegistrationStartDecision {
        if inFlightRegistrationKeys.contains(key) {
            return .skipInFlight
        }

        if !force, lastSuccessfulRegistrationKey == key {
            return .skipAlreadyRegistered
        }

        let keyChanged = lastSuccessfulRegistrationKey != nil && lastSuccessfulRegistrationKey != key
        inFlightRegistrationKeys.insert(key)
        return .start(keyChanged: keyChanged)
    }

    mutating func complete(_ key: NotificationRegistrationKey, status: NotificationRegistrationSyncStatus) {
        inFlightRegistrationKeys.remove(key)
        if status == .synced {
            lastSuccessfulRegistrationKey = key
        }
    }

    mutating func fail(_ key: NotificationRegistrationKey) {
        inFlightRegistrationKeys.remove(key)
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
        if preferences.gameStartEnabled { alertTypes.append(.gameStart) }
        if preferences.scoreChangeEnabled { alertTypes.append(.scoreChange) }
        if preferences.leadChangeEnabled { alertTypes.append(.leadChange) }
        if preferences.gameEndEnabled { alertTypes.append(.gameEnd) }
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
