//
//  StandingsContentState.swift
//  kboScore
//
//  Created by Codex on 6/8/26.
//

enum StandingsContentState {
    case loading
    case empty
    case table(
        rows: [TeamStandingsSnapshot],
        revision: Int,
        favoriteTeamID: String?
    )

    static func make(
        rows: [TeamStandingsSnapshot],
        isLoading: Bool,
        revision: Int,
        favoriteTeamID: String?
    ) -> StandingsContentState {
        if isLoading, rows.isEmpty {
            return .loading
        }
        guard rows.isEmpty == false else { return .empty }
        return .table(
            rows: rows,
            revision: revision,
            favoriteTeamID: favoriteTeamID
        )
    }
}
