//
//  StandingsRankMovementResolver.swift
//  kboScore
//
//  Created by Codex on 5/22/26.
//

import Foundation

enum RankingMovement: Equatable, Sendable {
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

enum StandingsRankMovementResolver {
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

    static func latestCompletedGameDay(games: [GameDetail], calendar: Calendar) -> Date? {
        games
            .filter { $0.isRegularSeason && $0.hasCompleteFinalScore }
            .map { calendar.startOfDay(for: $0.scheduledStart) }
            .max()
    }

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
