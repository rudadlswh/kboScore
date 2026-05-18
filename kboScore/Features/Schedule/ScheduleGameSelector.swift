//
//  ScheduleGameSelector.swift
//  kboScore
//
//  Created by Codex on 5/18/26.
//

import Foundation

enum ScheduleGameSelector {
    static func sortSelectedGames(_ games: [GameDetail], favoriteTeamID: String?) -> [GameDetail] {
        games.sorted { lhs, rhs in
            let lhsIsFavoriteTeam = favoriteTeamID.map { lhs.involves(teamID: $0) } ?? false
            let rhsIsFavoriteTeam = favoriteTeamID.map { rhs.involves(teamID: $0) } ?? false
            if lhsIsFavoriteTeam != rhsIsFavoriteTeam {
                return lhsIsFavoriteTeam && !rhsIsFavoriteTeam
            }
            if lhs.status == rhs.status {
                return lhs.scheduledStart < rhs.scheduledStart
            }
            return priority(for: lhs.status, isFavoriteTeamGame: lhsIsFavoriteTeam) <
                priority(for: rhs.status, isFavoriteTeamGame: rhsIsFavoriteTeam)
        }
    }

    private static func priority(for status: GameStatus, isFavoriteTeamGame: Bool) -> Int {
        switch status {
        case .live, .rainDelay:
            return isFavoriteTeamGame ? 0 : 1
        case .upcoming:
            return 2
        case .final, .cancelled:
            return 3
        }
    }
}
