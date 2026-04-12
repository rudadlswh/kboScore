//
//  Team.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import Foundation

struct Team: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let shortName: String
    let englishName: String
    let markText: String
    let previousRegularSeasonRank: Int?

    nonisolated init(
        id: String,
        name: String,
        shortName: String,
        englishName: String,
        markText: String,
        previousRegularSeasonRank: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.englishName = englishName
        self.markText = markText
        self.previousRegularSeasonRank = previousRegularSeasonRank
    }

    nonisolated var displayName: String {
        Self.displayName(forTeamID: id, fallback: shortName)
    }

    nonisolated static func displayName(forTeamID teamID: String?, fallback: String) -> String {
        let fallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedID = teamID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let normalizedID,
           let displayName = displayNamesByTeamID[normalizedID] {
            return displayName
        }

        let normalizedFallback = fallback.lowercased()
        if let displayName = displayNamesByTeamAlias[normalizedFallback] {
            return displayName
        }

        return fallback
    }

    private nonisolated static let displayNamesByTeamID: [String: String] = [
        "lotte": "롯데",
        "kiwoom": "키움",
        "hanwha": "한화",
        "kia": "기아",
        "doosan": "두산",
        "samsung": "삼성",
        "kt": "KT",
        "lg": "LG",
        "nc": "NC",
        "ssg": "SSG"
    ]

    private nonisolated static let displayNamesByTeamAlias: [String: String] = [
        "lotte": "롯데",
        "lotte giants": "롯데",
        "kiwoom": "키움",
        "kiwoom heroes": "키움",
        "hanwha": "한화",
        "hanwha eagles": "한화",
        "kia": "기아",
        "kia tigers": "기아",
        "doosan": "두산",
        "doosan bears": "두산",
        "samsung": "삼성",
        "samsung lions": "삼성",
        "kt": "KT",
        "kt wiz": "KT",
        "lg": "LG",
        "lg twins": "LG",
        "nc": "NC",
        "nc dinos": "NC",
        "ssg": "SSG",
        "ssg landers": "SSG"
    ]
}

extension TeamIdentity {
    nonisolated var teamDisplayName: String {
        Team.displayName(forTeamID: id, fallback: shortLabel)
    }
}
