//
//  GameCenterKeyStatsMapper.swift
//  kboScore
//  기능 설명: 경기 상세 기록에서 핵심 지표와 주요 기록을 추출합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 5/13/26.
//

import Foundation

// GameCenterKeyStatsMapper 구조체는 외부 데이터와 도메인 모델 사이의 변환을 담당합니다.
struct GameCenterKeyStatsMapper {
// Side 열거형는 Side 타입의 역할과 값을 정의합니다.
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

    // stats 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // battingSection 메서드는 이 타입의 주요 동작을 수행합니다.
    private func battingSection(for side: Side) -> GameCenterBattingSection {
        switch side {
        case .away:
            review.awayBatting
        case .home:
            review.homeBatting
        }
    }

    // team 메서드는 이 타입의 주요 동작을 수행합니다.
    private func team(for side: Side) -> Team {
        switch side {
        case .away:
            awayTeam
        case .home:
            homeTeam
        }
    }

    // lineScoreHits 메서드는 이 타입의 주요 동작을 수행합니다.
    private func lineScoreHits(for side: Side) -> Int? {
        switch side {
        case .away:
            lineScore?.awayTotals.hits?.gameCenterStatInt
        case .home:
            lineScore?.homeTotals.hits?.gameCenterStatInt
        }
    }

    // lineScoreErrors 메서드는 이 타입의 주요 동작을 수행합니다.
    private func lineScoreErrors(for side: Side) -> Int? {
        switch side {
        case .away:
            lineScore?.awayTotals.errors?.gameCenterStatInt
        case .home:
            lineScore?.homeTotals.errors?.gameCenterStatInt
        }
    }

    // extraRecordValue 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // sideColumnValue 메서드는 이 타입의 주요 동작을 수행합니다.
    private func sideColumnValue(in item: GameCenterSummaryItem, side: Side) -> Int? {
        guard item.values.count >= 2 else { return nil }
        let index = side == .away ? 0 : 1
        return item.values[safe: index]?.gameCenterStatInt
    }

    // teamNamedValue 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // playerEventCount 메서드는 이 타입의 주요 동작을 수행합니다.
    private func playerEventCount(in value: String, side: Side) -> Int {
        let playerNames = playerNames(for: side)
        guard playerNames.isEmpty == false else { return 0 }
        return playerNames.reduce(0) { count, name in
            count + value.gameCenterRegexMatchCount(
                pattern: "\(NSRegularExpression.escapedPattern(for: name))(?=\\s|\\d|\\(|\\[|,|，|/|·|ㆍ|$)"
            )
        }
    }

    // playerNames 메서드는 이 타입의 주요 동작을 수행합니다.
    private func playerNames(for side: Side) -> [String] {
        battingSection(for: side)
            .lines
            .map(\.name)
            .compactMap(\.nilIfBlank)
            .sorted { $0.count > $1.count }
    }

    // teamNames 메서드는 이 타입의 주요 동작을 수행합니다.
    private func teamNames(for side: Side) -> [String] {
        let team = team(for: side)
        return [team.displayName, team.shortName, team.name, team.markText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    // normalizedAliases 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
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

    // strippingHTML 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // firstGameCenterRegexCapture 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // gameCenterRegexMatchCount 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // total 메서드는 이 타입의 주요 동작을 수행합니다.
    func total(_ keyPath: KeyPath<GameCenterBattingLine, String?>) -> Int? {
        let values = lines.compactMap { $0[keyPath: keyPath]?.gameCenterStatInt }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}
