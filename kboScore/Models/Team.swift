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
}
