//
//  MyTeamCalendar.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import Foundation

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
