//
//  StandingsCalculator.swift
//  kboScore
//
//  Created by Codex on 5/18/26.
//

import Foundation

enum StandingsCalculator {
    static func makeSnapshot(
        for team: Team,
        completedGames: [GameDetail],
        seasonGames: [GameDetail],
        probabilitySignalsByTeamID: [String: LocalStandingsProbabilitySignal] = [:],
        recentResultsLimit: Int = 5
    ) -> TeamStandingsSnapshot {
        let seasonCompletedGames = seasonGames
            .filter { $0.involves(teamID: team.id) }
            .filter(\.hasCompleteFinalScore)
        let wins = completedGames.reduce(into: 0) { partialResult, game in
            if game.finalResult(for: team.id) == .win {
                partialResult += 1
            }
        }
        let losses = completedGames.reduce(into: 0) { partialResult, game in
            if game.finalResult(for: team.id) == .loss {
                partialResult += 1
            }
        }
        let ties = completedGames.reduce(into: 0) { partialResult, game in
            if game.hasCompleteFinalScore,
               let awayScore = game.awayScore,
               let homeScore = game.homeScore,
               awayScore == homeScore,
               game.involves(teamID: team.id) {
                partialResult += 1
            }
        }
        let runsScored = seasonCompletedGames.reduce(into: 0) { partialResult, game in
            guard let awayScore = game.awayScore,
                  let homeScore = game.homeScore else {
                return
            }

            if game.awayTeam.id == team.id {
                partialResult += awayScore
            } else if game.homeTeam.id == team.id {
                partialResult += homeScore
            }
        }
        let runsAllowed = seasonCompletedGames.reduce(into: 0) { partialResult, game in
            guard let awayScore = game.awayScore,
                  let homeScore = game.homeScore else {
                return
            }

            if game.awayTeam.id == team.id {
                partialResult += homeScore
            } else if game.homeTeam.id == team.id {
                partialResult += awayScore
            }
        }

        let probabilitySignal: LocalStandingsProbabilitySignal? = {
            guard let canonicalID = canonicalTeamIdentifier(team.id) else {
                return nil
            }
            return probabilitySignalsByTeamID[canonicalID]
        }()

        return TeamStandingsSnapshot(
            team: team,
            rank: 0,
            wins: wins,
            losses: losses,
            ties: ties,
            runsScored: runsScored,
            runsAllowed: runsAllowed,
            remainingRegularSeasonGames: max(0, 144 - (wins + losses + ties)),
            recentResults: Array(completedGames.compactMap { $0.finalResult(for: team.id) }.prefix(recentResultsLimit)),
            unknownClassificationGames: probabilitySignal?.unknownClassificationGames ?? 0,
            virtualUnscheduledRemainingGames: probabilitySignal?.virtualUnscheduledRemainingGames ?? 0,
            rankingResolution: probabilitySignal?.rankingResolution ?? .resolved,
            rankingResolutionPosition: probabilitySignal?.rankingResolutionPosition,
            postseasonQualificationProbability: probabilitySignal?.postseasonQualificationProbability,
            postseasonQualificationStatus: probabilitySignal?.postseasonQualificationStatus,
            postseasonProbabilityUnavailableReason: probabilitySignal?.postseasonProbabilityUnavailableReason
        )
    }

    private static func canonicalTeamIdentifier(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else {
            return nil
        }

        let lowered = raw.lowercased()
        if TeamIdentity.catalog[lowered] != nil {
            return lowered
        }

        if let matched = TeamIdentity.catalog.first(where: { _, identity in
            identity.shortLabel.caseInsensitiveCompare(raw) == .orderedSame ||
            identity.monogram.caseInsensitiveCompare(raw) == .orderedSame ||
            identity.displayName == raw
        })?.key {
            return matched
        }

        return lowered
    }
}
