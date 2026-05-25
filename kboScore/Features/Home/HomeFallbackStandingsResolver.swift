//
//  HomeFallbackStandingsResolver.swift
//  kboScore
//
//  Created by Codex on 5/25/26.
//

import Foundation

enum HomeFallbackStandingsResolver {
    static func completedRegularSeasonGamesBeforeToday(
        games: [GameDetail],
        currentDate: Date,
        calendar: Calendar
    ) -> [GameDetail] {
        let cutoffDate = calendar.startOfDay(for: currentDate)
        return games
            .filter { game in
                game.isRegularSeason &&
                    game.status == .final &&
                    game.awayScore != nil &&
                    game.homeScore != nil &&
                    game.scheduledStart < cutoffDate
            }
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    static func referenceWeekCompletedGames(
        games: [GameDetail],
        currentDate: Date,
        calendar: Calendar
    ) -> [GameDetail] {
        let completedGames = completedRegularSeasonGamesBeforeToday(
            games: games,
            currentDate: currentDate,
            calendar: calendar
        )
        guard let latestCompletedGameDate = completedGames.map(\.scheduledStart).max(),
              let referenceWeek = calendar.dateInterval(of: .weekOfYear, for: latestCompletedGameDate) else {
            return []
        }

        return completedGames.filter { referenceWeek.contains($0.scheduledStart) }
    }

    static func weekNumber(
        games: [GameDetail],
        currentDate: Date,
        calendar: Calendar
    ) -> Int? {
        let completedGames = completedRegularSeasonGamesBeforeToday(
            games: games,
            currentDate: currentDate,
            calendar: calendar
        )
        guard let latestCompletedGameDate = completedGames.map(\.scheduledStart).max(),
              let latestWeekStart = calendar.dateInterval(of: .weekOfYear, for: latestCompletedGameDate)?.start else {
            return nil
        }

        let orderedWeekStarts = Array(
            Set(
                completedGames.compactMap {
                    calendar.dateInterval(of: .weekOfYear, for: $0.scheduledStart)?.start
                }
            )
        ).sorted()

        guard let weekIndex = orderedWeekStarts.firstIndex(of: latestWeekStart) else {
            return nil
        }
        return weekIndex + 1
    }
}
