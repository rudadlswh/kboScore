//
//  Team.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import Foundation

nonisolated struct Team: Identifiable, Hashable, Codable, Sendable {
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

    nonisolated static func canonicalID(for value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else {
            return nil
        }

        let lowered = raw.lowercased()
        if displayNamesByTeamID[lowered] != nil {
            return lowered
        }

        return canonicalTeamIDsByAlias[lowered]
    }

    nonisolated static func displayName(forTeamID teamID: String?, fallback: String) -> String {
        let fallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        if let canonicalID = canonicalID(for: teamID),
           let displayName = displayNamesByTeamID[canonicalID] {
            return displayName
        }

        if let canonicalFallbackID = canonicalID(for: fallback),
           let displayName = displayNamesByTeamID[canonicalFallbackID] {
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

    private nonisolated static let canonicalTeamIDsByAlias: [String: String] = [
        "lotte": "lotte",
        "lotte giants": "lotte",
        "롯데": "lotte",
        "롯데 자이언츠": "lotte",
        "kiwoom": "kiwoom",
        "kiwoom heroes": "kiwoom",
        "키움": "kiwoom",
        "키움 히어로즈": "kiwoom",
        "hanwha": "hanwha",
        "hanwha eagles": "hanwha",
        "한화": "hanwha",
        "한화 이글스": "hanwha",
        "kia": "kia",
        "kia tigers": "kia",
        "kia 타이거즈": "kia",
        "기아": "kia",
        "기아 타이거즈": "kia",
        "doosan": "doosan",
        "doosan bears": "doosan",
        "두산": "doosan",
        "두산 베어스": "doosan",
        "samsung": "samsung",
        "samsung lions": "samsung",
        "삼성": "samsung",
        "삼성 라이온즈": "samsung",
        "kt": "kt",
        "kt wiz": "kt",
        "kt 위즈": "kt",
        "lg": "lg",
        "lg twins": "lg",
        "lg 트윈스": "lg",
        "nc": "nc",
        "nc dinos": "nc",
        "nc 다이노스": "nc",
        "ssg": "ssg",
        "ssg landers": "ssg",
        "ssg 랜더스": "ssg"
    ]
}

extension TeamIdentity {
    nonisolated var teamDisplayName: String {
        Team.displayName(forTeamID: id, fallback: shortLabel)
    }
}
