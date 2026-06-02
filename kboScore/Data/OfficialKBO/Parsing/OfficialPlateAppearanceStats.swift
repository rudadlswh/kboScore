//
//  OfficialPlateAppearanceStats.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

struct PlateAppearanceDerivedStats: Sendable, Equatable {
    let homeRuns: Int
    let walks: Int
    let strikeouts: Int

    init(homeRuns: Int = 0, walks: Int = 0, strikeouts: Int = 0) {
        self.homeRuns = homeRuns
        self.walks = walks
        self.strikeouts = strikeouts
    }

    func adding(resultText: String) -> PlateAppearanceDerivedStats {
        resultText.plateAppearanceResultTokens.reduce(self) { stats, result in
            PlateAppearanceDerivedStats(
                homeRuns: stats.homeRuns + (result.isHomeRunPlateAppearance ? 1 : 0),
                walks: stats.walks + (result.isWalkPlateAppearance ? 1 : 0),
                strikeouts: stats.strikeouts + (result.isStrikeoutPlateAppearance ? 1 : 0)
            )
        }
    }

    static func + (lhs: PlateAppearanceDerivedStats, rhs: PlateAppearanceDerivedStats) -> PlateAppearanceDerivedStats {
        PlateAppearanceDerivedStats(
            homeRuns: lhs.homeRuns + rhs.homeRuns,
            walks: lhs.walks + rhs.walks,
            strikeouts: lhs.strikeouts + rhs.strikeouts
        )
    }
}

extension OfficialKBOGameCenterClient {
    func plateAppearanceDerivedStats(
        table: OfficialGridTable?,
        row: OfficialGridRow?
    ) -> PlateAppearanceDerivedStats? {
        guard table?.battingTableInterpretation == .plateAppearanceResults,
              let row else {
            return nil
        }

        return row.cells.reduce(PlateAppearanceDerivedStats()) { stats, cell in
            stats.adding(resultText: cell.text)
        }
    }

    func plateAppearanceTotals(table: OfficialGridTable?) -> PlateAppearanceDerivedStats? {
        guard table?.battingTableInterpretation == .plateAppearanceResults,
              let rows = table?.rows,
              rows.isEmpty == false else {
            return nil
        }

        return rows
            .compactMap { plateAppearanceDerivedStats(table: table, row: $0) }
            .reduce(PlateAppearanceDerivedStats()) { $0 + $1 }
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

    var normalizedKeyStatLabel: String {
        let scalars = normalizedGridText.unicodeScalars.filter { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar) == false &&
            CharacterSet.punctuationCharacters.contains(scalar) == false &&
            CharacterSet.symbols.contains(scalar) == false
        }
        return String(String.UnicodeScalarView(scalars)).uppercased()
    }

    var isHomeRunPlateAppearance: Bool {
        let normalized = normalizedKeyStatLabel
        return normalized.contains("홈")
    }

    var isWalkPlateAppearance: Bool {
        let normalized = normalizedKeyStatLabel
        return ["4구", "볼넷", "고4", "고의4구", "자동고의4구"].contains(normalized)
    }

    var isStrikeoutPlateAppearance: Bool {
        let normalized = normalizedKeyStatLabel
        return normalized.contains("삼진") || normalized.contains("낫아웃")
    }

    var plateAppearanceResultTokens: [String] {
        normalizedGridText
            .split { character in
                character == "," ||
                    character == "，" ||
                    character == "/" ||
                    character == "\n" ||
                    character == "\r"
            }
            .map(String.init)
            .compactMap(\.nilIfBlank)
    }
}
