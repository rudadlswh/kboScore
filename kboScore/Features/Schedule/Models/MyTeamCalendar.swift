//
//  MyTeamCalendar.swift
//  kboScore
//  기능 설명: 마이팀 캘린더에서 사용하는 일자별 경기 상태 모델을 정의합니다.
//  KBO 경기와 팀 규칙을 화면·저장소와 분리된 값 모델로 표현해 계산과 비교 기준을 일관되게 유지합니다.
//  동명이인, 보류 경기, 취소 경기, 누락 점수처럼 원천 데이터가 불완전한 상황을 고려합니다.
//  TODO : 새 시즌 규칙이나 추가 지표가 생기면 모델 확장 지점을 명확히 분리합니다.
//
//  Created by Codex on 3/26/26.
//

import Foundation

// MyTeamCalendarDay 구조체는 MyTeamCalendarDay 타입의 역할과 값을 정의합니다.
struct MyTeamCalendarDay: Identifiable, Hashable, Sendable {
    let date: Date
    let isInDisplayedMonth: Bool
    let isToday: Bool
    let gameCount: Int
    let hasAttendedGame: Bool
    let dominantStatus: GameStatus?
    let opponentTeam: Team?
    let favoriteTeamIsHome: Bool?
    let favoriteTeamResult: TeamGameResult?

    var id: Date { date }
    var hasGames: Bool { gameCount > 0 }
}

// AttendedGameSummary 구조체는 AttendedGameSummary 타입의 역할과 값을 정의합니다.
struct AttendedGameSummary: Hashable, Sendable {
    let completedGames: Int
    let wins: Int
    let losses: Int
    let ties: Int

    var hasCompletedGames: Bool {
        completedGames > 0
    }

    var winPercentage: Double? {
        let decisions = wins + losses
        guard decisions > 0 else { return nil }
        return Double(wins) / Double(decisions)
    }

    var gamesText: String {
        "\(completedGames)경기"
    }

    var recordText: String {
        if ties > 0 {
            return "\(wins)승 \(losses)패 \(ties)무"
        }
        return "\(wins)승 \(losses)패"
    }

    var winPercentageText: String {
        guard let winPercentage else { return "---" }
        return String(format: "%.3f", winPercentage)
    }
}
