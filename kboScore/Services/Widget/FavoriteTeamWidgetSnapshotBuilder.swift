//
//  FavoriteTeamWidgetSnapshotBuilder.swift
//  kboScore
//

import Foundation

enum FavoriteTeamWidgetSnapshotBuilder {
    static func makeSnapshot(
        teamID: String,
        teamName: String,
        teamShortName: String,
        displayedMonth: Date,
        monthTitle: String,
        days calendarDays: [MyTeamCalendarDay],
        referenceDate: Date,
        calendar: Calendar
    ) -> FavoriteTeamScheduleWidgetSnapshot {
        let displayedMonthDays = calendarDays.filter(\.isInDisplayedMonth)
        let days = calendarDays.map { day in
            FavoriteTeamScheduleWidgetSnapshot.Day(
                date: day.date,
                isInDisplayedMonth: day.isInDisplayedMonth,
                isToday: day.isToday,
                gameCount: day.gameCount,
                dominantStatus: gameStatus(day.dominantStatus),
                opponentTeamID: day.opponentTeam?.id,
                favoriteTeamIsHome: day.favoriteTeamIsHome,
                favoriteTeamResult: teamResult(day.favoriteTeamResult)
            )
        }
        let displayedMonthGameCount = displayedMonthDays.reduce(0) { partialResult, day in
            partialResult + day.gameCount
        }

        return FavoriteTeamScheduleWidgetSnapshot(
            generatedAt: referenceDate,
            refreshAfter: nextRefreshDate(from: referenceDate, calendar: calendar),
            teamID: teamID,
            teamName: teamName,
            teamShortName: teamShortName,
            displayedMonth: displayedMonth,
            monthTitle: monthTitle,
            monthSummaryText: displayedMonthGameCount == 0 ? "등록 경기 없음" : "이달 경기 \(displayedMonthGameCount)",
            state: displayedMonthGameCount == 0 ? .emptySchedule : .ready,
            days: days
        )
    }

    static func semanticKey(
        favoriteTeamID: String?,
        snapshot: FavoriteTeamScheduleWidgetSnapshot?
    ) -> String {
        let dayKey = snapshot?.days.map { day in
            [
                scheduleDayKey(for: day.date),
                day.isInDisplayedMonth ? "1" : "0",
                day.isToday ? "1" : "0",
                String(day.gameCount),
                day.dominantStatus?.rawValue ?? "-",
                day.opponentTeamID ?? "-",
                day.favoriteTeamIsHome.map(String.init) ?? "-",
                day.favoriteTeamResult?.rawValue ?? "-"
            ].joined(separator: ":")
        }.joined(separator: "|") ?? "nil"
        return [
            favoriteTeamID ?? "nil",
            snapshot?.teamID ?? "nil",
            snapshot?.monthTitle ?? "nil",
            snapshot?.monthSummaryText ?? "nil",
            snapshot?.state.rawValue ?? "nil",
            dayKey
        ].joined(separator: "#")
    }

    private static func gameStatus(_ status: GameStatus?) -> FavoriteTeamScheduleWidgetGameStatus? {
        switch status {
        case .upcoming:
            .upcoming
        case .live:
            .live
        case .final:
            .final
        case .rainDelay:
            .rainDelay
        case .cancelled:
            .cancelled
        case .none:
            nil
        }
    }

    private static func teamResult(_ result: TeamGameResult?) -> FavoriteTeamScheduleWidgetTeamResult? {
        switch result {
        case .win:
            .win
        case .loss:
            .loss
        case .tie:
            .tie
        case .none:
            nil
        }
    }

    private static func nextRefreshDate(from startDate: Date, calendar: Calendar) -> Date {
        let nextMorning = calendar.nextDate(
            after: startDate,
            matching: DateComponents(hour: 6, minute: 0),
            matchingPolicy: .nextTime
        )
        return nextMorning ?? startDate.addingTimeInterval(60 * 60 * 6)
    }

    private static func scheduleDayKey(for date: Date) -> String {
        var scheduleCalendar = Calendar(identifier: .gregorian)
        scheduleCalendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let components = scheduleCalendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
