//
//  HomeContentState.swift
//  kboScore
//
//  Created by Codex on 6/8/26.
//

enum HomeContentState {
    case noGames
    case noFilteredGames
    case fallbackStandings(title: String, subtitle: String, snapshots: [TeamStandingsSnapshot])
    case games([GameDetail])

    static func make(
        todayGames: [GameDetail],
        filteredGames: [GameSummary],
        filteredGameDetails: [GameDetail],
        fallbackTitle: String,
        fallbackSubtitle: String,
        fallbackSnapshots: [TeamStandingsSnapshot]
    ) -> HomeContentState {
        if todayGames.isEmpty {
            if fallbackSnapshots.isEmpty {
                return .noGames
            }
            return .fallbackStandings(
                title: fallbackTitle,
                subtitle: fallbackSubtitle,
                snapshots: fallbackSnapshots
            )
        }

        if filteredGames.isEmpty {
            return .noFilteredGames
        }

        return .games(filteredGameDetails)
    }
}
