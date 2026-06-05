//
//  ScheduleCalendarDayBuilder.swift
//  kboScore
//
//  Created by Codex on 6/5/26.
//

import Foundation

nonisolated enum ScheduleCalendarDayBuilder {
    static func makeDays(
        monthStart: Date,
        gamesByDate: [String: [GameDetail]],
        filter: ScheduleFilter,
        favoriteTeamID: String?,
        calendar: Calendar,
        dayKey: (Date) -> String,
        isToday: (Date, String) -> Bool,
        hasAttendedGame: ([GameDetail]) -> Bool,
        favoriteTeamResult: ([GameDetail], String?) -> TeamGameResult?
    ) -> [MyTeamCalendarDay] {
        guard let monthRange = calendar.dateInterval(of: .month, for: monthStart),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthRange.start),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthRange.start),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthEnd) else {
            return []
        }

        var days: [MyTeamCalendarDay] = []
        var cursor = firstWeek.start
        while cursor < lastWeek.end {
            let cursorKey = dayKey(cursor)
            let dayGames = gamesByDate[cursorKey] ?? []
            let myTeamDayGames = myTeamGames(from: dayGames, favoriteTeamID: favoriteTeamID)
            days.append(
                MyTeamCalendarDay(
                    date: cursor,
                    isInDisplayedMonth: calendar.isDate(cursor, equalTo: monthStart, toGranularity: .month),
                    isToday: isToday(cursor, cursorKey),
                    gameCount: dayGames.count,
                    hasAttendedGame: hasAttendedGame(dayGames),
                    dominantStatus: ScheduleDayStatusResolver.dominantStatus(for: myTeamDayGames),
                    opponentTeam: opponentTeam(for: dayGames, filter: filter, favoriteTeamID: favoriteTeamID),
                    favoriteTeamIsHome: favoriteTeamIsHome(for: dayGames, filter: filter, favoriteTeamID: favoriteTeamID),
                    favoriteTeamResult: favoriteTeamResult(myTeamDayGames, favoriteTeamID)
                )
            )
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = nextDay
        }
        return days
    }

    private static func myTeamGames(from games: [GameDetail], favoriteTeamID: String?) -> [GameDetail] {
        guard let favoriteTeamID else { return [] }
        return games.filter { $0.involves(teamID: favoriteTeamID) }
    }

    private static func opponentTeam(
        for games: [GameDetail],
        filter: ScheduleFilter,
        favoriteTeamID: String?
    ) -> Team? {
        guard filter == .myTeam, let favoriteTeamID else { return nil }
        for game in games {
            if game.awayTeam.id == favoriteTeamID { return game.homeTeam }
            if game.homeTeam.id == favoriteTeamID { return game.awayTeam }
        }
        return nil
    }

    private static func favoriteTeamIsHome(
        for games: [GameDetail],
        filter: ScheduleFilter,
        favoriteTeamID: String?
    ) -> Bool? {
        guard filter == .myTeam, let favoriteTeamID else { return nil }
        for game in games {
            if game.homeTeam.id == favoriteTeamID { return true }
            if game.awayTeam.id == favoriteTeamID { return false }
        }
        return nil
    }
}
