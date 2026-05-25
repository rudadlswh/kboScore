//
//  StandingsRankMovementResolver.swift
//  kboScore
//
//  Created by Codex on 5/22/26.
//

import Foundation

enum RankingMovement: Equatable, Sendable {
    case up
    case down
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

    var accessibilityText: String? {
        switch self {
        case .up:
            "순위 상승"
        case .down:
            "순위 하락"
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
            return .up
        }
        if currentRank > preGameRank {
            return .down
        }
        return .unchanged
    }

    static func preGameRanks(
        teams: [Team],
        games: [GameDetail],
        currentDate: Date,
        previousRankProvider: (Team) -> Int?
    ) -> [String: Int] {
        let regularSeasonGames = games.filter(\.isRegularSeason)
        guard hasUsableSeasonSchedule(regularSeasonGames, teams: teams) else {
            return [:]
        }

        let startOfToday = kstCalendar.startOfDay(for: currentDate)
        let completedGamesBeforeToday = regularSeasonGames
            .filter(\.hasCompleteFinalScore)
            .filter { $0.scheduledStart < startOfToday }

        guard completedGamesBeforeToday.isEmpty == false else {
            return [:]
        }

        let rankedSnapshots = teams
            .map { team in
                StandingsCalculator.makeSnapshot(
                    for: team,
                    completedGames: completedGamesBeforeToday.filter { $0.involves(teamID: team.id) },
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
