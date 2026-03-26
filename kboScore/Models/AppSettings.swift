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
    var gameStart: Bool = true
    var scoreChange: Bool = true
    var leadChange: Bool = true
    var gameEnd: Bool = true
    var rainDelay: Bool = true

    nonisolated init(
        gameStart: Bool = true,
        scoreChange: Bool = true,
        leadChange: Bool = true,
        gameEnd: Bool = true,
        rainDelay: Bool = true
    ) {
        self.gameStart = gameStart
        self.scoreChange = scoreChange
        self.leadChange = leadChange
        self.gameEnd = gameEnd
        self.rainDelay = rainDelay
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
