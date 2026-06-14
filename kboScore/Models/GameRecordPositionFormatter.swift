//
//  GameRecordPositionFormatter.swift
//  kboScore
//
//  Created by Codex on 5/13/26.
//

import Foundation

enum GameRecordPositionFormatter {
    private static let separator = "·"
    private static let separatorCharacter: Character = "·"
    #if DEBUG
    private static let debugLogLock = NSLock()
    private static var debugLoggedPositionKeys: Set<String> = []
    #endif

    private static let positionMap: [String: String] = [
        "투": "P", "투수": "P",
        "포": "C", "포수": "C",
        "一": "1B", "1": "1B", "1루": "1B", "1루수": "1B", "일루": "1B", "일루수": "1B",
        "二": "2B", "2": "2B", "2루": "2B", "2루수": "2B", "이루": "2B", "이루수": "2B",
        "三": "3B", "3": "3B", "3루": "3B", "3루수": "3B", "삼루": "3B", "삼루수": "3B",
        "유": "SS", "유격": "SS", "유격수": "SS",
        "좌": "LF", "좌익": "LF", "좌익수": "LF",
        "중": "CF", "중견": "CF", "중견수": "CF",
        "우": "RF", "우익": "RF", "우익수": "RF",
        "지": "DH", "지명": "DH", "지명타자": "DH",
        "타": "PH", "대타": "PH",
        "주": "PR", "대주자": "PR",
        "수": "DEF", "대수비": "DEF"
    ]

    private static let tokenKeys = positionMap.keys.sorted { lhs, rhs in
        if lhs.count == rhs.count {
            lhs < rhs
        } else {
            lhs.count > rhs.count
        }
    }

    static func display(_ rawPosition: String?) -> String {
        let raw = rawPosition?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard raw.isEmpty == false else { return "-" }

        let compact = normalized(raw)
        guard compact.isEmpty == false, compact.allSatisfy({ $0 == "-" }) == false else {
            return "-"
        }

        if let mapped = positionMap[compact] {
            return mapped
        }

        let parts = compact
            .split { character in
                character == "/" ||
                    character == "," ||
                    character == "，" ||
                    character == separatorCharacter
            }
            .map(String.init)
            .filter { $0.isEmpty == false }
        let components = parts.isEmpty ? [compact] : parts
        let formatted = components.flatMap { displayTokens(for: $0) }
        guard formatted.isEmpty == false else {
            return raw
        }
        return formatted.joined(separator: separator)
    }

    static func isRicher(_ candidate: String, than current: String) -> Bool {
        let candidateDisplay = display(candidate)
        guard candidateDisplay != "-" else { return false }

        let currentDisplay = display(current)
        if currentDisplay == "-" {
            return true
        }

        return componentCount(in: candidateDisplay) > componentCount(in: currentDisplay)
    }

    private static func displayTokens(for component: String) -> [String] {
        if let mapped = positionMap[component] {
            return [mapped]
        }

        var remaining = component
        var mapped: [String] = []
        while remaining.isEmpty == false {
            guard let key = tokenKeys.first(where: { remaining.hasPrefix($0) }),
                  let value = positionMap[key] else {
                return [component]
            }
            mapped.append(value)
            remaining.removeFirst(key.count)
        }
        return mapped
    }

    private static func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "ㅡ", with: "-")
    }

    private static func componentCount(in display: String) -> Int {
        display.split(separator: separatorCharacter).count
    }

    #if DEBUG
    static func resetDebugLogCacheForTesting() {
        debugLogLock.withLock {
            debugLoggedPositionKeys.removeAll()
        }
    }

    static var debugLoggedPositionCountForTesting: Int {
        debugLogLock.withLock {
            debugLoggedPositionKeys.count
        }
    }

    static func logPositionChangeIfNeeded(
        sideLabel: String,
        playerName: String,
        rawPosition: String,
        resolvedPosition: String,
        enrichmentRaw: String?
    ) {
        let rawDisplay = display(rawPosition)
        let enrichmentDisplay = enrichmentRaw.map { display($0) }
        guard rawPosition != resolvedPosition || rawDisplay != rawPosition else { return }
        let key = "\(sideLabel)::\(playerName)::\(rawPosition)::\(resolvedPosition)::\(enrichmentRaw ?? "<nil>")"
        let shouldLog = debugLogLock.withLock {
            debugLoggedPositionKeys.insert(key).inserted
        }
        guard shouldLog else { return }
        print("[GameRecordPosition] side=\(sideLabel) player=\(playerName) raw=\(rawPosition) display=\(rawDisplay) enrichmentRaw=\(enrichmentRaw ?? "<nil>") enrichmentDisplay=\(enrichmentDisplay ?? "<nil>")")
    }
    #endif
}

extension GameCenterReview {
    func enrichingBatterPositions(from source: GameCenterReview?) -> GameCenterReview {
        guard let source else { return self }
        return GameCenterReview(
            summaryItems: summaryItems,
            awayBatting: awayBatting.enrichingPositions(from: source.awayBatting, sideLabel: "away"),
            homeBatting: homeBatting.enrichingPositions(from: source.homeBatting, sideLabel: "home"),
            awayPitching: awayPitching,
            homePitching: homePitching,
            recordSource: recordSource
        )
    }

    func enrichingBatterPositions(from sourceSections: [GameCenterBattingSection]?) -> GameCenterReview {
        guard let sourceSections, sourceSections.count >= 2 else { return self }
        return GameCenterReview(
            summaryItems: summaryItems,
            awayBatting: awayBatting.enrichingPositions(from: sourceSections[0], sideLabel: "away"),
            homeBatting: homeBatting.enrichingPositions(from: sourceSections[1], sideLabel: "home"),
            awayPitching: awayPitching,
            homePitching: homePitching,
            recordSource: recordSource
        )
    }
}

extension GameCenterBattingSection {
    func enrichingPositions(from source: GameCenterBattingSection?, sideLabel: String) -> GameCenterBattingSection {
        guard let source else { return self }

        let sourcePositions = Dictionary(grouping: source.lines, by: { $0.name.normalizedPositionLookupName })
            .compactMapValues { matches -> String? in
                let positions = Set(matches.map(\.position).filter { GameRecordPositionFormatter.display($0) != "-" })
                return positions.count == 1 ? positions.first : nil
            }
        let orderedSourceLines = source.lines.compactMap { line -> (order: String, position: String)? in
            guard let order = line.battingOrderNumber else { return nil }
            return (order, line.position)
        }
        let sourcePositionsByOrder = Dictionary(grouping: orderedSourceLines, by: \.order)
            .compactMapValues { matches -> String? in
                let positions = Set(matches.map(\.position).filter { GameRecordPositionFormatter.display($0) != "-" })
                return positions.count == 1 ? positions.first : nil
            }

        let enrichedLines = lines.map { line -> GameCenterBattingLine in
            let nameCandidate = sourcePositions[line.name.normalizedPositionLookupName]
            let orderCandidate = line.battingOrderNumber.flatMap { sourcePositionsByOrder[$0] }
            let adjacentOrderCandidate = line.battingOrderNumber == nil
                ? inferredAdjacentOrderPosition(for: line, in: lines, sourcePositionsByOrder: sourcePositionsByOrder)
                : nil
            let candidate = nameCandidate ?? orderCandidate ?? adjacentOrderCandidate
            let position = candidate.flatMap {
                GameRecordPositionFormatter.isRicher($0, than: line.position) ? $0 : nil
            } ?? line.position

            #if DEBUG
            GameRecordPositionFormatter.logPositionChangeIfNeeded(
                sideLabel: sideLabel,
                playerName: line.name,
                rawPosition: line.position,
                resolvedPosition: position,
                enrichmentRaw: candidate
            )
            #endif

            return line.replacingPosition(position)
        }

        return GameCenterBattingSection(lines: enrichedLines, totals: totals)
    }

    private func inferredAdjacentOrderPosition(
        for line: GameCenterBattingLine,
        in lines: [GameCenterBattingLine],
        sourcePositionsByOrder: [String: String]
    ) -> String? {
        guard let index = lines.firstIndex(where: { $0.id == line.id }) else {
            return nil
        }

        if index > lines.startIndex {
            for previousIndex in stride(from: lines.index(before: index), through: lines.startIndex, by: -1) {
                if let order = lines[previousIndex].battingOrderNumber,
                   let position = sourcePositionsByOrder[order],
                   GameRecordPositionFormatter.display(position) != "-" {
                    return position
                }
            }
        }

        let nextIndex = lines.index(after: index)
        if nextIndex < lines.endIndex {
            for followingIndex in nextIndex..<lines.endIndex {
                if let order = lines[followingIndex].battingOrderNumber,
                   let position = sourcePositionsByOrder[order],
                   GameRecordPositionFormatter.display(position) != "-" {
                    return position
                }
            }
        }

        return nil
    }
}

private extension GameCenterBattingLine {
    func replacingPosition(_ position: String) -> GameCenterBattingLine {
        GameCenterBattingLine(
            battingOrder: battingOrder,
            position: position,
            name: name,
            atBats: atBats,
            runs: runs,
            hits: hits,
            runsBattedIn: runsBattedIn,
            homeRuns: homeRuns,
            walks: walks,
            strikeouts: strikeouts,
            stolenBases: stolenBases,
            average: average,
            plateAppearanceHomeRuns: plateAppearanceHomeRuns,
            plateAppearanceWalks: plateAppearanceWalks,
            plateAppearanceStrikeouts: plateAppearanceStrikeouts
        )
    }
}

private extension String {
    var normalizedPositionLookupName: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
    }
}
