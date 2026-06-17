//
//  StandingsRankMovementResolver.swift
//  kboScore
//  기능 설명: 경기 결과에 따른 순위 변동 방향과 이전 순위를 계산합니다.
//  KBO 순위 산정 규칙과 홈 화면 대체 요약에 필요한 계산을 화면 코드에서 분리합니다.
//  완료되지 않은 경기, 취소 경기, 동률, 원정/홈 득실 계산이 순위에 잘못 반영되지 않도록 제한합니다.
//  TODO : 실제 KBO 동률 규정 변경이나 포스트시즌 확률 로직 개선 시 계산 기준을 갱신합니다.
//
//  Created by Codex on 5/22/26.
//

import Foundation

// RankingMovement 열거형는 RankingMovement 타입의 역할과 값을 정의합니다.
nonisolated enum RankingMovement: Equatable, Sendable {
    case up(Int)
    case down(Int)
    case unchanged

    var indicator: String? {
        switch self {
        case .up:
            "▲"
        case .down:
            "▼"
        case .unchanged:
            nil
        }
    }

    var displayText: String {
        switch self {
        case .up(let count):
            "▲\(count)"
        case .down(let count):
            "▼\(count)"
        case .unchanged:
            "-"
        }
    }

    var accessibilityText: String? {
        switch self {
        case .up(let count):
            "순위 \(count)단계 상승"
        case .down(let count):
            "순위 \(count)단계 하락"
        case .unchanged:
            nil
        }
    }
}

// StandingsRankMovementResolver 열거형는 입력 상태를 해석해 필요한 결과 값을 결정합니다.
nonisolated enum StandingsRankMovementResolver {
    // movement 메서드는 이 타입의 주요 동작을 수행합니다.
    static func movement(currentRank: Int?, preGameRank: Int?) -> RankingMovement {
        guard let currentRank, let preGameRank else {
            return .unchanged
        }

        if currentRank < preGameRank {
            return .up(preGameRank - currentRank)
        }
        if currentRank > preGameRank {
            return .down(currentRank - preGameRank)
        }
        return .unchanged
    }

    // preGameRanks 메서드는 이 타입의 주요 동작을 수행합니다.
    static func preGameRanks(
        teams: [Team],
        games: [GameDetail],
        previousRankProvider: (Team) -> Int?
    ) -> [String: Int] {
        let regularSeasonGames = games.filter(\.isRegularSeason)
        guard hasUsableSeasonSchedule(regularSeasonGames, teams: teams) else {
            return [:]
        }

        let completedGames = regularSeasonGames.filter(\.hasCompleteFinalScore)
        guard let latestCompletedDay = latestCompletedGameDay(
            games: completedGames,
            calendar: kstCalendar
        ) else {
            return [:]
        }

        let completedGamesBeforeLatestDay = completedGames.filter {
            kstCalendar.startOfDay(for: $0.scheduledStart) < latestCompletedDay
        }

        guard completedGamesBeforeLatestDay.isEmpty == false else {
            return [:]
        }

        let rankedSnapshots = teams
            .map { team in
                StandingsCalculator.makeSnapshot(
                    for: team,
                    completedGames: completedGamesBeforeLatestDay.filter { $0.involves(teamID: team.id) },
                    seasonGames: regularSeasonGames
                )
            }
            .sorted {
                StandingsSorter.compare($0, $1, previousRankProvider: previousRankProvider)
            }

        return Dictionary(uniqueKeysWithValues: rankedSnapshots.enumerated().map { index, snapshot in
            (snapshot.team.id, index + 1)
        })
    }

    // latestCompletedGameDay 메서드는 이 타입의 주요 동작을 수행합니다.
    static func latestCompletedGameDay(games: [GameDetail], calendar: Calendar) -> Date? {
        games
            .filter { $0.isRegularSeason && $0.hasCompleteFinalScore }
            .map { calendar.startOfDay(for: $0.scheduledStart) }
            .max()
    }

    // hasUsableSeasonSchedule 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private static func hasUsableSeasonSchedule(_ games: [GameDetail], teams: [Team]) -> Bool {
        guard games.isEmpty == false, teams.isEmpty == false else {
            return false
        }

        let scheduledTeamIDs = games.reduce(into: Set<String>()) { result, game in
            result.insert(game.awayTeam.id)
            result.insert(game.homeTeam.id)
        }
        return teams.allSatisfy { scheduledTeamIDs.contains($0.id) }
    }

    private static var kstCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }
}
