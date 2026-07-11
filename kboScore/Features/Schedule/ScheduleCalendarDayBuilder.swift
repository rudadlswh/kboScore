//
//  ScheduleCalendarDayBuilder.swift
//  kboScore
//  기능 설명: 월간 캘린더 그리드에 표시할 날짜 셀 모델을 생성합니다.
//  월별·일별 일정 상태를 일관되게 계산해 홈, 일정, 위젯이 같은 경기 선택 기준을 공유합니다.
//  우천 취소, 더블헤더, 시간 미정, 오래된 캐시가 섞일 수 있어 날짜 키와 동기화 순서를 엄격히 다룹니다.
//  TODO : 공식 일정 변경 감지와 보정 로직을 더 작은 단위로 검증합니다.
//
//  Created by Codex on 6/5/26.
//

import Foundation

// ScheduleCalendarDayBuilder 열거형는 화면이나 도메인 모델에 필요한 값을 조립합니다.
nonisolated enum ScheduleCalendarDayBuilder {
    // makeDays 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

    // myTeamGames 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func myTeamGames(from games: [GameDetail], favoriteTeamID: String?) -> [GameDetail] {
        guard let favoriteTeamID else { return [] }
        return games.filter { $0.involves(teamID: favoriteTeamID) }
    }

    // opponentTeam 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // favoriteTeamIsHome 메서드는 이 타입의 주요 동작을 수행합니다.
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
