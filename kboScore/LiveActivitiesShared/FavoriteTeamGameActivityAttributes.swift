//
//  FavoriteTeamGameActivityAttributes.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import Foundation

public enum KBOCountDisplay {
    public static func balls(_ value: Int?) -> Int? {
        normalized(value, upperBound: 3)
    }

    public static func strikes(_ value: Int?) -> Int? {
        normalized(value, upperBound: 2)
    }

    public static func outs(_ value: Int?) -> Int? {
        normalized(value, upperBound: 2)
    }

    private static func normalized(_ value: Int?, upperBound: Int) -> Int? {
        guard let value else { return nil }
        return min(max(value, 0), upperBound)
    }
}

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
        let currentBatterName: String?
        let currentPitcherName: String?
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
