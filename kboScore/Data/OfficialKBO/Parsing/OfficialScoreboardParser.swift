//
//  OfficialScoreboardParser.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

extension OfficialKBOGameCenterClient {
    func makeLineScore(from payload: OfficialScoreboardResponse) -> GameCenterLineScore? {
        guard let inningTable = decodeGridTable(from: payload.inningTable),
              let totalsTable = decodeGridTable(from: payload.totalsTable),
              inningTable.rows.count >= 2,
              totalsTable.rows.count >= 2 else {
            return nil
        }

        let inningLabels = inningTable.headers.first?.cells.map(\.text) ?? []
        let awayInnings = inningTable.rows[0].cells.map(\.text)
        let homeInnings = inningTable.rows[1].cells.map(\.text)

        return GameCenterLineScore(
            inningLabels: inningLabels,
            awayInnings: awayInnings,
            homeInnings: homeInnings,
            awayTotals: makeTotals(from: totalsTable.rows[0]),
            homeTotals: makeTotals(from: totalsTable.rows[1])
        )
    }

    private func makeTotals(from row: OfficialGridRow) -> GameCenterTeamLineTotals {
        GameCenterTeamLineTotals(
            runs: row.cells[safe: 0]?.text.nilIfBlank,
            hits: row.cells[safe: 1]?.text.nilIfBlank,
            errors: row.cells[safe: 2]?.text.nilIfBlank,
            walks: row.cells[safe: 3]?.text.nilIfBlank
        )
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
