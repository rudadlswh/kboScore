//
//  FavoriteTeamGameActivityAttributes.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import Foundation

#if canImport(ActivityKit)
import ActivityKit

struct FavoriteTeamGameActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        let favoriteScoreText: String
        let opponentScoreText: String
        let inningText: String
        let summaryText: String
        let balls: Int?
        let strikes: Int?
        let outs: Int?
        let runnerOnFirst: Bool?
        let runnerOnSecond: Bool?
        let runnerOnThird: Bool?
    }

    let gameID: String
    let favoriteTeamID: String
    let favoriteTeamName: String
    let favoriteTeamShortName: String
    let opponentTeamID: String
    let opponentTeamName: String
    let opponentTeamShortName: String
    let venue: String
    let isHomeGame: Bool
}
#endif
