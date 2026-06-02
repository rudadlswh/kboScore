//
//  HomeFallbackStandingsBuilder.swift
//  kboScore
//
//  Created by Codex on 5/18/26.
//

import Foundation

enum HomeFallbackStandingsBuilder {
    static func makeSnapshots(
        teams: [Team],
        referenceCompletedGames: [GameDetail],
        seasonGames: [GameDetail],
        probabilitySignalsByTeamID: [String: LocalStandingsProbabilitySignal] = [:],
        previousRankProvider: (Team) -> Int?
    ) -> [TeamStandingsSnapshot] {
        guard referenceCompletedGames.isEmpty == false else { return [] }

        let rankedSnapshots = teams
            .map { team in
                let completedGames = referenceCompletedGames
                    .filter { $0.involves(teamID: team.id) }
                    .sorted { $0.scheduledStart > $1.scheduledStart }
                return StandingsCalculator.makeSnapshot(
                    for: team,
                    completedGames: completedGames,
                    seasonGames: seasonGames,
                    probabilitySignalsByTeamID: probabilitySignalsByTeamID,
                    recentResultsLimit: completedGames.count
                )
            }
            .sorted {
                StandingsSorter.compare($0, $1, previousRankProvider: previousRankProvider)
            }

        return rankedSnapshots.enumerated().map { index, snapshot in
            TeamStandingsSnapshot(
                team: snapshot.team,
                rank: index + 1,
                wins: snapshot.wins,
                losses: snapshot.losses,
                ties: snapshot.ties,
                runsScored: snapshot.runsScored,
                runsAllowed: snapshot.runsAllowed,
                remainingRegularSeasonGames: snapshot.remainingRegularSeasonGames,
                recentResults: snapshot.recentResults,
                unknownClassificationGames: snapshot.unknownClassificationGames,
                virtualUnscheduledRemainingGames: snapshot.virtualUnscheduledRemainingGames,
                rankingResolution: snapshot.rankingResolution,
                rankingResolutionPosition: snapshot.rankingResolutionPosition,
                postseasonQualificationProbability: snapshot.postseasonQualificationProbability,
                postseasonQualificationStatus: snapshot.postseasonQualificationStatus,
                postseasonProbabilityUnavailableReason: snapshot.postseasonProbabilityUnavailableReason,
                precomputedStreakText: snapshot.precomputedStreakText
            )
        }
    }
}
