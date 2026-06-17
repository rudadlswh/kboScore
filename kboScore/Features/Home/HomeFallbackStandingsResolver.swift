//
//  HomeFallbackStandingsResolver.swift
//  kboScore
//  기능 설명: 경기 없는 날 홈 화면에 사용할 직전 완료 주차 경기 범위를 계산합니다.
//  오늘 경기와 경기 없는 날의 대체 정보를 홈에서 바로 판단할 수 있도록 표시용 요약을 별도로 구성합니다.
//  월요일 직전 주 요약, 마이팀 경기 우선순위, 빈 일정 상태가 겹칠 수 있어 선택 순서를 명확히 유지합니다.
//  TODO : 홈 요약 정책이 바뀌면 날짜별 스냅샷 테스트를 추가합니다.
//
//  Created by Codex on 5/25/26.
//

import Foundation

// HomeFallbackStandingsResolver 열거형는 입력 상태를 해석해 필요한 결과 값을 결정합니다.
enum HomeFallbackStandingsResolver {
    // completedRegularSeasonGamesBeforeToday 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // referenceWeekCompletedGames 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // weekNumber 메서드는 이 타입의 주요 동작을 수행합니다.
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
