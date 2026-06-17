//
//  AppSettings.swift
//  kboScore
//  기능 설명: 앱 설정, 알림 옵션, 테마 선택 값을 정의합니다.
//  KBO 경기와 팀 규칙을 화면·저장소와 분리된 값 모델로 표현해 계산과 비교 기준을 일관되게 유지합니다.
//  동명이인, 보류 경기, 취소 경기, 누락 점수처럼 원천 데이터가 불완전한 상황을 고려합니다.
//  TODO : 새 시즌 규칙이나 추가 지표가 생기면 모델 확장 지점을 명확히 분리합니다.
//
//  Created by Codex on 3/25/26.
//

import Foundation
import SwiftUI

// AppearanceOption 열거형는 AppearanceOption 타입의 역할과 값을 정의합니다.
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

// NotificationPreferences 구조체는 NotificationPreferences 타입의 역할과 값을 정의합니다.
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

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
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

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
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

// LegacyCodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum LegacyCodingKeys: String, CodingKey {
        case gameStart
        case scoreChange
        case leadChange
        case gameEnd
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
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

// QuietHours 구조체는 QuietHours 타입의 역할과 값을 정의합니다.
struct QuietHours: Hashable, Codable, Sendable {
    var isEnabled: Bool
    var startHour: Int
    var endHour: Int

    var description: String {
        guard isEnabled else { return "설정 안 함" }
        return String(format: "%02d:00 - %02d:00", startHour, endHour)
    }
}

// AppSettings 구조체는 AppSettings 타입의 역할과 값을 정의합니다.
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

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
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

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
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
