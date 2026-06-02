//
//  OfficialBoxScoreBattingParser.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

extension OfficialKBOGameCenterClient {
    func makeBattingSection(
        orderTable: OfficialGridTable,
        detailTable: OfficialGridTable?,
        summaryTable: OfficialGridTable?
    ) -> GameCenterBattingSection? {
        let lines = orderTable.rows.indices.compactMap { index -> GameCenterBattingLine? in
            let orderRow = orderTable.rows[index]
            let detailRow = detailTable?.rows[safe: index]
            let summaryRow = summaryTable?.rows[safe: index]
            let plateAppearanceStats = plateAppearanceDerivedStats(table: detailTable, row: detailRow)
            guard orderRow.cells.count >= 3,
                  orderRow.cells[0].text.battingOrderNumber != nil,
                  orderRow.cells[2].text.nilIfBlank != nil else {
                return nil
            }

            logPlateAppearanceDiagnosticsIfNeeded(table: detailTable, row: detailRow, stats: plateAppearanceStats, rowIndex: index)

            return GameCenterBattingLine(
                battingOrder: orderRow.cells[0].text,
                position: orderRow.cells[1].text,
                name: orderRow.cells[2].text,
                atBats: battingIntegerStat(detailTable: detailTable, detailRow: detailRow, summaryTable: summaryTable, summaryRow: summaryRow, labels: ["타수", "AB"], summaryFallbackIndex: 0),
                runs: battingIntegerStat(detailTable: detailTable, detailRow: detailRow, summaryTable: summaryTable, summaryRow: summaryRow, labels: ["득점", "R"], summaryFallbackIndex: 3),
                hits: battingIntegerStat(detailTable: detailTable, detailRow: detailRow, summaryTable: summaryTable, summaryRow: summaryRow, labels: ["안타", "H"], summaryFallbackIndex: 1),
                runsBattedIn: battingIntegerStat(detailTable: detailTable, detailRow: detailRow, summaryTable: summaryTable, summaryRow: summaryRow, labels: ["타점", "RBI"], summaryFallbackIndex: 2),
                homeRuns: battingIntegerStat(detailTable: detailTable, detailRow: detailRow, summaryTable: summaryTable, summaryRow: summaryRow, labels: ["홈런", "HR", "HRA"], summaryFallbackIndex: nil),
                walks: battingIntegerStat(detailTable: detailTable, detailRow: detailRow, summaryTable: summaryTable, summaryRow: summaryRow, labels: ["볼넷", "BB", "4구"], summaryFallbackIndex: nil),
                strikeouts: battingIntegerStat(detailTable: detailTable, detailRow: detailRow, summaryTable: summaryTable, summaryRow: summaryRow, labels: ["삼진", "SO", "K"], summaryFallbackIndex: nil),
                average: battingAverageStat(detailTable: detailTable, detailRow: detailRow, summaryTable: summaryTable, summaryRow: summaryRow),
                plateAppearanceHomeRuns: plateAppearanceStats?.homeRuns.stringValue,
                plateAppearanceWalks: plateAppearanceStats?.walks.stringValue,
                plateAppearanceStrikeouts: plateAppearanceStats?.strikeouts.stringValue
            )
        }

        let detailFooter = detailTable?.tfoot.first
        let summaryFooter = summaryTable?.tfoot.first
        let plateAppearanceTotals = plateAppearanceTotals(table: detailTable)
        let totals = (detailFooter != nil || summaryFooter != nil) ? GameCenterBattingTotals(
            atBats: battingIntegerStat(detailTable: detailTable, detailRow: detailFooter, summaryTable: summaryTable, summaryRow: summaryFooter, labels: ["타수", "AB"], summaryFallbackIndex: 0),
            runs: battingIntegerStat(detailTable: detailTable, detailRow: detailFooter, summaryTable: summaryTable, summaryRow: summaryFooter, labels: ["득점", "R"], summaryFallbackIndex: 3),
            hits: battingIntegerStat(detailTable: detailTable, detailRow: detailFooter, summaryTable: summaryTable, summaryRow: summaryFooter, labels: ["안타", "H"], summaryFallbackIndex: 1),
            runsBattedIn: battingIntegerStat(detailTable: detailTable, detailRow: detailFooter, summaryTable: summaryTable, summaryRow: summaryFooter, labels: ["타점", "RBI"], summaryFallbackIndex: 2),
            homeRuns: battingIntegerStat(detailTable: detailTable, detailRow: detailFooter, summaryTable: summaryTable, summaryRow: summaryFooter, labels: ["홈런", "HR", "HRA"], summaryFallbackIndex: nil),
            walks: battingIntegerStat(detailTable: detailTable, detailRow: detailFooter, summaryTable: summaryTable, summaryRow: summaryFooter, labels: ["볼넷", "BB", "4구"], summaryFallbackIndex: nil),
            strikeouts: battingIntegerStat(detailTable: detailTable, detailRow: detailFooter, summaryTable: summaryTable, summaryRow: summaryFooter, labels: ["삼진", "SO", "K"], summaryFallbackIndex: nil),
            average: battingAverageStat(detailTable: detailTable, detailRow: detailFooter, summaryTable: summaryTable, summaryRow: summaryFooter),
            plateAppearanceHomeRuns: plateAppearanceTotals?.homeRuns.stringValue,
            plateAppearanceWalks: plateAppearanceTotals?.walks.stringValue,
            plateAppearanceStrikeouts: plateAppearanceTotals?.strikeouts.stringValue
        ) : nil

        return GameCenterBattingSection(lines: lines, totals: totals)
    }

    private func logPlateAppearanceDiagnosticsIfNeeded(
        table: OfficialGridTable?,
        row: OfficialGridRow?,
        stats: PlateAppearanceDerivedStats?,
        rowIndex: Int
    ) {
        #if DEBUG
        guard rowIndex == 0,
              table?.battingTableInterpretation == .plateAppearanceResults,
              let row,
              let stats else { return }
        let sample = row.cells.prefix(4).map(\.text).joined(separator: ",")
        print("[GameDetailStats] arrHitter.table2 interpretedAs=plateAppearanceResults row0=\(sample) derivedHR=\(stats.homeRuns) BB=\(stats.walks) SO=\(stats.strikeouts)")
        #endif
    }

    private func battingIntegerStat(
        detailTable: OfficialGridTable?,
        detailRow: OfficialGridRow?,
        summaryTable: OfficialGridTable?,
        summaryRow: OfficialGridRow?,
        labels: [String],
        summaryFallbackIndex: Int?
    ) -> String? {
        if let value = battingStatByLabel(
            detailTable: detailTable,
            detailRow: detailRow,
            summaryTable: summaryTable,
            summaryRow: summaryRow,
            labels: labels,
            requireInteger: true
        ) {
            return value
        }

        guard let summaryFallbackIndex,
              summaryTable?.battingTableInterpretation == .aggregateBattingStats,
              let value = summaryRow?.cells[safe: summaryFallbackIndex]?.text.nilIfBlank,
              value.isIntegerStatValue else {
            return nil
        }
        return value
    }

    private func battingAverageStat(
        detailTable: OfficialGridTable?,
        detailRow: OfficialGridRow?,
        summaryTable: OfficialGridTable?,
        summaryRow: OfficialGridRow?
    ) -> String? {
        if let value = battingStatByLabel(
            detailTable: detailTable,
            detailRow: detailRow,
            summaryTable: summaryTable,
            summaryRow: summaryRow,
            labels: ["타율", "AVG"],
            requireInteger: false
        ) {
            return value
        }

        guard summaryTable?.battingTableInterpretation == .aggregateBattingStats,
              let value = summaryRow?.cells[safe: 4]?.text.nilIfBlank,
              value.isDecimalStatValue else {
            return nil
        }
        return value
    }

    private func battingStatByLabel(
        detailTable: OfficialGridTable?,
        detailRow: OfficialGridRow?,
        summaryTable: OfficialGridTable?,
        summaryRow: OfficialGridRow?,
        labels: [String],
        requireInteger: Bool
    ) -> String? {
        [
            (detailTable, detailRow),
            (summaryTable, summaryRow)
        ].lazy.compactMap { table, row -> String? in
            guard let index = battingColumnIndex(in: table, labels: labels),
                  let value = row?.cells[safe: index]?.text.nilIfBlank else {
                return nil
            }
            guard requireInteger == false || value.isIntegerStatValue else {
                return nil
            }
            return value
        }.first
    }

    private func battingColumnIndex(in table: OfficialGridTable?, labels: [String]) -> Int? {
        guard let headerCells = table?.headers.first?.cells else { return nil }
        let normalizedLabels = labels.map(normalizeBattingStatLabel)
        return headerCells.firstIndex { cell in
            normalizedLabels.contains(normalizeBattingStatLabel(cell.text))
        }
    }

    private func normalizeBattingStatLabel(_ value: String) -> String {
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

private extension Int {
    var stringValue: String {
        String(self)
    }
}

private extension String {
    var battingOrderNumber: String? {
        let digits = trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

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

    var isIntegerStatValue: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }
        return trimmed.allSatisfy(\.isNumber)
    }

    var isDecimalStatValue: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 1 {
            return trimmed.isIntegerStatValue
        }
        guard parts.count == 2,
              parts[0].allSatisfy(\.isNumber),
              parts[1].allSatisfy(\.isNumber) else {
            return false
        }
        return true
    }
}
