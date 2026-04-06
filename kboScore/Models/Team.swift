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
}
