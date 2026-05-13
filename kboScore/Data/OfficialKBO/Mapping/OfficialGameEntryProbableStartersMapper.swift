//
//  OfficialGameEntryProbableStartersMapper.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

extension OfficialGameEntry {
    var probableStarters: GameCenterProbableStarters {
        GameCenterProbableStarters(
            away: awayProbablePitcherName?.nilIfBlank,
            home: homeProbablePitcherName?.nilIfBlank
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
