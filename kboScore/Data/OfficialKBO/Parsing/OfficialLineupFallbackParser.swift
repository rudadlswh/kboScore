//
//  OfficialLineupFallbackParser.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

extension OfficialKBOGameCenterClient {
    func makeLineupBattingSections(from data: Data) -> [GameCenterBattingSection] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        if let outer = json as? [Any] {
            let homeTable = ((outer[safe: 3] as? [Any])?.first as? String).flatMap(makeBattingSection(fromRawTable:))
            let awayTable = ((outer[safe: 4] as? [Any])?.first as? String).flatMap(makeBattingSection(fromRawTable:))
            let orderedSections = [awayTable, homeTable].compactMap { $0 }
            if orderedSections.count == 2 {
                return orderedSections
            }
        }

        let candidates = battingSectionCandidates(in: json)
        #if DEBUG
        print("[BaseRunners] candidate batting section keys=\(candidates.prefix(6).map(\.path).joined(separator: ",")) count=\(candidates.count)")
        #endif
        return Array(candidates.prefix(2).map(\.section))
    }

    private func makeBattingSection(fromRawTable rawTable: String) -> GameCenterBattingSection? {
        guard let orderTable = decodeLineupFallbackGridTable(from: rawTable) else {
            return nil
        }
        return makeBattingSection(orderTable: orderTable, detailTable: nil, summaryTable: nil)
    }

    func battingSectionCandidates(in value: Any, path: String = "$") -> [BattingSectionCandidate] {
        var candidates: [BattingSectionCandidate] = []

        if let object = value as? [String: Any] {
            for key in ["table1", "TABLE1", "batters", "hitters", "rows"] {
                if let rawTable = object[key] as? String,
                   let section = makeBattingSection(fromRawTable: rawTable),
                   section.lines.isEmpty == false {
                    candidates.append(BattingSectionCandidate(path: "\(path).\(key)", section: section))
                }
            }

            if let section = makeFieldBasedBattingSection(from: object) {
                candidates.append(BattingSectionCandidate(path: path, section: section))
            }

            for key in object.keys.sorted() {
                guard let child = object[key] else { continue }
                candidates.append(contentsOf: battingSectionCandidates(in: child, path: "\(path).\(key)"))
            }
        } else if let array = value as? [Any] {
            if let section = makeFieldBasedBattingSection(from: array) {
                candidates.append(BattingSectionCandidate(path: path, section: section))
            }

            for (index, child) in array.enumerated() {
                candidates.append(contentsOf: battingSectionCandidates(in: child, path: "\(path)[\(index)]"))
            }
        } else if let rawTable = value as? String,
                  let section = makeBattingSection(fromRawTable: rawTable),
                  section.lines.isEmpty == false {
            candidates.append(BattingSectionCandidate(path: path, section: section))
        }

        return candidates
    }

    private func makeFieldBasedBattingSection(from value: Any) -> GameCenterBattingSection? {
        let rows: [[String: Any]]
        if let array = value as? [[String: Any]] {
            rows = array
        } else if let object = value as? [String: Any],
                  let array = (object["rows"] as? [[String: Any]]) ?? (object["record"] as? [[String: Any]]) {
            rows = array
        } else {
            return nil
        }

        let lines = rows.compactMap { row -> GameCenterBattingLine? in
            guard let order = battingOrderValue(in: row),
                  let name = playerNameValue(in: row) else {
                return nil
            }

            return GameCenterBattingLine(
                battingOrder: order,
                position: stringValue(in: row, keys: ["POS", "POSITION", "PITCHER_POS", "DEF_POS", "守備位置"]) ?? "",
                name: name,
                atBats: nil,
                runs: nil,
                hits: nil,
                runsBattedIn: nil,
                homeRuns: nil,
                walks: nil,
                strikeouts: nil,
                average: nil
            )
        }

        return lines.isEmpty ? nil : GameCenterBattingSection(lines: lines, totals: nil)
    }

    private func battingOrderValue(in row: [String: Any]) -> String? {
        stringValue(in: row, keys: ["BAT_ORDER_NO", "BAT_ORDER", "BO", "BAT_ORDER_CN", "LINEUP_NO", "ORDER_NO", "ORDER"])
            .flatMap { $0.battingOrderNumber }
    }

    private func playerNameValue(in row: [String: Any]) -> String? {
        stringValue(in: row, keys: ["NAME", "P_NM", "PLAYER_NM", "HITTER_NM", "BATTER_NM", "P_NM_KOR"])
    }

    private func stringValue(in row: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let rawValue = row[key] else { continue }
            let value: String?
            if let rawValue = rawValue as? String {
                value = rawValue
            } else if let rawValue = rawValue as? NSNumber {
                value = rawValue.stringValue
            } else {
                value = nil
            }
            if let normalized = value?.normalizedGridText.nilIfBlank {
                return normalized
            }
        }
        return nil
    }
}

struct BattingSectionCandidate {
    let path: String
    let section: GameCenterBattingSection
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
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
}
