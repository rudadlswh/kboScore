//
//  SchedulePresentation.swift
//  kboScore
//
//  Created by Codex on 6/8/26.
//

import Foundation

struct ScheduleMonthCacheEntry: Sendable {
    let key: KBOMonthScheduleKey
    let games: [GameDetail]
    let gamesByDate: [String: [GameDetail]]

    nonisolated static func build(key: KBOMonthScheduleKey, games: [GameDetail]) async -> ScheduleMonthCacheEntry {
        await Task.detached(priority: .userInitiated) {
            let sortedGames = games.sorted { $0.scheduledStart < $1.scheduledStart }
            let gamesByDate = Dictionary(grouping: sortedGames) { game in
                SchedulePresentation.dayKey(for: game.scheduledStart)
            }
            return ScheduleMonthCacheEntry(key: key, games: sortedGames, gamesByDate: gamesByDate)
        }.value
    }
}

struct SchedulePresentation: Sendable {
    let calendarDays: [MyTeamCalendarDay]
    let selectedDateGames: [GameDetail]
    let isDisplayedMonthAvailable: Bool
    let hasAvailableMonths: Bool
    let previousAvailableMonth: Date?
    let nextAvailableMonth: Date?
    let statusMessage: String?
    let monthGameCount: Int
#if DEBUG
    let debugSummary: String?
#endif

    nonisolated static func build(
        displayedMonth: Date,
        selectedDate: Date,
        filter: ScheduleFilter,
        favoriteTeamID: String?,
        attendedGameKeys: Set<String>,
        cachedMonthEntries: [String: ScheduleMonthCacheEntry],
        failedMonthKeys: Set<String>,
        currentDate: Date
    ) async -> SchedulePresentation {
        await Task.detached(priority: .userInitiated) {
            buildSynchronously(
                displayedMonth: displayedMonth,
                selectedDate: selectedDate,
                filter: filter,
                favoriteTeamID: favoriteTeamID,
                attendedGameKeys: attendedGameKeys,
                cachedMonthEntries: cachedMonthEntries,
                failedMonthKeys: failedMonthKeys,
                currentDate: currentDate
            )
        }.value
    }

    nonisolated static func dayKey(for date: Date) -> String {
        ScheduleDateKeyFormatter.dayKey(for: date)
    }

    nonisolated private static func buildSynchronously(
        displayedMonth: Date,
        selectedDate: Date,
        filter: ScheduleFilter,
        favoriteTeamID: String?,
        attendedGameKeys: Set<String>,
        cachedMonthEntries: [String: ScheduleMonthCacheEntry],
        failedMonthKeys: Set<String>,
        currentDate: Date
    ) -> SchedulePresentation {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let displayedKey = KBOMonthScheduleKey(date: displayedMonth, calendar: calendar)
        let displayedKeyText = displayedKey.yearMonthText
        let monthEntry = cachedMonthEntries[displayedKeyText]
        let filteredGamesByDate = filteredGamesByDate(
            from: monthEntry,
            filter: filter,
            favoriteTeamID: favoriteTeamID
        )
        let monthStart = startOfMonth(for: displayedMonth, calendar: calendar)
        let selectedDayKey = dayKey(for: selectedDate)
        let selectedGames = sortSelectedGames(
            filteredGamesByDate[selectedDayKey] ?? [],
            favoriteTeamID: favoriteTeamID
        )
        let todayKey = dayKey(for: currentDate)
        let days = ScheduleCalendarDayBuilder.makeDays(
            monthStart: monthStart,
            gamesByDate: filteredGamesByDate,
            filter: filter,
            favoriteTeamID: favoriteTeamID,
            calendar: calendar,
            dayKey: dayKey(for:),
            isToday: { _, cursorKey in cursorKey == todayKey },
            hasAttendedGame: { games in
                games.contains {
                    attendedGameKeys.isDisjoint(with: $0.attendanceStorageAliases) == false
                }
            },
            favoriteTeamResult: calendarFavoriteTeamResult(for:favoriteTeamID:)
        )
        let displayedMonthStart = startOfMonth(for: displayedMonth, calendar: calendar)
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonthStart)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonthStart)
        let isDisplayedMonthAvailable = true
        let statusMessage = failedMonthKeys.contains(displayedKeyText) && monthEntry == nil
            ? "월간 일정을 불러오지 못했습니다."
            : nil
        let monthGameCount = days.reduce(0) { count, day in
            count + (day.isInDisplayedMonth ? day.gameCount : 0)
        }

#if DEBUG
        return SchedulePresentation(
            calendarDays: days,
            selectedDateGames: selectedGames,
            isDisplayedMonthAvailable: isDisplayedMonthAvailable,
            hasAvailableMonths: true,
            previousAvailableMonth: previousMonth,
            nextAvailableMonth: nextMonth,
            statusMessage: statusMessage,
            monthGameCount: monthGameCount,
            debugSummary: monthEntry.map { "월간 캐시 \($0.games.count)경기" }
        )
#else
        return SchedulePresentation(
            calendarDays: days,
            selectedDateGames: selectedGames,
            isDisplayedMonthAvailable: isDisplayedMonthAvailable,
            hasAvailableMonths: true,
            previousAvailableMonth: previousMonth,
            nextAvailableMonth: nextMonth,
            statusMessage: statusMessage,
            monthGameCount: monthGameCount
        )
#endif
    }

    nonisolated private static func filteredGamesByDate(
        from entry: ScheduleMonthCacheEntry?,
        filter: ScheduleFilter,
        favoriteTeamID: String?
    ) -> [String: [GameDetail]] {
        guard let entry else { return [:] }
        switch filter {
        case .all:
            return entry.gamesByDate
        case .myTeam:
            guard let favoriteTeamID else { return [:] }
            return entry.gamesByDate.mapValues { games in
                games.filter { $0.involves(teamID: favoriteTeamID) }
            }
        }
    }

    nonisolated private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    nonisolated private static func sortSelectedGames(_ games: [GameDetail], favoriteTeamID: String?) -> [GameDetail] {
        ScheduleGameSelector.sortSelectedGames(games, favoriteTeamID: favoriteTeamID)
    }

    nonisolated private static func calendarFavoriteTeamResult(
        for games: [GameDetail],
        favoriteTeamID: String?
    ) -> TeamGameResult? {
        for game in games {
            guard let favoriteTeamID,
                  game.involves(teamID: favoriteTeamID),
                  game.status == .final,
                  let awayScore = game.awayScore,
                  let homeScore = game.homeScore else { continue }
            if awayScore == homeScore { return .tie }
            let favoriteTeamWon = (game.awayTeam.id == favoriteTeamID && awayScore > homeScore) ||
                (game.homeTeam.id == favoriteTeamID && homeScore > awayScore)
            return favoriteTeamWon ? .win : .loss
        }
        return nil
    }
}
