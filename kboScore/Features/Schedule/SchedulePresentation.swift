//
//  SchedulePresentation.swift
//  kboScore
//  기능 설명: 일정 화면에서 날짜, 상태, 경기 정보를 표시하기 위한 문구를 구성합니다.
//  월별·일별 일정 상태를 일관되게 계산해 홈, 일정, 위젯이 같은 경기 선택 기준을 공유합니다.
//  우천 취소, 더블헤더, 시간 미정, 오래된 캐시가 섞일 수 있어 날짜 키와 동기화 순서를 엄격히 다룹니다.
//  TODO : 공식 일정 변경 감지와 보정 로직을 더 작은 단위로 검증합니다.
//
//  Created by Codex on 6/8/26.
//

import Foundation

// ScheduleMonthCacheEntry 구조체는 ScheduleMonthCacheEntry 타입의 역할과 값을 정의합니다.
struct ScheduleMonthCacheEntry: Sendable {
    let key: KBOMonthScheduleKey
    let games: [GameDetail]
    let gamesByDate: [String: [GameDetail]]

    // build 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

// SchedulePresentation 구조체는 SchedulePresentation 타입의 역할과 값을 정의합니다.
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

    // build 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

    // dayKey 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated static func dayKey(for date: Date) -> String {
        ScheduleDateKeyFormatter.dayKey(for: date)
    }

    // buildSynchronously 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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
        let normalizedAttendedGameKeys = Set(attendedGameKeys.compactMap(GameIdentifier.attendanceCanonicalKey(from:)))
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
                games.contains { normalizedAttendedGameKeys.contains($0.attendanceCanonicalKey) }
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
        let matchedGameKeys = Set(monthEntry?.games.map(\.attendanceCanonicalKey) ?? [])
            .intersection(normalizedAttendedGameKeys)
        let visibleMarkedCount = monthEntry?.games.filter {
            normalizedAttendedGameKeys.contains($0.attendanceCanonicalKey)
        }.count ?? 0
        print("[AttendanceMarker] merge month=\(displayedKey.yearMonthText) confirmedCount=\(normalizedAttendedGameKeys.count) matchedCount=\(matchedGameKeys.count) visibleMarkedCount=\(visibleMarkedCount)")
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

    // filteredGamesByDate 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
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

    // startOfMonth 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    nonisolated private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    // sortSelectedGames 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    nonisolated private static func sortSelectedGames(_ games: [GameDetail], favoriteTeamID: String?) -> [GameDetail] {
        ScheduleGameSelector.sortSelectedGames(games, favoriteTeamID: favoriteTeamID)
    }

    // calendarFavoriteTeamResult 메서드는 이 타입의 주요 동작을 수행합니다.
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
