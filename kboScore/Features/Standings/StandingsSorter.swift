//
//  StandingsSorter.swift
//  kboScore
//
//  Created by Codex on 5/18/26.
//

import Foundation

enum StandingsSorter {
    static func compare(
        _ lhs: TeamStandingsSnapshot,
        _ rhs: TeamStandingsSnapshot,
        previousRankProvider: (Team) -> Int?
    ) -> Bool {
        // Standings are derived locally from the current games payload so the
        // Standings tab stays aligned with the bundled bootstrap file.
        switch (lhs.winPercentage, rhs.winPercentage) {
        case let (left?, right?) where left != right:
            return left > right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            break
        }

        if let leftPreviousRank = previousRankProvider(lhs.team),
           let rightPreviousRank = previousRankProvider(rhs.team),
           leftPreviousRank != rightPreviousRank {
            return leftPreviousRank < rightPreviousRank
        }

        if lhs.wins != rhs.wins {
            return lhs.wins > rhs.wins
        }
        if lhs.losses != rhs.losses {
            return lhs.losses < rhs.losses
        }
        if lhs.ties != rhs.ties {
            return lhs.ties > rhs.ties
        }
        return lhs.team.name.localizedStandardCompare(rhs.team.name) == .orderedAscending
    }
}
