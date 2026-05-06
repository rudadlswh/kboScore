//
//  AppSettings.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import Foundation
import SwiftUI

enum AppearanceOption: String, CaseIterable, Identifiable, Codable, Sendable {
    case system = "시스템"
    case light = "라이트"
    case dark = "다크"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

struct NotificationPreferences: Hashable, Codable, Sendable {
    var gameStartEnabled: Bool = true
    var scoreChangeEnabled: Bool = true
    var leadChangeEnabled: Bool = true
    var gameEndEnabled: Bool = true
    var onBaseEnabled: Bool = false
    var inningChangeEnabled: Bool = false
    var favoriteTeamOnlyEnabled: Bool = false
    var muteWhenLosingEnabled: Bool = false
    var rainDelay: Bool = true

    nonisolated init(
        gameStart: Bool = true,
        scoreChange: Bool = true,
        leadChange: Bool = true,
        gameEnd: Bool = true,
        rainDelay: Bool = true,
        onBaseEnabled: Bool = false,
        inningChangeEnabled: Bool = false,
        favoriteTeamOnlyEnabled: Bool = false,
        muteWhenLosingEnabled: Bool = false
    ) {
        self.gameStartEnabled = gameStart
        self.scoreChangeEnabled = scoreChange
        self.leadChangeEnabled = leadChange
        self.gameEndEnabled = gameEnd
        self.rainDelay = rainDelay
        self.onBaseEnabled = onBaseEnabled
        self.inningChangeEnabled = inningChangeEnabled
        self.favoriteTeamOnlyEnabled = favoriteTeamOnlyEnabled
        self.muteWhenLosingEnabled = muteWhenLosingEnabled
    }

    var gameStart: Bool {
        get { gameStartEnabled }
        set { gameStartEnabled = newValue }
    }

    var scoreChange: Bool {
        get { scoreChangeEnabled }
        set { scoreChangeEnabled = newValue }
    }

    var leadChange: Bool {
        get { leadChangeEnabled }
        set { leadChangeEnabled = newValue }
    }

    var gameEnd: Bool {
        get { gameEndEnabled }
        set { gameEndEnabled = newValue }
    }

    private enum CodingKeys: String, CodingKey {
        case gameStartEnabled
        case scoreChangeEnabled
        case leadChangeEnabled
        case gameEndEnabled
        case onBaseEnabled
        case inningChangeEnabled
        case favoriteTeamOnlyEnabled
        case muteWhenLosingEnabled
        case rainDelay
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case gameStart
        case scoreChange
        case leadChange
        case gameEnd
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        gameStartEnabled = try container.decodeIfPresent(Bool.self, forKey: .gameStartEnabled)
            ?? (try legacyContainer.decodeIfPresent(Bool.self, forKey: .gameStart))
            ?? true
        scoreChangeEnabled = try container.decodeIfPresent(Bool.self, forKey: .scoreChangeEnabled)
            ?? (try legacyContainer.decodeIfPresent(Bool.self, forKey: .scoreChange))
            ?? true
        leadChangeEnabled = try container.decodeIfPresent(Bool.self, forKey: .leadChangeEnabled)
            ?? (try legacyContainer.decodeIfPresent(Bool.self, forKey: .leadChange))
            ?? true
        gameEndEnabled = try container.decodeIfPresent(Bool.self, forKey: .gameEndEnabled)
            ?? (try legacyContainer.decodeIfPresent(Bool.self, forKey: .gameEnd))
            ?? true
        onBaseEnabled = try container.decodeIfPresent(Bool.self, forKey: .onBaseEnabled) ?? false
        inningChangeEnabled = try container.decodeIfPresent(Bool.self, forKey: .inningChangeEnabled) ?? false
        favoriteTeamOnlyEnabled = try container.decodeIfPresent(Bool.self, forKey: .favoriteTeamOnlyEnabled) ?? false
        muteWhenLosingEnabled = try container.decodeIfPresent(Bool.self, forKey: .muteWhenLosingEnabled) ?? false
        rainDelay = try container.decodeIfPresent(Bool.self, forKey: .rainDelay) ?? true
    }
}

struct QuietHours: Hashable, Codable, Sendable {
    var isEnabled: Bool
    var startHour: Int
    var endHour: Int

    var description: String {
        guard isEnabled else { return "설정 안 함" }
        return String(format: "%02d:00 - %02d:00", startHour, endHour)
    }
}

struct AppSettings: Hashable, Codable, Sendable {
    var favoriteTeamID: String?
    var notificationPreferences: NotificationPreferences
    var quietHours: QuietHours
    var liveActivitiesEnabled: Bool
    var appearance: AppearanceOption
    var teamThemeMode: TeamThemeMode

    nonisolated static let `default` = AppSettings(
        favoriteTeamID: "lg",
        notificationPreferences: NotificationPreferences(),
        quietHours: QuietHours(isEnabled: false, startHour: 23, endHour: 7),
        liveActivitiesEnabled: true,
        appearance: .system,
        teamThemeMode: .favoriteTeam
    )

    nonisolated init(
        favoriteTeamID: String?,
        notificationPreferences: NotificationPreferences,
        quietHours: QuietHours,
        liveActivitiesEnabled: Bool,
        appearance: AppearanceOption,
        teamThemeMode: TeamThemeMode
    ) {
        self.favoriteTeamID = favoriteTeamID
        self.notificationPreferences = notificationPreferences
        self.quietHours = quietHours
        self.liveActivitiesEnabled = liveActivitiesEnabled
        self.appearance = appearance
        self.teamThemeMode = teamThemeMode
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favoriteTeamID = try container.decodeIfPresent(String.self, forKey: .favoriteTeamID)
        notificationPreferences = try container.decodeIfPresent(NotificationPreferences.self, forKey: .notificationPreferences) ?? NotificationPreferences()
        quietHours = try container.decodeIfPresent(QuietHours.self, forKey: .quietHours) ?? QuietHours(isEnabled: false, startHour: 23, endHour: 7)
        liveActivitiesEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveActivitiesEnabled) ?? true
        appearance = try container.decodeIfPresent(AppearanceOption.self, forKey: .appearance) ?? .system
        teamThemeMode = try container.decodeIfPresent(TeamThemeMode.self, forKey: .teamThemeMode) ?? .favoriteTeam
    }
}
