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

public enum KBOInningFormatter {
    public static func korean(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let lowercased = trimmed.lowercased()
        let half: String?
        if trimmed.contains("초") || lowercased.contains("top") {
            half = "초"
        } else if trimmed.contains("말") || lowercased.contains("bottom") || lowercased.contains("bot") {
            half = "말"
        } else {
            half = nil
        }

        guard let inning = firstInteger(in: trimmed) else {
            return trimmed
        }
        guard let half else {
            return "\(inning)회"
        }
        return "\(inning)회 \(half)"
    }

    private static func firstInteger(in value: String) -> Int? {
        var digits = ""
        for character in value {
            if character.isNumber {
                digits.append(character)
            } else if digits.isEmpty == false {
                break
            }
        }
        return digits.isEmpty ? nil : Int(digits)
    }
}

#if canImport(ActivityKit)
import ActivityKit

struct FavoriteTeamGameActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        let isPreGame: Bool
        let favoriteScoreText: String
        let opponentScoreText: String
        let inningText: String
        let summaryText: String
        let favoriteStartingPitcherName: String?
        let opponentStartingPitcherName: String?
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
