//
//  OfficialPreviewParser.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

extension OfficialKBOGameCenterClient {
    func makeMatchupSnapshot(from row: OfficialPreviewRecordRow) -> GameCenterMatchupSnapshot? {
        guard row.row.count >= 7 else { return nil }

        let cells = row.row.map { $0.normalizedText }
        guard let teamName = cells[safe: 0]?.nilIfBlank else {
            return nil
        }

        return GameCenterMatchupSnapshot(
            teamName: teamName,
            seasonRecord: cells[safe: 1]?.nilIfBlank,
            recentFive: cells[safe: 2]?.nilIfBlank,
            teamERA: cells[safe: 3]?.nilIfBlank,
            battingAverage: cells[safe: 4]?.nilIfBlank,
            runsScored: cells[safe: 5]?.nilIfBlank,
            runsAllowed: cells[safe: 6]?.nilIfBlank
        )
    }
}

private extension OfficialPreviewRecordCell {
    var normalizedText: String {
        text.normalizedGridText
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var normalizedGridText: String {
        replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\r", with: "")
            .strippingHTML()
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func strippingHTML() -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) else {
            return self
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: "")
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
