//
//  FavoriteTeamWidgetSnapshotBuilder.swift
//  kboScore
//  기능 설명: 마이팀 일정 위젯에 전달할 최신 경기 스냅샷을 생성합니다.
//  마이팀 일정 위젯에 전달할 최신 경기 스냅샷을 생성합니다.을 명확히 분리해 변경 범위와 책임을 예측 가능하게 유지합니다.
//  입력 데이터 누락, 비동기 실행 순서, 플랫폼별 동작 차이를 고려해 방어적으로 처리합니다.
//  TODO : 반복되는 정책이나 화면 상태가 늘어나면 전용 모델과 테스트로 분리합니다.
//

import Foundation

// FavoriteTeamWidgetSnapshotBuilder 열거형는 화면이나 도메인 모델에 필요한 값을 조립합니다.
enum FavoriteTeamWidgetSnapshotBuilder {
    // makeSnapshot 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

    // semanticKey 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameStatus 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // teamResult 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // nextRefreshDate 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func nextRefreshDate(from startDate: Date, calendar: Calendar) -> Date {
        let nextMorning = calendar.nextDate(
            after: startDate,
            matching: DateComponents(hour: 6, minute: 0),
            matchingPolicy: .nextTime
        )
        return nextMorning ?? startDate.addingTimeInterval(60 * 60 * 6)
    }

    // scheduleDayKey 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    private static func scheduleDayKey(for date: Date) -> String {
        ScheduleDateKeyFormatter.dayKey(for: date)
    }
}
