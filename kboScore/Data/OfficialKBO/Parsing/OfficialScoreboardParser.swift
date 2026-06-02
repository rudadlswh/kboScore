//
//  OfficialScoreboardParser.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

extension OfficialKBOGameCenterClient {
    func makeLineScore(from payload: OfficialScoreboardResponse) -> GameCenterLineScore? {
        guard let rawInningTable = payload.inningTable,
              let rawTotalsTable = payload.totalsTable,
              let inningTable = decodeGridTable(from: rawInningTable),
              let totalsTable = decodeGridTable(from: rawTotalsTable),
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

    func makeLineScoreFromScoreboardPageHTML(
        _ html: String,
        context: OfficialGameLookupContext
    ) -> GameCenterLineScore? {
        for block in scoreboardBlocks(in: html) {
            let teams = teamNames(in: block)
            guard teams.count >= 2,
                  normalizedTeamName(teams[0]) == normalizedTeamName(context.entry.awayTeamName),
                  normalizedTeamName(teams[1]) == normalizedTeamName(context.entry.homeTeamName),
                  let table = firstTableHTML(withClass: "tScore", in: block) else {
                continue
            }
            return makeLineScoreFromScoreboardTableHTML(table)
        }
        return nil
    }

    func makeBoxScoreFromScoreboardPageHTML(
        _ html: String,
        context: OfficialGameLookupContext
    ) -> GameCenterBoxScorePayload? {
        guard html.isGenericKBOErrorHTML == false else { return nil }

        let searchScopes = scoreboardBlocks(in: html) + [html]
        for scope in searchScopes {
            let tables = tableHTMLs(in: scope)
            let awayBatting = makeRenderedBattingSection(
                orderTable: tableHTML(withID: "tblAwayHitter1", in: tables),
                summaryTable: tableHTML(withID: "tblAwayHitter3", in: tables)
            )
            let homeBatting = makeRenderedBattingSection(
                orderTable: tableHTML(withID: "tblHomeHitter1", in: tables),
                summaryTable: tableHTML(withID: "tblHomeHitter3", in: tables)
            )
            let awayPitching = tableHTML(withID: "tblAwayPitcher", in: tables).flatMap(makeRenderedPitchingSection)
            let homePitching = tableHTML(withID: "tblHomePitcher", in: tables).flatMap(makeRenderedPitchingSection)

            let battingSections = [awayBatting, homeBatting].compactMap { $0 }
            let pitchingSections = [awayPitching, homePitching].compactMap { $0 }
            guard battingSections.count >= 2 || pitchingSections.count >= 2 else {
                continue
            }

            let summaryItems = tableHTML(withID: "tblEtc", in: tables).map(makeRenderedSummaryItems) ?? []
            let payload = GameCenterBoxScorePayload(
                source: .scoreboardHTMLBoxscore,
                summaryItems: summaryItems,
                battingSections: [
                    awayBatting ?? GameCenterBattingSection(lines: [], totals: nil),
                    homeBatting ?? GameCenterBattingSection(lines: [], totals: nil)
                ],
                pitchingSections: [
                    awayPitching ?? GameCenterPitchingSection(lines: []),
                    homePitching ?? GameCenterPitchingSection(lines: [])
                ]
            )
            #if DEBUG
            print("[GameDetailLive] scoreboard html boxscore parsed battersAway=\(payload.battingSections[0].lines.count) battersHome=\(payload.battingSections[1].lines.count) pitchersAway=\(payload.pitchingSections[0].lines.count) pitchersHome=\(payload.pitchingSections[1].lines.count)")
            #endif
            return payload
        }

        return nil
    }

    private func makeLineScoreFromScoreboardTableHTML(_ tableHTML: String) -> GameCenterLineScore? {
        let headers = firstRowCells(in: firstSectionHTML("thead", in: tableHTML) ?? "")
        let rows = rowHTMLs(in: firstSectionHTML("tbody", in: tableHTML) ?? "")
        guard headers.count >= 5, rows.count >= 2 else { return nil }

        let awayCells = rowCells(in: rows[0])
        let homeCells = rowCells(in: rows[1])
        guard awayCells.count >= 5, homeCells.count >= 5 else { return nil }

        let inningLabels = Array(headers.dropFirst().dropLast(4))
        let awayValues = Array(awayCells.dropFirst())
        let homeValues = Array(homeCells.dropFirst())
        guard awayValues.count >= inningLabels.count + 4,
              homeValues.count >= inningLabels.count + 4 else {
            return nil
        }

        let awayTotals = Array(awayValues.suffix(4))
        let homeTotals = Array(homeValues.suffix(4))
        return GameCenterLineScore(
            inningLabels: inningLabels,
            awayInnings: Array(awayValues.prefix(inningLabels.count)),
            homeInnings: Array(homeValues.prefix(inningLabels.count)),
            awayTotals: GameCenterTeamLineTotals(
                runs: awayTotals[safe: 0]?.nilIfBlank,
                hits: awayTotals[safe: 1]?.nilIfBlank,
                errors: awayTotals[safe: 2]?.nilIfBlank,
                walks: awayTotals[safe: 3]?.nilIfBlank
            ),
            homeTotals: GameCenterTeamLineTotals(
                runs: homeTotals[safe: 0]?.nilIfBlank,
                hits: homeTotals[safe: 1]?.nilIfBlank,
                errors: homeTotals[safe: 2]?.nilIfBlank,
                walks: homeTotals[safe: 3]?.nilIfBlank
            )
        )
    }

    private func makeRenderedBattingSection(orderTable: String?, summaryTable: String?) -> GameCenterBattingSection? {
        guard let orderTable else { return nil }
        let orderRows = bodyRows(in: orderTable)
        let summaryRows = summaryTable.map(bodyRows(in:)) ?? []
        let summaryHeaders = summaryTable.map(headerCells(in:)) ?? []
        let lines = orderRows.indices.compactMap { index -> GameCenterBattingLine? in
            let orderCells = rowCells(in: orderRows[index])
            guard orderCells.count >= 3,
                  let order = orderCells[safe: 0]?.battingOrderNumber,
                  let name = orderCells[safe: 2]?.nilIfBlank else {
                return nil
            }
            let summaryCells = summaryRows[safe: index].map(rowCells(in:)) ?? []
            return GameCenterBattingLine(
                battingOrder: order,
                position: orderCells[safe: 1]?.nilIfBlank ?? "",
                name: name,
                atBats: statValue(labels: ["타수", "AB"], headers: summaryHeaders, cells: summaryCells, fallbackIndex: 0),
                runs: statValue(labels: ["득점", "R"], headers: summaryHeaders, cells: summaryCells, fallbackIndex: 3),
                hits: statValue(labels: ["안타", "H"], headers: summaryHeaders, cells: summaryCells, fallbackIndex: 1),
                runsBattedIn: statValue(labels: ["타점", "RBI"], headers: summaryHeaders, cells: summaryCells, fallbackIndex: 2),
                homeRuns: statValue(labels: ["홈런", "HR"], headers: summaryHeaders, cells: summaryCells, fallbackIndex: nil),
                walks: statValue(labels: ["볼넷", "BB", "4구"], headers: summaryHeaders, cells: summaryCells, fallbackIndex: nil),
                strikeouts: statValue(labels: ["삼진", "SO", "K"], headers: summaryHeaders, cells: summaryCells, fallbackIndex: nil),
                average: statValue(labels: ["타율", "AVG"], headers: summaryHeaders, cells: summaryCells, fallbackIndex: 4)
            )
        }
        guard lines.isEmpty == false else { return nil }

        let footerCells = summaryTable.flatMap { footerRows(in: $0).first.map(rowCells(in:)) }
        let totals = footerCells.map { cells in
            GameCenterBattingTotals(
                atBats: statValue(labels: ["타수", "AB"], headers: summaryHeaders, cells: cells, fallbackIndex: 0),
                runs: statValue(labels: ["득점", "R"], headers: summaryHeaders, cells: cells, fallbackIndex: 3),
                hits: statValue(labels: ["안타", "H"], headers: summaryHeaders, cells: cells, fallbackIndex: 1),
                runsBattedIn: statValue(labels: ["타점", "RBI"], headers: summaryHeaders, cells: cells, fallbackIndex: 2),
                homeRuns: statValue(labels: ["홈런", "HR"], headers: summaryHeaders, cells: cells, fallbackIndex: nil),
                walks: statValue(labels: ["볼넷", "BB", "4구"], headers: summaryHeaders, cells: cells, fallbackIndex: nil),
                strikeouts: statValue(labels: ["삼진", "SO", "K"], headers: summaryHeaders, cells: cells, fallbackIndex: nil),
                average: statValue(labels: ["타율", "AVG"], headers: summaryHeaders, cells: cells, fallbackIndex: 4)
            )
        }
        return GameCenterBattingSection(lines: lines, totals: totals)
    }

    private func makeRenderedPitchingSection(from table: String) -> GameCenterPitchingSection? {
        let headers = headerCells(in: table)
        let lines = bodyRows(in: table).compactMap { row -> GameCenterPitchingLine? in
            let cells = rowCells(in: row)
            guard let name = statValue(labels: ["선수명", "투수명", "투수"], headers: headers, cells: cells, fallbackIndex: 0) else {
                return nil
            }
            return GameCenterPitchingLine(
                name: name,
                role: statValue(labels: ["등판"], headers: headers, cells: cells, fallbackIndex: 1),
                result: statValue(labels: ["결과"], headers: headers, cells: cells, fallbackIndex: 2),
                innings: statValue(labels: ["이닝", "IP"], headers: headers, cells: cells, fallbackIndex: 6),
                battersFaced: statValue(labels: ["타자", "BF"], headers: headers, cells: cells, fallbackIndex: 7),
                pitches: statValue(labels: ["투구수", "투구", "NP", "P"], headers: headers, cells: cells, fallbackIndex: 8),
                atBats: statValue(labels: ["타수", "AB"], headers: headers, cells: cells, fallbackIndex: 9),
                hitsAllowed: statValue(labels: ["피안타", "H"], headers: headers, cells: cells, fallbackIndex: 10),
                walksAllowed: statValue(labels: ["볼넷", "BB", "4구"], headers: headers, cells: cells, fallbackIndex: nil),
                hitBatters: nil,
                walksOrHitByPitch: statValue(labels: ["4사구", "사사구", "BB"], headers: headers, cells: cells, fallbackIndex: 12),
                strikeouts: statValue(labels: ["삼진", "SO", "K"], headers: headers, cells: cells, fallbackIndex: 13),
                homeRunsAllowed: statValue(labels: ["홈런", "피홈런", "HR"], headers: headers, cells: cells, fallbackIndex: 11),
                runsAllowed: statValue(labels: ["실점", "R"], headers: headers, cells: cells, fallbackIndex: 14),
                earnedRuns: statValue(labels: ["자책", "ER"], headers: headers, cells: cells, fallbackIndex: 15),
                earnedRunAverage: statValue(labels: ["평균자책점", "ERA"], headers: headers, cells: cells, fallbackIndex: 16)
            )
        }
        return lines.isEmpty ? nil : GameCenterPitchingSection(lines: lines)
    }

    private func makeRenderedSummaryItems(from table: String) -> [GameCenterSummaryItem] {
        bodyRows(in: table).compactMap { row in
            let cells = rowCells(in: row)
            guard let title = cells.first?.nilIfBlank else { return nil }
            let values = cells.dropFirst().compactMap(\.nilIfBlank)
            guard values.isEmpty == false else { return nil }
            return GameCenterSummaryItem(title: title, value: values.joined(separator: " · "), values: values)
        }
    }

    private func makeTotals(from row: OfficialGridRow) -> GameCenterTeamLineTotals {
        GameCenterTeamLineTotals(
            runs: row.cells[safe: 0]?.text.nilIfBlank,
            hits: row.cells[safe: 1]?.text.nilIfBlank,
            errors: row.cells[safe: 2]?.text.nilIfBlank,
            walks: row.cells[safe: 3]?.text.nilIfBlank
        )
    }

    private func scoreboardBlocks(in html: String) -> [String] {
        matches(pattern: #"(?is)<div\s+class=['"]smsScore['"][^>]*>.*?(?=<div\s+class=['"]smsScore['"]|<!-- //smsscore -->)"#, in: html)
    }

    private func teamNames(in html: String) -> [String] {
        matches(pattern: #"(?is)<strong\s+class=['"]teamT['"][^>]*>(.*?)</strong>"#, in: html)
            .map { $0.strippingHTML().decodedHTMLEntities.nilIfBlank ?? "" }
            .filter { $0.isEmpty == false }
    }

    private func firstTableHTML(withClass className: String, in html: String) -> String? {
        matches(pattern: #"(?is)<table[^>]*class=['"][^'"]*\#(className)[^'"]*['"][^>]*>.*?</table>"#, in: html).first
    }

    private func tableHTMLs(in html: String) -> [String] {
        matches(pattern: #"(?is)<table\b[^>]*>.*?</table>"#, in: html)
    }

    private func tableHTML(withID id: String, in tables: [String]) -> String? {
        tables.first { table in
            table.range(of: #"(?i)\bid=['"]\#(id)['"]"#, options: .regularExpression) != nil
        }
    }

    private func firstSectionHTML(_ section: String, in html: String) -> String? {
        matches(pattern: #"(?is)<\#(section)[^>]*>.*?</\#(section)>"#, in: html).first
    }

    private func sectionHTMLs(_ section: String, in html: String) -> [String] {
        matches(pattern: #"(?is)<\#(section)[^>]*>.*?</\#(section)>"#, in: html)
    }

    private func rowHTMLs(in html: String) -> [String] {
        matches(pattern: #"(?is)<tr[^>]*>.*?</tr>"#, in: html)
    }

    private func bodyRows(in table: String) -> [String] {
        sectionHTMLs("tbody", in: table).flatMap(rowHTMLs(in:))
    }

    private func footerRows(in table: String) -> [String] {
        sectionHTMLs("tfoot", in: table).flatMap(rowHTMLs(in:))
    }

    private func headerCells(in table: String) -> [String] {
        sectionHTMLs("thead", in: table)
            .flatMap(rowHTMLs(in:))
            .map(rowCells(in:))
            .last { $0.contains { $0.nilIfBlank != nil } } ?? []
    }

    private func firstRowCells(in html: String) -> [String] {
        guard let row = rowHTMLs(in: html).first else { return [] }
        return rowCells(in: row)
    }

    private func rowCells(in html: String) -> [String] {
        matches(pattern: #"(?is)<t[hd][^>]*>.*?</t[hd]>"#, in: html)
            .map { $0.strippingHTML().decodedHTMLEntities.nilIfBlank ?? "" }
    }

    private func statValue(labels: [String], headers: [String], cells: [String], fallbackIndex: Int?) -> String? {
        let normalizedLabels = labels.map(normalizedStatLabel)
        if let index = headers.firstIndex(where: { normalizedLabels.contains(normalizedStatLabel($0)) }),
           let value = cells[safe: index]?.nilIfBlank {
            return value
        }
        guard let fallbackIndex else { return nil }
        return cells[safe: fallbackIndex]?.nilIfBlank
    }

    private func normalizedStatLabel(_ value: String) -> String {
        let scalars = value.unicodeScalars.filter { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar) == false &&
                CharacterSet.punctuationCharacters.contains(scalar) == false &&
                CharacterSet.symbols.contains(scalar) == false
        }
        return String(String.UnicodeScalarView(scalars)).uppercased()
    }

    private func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    private func normalizedTeamName(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "자이언츠", with: "")
            .replacingOccurrences(of: "트윈스", with: "")
            .replacingOccurrences(of: "베어스", with: "")
            .replacingOccurrences(of: "이글스", with: "")
            .replacingOccurrences(of: "타이거즈", with: "")
            .replacingOccurrences(of: "라이온즈", with: "")
            .replacingOccurrences(of: "히어로즈", with: "")
            .replacingOccurrences(of: "다이노스", with: "")
            .replacingOccurrences(of: "위즈", with: "")
            .lowercased()
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var isGenericKBOErrorHTML: Bool {
        let normalized = replacingOccurrences(of: " ", with: "").lowercased()
        return normalized.contains("objectmoved") ||
            normalized.contains("오류가발생") ||
            normalized.contains("입력문자열의형식이잘못되었습니다")
    }

    var battingOrderNumber: String? {
        let digits = trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func strippingHTML() -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) else {
            return self
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: "")
    }

    var decodedHTMLEntities: String {
        replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }
}
