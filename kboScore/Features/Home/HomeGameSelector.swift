//
//  HomeGameSelector.swift
//  kboScore
//
//  Created by Codex on 5/18/26.
//

import Foundation

enum HomeGameSelector {
    static func matches(_ summary: GameSummary, filter: HomeGameFilter) -> Bool {
        switch filter {
        case .all:
            true
        case .live:
            summary.status.isLiveLike
        case .upcoming:
            summary.status == .upcoming
        case .final:
            summary.status.isFinishedLike
        case .myTeam:
            summary.isMyTeamGame
        }
    }

    static func compare(_ lhs: GameSummary, _ rhs: GameSummary) -> Bool {
        if lhs.isMyTeamGame != rhs.isMyTeamGame {
            return lhs.isMyTeamGame && !rhs.isMyTeamGame
        }

        let lhsPriority = priority(for: lhs)
        let rhsPriority = priority(for: rhs)

        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        if lhs.status.isLiveLike && rhs.status.isLiveLike, lhs.isMyTeamGame == rhs.isMyTeamGame {
            return lhs.scheduledStart > rhs.scheduledStart
        }

        return lhs.scheduledStart < rhs.scheduledStart
    }

    static func compareTodayGames(_ lhs: GameDetail, _ rhs: GameDetail, favoriteTeamID: String?) -> Bool {
        compare(
            lhs.summary(isMyTeamGame: lhs.involves(teamID: favoriteTeamID)),
            rhs.summary(isMyTeamGame: rhs.involves(teamID: favoriteTeamID))
        )
    }

    static func priority(for summary: GameSummary) -> Int {
        switch summary.status {
        case .live, .rainDelay:
            return summary.isMyTeamGame ? 0 : 1
        case .upcoming:
            return 2
        case .final, .cancelled:
            return 3
        }
    }
}
