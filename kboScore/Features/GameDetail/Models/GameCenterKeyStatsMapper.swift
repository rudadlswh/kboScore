//
//  GameCenterKeyStatsMapper.swift
//  kboScore
//
//  Created by Codex on 5/13/26.
//

import Foundation

struct GameCenterKeyStatsMapper {
    enum Side: CaseIterable {
        case away
        case home
    }

    let review: GameCenterReview
    let awayTeam: Team
    let homeTeam: Team
    let lineScore: GameCenterLineScore?

    var comparison: GameCenterKeyStatsComparison {
        GameCenterKeyStatsComparison(
            away: stats(for: .away),
            home: stats(for: .home)
        )
    }

    private func stats(for side: Side) -> GameCenterTeamKeyStats {
        let batting = battingSection(for: side)
        return GameCenterTeamKeyStats(
            hits: lineScoreHits(for: side) ?? batting.totalHits ?? 0,
            homeRuns: extraRecordValue(for: side, aliases: homeRunAliases) ?? batting.totalHomeRuns ?? 0,
            stolenBases: extraRecordValue(for: side, aliases: stolenBaseAliases) ?? 0,
            strikeouts: batting.totalStrikeouts ?? extraRecordValue(for: side, aliases: strikeoutAliases) ?? 0,
            doublePlays: extraRecordValue(for: side, aliases: doublePlayAliases) ?? 0,
            errors: lineScoreErrors(for: side) ?? extraRecordValue(for: side, aliases: errorAliases) ?? 0
        )
    }

    private var homeRunAliases: Set<String> {
        normalizedAliases(["홈런", "HR", "HRA", "HOMERUN", "HOMERUNS"])
    }

    private var stolenBaseAliases: Set<String> {
        normalizedAliases(["도루", "SB", "STOLENBASE", "STOLENBASES"])
    }

    private var strikeoutAliases: Set<String> {
        normalizedAliases(["삼진", "SO", "K", "STRIKEOUT", "STRIKEOUTS"])
    }

    private var doublePlayAliases: Set<String> {
        normalizedAliases(["병살", "병살타", "GDP", "GIDP", "DOUBLEPLAY", "DOUBLEPLAYS", "GROUNDEDINTODOUBLEPLAY"])
    }

    private var errorAliases: Set<String> {
        normalizedAliases(["실책", "E", "ERROR", "ERRORS"])
    }

    private func battingSection(for side: Side) -> GameCenterBattingSection {
        switch side {
        case .away:
            review.awayBatting
        case .home:
            review.homeBatting
        }
    }

    private func team(for side: Side) -> Team {
        switch side {
        case .away:
            awayTeam
        case .home:
            homeTeam
        }
    }

    private func lineScoreHits(for side: Side) -> Int? {
        switch side {
        case .away:
            lineScore?.awayTotals.hits?.gameCenterStatInt
        case .home:
            lineScore?.homeTotals.hits?.gameCenterStatInt
        }
    }

    private func lineScoreErrors(for side: Side) -> Int? {
        switch side {
        case .away:
            lineScore?.awayTotals.errors?.gameCenterStatInt
        case .home:
            lineScore?.homeTotals.errors?.gameCenterStatInt
        }
    }

    private func extraRecordValue(for side: Side, aliases: Set<String>) -> Int? {
        let matchingItems = review.summaryItems.filter { aliases.contains($0.title.normalizedKeyStatLabel) }
        guard matchingItems.isEmpty == false else { return nil }

        var total = 0
        var didResolve = false
        for item in matchingItems {
            if let value = sideColumnValue(in: item, side: side) {
                total += value
                didResolve = true
                continue
            }
            if let value = teamNamedValue(in: item, side: side) {
                total += value
                didResolve = true
                continue
            }

            let eventCount = playerEventCount(in: item.value, side: side)
            total += eventCount
            didResolve = didResolve || eventCount > 0 || item.value.representsNoOfficialEvents
        }

        return didResolve ? total : nil
    }

    private func sideColumnValue(in item: GameCenterSummaryItem, side: Side) -> Int? {
        guard item.values.count >= 2 else { return nil }
        let index = side == .away ? 0 : 1
        return item.values[safe: index]?.gameCenterStatInt
    }

    private func teamNamedValue(in item: GameCenterSummaryItem, side: Side) -> Int? {
        let value = item.value
        let names = teamNames(for: side)
        for name in names {
            let pattern = "\(NSRegularExpression.escapedPattern(for: name))\\s*[:：]?\\s*(\\d+)"
            if let capture = value.firstGameCenterRegexCapture(pattern: pattern),
               let intValue = Int(capture) {
                return intValue
            }
        }
        return nil
    }

    private func playerEventCount(in value: String, side: Side) -> Int {
        let playerNames = playerNames(for: side)
        guard playerNames.isEmpty == false else { return 0 }
        return playerNames.reduce(0) { count, name in
            count + value.gameCenterRegexMatchCount(
                pattern: "\(NSRegularExpression.escapedPattern(for: name))(?=\\s|\\d|\\(|\\[|,|，|/|·|ㆍ|$)"
            )
        }
    }

    private func playerNames(for side: Side) -> [String] {
        battingSection(for: side)
            .lines
            .map(\.name)
            .compactMap(\.nilIfBlank)
            .sorted { $0.count > $1.count }
    }

    private func teamNames(for side: Side) -> [String] {
        let team = team(for: side)
        return [team.displayName, team.shortName, team.name, team.markText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    private func normalizedAliases(_ aliases: [String]) -> Set<String> {
        Set(aliases.map(\.normalizedKeyStatLabel))
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

    var gameCenterStatInt: Int? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        if trimmed.representsNoOfficialEvents { return 0 }
        guard trimmed.isIntegerStatValue else { return nil }
        return Int(trimmed)
    }

    var isIntegerStatValue: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }
        return trimmed.allSatisfy(\.isNumber)
    }

    var normalizedKeyStatLabel: String {
        let scalars = normalizedGridText.unicodeScalars.filter { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar) == false &&
            CharacterSet.punctuationCharacters.contains(scalar) == false &&
            CharacterSet.symbols.contains(scalar) == false
        }
        return String(String.UnicodeScalarView(scalars)).uppercased()
    }

    var representsNoOfficialEvents: Bool {
        let normalized = normalizedKeyStatLabel
        return normalized.isEmpty || ["없음", "무", "NONE", "NO", "NIL", "-"].contains(normalized)
    }

    func firstGameCenterRegexCapture(pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: self) else {
            return nil
        }
        return String(self[captureRange])
    }

    func gameCenterRegexMatchCount(pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.numberOfMatches(in: self, range: range)
    }
}

private extension GameCenterBattingSection {
    var totalHits: Int? {
        totals?.hits?.gameCenterStatInt ?? total(\.hits)
    }

    var totalHomeRuns: Int? {
        totals?.homeRuns?.gameCenterStatInt ?? total(\.homeRuns)
    }

    var totalStrikeouts: Int? {
        totals?.strikeouts?.gameCenterStatInt ?? total(\.strikeouts)
    }

    func total(_ keyPath: KeyPath<GameCenterBattingLine, String?>) -> Int? {
        let values = lines.compactMap { $0[keyPath: keyPath]?.gameCenterStatInt }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}
