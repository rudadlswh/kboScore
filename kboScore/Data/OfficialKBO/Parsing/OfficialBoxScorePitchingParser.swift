//
//  OfficialBoxScorePitchingParser.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

extension OfficialKBOGameCenterClient {
    func makePitchingSection(from table: OfficialGridTable) -> GameCenterPitchingSection? {
        logPitcherDiagnosticsIfNeeded(table)

        let lines = table.rows.compactMap { row -> GameCenterPitchingLine? in
            guard let name = row.cells[safe: 0]?.text.nilIfBlank else {
                return nil
            }

            // Current official unlabeled pitcher shape: 9 피홈런, 10 피안타, 11 볼넷, 12 사구, 13 삼진.
            return GameCenterPitchingLine(
                name: name,
                role: row.cells[safe: 1]?.text.nilIfBlank,
                result: row.cells[safe: 2]?.text.nilIfBlank,
                innings: pitchingStat(table, row: row, labels: ["이닝", "IP"], fallbackIndex: 6),
                pitches: pitchingStat(table, row: row, labels: ["투구수", "투구", "NP", "P"], fallbackIndex: 8),
                hitsAllowed: pitchingStat(table, row: row, labels: ["피안타", "H"], fallbackIndex: 10),
                walksAllowed: pitchingStat(table, row: row, labels: ["볼넷", "BB", "4구"], fallbackIndex: 11),
                hitBatters: pitchingStat(table, row: row, labels: ["사구", "HBP"], fallbackIndex: 12),
                strikeouts: pitchingStat(table, row: row, labels: ["삼진", "SO", "K"], fallbackIndex: 13),
                homeRunsAllowed: pitchingStat(table, row: row, labels: ["피홈런", "홈런", "HR"], fallbackIndex: 9),
                runsAllowed: pitchingStat(table, row: row, labels: ["실점", "R"], fallbackIndex: 14),
                earnedRuns: pitchingStat(table, row: row, labels: ["자책", "ER"], fallbackIndex: 15),
                earnedRunAverage: pitchingStat(table, row: row, labels: ["평균자책점", "ERA"], fallbackIndex: 16)
            )
        }

        return GameCenterPitchingSection(lines: lines)
    }

    private func logPitcherDiagnosticsIfNeeded(_ table: OfficialGridTable) {
        #if DEBUG
        let labels = table.headers.first?.cells.map { normalizePitchingStatLabel($0.text) }.joined(separator: ",") ?? "<none>"
        let rowSample = table.rows.first?.cells.prefix(17).map(\.text).joined(separator: ",") ?? "<none>"
        let hbpColumn = pitchingColumnIndex(in: table, labels: ["사구", "HBP"]) ?? 12
        print("[GameDetailStats] arrPitcher labels=\(labels) row0=\(rowSample) hbpColumn=\(hbpColumn)")
        #endif
    }

    private func pitchingStat(_ table: OfficialGridTable, row: OfficialGridRow, labels: [String], fallbackIndex: Int?) -> String? {
        if let index = pitchingColumnIndex(in: table, labels: labels),
           let value = row.cells[safe: index]?.text.nilIfBlank {
            return value
        }
        guard let fallbackIndex else { return nil }
        return row.cells[safe: fallbackIndex]?.text.nilIfBlank
    }

    private func pitchingColumnIndex(in table: OfficialGridTable?, labels: [String]) -> Int? {
        guard let headerCells = table?.headers.first?.cells else { return nil }
        let normalizedLabels = labels.map(normalizePitchingStatLabel)
        return headerCells.firstIndex { cell in
            normalizedLabels.contains(normalizePitchingStatLabel(cell.text))
        }
    }

    private func normalizePitchingStatLabel(_ value: String) -> String {
        let scalars = value.normalizedGridText.unicodeScalars.filter { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar) == false &&
                CharacterSet.punctuationCharacters.contains(scalar) == false &&
                CharacterSet.symbols.contains(scalar) == false
        }
        return String(String.UnicodeScalarView(scalars)).uppercased()
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
