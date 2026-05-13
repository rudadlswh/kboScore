//
//  OfficialGridModels.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

struct OfficialGridRowDTO: Decodable {
    let row: OfficialGridRow
}

struct OfficialGridRow: Decodable {
    let cells: [OfficialGridCell]

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawCells = try container.decode([OfficialGridCellDTO].self)
        cells = rawCells.map { OfficialGridCell(text: $0.text.normalizedGridText) }
    }
}

struct OfficialGridCell: Sendable {
    let text: String
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
}
