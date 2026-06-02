//
//  OfficialKBOGameCenterClient.swift
//  kboScore
//
//  Created by Codex on 4/8/26.
//

import Foundation

struct GameCenterBoxScorePayload: Sendable {
    enum Source: String, Sendable {
        case fullBoxscore
        case scoreboardHTMLBoxscore
        case keyplayerPartialLimited
    }

    let source: Source
    let summaryItems: [GameCenterSummaryItem]
    let battingSections: [GameCenterBattingSection]
    let pitchingSections: [GameCenterPitchingSection]

    var recordSource: GameCenterRecordSource {
        switch source {
        case .fullBoxscore:
            .fullBoxscore
        case .scoreboardHTMLBoxscore:
            .scoreboardHTMLBoxscore
        case .keyplayerPartialLimited:
            .keyplayerPartialLimited
        }
    }

    var batterCount: Int {
        battingSections.reduce(0) { $0 + $1.lines.count }
    }

    var pitcherCount: Int {
        pitchingSections.reduce(0) { $0 + $1.lines.count }
    }

    var review: GameCenterReview? {
        guard battingSections.count >= 2 || pitchingSections.count >= 2 else {
            return nil
        }
        let emptyBatting = GameCenterBattingSection(lines: [], totals: nil)
        let emptyPitching = GameCenterPitchingSection(lines: [])

        return GameCenterReview(
            summaryItems: summaryItems,
            awayBatting: battingSections[safe: 0] ?? emptyBatting,
            homeBatting: battingSections[safe: 1] ?? emptyBatting,
            awayPitching: pitchingSections[safe: 0] ?? emptyPitching,
            homePitching: pitchingSections[safe: 1] ?? emptyPitching,
            recordSource: recordSource
        )
    }
}

extension GameCenterReview {
    func keyStats(
        awayTeam: Team,
        homeTeam: Team,
        lineScore: GameCenterLineScore?
    ) -> GameCenterKeyStatsComparison {
        GameCenterKeyStatsMapper(
            review: self,
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            lineScore: lineScore
        ).comparison
    }

    func fillingMissingLiveBatters(from lineupSections: [GameCenterBattingSection]?) -> GameCenterReview {
        guard let lineupSections, lineupSections.count >= 2 else { return self }
        return GameCenterReview(
            summaryItems: summaryItems,
            awayBatting: awayBatting.fillingMissingLiveBatters(from: lineupSections[0]),
            homeBatting: homeBatting.fillingMissingLiveBatters(from: lineupSections[1]),
            awayPitching: awayPitching,
            homePitching: homePitching,
            recordSource: recordSource
        )
    }

    func overlayingLivePlateAppearanceStats(from plateAppearanceSections: [GameCenterBattingSection]?) -> GameCenterReview {
        guard let plateAppearanceSections, plateAppearanceSections.count >= 2 else { return self }
        return GameCenterReview(
            summaryItems: summaryItems,
            awayBatting: awayBatting.overlayingLivePlateAppearanceStats(from: plateAppearanceSections[0]),
            homeBatting: homeBatting.overlayingLivePlateAppearanceStats(from: plateAppearanceSections[1]),
            awayPitching: awayPitching,
            homePitching: homePitching,
            recordSource: recordSource
        )
    }

    func fillingMissingLivePitchers(from baseSections: [GameCenterPitchingSection]?) -> GameCenterReview {
        guard let baseSections, baseSections.count >= 2 else { return self }
        return GameCenterReview(
            summaryItems: summaryItems,
            awayBatting: awayBatting,
            homeBatting: homeBatting,
            awayPitching: awayPitching.fillingMissingLivePitchers(from: baseSections[0]),
            homePitching: homePitching.fillingMissingLivePitchers(from: baseSections[1]),
            recordSource: recordSource
        )
    }
}

private extension GameCenterBattingSection {
    func fillingMissingLiveBatters(from lineupSection: GameCenterBattingSection) -> GameCenterBattingSection {
        guard lineupSection.lines.isEmpty == false else { return self }

        var mergedLines = lineupSection.lines.map { $0.liveLineupBaseLine }
        var mergedKeys = Set(mergedLines.map(\.liveBatterMergeKey))

        for statsLine in lines {
            let key = statsLine.liveBatterMergeKey
            if let index = mergedLines.firstIndex(where: { $0.liveBatterMergeKey == key }) {
                mergedLines[index] = mergedLines[index].overlayingLiveStats(from: statsLine)
                #if DEBUG
                let line = mergedLines[index]
                print("[GameDetailLive] live batter overlay player=\(line.name) order=\(line.battingOrder) HR=\(line.homeRuns ?? line.plateAppearanceHomeRuns ?? "<nil>") SO=\(line.strikeouts ?? line.plateAppearanceStrikeouts ?? "<nil>") BB=\(line.walks ?? line.plateAppearanceWalks ?? "<nil>")")
                #endif
            } else if mergedKeys.insert(key).inserted {
                mergedLines.append(statsLine)
            }
        }

        let sortedLines = mergedLines.sortedByLiveBattingOrder
        #if DEBUG
        let homeRunCount = sortedLines.filter { ($0.homeRuns ?? $0.plateAppearanceHomeRuns)?.nilIfBlank != nil }.count
        let strikeoutCount = sortedLines.filter { ($0.strikeouts ?? $0.plateAppearanceStrikeouts)?.nilIfBlank != nil }.count
        let walkCount = sortedLines.filter { ($0.walks ?? $0.plateAppearanceWalks)?.nilIfBlank != nil }.count
        print("[GameDetailLive] live batter section merged finalRowCount=\(sortedLines.count) nonEmptyHR=\(homeRunCount) nonEmptySO=\(strikeoutCount) nonEmptyBB=\(walkCount)")
        #endif

        return GameCenterBattingSection(
            lines: sortedLines,
            totals: totals
        )
    }

    func overlayingLivePlateAppearanceStats(from plateAppearanceSection: GameCenterBattingSection) -> GameCenterBattingSection {
        guard plateAppearanceSection.lines.isEmpty == false else { return self }

        var mergedLines = lines
        for statsLine in plateAppearanceSection.lines {
            guard let index = mergedLines.firstIndex(where: { $0.liveBatterMergeKey == statsLine.liveBatterMergeKey }) else {
                continue
            }
            mergedLines[index] = mergedLines[index].overlayingLivePlateAppearanceStats(from: statsLine)
        }

        return GameCenterBattingSection(lines: mergedLines.sortedByLiveBattingOrder, totals: totals)
    }
}

private extension GameCenterBattingLine {
    var liveLineupBaseLine: GameCenterBattingLine {
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

    var liveBatterMergeKey: String {
        name.normalizedLiveBatterName
    }

    func overlayingLiveStats(from statsLine: GameCenterBattingLine) -> GameCenterBattingLine {
        GameCenterBattingLine(
            battingOrder: battingOrder.nilIfBlank ?? statsLine.battingOrder,
            position: GameRecordPositionFormatter.isRicher(statsLine.position, than: position) ? statsLine.position : position,
            name: name.nilIfBlank ?? statsLine.name,
            atBats: statsLine.atBats ?? atBats,
            runs: statsLine.runs ?? runs,
            hits: statsLine.hits ?? hits,
            runsBattedIn: statsLine.runsBattedIn ?? runsBattedIn,
            homeRuns: statsLine.homeRuns ?? homeRuns,
            walks: statsLine.walks ?? walks,
            strikeouts: statsLine.strikeouts ?? strikeouts,
            stolenBases: statsLine.stolenBases ?? stolenBases,
            average: statsLine.average ?? average,
            plateAppearanceHomeRuns: statsLine.plateAppearanceHomeRuns ?? plateAppearanceHomeRuns,
            plateAppearanceWalks: statsLine.plateAppearanceWalks ?? plateAppearanceWalks,
            plateAppearanceStrikeouts: statsLine.plateAppearanceStrikeouts ?? plateAppearanceStrikeouts
        )
    }

    func overlayingLivePlateAppearanceStats(from statsLine: GameCenterBattingLine) -> GameCenterBattingLine {
        GameCenterBattingLine(
            battingOrder: battingOrder,
            position: position,
            name: name,
            atBats: atBats,
            runs: runs,
            hits: hits,
            runsBattedIn: runsBattedIn,
            homeRuns: statsLine.homeRuns ?? homeRuns,
            walks: statsLine.walks ?? walks,
            strikeouts: statsLine.strikeouts ?? strikeouts,
            stolenBases: stolenBases,
            average: average,
            plateAppearanceHomeRuns: statsLine.homeRuns ?? plateAppearanceHomeRuns,
            plateAppearanceWalks: statsLine.walks ?? plateAppearanceWalks,
            plateAppearanceStrikeouts: statsLine.strikeouts ?? plateAppearanceStrikeouts
        )
    }
}

private extension GameCenterPitchingSection {
    func fillingMissingLivePitchers(from baseSection: GameCenterPitchingSection) -> GameCenterPitchingSection {
        var mergedLines = baseSection.lines
        var mergedKeys = Set(mergedLines.map(\.livePitcherMergeKey))

        for statsLine in lines {
            let key = statsLine.livePitcherMergeKey
            if let index = mergedLines.firstIndex(where: { $0.livePitcherMergeKey == key }) {
                mergedLines[index] = mergedLines[index].overlayingLivePitchingStats(from: statsLine)
            } else if mergedKeys.insert(key).inserted {
                mergedLines.append(statsLine)
            }
        }

        return GameCenterPitchingSection(lines: mergedLines)
    }
}

private extension GameCenterPitchingLine {
    var livePitcherMergeKey: String {
        name.normalizedLivePitcherName
    }

    func overlayingLivePitchingStats(from statsLine: GameCenterPitchingLine) -> GameCenterPitchingLine {
        GameCenterPitchingLine(
            pitchingOrder: pitchingOrder ?? statsLine.pitchingOrder,
            name: name.nilIfBlank ?? statsLine.name,
            role: role ?? statsLine.role,
            result: statsLine.result ?? result,
            innings: statsLine.innings ?? innings,
            battersFaced: statsLine.battersFaced ?? battersFaced,
            pitches: statsLine.pitches ?? pitches,
            atBats: statsLine.atBats ?? atBats,
            hitsAllowed: statsLine.hitsAllowed ?? hitsAllowed,
            walksAllowed: statsLine.walksAllowed ?? walksAllowed,
            hitBatters: statsLine.hitBatters ?? hitBatters,
            walksOrHitByPitch: statsLine.walksOrHitByPitch ?? walksOrHitByPitch,
            strikeouts: statsLine.strikeouts ?? strikeouts,
            homeRunsAllowed: statsLine.homeRunsAllowed ?? homeRunsAllowed,
            runsAllowed: statsLine.runsAllowed ?? runsAllowed,
            earnedRuns: statsLine.earnedRuns ?? earnedRuns,
            earnedRunAverage: statsLine.earnedRunAverage ?? earnedRunAverage
        )
    }
}

private extension Array where Element == GameCenterBattingLine {
    var sortedByLiveBattingOrder: [GameCenterBattingLine] {
        enumerated().sorted { lhs, rhs in
            let lhsOrder = Int(lhs.element.battingOrder.battingOrderNumber ?? "") ?? Int.max
            let rhsOrder = Int(rhs.element.battingOrder.battingOrderNumber ?? "") ?? Int.max
            if lhsOrder == rhsOrder {
                return lhs.offset < rhs.offset
            }
            return lhsOrder < rhsOrder
        }.map(\.element)
    }

    func sum(_ keyPath: KeyPath<GameCenterBattingLine, String?>) -> Int? {
        let values = compactMap { $0[keyPath: keyPath]?.intValue }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}

#if DEBUG
private extension GameCenterBattingTotals {
    static func derived(from lines: [GameCenterBattingLine]) -> GameCenterBattingTotals? {
        let atBats = lines.sum(\.atBats)
        let runs = lines.sum(\.runs)
        let hits = lines.sum(\.hits)
        let runsBattedIn = lines.sum(\.runsBattedIn)
        let homeRuns = lines.sum(\.homeRuns)
        let walks = lines.sum(\.walks)
        let strikeouts = lines.sum(\.strikeouts)
        guard [atBats, runs, hits, runsBattedIn, homeRuns, walks, strikeouts].contains(where: { $0 != nil }) else {
            return nil
        }
        return GameCenterBattingTotals(
            atBats: atBats.map(String.init),
            runs: runs.map(String.init),
            hits: hits.map(String.init),
            runsBattedIn: runsBattedIn.map(String.init),
            homeRuns: homeRuns.map(String.init),
            walks: walks.map(String.init),
            strikeouts: strikeouts.map(String.init),
            average: nil
        )
    }

    var debugSummary: String {
        "AB:\(atBats ?? "-") R:\(runs ?? "-") H:\(hits ?? "-") RBI:\(runsBattedIn ?? "-") HR:\(homeRuns ?? "-") BB:\(walks ?? "-") SO:\(strikeouts ?? "-")"
    }
}

private extension Array where Element == GameCenterPitchingLine {
    var debugPitchingSummary: String {
        "IP:\(compactMap(\.innings).joined(separator: "+")) R:\(sum(\.runsAllowed).map(String.init) ?? "-") ER:\(sum(\.earnedRuns).map(String.init) ?? "-") BB:\(sum(\.walksAllowed).map(String.init) ?? "-") SO:\(sum(\.strikeouts).map(String.init) ?? "-")"
    }

    func sum(_ keyPath: KeyPath<GameCenterPitchingLine, String?>) -> Int? {
        let values = compactMap { $0[keyPath: keyPath]?.intValue }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}
#endif

private extension String {
    var intValue: Int? {
        Int(trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var normalizedLiveBatterName: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    var normalizedLivePitcherName: String {
        normalizedLiveBatterName
    }
}

private enum LivePlateAppearanceSide {
    case away
    case home

    init?(inningText: String) {
        let normalized = inningText.normalizedLivePlateAppearanceText
        if normalized.contains("초") || normalized.contains("TOP") {
            self = .away
        } else if normalized.contains("말") || normalized.contains("BOTTOM") || normalized.contains("BOT") {
            self = .home
        } else {
            return nil
        }
    }
}

private enum LivePitcherSide: String {
    case away
    case home

    init?(inningText: String?) {
        guard let inningText else { return nil }
        let normalized = inningText.normalizedLivePlateAppearanceText
        if normalized.contains("초") || normalized.contains("TOP") {
            self = .home
        } else if normalized.contains("말") || normalized.contains("BOTTOM") || normalized.contains("BOT") {
            self = .away
        } else {
            return nil
        }
    }
}

private struct LivePitcherAppearance: Sendable {
    let playerName: String
    let side: LivePitcherSide
    let role: String
    let firstObservedOrder: Int
    let inningText: String
}

private extension PlateAppearanceDerivedStats {
    var hasEvent: Bool {
        homeRuns > 0 || walks > 0 || strikeouts > 0
    }
}

private extension OfficialKeyPlayerRecord {
    func keyPlayerIntegerStat(aliases: [String]) -> String? {
        keyPlayerRawValue(aliases: aliases).flatMap(\.gameCenterStatInt).map(String.init)
    }

    private func keyPlayerRawValue(aliases: [String]) -> String? {
        let normalizedAliases = Set(aliases.map(\.normalizedKeyPlayerFieldName))
        return rawValues.first { key, _ in
            normalizedAliases.contains(key.normalizedKeyPlayerFieldName)
        }?.value
    }
}

private extension String {
    var normalizedKeyPlayerFieldName: String {
        let scalars = unicodeScalars.filter { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar) == false &&
                CharacterSet.punctuationCharacters.contains(scalar) == false &&
                CharacterSet.symbols.contains(scalar) == false
        }
        return String(String.UnicodeScalarView(scalars)).uppercased()
    }

    var normalizedLivePlateAppearanceText: String {
        let scalars = unicodeScalars.filter { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar) == false &&
                CharacterSet.punctuationCharacters.contains(scalar) == false &&
                CharacterSet.symbols.contains(scalar) == false
        }
        return String(String.UnicodeScalarView(scalars)).uppercased()
    }

    var livePlateAppearanceDerivedStats: PlateAppearanceDerivedStats {
        let normalized = normalizedLivePlateAppearanceText
        return PlateAppearanceDerivedStats(
            homeRuns: (normalized.contains("홈런") || normalized.contains("HOMERUN") || normalized.contains("HR")) ? 1 : 0,
            walks: (normalized.contains("볼넷") || normalized.contains("고의4구") || normalized.contains("자동고의4구") || normalized.contains("4구") || normalized.contains("WALK") || normalized.contains("BB")) ? 1 : 0,
            strikeouts: (normalized.contains("삼진") || normalized.contains("낫아웃") || normalized.contains("STRIKEOUT") || normalized.contains("SO")) ? 1 : 0
        )
    }

    var livePitcherAppearanceName: String? {
        let patterns = [
            #"투수\s*[:：]?\s*([가-힣A-Za-z·.\-]{2,20})"#,
            #"([가-힣A-Za-z·.\-]{2,20})\s*(?:투수\s*)?(?:등판|교체|투입)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(startIndex..<endIndex, in: self)
            guard let match = regex.firstMatch(in: self, range: range),
                  match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: self) else {
                continue
            }
            let name = String(self[captureRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,:;()[]{}"))
            if name.nilIfBlank != nil,
               ["교체", "등판", "투입", "투수"].contains(name) == false {
                return name
            }
        }
        return nil
    }
}

struct OfficialKBOGameCenterClient: Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let calendar: Calendar

    init(
        baseURL: URL = URL(string: "https://www.koreabaseball.com/")!,
        session: URLSession = .shared,
        calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
            return calendar
        }()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.calendar = calendar
    }

    func fetchDetail(for game: GameDetail) async throws -> GameCenterDetailPayload? {
        try await fetchDetail(for: game, includeRecordFallback: true)
    }

    func fetchDetail(for game: GameDetail, includeRecordFallback: Bool) async throws -> GameCenterDetailPayload? {
        guard let context = try await fetchContext(for: game) else {
            return nil
        }

        async let scoreboard = fetchScoreboardIfNeeded(for: context)
        async let boxScore = includeRecordFallback ? fetchBoxScoreIfNeeded(for: context) : nil
        async let lineupBattingSections = shouldFetchLineupBattingSections(
            for: context,
            includeRecordFallback: includeRecordFallback
        ) ? fetchLineupBattingSectionsIfNeeded(for: context) : nil
        async let preview = fetchPreviewIfNeeded(for: context)

        let scoreboardValue = try await scoreboard
        let boxScoreValue = try await boxScore
        let lineupBattingSectionsValue = try await lineupBattingSections
        let battingSectionsForBaseRunners = (boxScoreValue?.battingSections.count ?? 0) >= 2
            ? boxScoreValue?.battingSections
            : lineupBattingSectionsValue
        let review = makeReview(
            from: boxScoreValue,
            lineupBattingSections: lineupBattingSectionsValue,
            context: context
        )
        #if DEBUG
        if context.entry.status.isLiveLike {
            print("[GameDetailLive] official detail result gameID=\(context.entry.gameID) lineScorePresent=\(scoreboardValue?.lineScore != nil) liveRecordPresent=\(review?.hasDisplayableRecords == true) recordSource=\(boxScoreValue?.source.rawValue ?? "<none>") finalBatterCount=\(review.map { $0.awayBatting.lines.count + $0.homeBatting.lines.count } ?? 0) finalPitcherCount=\(review.map { $0.awayPitching.lines.count + $0.homePitching.lines.count } ?? 0) majorRecordCount=\(review?.summaryItems.count ?? 0)")
        }
        #endif
        return GameCenterDetailPayload(
            summary: GameCenterSummary(
                officialGameID: context.entry.gameID,
                dateText: context.entry.displayDateText,
                stadium: scoreboardValue?.stadium ?? context.entry.stadiumName,
                startTime: scoreboardValue?.startTime ?? context.entry.startTime,
                endTime: scoreboardValue?.endTime,
                durationText: scoreboardValue?.durationText,
                crowdText: scoreboardValue?.crowdText,
                status: context.entry.status,
                inningText: context.entry.inningText,
                awayScore: context.entry.awayScore,
                homeScore: context.entry.homeScore,
                balls: context.entry.balls,
                strikes: context.entry.strikes,
                outs: context.entry.outs,
                bases: context.entry.bases,
                baseRunners: context.entry.baseRunners(from: battingSectionsForBaseRunners),
                probableStarters: context.entry.probableStarters,
                winningPitcher: context.entry.winningPitcherName,
                losingPitcher: context.entry.losingPitcherName,
                savePitcher: context.entry.savePitcherName
            ),
            lineScore: scoreboardValue?.lineScore,
            review: review,
            preview: try await preview
        )
    }

    func fetchRecordFallbackReview(for game: GameDetail) async throws -> GameCenterReview? {
        guard let context = try await fetchContext(for: game) else {
            return nil
        }

        async let boxScore = fetchBoxScoreIfNeeded(for: context)
        async let lineupBattingSections = fetchLineupBattingSectionsIfNeeded(for: context)
        let boxScoreValue = try await boxScore
        let lineupBattingSectionsValue = try await lineupBattingSections
        return makeReview(
            from: boxScoreValue,
            lineupBattingSections: lineupBattingSectionsValue,
            context: context
        )
    }

    private func shouldFetchLineupBattingSections(
        for context: OfficialGameLookupContext,
        includeRecordFallback: Bool
    ) -> Bool {
        if includeRecordFallback {
            return true
        }
        guard context.entry.status == .live || context.entry.status == .rainDelay,
              let bases = context.entry.bases else {
            return false
        }
        return bases.first || bases.second || bases.third
    }

    private func makeReview(
        from boxScore: GameCenterBoxScorePayload?,
        lineupBattingSections: [GameCenterBattingSection]?,
        context: OfficialGameLookupContext
    ) -> GameCenterReview? {
        guard context.entry.status.isLiveLike else {
            return boxScore?.review?.enrichingBatterPositions(from: lineupBattingSections)
        }

        let sourceReview = boxScore?.review
        guard sourceReview != nil || (lineupBattingSections?.count ?? 0) >= 2 else {
            return nil
        }

        let emptyBatting = GameCenterBattingSection(lines: [], totals: nil)
        let emptyPitching = GameCenterPitchingSection(lines: [])
        let baseReview = sourceReview ?? GameCenterReview(
            summaryItems: [],
            awayBatting: emptyBatting,
            homeBatting: emptyBatting,
            awayPitching: emptyPitching,
            homePitching: emptyPitching,
            recordSource: .lineupLimited
        )
        let enrichedReview = baseReview.enrichingBatterPositions(from: lineupBattingSections)
        let lineupMergedReview = enrichedReview.fillingMissingLiveBatters(from: lineupBattingSections)
        if boxScore?.source == .fullBoxscore || boxScore?.source == .scoreboardHTMLBoxscore {
            let fullReview = enrichedReview
            #if DEBUG
            logOfficialRecordConsistency(review: fullReview, source: boxScore?.source.rawValue ?? "<none>")
            #endif
            return fullReview
        }

        let plateAppearanceSections = makeLivePlateAppearanceBattingSections(
            from: context.game.events,
            lineupSections: lineupBattingSections
        )
        let pitcherBaseSections = makeLivePitchingBaseSections(context: context)
        let mergedReview = lineupMergedReview
            .overlayingLivePlateAppearanceStats(from: plateAppearanceSections)
            .fillingMissingLivePitchers(from: pitcherBaseSections)

        #if DEBUG
        let lineupBaseBatterCount = lineupBattingSections?.reduce(0) { $0 + $1.lines.count } ?? 0
        let fullBatterCount = (boxScore?.source == .fullBoxscore || boxScore?.source == .scoreboardHTMLBoxscore) ? boxScore?.batterCount ?? 0 : 0
        let keyplayerBatterCount = boxScore?.source == .keyplayerPartialLimited ? boxScore?.batterCount ?? 0 : 0
        let mergedBatterCount = mergedReview.awayBatting.lines.count + mergedReview.homeBatting.lines.count
        let fullPitcherCount = (boxScore?.source == .fullBoxscore || boxScore?.source == .scoreboardHTMLBoxscore) ? boxScore?.pitcherCount ?? 0 : 0
        let keyplayerPitcherCount = boxScore?.source == .keyplayerPartialLimited ? boxScore?.pitcherCount ?? 0 : 0
        let mergedPitcherCount = mergedReview.awayPitching.lines.count + mergedReview.homePitching.lines.count
        print("[GameDetailLive] live batter merge gameID=\(context.entry.gameID) lineupBaseBatterCount=\(lineupBaseBatterCount) keyplayerBatterCount=\(keyplayerBatterCount) fullBatterCount=\(fullBatterCount) mergedBatterCount=\(mergedBatterCount) recordSource=\(boxScore?.source.rawValue ?? "lineupBase")")
        print("[GameDetailLive] pitcher keyplayer count=\(keyplayerPitcherCount)")
        print("[GameDetailLive] pitcher full count=\(fullPitcherCount)")
        print("[GameDetailLive] pitcher merged count=\(mergedPitcherCount)")
        #endif

        return mergedReview
    }

    #if DEBUG
    private func logOfficialRecordConsistency(review: GameCenterReview, source: String) {
        let awayOfficialBatting = review.awayBatting.totals
        let homeOfficialBatting = review.homeBatting.totals
        let awayRenderedBatting = GameCenterBattingTotals.derived(from: review.awayBatting.lines)
        let homeRenderedBatting = GameCenterBattingTotals.derived(from: review.homeBatting.lines)
        let battingPass = battingTotalsMatch(awayOfficialBatting, awayRenderedBatting) &&
            battingTotalsMatch(homeOfficialBatting, homeRenderedBatting)

        print("[GameDetailLive] official batting totals away=\(awayOfficialBatting?.debugSummary ?? "<nil>") home=\(homeOfficialBatting?.debugSummary ?? "<nil>") source=\(source)")
        print("[GameDetailLive] rendered batting totals away=\(awayRenderedBatting?.debugSummary ?? "<nil>") home=\(homeRenderedBatting?.debugSummary ?? "<nil>") source=\(source)")
        print("[GameDetailLive] official pitching totals away=<derived> home=<derived> source=\(source)")
        print("[GameDetailLive] rendered pitching totals away=\(review.awayPitching.lines.debugPitchingSummary) home=\(review.homePitching.lines.debugPitchingSummary) source=\(source)")
        print("[GameDetailLive] record consistency batting=\(battingPass ? "pass" : "fail") reason=\(battingPass ? "totalsMatchOrUnavailable" : "officialTotalsDifferFromRows")")
        print("[GameDetailLive] record consistency pitching=pass reason=renderedFromOfficialRows")
    }

    private func battingTotalsMatch(_ official: GameCenterBattingTotals?, _ rendered: GameCenterBattingTotals?) -> Bool {
        guard let official, let rendered else { return true }
        return official.atBats == rendered.atBats &&
            official.runs == rendered.runs &&
            official.hits == rendered.hits &&
            official.runsBattedIn == rendered.runsBattedIn
    }
    #endif

    private func makeLivePitchingBaseSections(context: OfficialGameLookupContext) -> [GameCenterPitchingSection] {
        var awayLines: [GameCenterPitchingLine] = []
        var homeLines: [GameCenterPitchingLine] = []
        let game = context.game

        if let awayStarter = game.awayStartingPitcherName?.nilIfBlank {
            awayLines.append(makeLivePitchingBaseLine(name: awayStarter, order: "1", role: "선발"))
        }
        if let homeStarter = game.homeStartingPitcherName?.nilIfBlank {
            homeLines.append(makeLivePitchingBaseLine(name: homeStarter, order: "1", role: "선발"))
        }

        let inferredSide = LivePitcherSide(inningText: context.entry.inningText) ?? LivePitcherSide(inningText: game.inningText)
        if let currentName = game.currentPitcherName?.nilIfBlank,
           let inferredSide {
            let currentLine = makeLivePitchingBaseLine(name: currentName, order: "2", role: "현재")
            switch inferredSide {
            case .away:
                if awayLines.contains(where: { $0.livePitcherMergeKey == currentLine.livePitcherMergeKey }) == false {
                    awayLines.append(currentLine)
                }
            case .home:
                if homeLines.contains(where: { $0.livePitcherMergeKey == currentLine.livePitcherMergeKey }) == false {
                    homeLines.append(currentLine)
                }
            }
        }

        let appearanceSections = makeLivePitcherAppearanceSections(from: game.events)
        for line in appearanceSections[0].lines where awayLines.contains(where: { $0.livePitcherMergeKey == line.livePitcherMergeKey }) == false {
            awayLines.append(line)
        }
        for line in appearanceSections[1].lines where homeLines.contains(where: { $0.livePitcherMergeKey == line.livePitcherMergeKey }) == false {
            homeLines.append(line)
        }

        #if DEBUG
        print("[GameDetailLive] pitcher base awayStarter=\(game.awayStartingPitcherName?.nilIfBlank ?? "<nil>") homeStarter=\(game.homeStartingPitcherName?.nilIfBlank ?? "<nil>")")
        print("[GameDetailLive] pitcher current name=\(game.currentPitcherName?.nilIfBlank ?? "<nil>") inferredSide=\(inferredSide?.rawValue ?? "<nil>")")
        for line in awayLines {
            print("[GameDetailLive] pitcher row side=away player=\(line.name) source=base stats=IP:\(line.innings ?? "-") K:\(line.strikeouts ?? "-") R:\(line.runsAllowed ?? "-")")
        }
        for line in homeLines {
            print("[GameDetailLive] pitcher row side=home player=\(line.name) source=base stats=IP:\(line.innings ?? "-") K:\(line.strikeouts ?? "-") R:\(line.runsAllowed ?? "-")")
        }
        #endif

        return [
            GameCenterPitchingSection(lines: awayLines),
            GameCenterPitchingSection(lines: homeLines)
        ]
    }

    private func makeLivePitcherAppearanceSections(from events: [GameEvent]) -> [GameCenterPitchingSection] {
        guard events.isEmpty == false else {
            #if DEBUG
            print("[GameDetailLive] pitcher appearance source available=false reason=noEvents")
            #endif
            return [GameCenterPitchingSection(lines: []), GameCenterPitchingSection(lines: [])]
        }

        var appearances: [LivePitcherAppearance] = []
        var seenKeys: Set<String> = []

        for (index, event) in events.enumerated() {
            guard let side = LivePitcherSide(inningText: event.inningText) else { continue }
            guard event.type == .pitching || event.headline.normalizedLivePlateAppearanceText.contains("투수") || event.headline.normalizedLivePlateAppearanceText.contains("등판") || event.headline.normalizedLivePlateAppearanceText.contains("교체") || event.headline.normalizedLivePlateAppearanceText.contains("투입") else {
                continue
            }
            guard let playerName = event.headline.livePitcherAppearanceName?.nilIfBlank else { continue }
            let key = "\(side.rawValue)|\(playerName.normalizedLivePitcherName)"
            guard seenKeys.insert(key).inserted else { continue }

            appearances.append(
                LivePitcherAppearance(
                    playerName: playerName,
                    side: side,
                    role: "구원",
                    firstObservedOrder: index,
                    inningText: event.inningText
                )
            )
        }

        guard appearances.isEmpty == false else {
            #if DEBUG
            print("[GameDetailLive] pitcher appearance source available=false reason=noPitcherAppearanceEvents eventCount=\(events.count)")
            #endif
            return [GameCenterPitchingSection(lines: []), GameCenterPitchingSection(lines: [])]
        }

        let sortedAppearances = appearances.sorted { $0.firstObservedOrder < $1.firstObservedOrder }
        #if DEBUG
        print("[GameDetailLive] pitcher appearance source available=true reason=events")
        print("[GameDetailLive] pitcher appearance parsed count=\(sortedAppearances.count)")
        for appearance in sortedAppearances {
            print("[GameDetailLive] pitcher appearance row side=\(appearance.side.rawValue) player=\(appearance.playerName) inning=\(appearance.inningText) source=events")
        }
        #endif

        let awayLines = sortedAppearances
            .filter { $0.side == .away }
            .map { makeLivePitchingBaseLine(name: $0.playerName, order: String($0.firstObservedOrder + 2), role: $0.role) }
        let homeLines = sortedAppearances
            .filter { $0.side == .home }
            .map { makeLivePitchingBaseLine(name: $0.playerName, order: String($0.firstObservedOrder + 2), role: $0.role) }
        return [
            GameCenterPitchingSection(lines: awayLines),
            GameCenterPitchingSection(lines: homeLines)
        ]
    }

    private func makeLivePitchingBaseLine(name: String, order: String, role: String) -> GameCenterPitchingLine {
        GameCenterPitchingLine(
            pitchingOrder: order,
            name: name,
            role: role,
            result: nil,
            innings: nil,
            pitches: nil,
            hitsAllowed: nil,
            walksAllowed: nil,
            hitBatters: nil,
            strikeouts: nil,
            homeRunsAllowed: nil,
            runsAllowed: nil,
            earnedRuns: nil,
            earnedRunAverage: nil
        )
    }

    private func makeLivePlateAppearanceBattingSections(
        from events: [GameEvent],
        lineupSections: [GameCenterBattingSection]?
    ) -> [GameCenterBattingSection]? {
        guard let lineupSections, lineupSections.count >= 2 else {
            #if DEBUG
            print("[GameDetailLive] plate appearance source available=false reason=missingLineup")
            #endif
            return nil
        }
        guard events.isEmpty == false else {
            #if DEBUG
            print("[GameDetailLive] plate appearance source available=false reason=noEvents")
            #endif
            return nil
        }

        let awaySection = lineupSections[0]
        let homeSection = lineupSections[1]
        var awayStats = Dictionary(uniqueKeysWithValues: awaySection.lines.map { ($0.liveBatterMergeKey, PlateAppearanceDerivedStats()) })
        var homeStats = Dictionary(uniqueKeysWithValues: homeSection.lines.map { ($0.liveBatterMergeKey, PlateAppearanceDerivedStats()) })
        var matchedEventCount = 0
        var parsedCount = 0

        for event in events {
            guard let side = LivePlateAppearanceSide(inningText: event.inningText) else {
                continue
            }
            let section = side == .away ? awaySection : homeSection
            guard let player = section.lines.first(where: { event.headline.normalizedLivePlateAppearanceText.contains($0.name.normalizedLiveBatterName) }) else {
                continue
            }

            matchedEventCount += 1
            let eventStats = event.headline.livePlateAppearanceDerivedStats
            if eventStats.hasEvent {
                parsedCount += 1
            }

            let key = player.liveBatterMergeKey
            if side == .away {
                awayStats[key] = (awayStats[key] ?? PlateAppearanceDerivedStats()) + eventStats
            } else {
                homeStats[key] = (homeStats[key] ?? PlateAppearanceDerivedStats()) + eventStats
            }
        }

        guard matchedEventCount > 0 else {
            #if DEBUG
            print("[GameDetailLive] plate appearance source available=false reason=noMatchedLineupEvents eventCount=\(events.count)")
            #endif
            return nil
        }

        #if DEBUG
        print("[GameDetailLive] plate appearance source available=true eventCount=\(events.count) matchedEventCount=\(matchedEventCount)")
        print("[GameDetailLive] plate appearance parsed count=\(parsedCount)")
        #endif

        let awayLines = makeLivePlateAppearanceLines(from: awaySection, statsByKey: awayStats)
        let homeLines = makeLivePlateAppearanceLines(from: homeSection, statsByKey: homeStats)
        return [
            GameCenterBattingSection(lines: awayLines, totals: nil),
            GameCenterBattingSection(lines: homeLines, totals: nil)
        ]
    }

    private func makeLivePlateAppearanceLines(
        from lineupSection: GameCenterBattingSection,
        statsByKey: [String: PlateAppearanceDerivedStats]
    ) -> [GameCenterBattingLine] {
        lineupSection.lines.map { line in
            let stats = statsByKey[line.liveBatterMergeKey] ?? PlateAppearanceDerivedStats()
            #if DEBUG
            print("[GameDetailLive] hitter aggregate player=\(line.name) HR=\(stats.homeRuns) SO=\(stats.strikeouts) BB=\(stats.walks)")
            #endif
            return GameCenterBattingLine(
                battingOrder: line.battingOrder,
                position: line.position,
                name: line.name,
                atBats: nil,
                runs: nil,
                hits: nil,
                runsBattedIn: nil,
                homeRuns: String(stats.homeRuns),
                walks: String(stats.walks),
                strikeouts: String(stats.strikeouts),
                stolenBases: nil,
                average: nil
            )
        }
    }

    func reconcileScheduledStartTimes(in games: [GameDetail]) async -> [GameDetail] {
        guard games.isEmpty == false else { return games }

        let gamesByDate = Dictionary(grouping: games, by: officialDateText(for:))
        var updatedGroups: [String: [GameDetail]] = [:]
        for (dateText, dateGames) in gamesByDate {
            do {
                let entries = try await fetchEntries(for: dateText)
                updatedGroups[dateText] = dateGames.map { game in
                    reconcileScheduledStart(for: game, entries: entries) ?? game
                }
            } catch {
                updatedGroups[dateText] = dateGames
            }
        }

        return games.map { game in
            let dateText = officialDateText(for: game)
            return updatedGroups[dateText]?.first(where: { $0.id == game.id }) ?? game
        }
    }

    private func fetchContext(for game: GameDetail) async throws -> OfficialGameLookupContext? {
        let requestContext = OfficialKBORequestDebugContext(game: game)
        let payload = try await fetchGameList(
            for: officialDateText(for: game),
            requestContext: requestContext
        )

        guard let entry = resolveEntry(in: payload.game, game: game) else {
            return nil
        }

        return OfficialGameLookupContext(
            game: game,
            entry: entry,
            requestContext: requestContext.with(officialGameID: entry.gameID)
        )
    }

    private func fetchEntries(for dateText: String) async throws -> [OfficialGameEntry] {
        try await fetchGameList(for: dateText, requestContext: nil).game
    }

    private func fetchGameList(
        for dateText: String,
        requestContext: OfficialKBORequestDebugContext?
    ) async throws -> OfficialGameListResponse {
        try await post(
            endpoint: "ws/Main.asmx/GetKboGameList",
            form: [
                "leId": "1",
                "srId": "0,1,3,4,5,6,7,8,9",
                "date": dateText
            ],
            as: OfficialGameListResponse.self,
            requestContext: requestContext
        )
    }

    private func fetchScoreboardIfNeeded(
        for context: OfficialGameLookupContext
    ) async throws -> OfficialScoreboardPayload? {
        guard context.entry.status != .upcoming else { return nil }

        #if DEBUG
        print("[GameDetailLive] scoreboard fetch start gameID=\(context.entry.gameID) status=\(context.entry.status.rawValue)")
        #endif

        do {
            let payload = try await post(
                endpoint: "ws/Schedule.asmx/GetScoreBoardScroll",
                form: [
                    "leId": String(context.entry.leagueID),
                    "srId": String(context.entry.seriesID),
                    "seasonId": String(context.entry.seasonID),
                    "gameId": context.entry.gameID
                ],
                as: OfficialScoreboardResponse.self,
                requestContext: context.requestContext
            )
            let lineScore = makeLineScore(from: payload)
            #if DEBUG
            print("[GameDetailLive] scoreboard fetch success gameID=\(context.entry.gameID) lineScorePresent=\(lineScore != nil)")
            #endif
            return OfficialScoreboardPayload(
                stadium: payload.stadiumName?.nilIfBlank,
                startTime: payload.startTime?.nilIfBlank,
                endTime: payload.endTime?.nilIfBlank,
                durationText: payload.durationText?.nilIfBlank,
                crowdText: payload.crowdText?.nilIfBlank,
                lineScore: lineScore
            )
        } catch {
            #if DEBUG
            print("[GameDetailLive] scoreboard fetch failed gameID=\(context.entry.gameID) error=\(error)")
            #endif
            do {
                return try await fetchScoreboardPageLineScoreIfNeeded(for: context)
            } catch {
                #if DEBUG
                print("[GameDetailLive] scoreboard html fallback failed gameID=\(context.entry.gameID) error=\(error)")
                #endif
                return nil
            }
        }
    }

    private func fetchScoreboardPageLineScoreIfNeeded(
        for context: OfficialGameLookupContext
    ) async throws -> OfficialScoreboardPayload? {
        guard context.entry.status.isLiveLike else { return nil }
        #if DEBUG
        print("[GameDetailLive] scoreboard html fallback start gameID=\(context.entry.gameID)")
        #endif
        let html = try await getHTMLText(
            endpoint: "Schedule/ScoreBoard.aspx",
            queryItems: [
                URLQueryItem(name: "date", value: context.entry.gameDate)
            ],
            requestContext: context.requestContext.with(referer: "https://www.koreabaseball.com/Schedule/ScoreBoard.aspx")
        )
        let containsProviderGameID = context.requestContext.providerGameID.map { html.contains($0) } ?? false
        let lineScore = makeLineScoreFromScoreboardPageHTML(html, context: context)
        #if DEBUG
        print("[GameDetailLive] scoreboard html fallback parsed gameID=\(context.entry.gameID) containsProviderGameID=\(containsProviderGameID) parsedLineScorePresent=\(lineScore != nil) parsedInningCount=\(lineScore?.inningLabels.count ?? 0)")
        #endif
        guard let lineScore else {
            #if DEBUG
            print("[GameDetailLive] scoreboard page fallback empty gameID=\(context.entry.gameID)")
            #endif
            return nil
        }
        #if DEBUG
        print("[GameDetailLive] scoreboard page fallback success gameID=\(context.entry.gameID) lineScorePresent=true")
        #endif
        return OfficialScoreboardPayload(
            stadium: context.entry.stadiumName,
            startTime: context.entry.startTime,
            endTime: nil,
            durationText: nil,
            crowdText: nil,
            lineScore: lineScore
        )
    }

    private func fetchBoxScoreIfNeeded(
        for context: OfficialGameLookupContext
    ) async throws -> GameCenterBoxScorePayload? {
        guard context.entry.status == .live || context.entry.status == .rainDelay || context.entry.status == .final else {
            return nil
        }

        do {
            #if DEBUG
            if context.entry.status.isLiveLike {
                print("[GameDetailLive] full record source attempted source=fullBoxscore gameID=\(context.entry.gameID)")
            }
            #endif
            let payload = try await postPayload(
                endpoint: "ws/Schedule.asmx/GetBoxScoreScroll",
                form: [
                    "leId": String(context.entry.leagueID),
                    "srId": String(context.entry.seriesID),
                    "seasonId": String(context.entry.seasonID),
                    "gameId": context.entry.gameID
                ],
                requestContext: context.requestContext.with(
                    referer: "https://www.koreabaseball.com/Schedule/GameCenter/ReviewNew.aspx?leId=\(context.entry.leagueID)&srId=\(context.entry.seriesID)&seasonId=\(context.entry.seasonID)&gameId=\(context.entry.gameID)"
                )
            )
            let data = payload.data
            debugLogOfficialBoxScoreStructure(data)
            let response: OfficialBoxScoreResponse
            do {
                response = try JSONDecoder().decode(OfficialBoxScoreResponse.self, from: data)
            } catch {
                throw OfficialKBOGameCenterError.decodingFailed(
                    payload.diagnostic.with(parseFailureReason: String(describing: error))
                )
            }

            let summaryItems: [GameCenterSummaryItem] = decodeGridTable(from: response.summaryTable)?.rows.compactMap { row in
                guard row.cells.count >= 2,
                      let title = row.cells[0].text.nilIfBlank else {
                    return nil
                }
                let values = row.cells.dropFirst().compactMap { $0.text.nilIfBlank }
                guard values.isEmpty == false else { return nil }
                return GameCenterSummaryItem(
                    title: title,
                    value: values.joined(separator: " · "),
                    values: values
                )
            } ?? []

            let battingSections = response.battingTables.compactMap(makeBattingSection(from:))
            let pitchingSections = response.pitchingTables.compactMap(makePitchingSection(from:))

            guard battingSections.count >= 2 || pitchingSections.count >= 2 else {
                #if DEBUG
                print("[BaseRunners] source=official skipped=missingBattingSections source=boxscore count=\(battingSections.count)")
                #endif
                return nil
            }

            let fullPayload = GameCenterBoxScorePayload(
                source: .fullBoxscore,
                summaryItems: summaryItems,
                battingSections: battingSections,
                pitchingSections: pitchingSections
            )
            #if DEBUG
            if context.entry.status.isLiveLike {
                print("[GameDetailLive] full record source parsed source=fullBoxscore gameID=\(context.entry.gameID) fullRecordAvailable=true parsedFullBatterCount=\(fullPayload.batterCount) parsedFullPitcherCount=\(fullPayload.pitcherCount) parsedKeyBatterCount=0 parsedKeyPitcherCount=0 finalBatterCount=\(fullPayload.batterCount) finalPitcherCount=\(fullPayload.pitcherCount) majorRecordCount=\(fullPayload.summaryItems.count)")
            }
            #endif
            return fullPayload
        } catch {
            if context.entry.status == .final {
                throw error
            }
            #if DEBUG
            print("[GameDetailLive] full record source failed source=fullBoxscore gameID=\(context.entry.gameID) fullRecordAvailable=false reason=\(error)")
            #endif
            if let htmlPayload = try await fetchScoreboardHTMLBoxScoreIfNeeded(for: context) {
                return htmlPayload
            }
            return try await fetchLiveKeyPlayerRecordsIfNeeded(for: context)
        }
    }

    private func fetchScoreboardHTMLBoxScoreIfNeeded(
        for context: OfficialGameLookupContext
    ) async throws -> GameCenterBoxScorePayload? {
        guard context.entry.status.isLiveLike else { return nil }
        #if DEBUG
        print("[GameDetailLive] full boxscore source=scoreboardHTMLBoxscore available=attempt gameID=\(context.entry.gameID)")
        #endif

        let candidates: [(endpoint: String, queryItems: [URLQueryItem], referer: String)] = [
            (
                "Schedule/ScoreBoard.aspx",
                [URLQueryItem(name: "date", value: context.entry.gameDate)],
                "https://www.koreabaseball.com/Schedule/ScoreBoard.aspx"
            ),
            (
                "Schedule/GameCenter/ReviewNew.aspx",
                [
                    URLQueryItem(name: "leId", value: String(context.entry.leagueID)),
                    URLQueryItem(name: "srId", value: String(context.entry.seriesID)),
                    URLQueryItem(name: "seasonId", value: String(context.entry.seasonID)),
                    URLQueryItem(name: "gameId", value: context.entry.gameID)
                ],
                "https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx?gameId=\(context.entry.gameID)&section=REVIEW"
            )
        ]

        for candidate in candidates {
            let html = try await getHTMLText(
                endpoint: candidate.endpoint,
                queryItems: candidate.queryItems,
                requestContext: context.requestContext.with(referer: candidate.referer)
            )
            guard let payload = makeBoxScoreFromScoreboardPageHTML(html, context: context) else {
                #if DEBUG
                print("[GameDetailLive] full boxscore source=scoreboardHTMLBoxscore available=false endpoint=\(candidate.endpoint) reason=noFullRecordTables")
                #endif
                continue
            }
            #if DEBUG
            print("[GameDetailLive] full boxscore source=scoreboardHTMLBoxscore available=true endpoint=\(candidate.endpoint) battersAway=\(payload.battingSections[safe: 0]?.lines.count ?? 0) battersHome=\(payload.battingSections[safe: 1]?.lines.count ?? 0) pitchersAway=\(payload.pitchingSections[safe: 0]?.lines.count ?? 0) pitchersHome=\(payload.pitchingSections[safe: 1]?.lines.count ?? 0)")
            #endif
            return payload
        }

        return nil
    }

    private func fetchLiveKeyPlayerRecordsIfNeeded(
        for context: OfficialGameLookupContext
    ) async throws -> GameCenterBoxScorePayload? {
        guard context.entry.status.isLiveLike else { return nil }
        #if DEBUG
        print("[GameDetailLive] live keyplayer fallback start gameID=\(context.entry.gameID)")
        #endif

        async let hitterResponse = fetchKeyPlayerRecords(
            endpoint: "ws/Schedule.asmx/GetKeyPlayerHitter",
            section: "KEY_HIT",
            context: context
        )
        async let pitcherResponse = fetchKeyPlayerRecords(
            endpoint: "ws/Schedule.asmx/GetKeyPlayerPitcher",
            section: "KEY_PIT",
            context: context
        )

        let hitterRecords: [OfficialKeyPlayerRecord]
        do {
            hitterRecords = try await hitterResponse
        } catch {
            #if DEBUG
            print("[GameDetailLive] live keyplayer request failed source=keyplayerPartialLimited section=hitter gameID=\(context.entry.gameID) error=\(error)")
            #endif
            hitterRecords = []
        }
        let pitcherRecords: [OfficialKeyPlayerRecord]
        do {
            pitcherRecords = try await pitcherResponse
        } catch {
            #if DEBUG
            print("[GameDetailLive] live keyplayer request failed source=keyplayerPartialLimited section=pitcher gameID=\(context.entry.gameID) error=\(error)")
            #endif
            pitcherRecords = []
        }
        let payload = makeLiveKeyPlayerPayload(
            hitterRecords: hitterRecords,
            pitcherRecords: pitcherRecords,
            context: context
        )

        #if DEBUG
        print("[GameDetailLive] live keyplayer parsed source=keyplayerPartialLimited gameID=\(context.entry.gameID) fullRecordAvailable=false parsedFullBatterCount=0 parsedFullPitcherCount=0 parsedKeyBatterCount=\(payload.batterCount) parsedKeyPitcherCount=\(payload.pitcherCount) finalBatterCount=\(payload.batterCount) finalPitcherCount=\(payload.pitcherCount) parsedMajorRecordCount=\(payload.summaryItems.count) liveRecordPresent=\(payload.review?.hasDisplayableRecords == true)")
        #endif
        return payload.review?.hasDisplayableRecords == true ? payload : nil
    }

    private func fetchKeyPlayerRecords(
        endpoint: String,
        section: String,
        context: OfficialGameLookupContext
    ) async throws -> [OfficialKeyPlayerRecord] {
        let response = try await post(
            endpoint: endpoint,
            form: [
                "leId": String(context.entry.leagueID),
                "srId": String(context.entry.seriesID),
                "gameId": context.entry.gameID,
                "groupSc": "GAME_WPA_RT",
                "sort": "DESC"
            ],
            as: OfficialKeyPlayerResponse.self,
            requestContext: context.requestContext.with(
                referer: "https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx?gameId=\(context.entry.gameID)&section=\(section)"
            )
        )
        return response.records
    }

    private func makeLiveKeyPlayerPayload(
        hitterRecords: [OfficialKeyPlayerRecord],
        pitcherRecords: [OfficialKeyPlayerRecord],
        context: OfficialGameLookupContext
    ) -> GameCenterBoxScorePayload {
        let awayCode = context.entry.awayTeamCode.uppercased()
        let homeCode = context.entry.homeTeamCode.uppercased()
        let awayBatters = hitterRecords
            .filter { $0.teamID.uppercased() == awayCode }
            .compactMap(makeLiveKeyPlayerBattingLine(from:))
        let homeBatters = hitterRecords
            .filter { $0.teamID.uppercased() == homeCode }
            .compactMap(makeLiveKeyPlayerBattingLine(from:))
        let awayPitchers = pitcherRecords
            .filter { $0.teamID.uppercased() == awayCode }
            .compactMap(makeLiveKeyPlayerPitchingLine(from:))
        let homePitchers = pitcherRecords
            .filter { $0.teamID.uppercased() == homeCode }
            .compactMap(makeLiveKeyPlayerPitchingLine(from:))
        let summaryItems = makeLiveKeyPlayerSummaryItems(
            hitterRecords: hitterRecords,
            pitcherRecords: pitcherRecords
        )

        return GameCenterBoxScorePayload(
            source: .keyplayerPartialLimited,
            summaryItems: summaryItems,
            battingSections: [
                GameCenterBattingSection(lines: awayBatters, totals: nil),
                GameCenterBattingSection(lines: homeBatters, totals: nil)
            ],
            pitchingSections: [
                GameCenterPitchingSection(lines: awayPitchers),
                GameCenterPitchingSection(lines: homePitchers)
            ]
        )
    }

    private func makeLiveKeyPlayerSummaryItems(
        hitterRecords: [OfficialKeyPlayerRecord],
        pitcherRecords: [OfficialKeyPlayerRecord]
    ) -> [GameCenterSummaryItem] {
        let hitterItems = hitterRecords.map {
            GameCenterSummaryItem(
                title: "타자 WPA \($0.rank)위",
                value: "\($0.playerName) \($0.recordInfo.gameCenterPlainRecordText)"
            )
        }
        let pitcherItems = pitcherRecords.map {
            GameCenterSummaryItem(
                title: "투수 WPA \($0.rank)위",
                value: "\($0.playerName) \($0.recordInfo.gameCenterPlainRecordText)"
            )
        }
        return hitterItems + pitcherItems
    }

    private func makeLiveKeyPlayerBattingLine(
        from record: OfficialKeyPlayerRecord
    ) -> GameCenterBattingLine? {
        guard record.playerName.nilIfBlank != nil else { return nil }
        let stats = record.recordInfo.gameCenterParenthesizedRecordText
        let line = GameCenterBattingLine(
            battingOrder: record.rank,
            position: "",
            name: record.playerName,
            atBats: record.keyPlayerIntegerStat(aliases: ["AB", "PA_AB", "TASU", "AT_BATS", "ATBAT", "타수"]) ?? stats.gameCenterFirstCapture(#"(\d+)\s*(?:타수|AB)"#),
            runs: record.keyPlayerIntegerStat(aliases: ["R", "RUN", "RUNS", "득점"]) ?? stats.gameCenterFirstCapture(#"(\d+)\s*(?:득점|R)"#),
            hits: record.keyPlayerIntegerStat(aliases: ["H", "HIT", "HITS", "안타"]) ?? stats.gameCenterFirstCapture(#"(\d+)\s*(?:안타|H)"#),
            runsBattedIn: record.keyPlayerIntegerStat(aliases: ["RBI", "타점"]) ?? stats.gameCenterFirstCapture(#"(\d+)\s*(?:타점|RBI)"#),
            homeRuns: nil,
            walks: nil,
            strikeouts: nil,
            stolenBases: record.keyPlayerIntegerStat(aliases: ["SB", "STEAL", "STOLEN_BASE", "STOLEN_BASES", "도루"]) ?? stats.gameCenterFirstCapture(#"(\d+)\s*(?:도루|SB)"#),
            average: nil
        )
        #if DEBUG
        let rawKeys = record.rawValues.keys.sorted().joined(separator: ",")
        print("[GameDetailLive] keyplayer hitter raw player=\(record.playerName) team=\(record.teamID) keys=\(rawKeys) recordInfo=\(record.recordInfo.gameCenterPlainRecordText) parsedHR=\(line.homeRuns ?? "<nil>") parsedSO=\(line.strikeouts ?? "<nil>") parsedBB=\(line.walks ?? "<nil>")")
        #endif
        return line
    }

    private func makeLiveKeyPlayerPitchingLine(
        from record: OfficialKeyPlayerRecord
    ) -> GameCenterPitchingLine? {
        guard record.playerName.nilIfBlank != nil else { return nil }
        let stats = record.recordInfo.gameCenterParenthesizedRecordText
        return GameCenterPitchingLine(
            pitchingOrder: record.rank,
            name: record.playerName,
            role: nil,
            result: nil,
            innings: stats.gameCenterFirstCapture(#"(\d+(?:\s+\d/\d|/\d)?)이닝"#),
            pitches: nil,
            hitsAllowed: stats.gameCenterFirstCapture(#"(\d+)피안타"#),
            walksAllowed: stats.gameCenterFirstCapture(#"(\d+)볼넷"#),
            hitBatters: stats.gameCenterFirstCapture(#"(\d+)사구"#),
            strikeouts: stats.gameCenterFirstCapture(#"(\d+)삼진"#),
            homeRunsAllowed: stats.gameCenterFirstCapture(#"(\d+)피홈런"#),
            runsAllowed: stats.gameCenterFirstCapture(#"(\d+)실점"#),
            earnedRuns: stats.gameCenterFirstCapture(#"(\d+)자책"#),
            earnedRunAverage: nil
        )
    }

    private func fetchLineupBattingSectionsIfNeeded(
        for context: OfficialGameLookupContext
    ) async throws -> [GameCenterBattingSection]? {
        guard context.entry.status == .live || context.entry.status == .rainDelay || context.entry.status == .final else {
            return nil
        }

        do {
            let data = try await postData(
                endpoint: "ws/Schedule.asmx/GetLineUpAnalysis",
                form: [
                    "leId": String(context.entry.leagueID),
                    "srId": String(context.entry.seriesID),
                    "seasonId": String(context.entry.seasonID),
                    "gameId": context.entry.gameID
                ],
                requestContext: context.requestContext
            )
            debugLogOfficialLineupStructure(data)
            let sections = makeLineupBattingSections(from: data)
            guard sections.count == 2 else {
                #if DEBUG
                print("[BaseRunners] source=official skipped=missingBattingSections source=lineup count=\(sections.count)")
                #endif
                return nil
            }
            return sections
        } catch {
            #if DEBUG
            print("[BaseRunners] source=official skipped=missingBattingSections source=lineup error=\(error)")
            #endif
            return nil
        }
    }

    private func fetchPreviewIfNeeded(
        for context: OfficialGameLookupContext
    ) async throws -> GameCenterPreview? {
        guard context.entry.status == .upcoming else { return nil }

        let payload = try await post(
            endpoint: "ws/Schedule.asmx/GetTeamRecord",
            form: [
                "leId": String(context.entry.leagueID),
                "srId": String(context.entry.seriesID),
                "seasonId": String(context.entry.seasonID),
                "gameId": context.entry.gameID,
                "groupSc": "SEASON"
            ],
            as: OfficialPreviewRecordResponse.self,
            requestContext: context.requestContext
        )

        let awayMatchup: GameCenterMatchupSnapshot?
        let homeMatchup: GameCenterMatchupSnapshot?
        if payload.rows.count >= 2 {
            awayMatchup = makeMatchupSnapshot(from: payload.rows[0])
            homeMatchup = makeMatchupSnapshot(from: payload.rows[1])
        } else {
            awayMatchup = nil
            homeMatchup = nil
        }

        guard context.entry.probableStarters.away != nil ||
                context.entry.probableStarters.home != nil ||
                awayMatchup != nil ||
                homeMatchup != nil else {
            return nil
        }

        return GameCenterPreview(
            probableStarters: context.entry.probableStarters,
            awayMatchup: awayMatchup,
            homeMatchup: homeMatchup
        )
    }

    private func resolveEntry(
        in entries: [OfficialGameEntry],
        game: GameDetail
    ) -> OfficialGameEntry? {
        if let officialGameID = game.officialGameCenterID,
           let exactMatch = entries.first(where: { $0.gameID == officialGameID }) {
            return exactMatch
        }

        let awayCode = Self.officialTeamCode(for: game.awayTeam.id)
        let homeCode = Self.officialTeamCode(for: game.homeTeam.id)
        let scheduledTime = game.scheduledStart.formatted(.dateTime.hour().minute())
        let normalizedVenue = Self.normalizeVenue(game.venue)

        let matches = entries.filter { entry in
            entry.awayTeamCode == awayCode && entry.homeTeamCode == homeCode
        }
        if matches.count == 1 {
            return matches.first
        }

        if let venueMatch = matches.first(where: { Self.normalizeVenue($0.stadiumName ?? "") == normalizedVenue }) {
            return venueMatch
        }

        if let timeMatch = matches.first(where: { $0.startTime == scheduledTime }) {
            return timeMatch
        }

        return matches.first
    }

    private func reconcileScheduledStart(
        for game: GameDetail,
        entries: [OfficialGameEntry]
    ) -> GameDetail? {
        guard let entry = resolveEntry(in: entries, game: game),
              let updatedStart = scheduledStart(for: entry, fallback: game.scheduledStart),
              updatedStart != game.scheduledStart else {
            return nil
        }

        return GameDetail(
            id: game.id,
            scheduledStart: updatedStart,
            venue: game.venue,
            awayTeam: game.awayTeam,
            homeTeam: game.homeTeam,
            awayScore: game.awayScore,
            homeScore: game.homeScore,
            status: game.status,
            seasonClassification: game.seasonClassification,
            inningText: game.inningText,
            bases: game.bases,
            baseRunners: game.baseRunners,
            balls: game.balls,
            strikes: game.strikes,
            outs: game.outs,
            highlightText: game.highlightText,
            events: game.events,
            note: game.note,
            providerGameID: game.providerGameID,
            awayStartingPitcherName: game.awayStartingPitcherName,
            homeStartingPitcherName: game.homeStartingPitcherName,
            currentPitcherName: game.currentPitcherName,
            currentBatterName: game.currentBatterName
        )
    }

    private func officialDateText(for game: GameDetail) -> String {
        if let officialGameID = game.officialGameCenterID,
           officialGameID.count >= 8 {
            return String(officialGameID.prefix(8))
        }
        let components = calendar.dateComponents([.year, .month, .day], from: game.scheduledStart)
        return String(
            format: "%04d%02d%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    private func scheduledStart(for entry: OfficialGameEntry, fallback: Date) -> Date? {
        let trimmedStartTime = entry.startTime.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedStartTime.isEmpty == false else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyyMMdd HH:mm"

        if let resolved = formatter.date(from: "\(entry.gameDate) \(trimmedStartTime)") {
            return resolved
        }

        let fallbackComponents = calendar.dateComponents([.year, .month, .day], from: fallback)
        guard let year = fallbackComponents.year,
              let month = fallbackComponents.month,
              let day = fallbackComponents.day else {
            return nil
        }

        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: String(format: "%04d-%02d-%02d %@", year, month, day, trimmedStartTime))
    }

    private func makeBattingSection(from tableGroup: OfficialBattingTableGroup) -> GameCenterBattingSection? {
        guard let orderTable = decodeGridTable(from: tableGroup.orderTable) else {
            return nil
        }

        return makeBattingSection(
            orderTable: orderTable,
            detailTable: tableGroup.detailTable.flatMap(decodeGridTable(from:)),
            summaryTable: tableGroup.summaryTable.flatMap(decodeGridTable(from:))
        )
    }

    private func battingStat(
        _ table: OfficialGridTable?,
        row: OfficialGridRow?,
        labels: [String],
        oldFallbackIndex: Int?,
        wideFallbackIndex: Int?
    ) -> String? {
        guard let row else { return nil }
        if let index = columnIndex(in: table, labels: labels),
           let value = row.cells[safe: index]?.text.nilIfBlank {
            return value.isIntegerStatValue ? value : nil
        }
        if let oldFallbackIndex {
            let value = row.cells[safe: oldFallbackIndex]?.text.nilIfBlank
            return value?.isIntegerStatValue == true ? value : nil
        }
        _ = wideFallbackIndex
        return nil
    }

    private func makePitchingSection(from tableGroup: OfficialPitchingTableGroup) -> GameCenterPitchingSection? {
        guard let table = decodeGridTable(from: tableGroup.table) else {
            return nil
        }

        return makePitchingSection(from: table)
    }

    private func columnIndex(in table: OfficialGridTable?, labels: [String]) -> Int? {
        guard let headerCells = table?.headers.first?.cells else { return nil }
        let normalizedLabels = labels.map(normalizeStatLabel)
        return headerCells.firstIndex { cell in
            normalizedLabels.contains(normalizeStatLabel(cell.text))
        }
    }

    private func normalizeStatLabel(_ value: String) -> String {
        let scalars = value.normalizedGridText.unicodeScalars.filter { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar) == false &&
            CharacterSet.punctuationCharacters.contains(scalar) == false &&
            CharacterSet.symbols.contains(scalar) == false
        }
        return String(String.UnicodeScalarView(scalars)).uppercased()
    }

    func decodeLineupFallbackGridTable(from rawValue: String) -> OfficialGridTable? {
        decodeGridTable(from: rawValue)
    }

    private func gridRowCount(in rawTable: String?) -> Int {
        guard let rawTable, let table = decodeGridTable(from: rawTable) else {
            return 0
        }
        return table.rows.count
    }

    private func logGridSample(prefix: String, rawTable: String?) {
        #if DEBUG
        guard let rawTable, let table = decodeGridTable(from: rawTable) else {
            print("\(prefix) sample=<none>")
            return
        }
        let samples = table.rows.prefix(3).map { row in
            row.cells.prefix(3).map(\.text).joined(separator: "/")
        }
        print("\(prefix) sample=\(samples.joined(separator: " | "))")
        #endif
    }

    private func logGridDiagnostics(prefix: String, rawTable: String?) {
        #if DEBUG
        guard let rawTable, let table = decodeGridTable(from: rawTable) else {
            print("\(prefix) interpretedAs=unavailable labels=<none> sample=<none>")
            return
        }

        let labels = table.headers.first?.cells.map { normalizeStatLabel($0.text) }.joined(separator: ",") ?? "<none>"
        let rowSample = table.rows.first?.cells.map(\.text).joined(separator: ",") ?? "<none>"
        let footerSample = table.tfoot.first?.cells.map(\.text).joined(separator: ",") ?? "<none>"
        print("\(prefix) interpretedAs=\(table.battingTableInterpretation.rawValue) labels=\(labels) row0=\(rowSample) footer0=\(footerSample)")
        #endif
    }

    private func post<Response: Decodable>(
        endpoint: String,
        form: [String: String],
        as type: Response.Type,
        requestContext: OfficialKBORequestDebugContext? = nil
    ) async throws -> Response {
        let payload = try await postPayload(endpoint: endpoint, form: form, requestContext: requestContext)
        do {
            return try JSONDecoder().decode(Response.self, from: payload.data)
        } catch {
            throw OfficialKBOGameCenterError.decodingFailed(
                payload.diagnostic.with(parseFailureReason: String(describing: error))
            )
        }
    }

    private func getText(
        endpoint: String,
        queryItems: [URLQueryItem],
        requestContext: OfficialKBORequestDebugContext?
    ) async throws -> String {
        let payload = try await requestPayload(
            endpoint: endpoint,
            method: "GET",
            form: nil,
            queryItems: queryItems,
            requestContext: requestContext
        )
        return String(data: payload.data, encoding: .utf8) ?? ""
    }

    private func getHTMLText(
        endpoint: String,
        queryItems: [URLQueryItem],
        requestContext: OfficialKBORequestDebugContext?
    ) async throws -> String {
        let payload = try await requestPayload(
            endpoint: endpoint,
            method: "GET",
            form: nil,
            queryItems: queryItems,
            requestContext: requestContext,
            allowsHTMLBody: true
        )
        return String(data: payload.data, encoding: .utf8) ?? ""
    }

    private func postData(
        endpoint: String,
        form: [String: String],
        requestContext: OfficialKBORequestDebugContext? = nil
    ) async throws -> Data {
        try await postPayload(endpoint: endpoint, form: form, requestContext: requestContext).data
    }

    private func postPayload(
        endpoint: String,
        form: [String: String],
        requestContext: OfficialKBORequestDebugContext?
    ) async throws -> OfficialKBOHTTPPayload {
        try await requestPayload(
            endpoint: endpoint,
            method: "POST",
            form: form,
            queryItems: [],
            requestContext: requestContext,
            allowsHTMLBody: false
        )
    }

    private func requestPayload(
        endpoint: String,
        method: String,
        form: [String: String]?,
        queryItems: [URLQueryItem],
        requestContext: OfficialKBORequestDebugContext?,
        allowsHTMLBody: Bool = false
    ) async throws -> OfficialKBOHTTPPayload {
        guard let url = URL(string: endpoint, relativeTo: baseURL)?.absoluteURL else {
            throw OfficialKBOGameCenterError.invalidURL
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let requestURL = components?.url else {
            throw OfficialKBOGameCenterError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        request.setValue("ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://www.koreabaseball.com", forHTTPHeaderField: "Origin")
        request.setValue(
            requestContext?.referer ?? "https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx",
            forHTTPHeaderField: "Referer"
        )
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let form {
            request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formEncodedBody(from: form)
        }

        #if DEBUG
        print("[GameDetailLive] official request method=\(method) url=\(requestURL.absoluteString) providerGameID=\(requestContext?.providerGameID ?? "<nil>") officialProviderGameID=\(requestContext?.officialProviderGameID ?? "<nil>") publicGameID=\(requestContext?.publicGameID ?? "<nil>") form=\(Self.formDebugDescription(form)) headers=accept:\(request.value(forHTTPHeaderField: "Accept") ?? "<nil>"),referer:\(request.value(forHTTPHeaderField: "Referer") ?? "<nil>"),xrw:\(request.value(forHTTPHeaderField: "X-Requested-With") ?? "<nil>")")
        #endif

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            let diagnostic = OfficialKBOResponseDiagnostic(
                requestURL: requestURL.absoluteString,
                providerGameID: requestContext?.providerGameID,
                officialProviderGameID: requestContext?.officialProviderGameID,
                publicGameID: requestContext?.publicGameID,
                officialGameID: requestContext?.officialGameID,
                httpStatus: nil,
                contentType: nil,
                bodyPreview: Self.bodyPreview(from: data),
                parseFailureReason: "Response was not HTTPURLResponse"
            )
            debugLogOfficialInvalidResponse(diagnostic)
            throw OfficialKBOGameCenterError.invalidResponse(diagnostic)
        }

        let diagnostic = OfficialKBOResponseDiagnostic(
            requestURL: requestURL.absoluteString,
            providerGameID: requestContext?.providerGameID,
            officialProviderGameID: requestContext?.officialProviderGameID,
            publicGameID: requestContext?.publicGameID,
            officialGameID: requestContext?.officialGameID,
            httpStatus: httpResponse.statusCode,
            contentType: httpResponse.value(forHTTPHeaderField: "Content-Type"),
            bodyPreview: Self.bodyPreview(from: data),
            parseFailureReason: nil
        )

        guard (200...299).contains(httpResponse.statusCode) else {
            let invalid = diagnostic.with(parseFailureReason: "HTTP status \(httpResponse.statusCode)")
            debugLogOfficialInvalidResponse(invalid)
            throw OfficialKBOGameCenterError.invalidResponse(invalid)
        }

        if allowsHTMLBody {
            if Self.isRedirectOrKnownErrorHTML(data: data) {
                let invalid = diagnostic.with(parseFailureReason: "Unexpected redirect or KBO error HTML")
                debugLogOfficialInvalidResponse(invalid)
                throw OfficialKBOGameCenterError.invalidResponse(invalid)
            }
        } else {
            if Self.isHTMLOrRedirectBody(data: data, contentType: diagnostic.contentType) {
                let invalid = diagnostic.with(parseFailureReason: "Unexpected HTML or redirect response")
                debugLogOfficialInvalidResponse(invalid)
                throw OfficialKBOGameCenterError.invalidResponse(invalid)
            }
        }

        if let officialError = Self.officialError(in: data) {
            let reason = "Official KBO error code \(officialError.code): \(officialError.message)"
            let invalid = diagnostic.with(parseFailureReason: reason)
            debugLogOfficialInvalidResponse(invalid)
            throw OfficialKBOGameCenterError.officialError(message: officialError.message, diagnostic: invalid)
        }

        return OfficialKBOHTTPPayload(data: data, diagnostic: diagnostic)
    }

    private func debugLogOfficialInvalidResponse(_ diagnostic: OfficialKBOResponseDiagnostic) {
        #if DEBUG
        print("[GameDetailLive] official request invalidResponse \(diagnostic.debugDescription)")
        #endif
    }

    private static func bodyPreview(from data: Data) -> String {
        let prefix = data.prefix(1000)
        if let text = String(data: prefix, encoding: .utf8) {
            return text
        }
        return "<non-utf8 body \(data.count) bytes>"
    }

    private static func isHTMLOrRedirectBody(data: Data, contentType: String?) -> Bool {
        if contentType?.localizedCaseInsensitiveContains("text/html") == true {
            return true
        }
        return isRedirectOrKnownErrorHTML(data: data)
    }

    private static func isRedirectOrKnownErrorHTML(data: Data) -> Bool {
        guard let text = String(data: data.prefix(1000), encoding: .utf8) else {
            return false
        }
        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered.contains("object moved") ||
            lowered.contains("페이지를 찾을 수 없습니다") ||
            lowered.contains("요청하신 페이지") ||
            lowered.contains("오류가 발생")
    }

    private static func officialError(in data: Data) -> (code: String, message: String)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawCode = object["code"] else {
            return nil
        }
        let code = String(describing: rawCode)
        guard code != "100" else { return nil }
        return (code, (object["msg"] as? String)?.nilIfBlank ?? "<missing message>")
    }

    private static func formDebugDescription(_ form: [String: String]?) -> String {
        guard let form else { return "<none>" }
        return form.keys.sorted().map { "\($0)=\(form[$0] ?? "")" }.joined(separator: "&")
    }

    private func debugLogOfficialBoxScoreStructure(_ data: Data) {
        #if DEBUG
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let object = json as? [String: Any] else {
            print("[BaseRunners] official response keys=<decodeFailed>")
            return
        }

        let keys = object.keys.sorted()
        print("[BaseRunners] official response keys=\(keys.joined(separator: ","))")
        print("[BaseRunners] tableEtc present=\(object["tableEtc"] != nil)")

        let hitters = object["arrHitter"] as? [[String: Any]]
        print("[BaseRunners] arrHitter present=\(hitters != nil) count=\(hitters?.count ?? 0)")
        if let hitters {
            for (index, hitter) in hitters.enumerated().prefix(2) {
                let table1Rows = gridRowCount(in: hitter["table1"] as? String)
                let table2Rows = gridRowCount(in: hitter["table2"] as? String)
                let table3Rows = gridRowCount(in: hitter["table3"] as? String)
                print("[BaseRunners] arrHitter[\(index)] keys=\(hitter.keys.sorted().joined(separator: ",")) table1 present=\(hitter["table1"] != nil) rows=\(table1Rows) table2 present=\(hitter["table2"] != nil) rows=\(table2Rows) table3 present=\(hitter["table3"] != nil) rows=\(table3Rows)")
                logGridSample(prefix: "[BaseRunners] arrHitter[\(index)].table1", rawTable: hitter["table1"] as? String)
                logGridDiagnostics(prefix: "[GameDetailStats] arrHitter[\(index)].table1", rawTable: hitter["table1"] as? String)
                logGridDiagnostics(prefix: "[GameDetailStats] arrHitter[\(index)].table2", rawTable: hitter["table2"] as? String)
                logGridDiagnostics(prefix: "[GameDetailStats] arrHitter[\(index)].table3", rawTable: hitter["table3"] as? String)
            }
        }

        let candidates = battingSectionCandidates(in: json)
        print("[BaseRunners] candidate batting section keys=\(candidates.prefix(6).map(\.path).joined(separator: ",")) count=\(candidates.count)")
        #endif
    }

    private func debugLogOfficialLineupStructure(_ data: Data) {
        #if DEBUG
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            print("[BaseRunners] lineup response keys=<decodeFailed>")
            return
        }

        if let array = json as? [Any] {
            print("[BaseRunners] lineup response topLevel=array count=\(array.count)")
            let homeRows = ((array[safe: 3] as? [Any])?.first as? String).map(gridRowCount(in:)) ?? 0
            let awayRows = ((array[safe: 4] as? [Any])?.first as? String).map(gridRowCount(in:)) ?? 0
            print("[BaseRunners] lineup table homeIndex=3 present=\(((array[safe: 3] as? [Any])?.first as? String) != nil) rows=\(homeRows) awayIndex=4 present=\(((array[safe: 4] as? [Any])?.first as? String) != nil) rows=\(awayRows)")
            logGridSample(prefix: "[BaseRunners] lineup.home.table", rawTable: (array[safe: 3] as? [Any])?.first as? String)
            logGridSample(prefix: "[BaseRunners] lineup.away.table", rawTable: (array[safe: 4] as? [Any])?.first as? String)
        } else if let object = json as? [String: Any] {
            print("[BaseRunners] lineup response keys=\(object.keys.sorted().joined(separator: ","))")
        }

        let candidates = battingSectionCandidates(in: json)
        print("[BaseRunners] candidate batting section keys=\(candidates.prefix(6).map(\.path).joined(separator: ",")) count=\(candidates.count)")
        #endif
    }

    private static func formEncodedBody(from values: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    private static func officialTeamCode(for appTeamID: String) -> String {
        switch appTeamID {
        case "doosan":
            "OB"
        case "hanwha":
            "HH"
        case "kia":
            "HT"
        case "kiwoom":
            "WO"
        case "kt":
            "KT"
        case "lg":
            "LG"
        case "lotte":
            "LT"
        case "nc":
            "NC"
        case "samsung":
            "SS"
        case "ssg":
            "SK"
        default:
            appTeamID.uppercased()
        }
    }

    private static func normalizeVenue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "야구장", with: "")
            .replacingOccurrences(of: "구장", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }
}

struct OfficialGameLookupContext: Sendable {
    let game: GameDetail
    let entry: OfficialGameEntry
    let requestContext: OfficialKBORequestDebugContext
}

private struct OfficialScoreboardPayload: Sendable {
    let stadium: String?
    let startTime: String?
    let endTime: String?
    let durationText: String?
    let crowdText: String?
    let lineScore: GameCenterLineScore?
}

private struct OfficialKBOHTTPPayload: Sendable {
    let data: Data
    let diagnostic: OfficialKBOResponseDiagnostic
}

struct OfficialKBORequestDebugContext: Sendable {
    let providerGameID: String?
    let officialProviderGameID: String?
    let publicGameID: String?
    let officialGameID: String?
    let referer: String?

    init(
        providerGameID: String?,
        officialProviderGameID: String?,
        publicGameID: String?,
        officialGameID: String?,
        referer: String? = nil
    ) {
        self.providerGameID = providerGameID
        self.officialProviderGameID = officialProviderGameID
        self.publicGameID = publicGameID
        self.officialGameID = officialGameID
        self.referer = referer
    }

    init(game: GameDetail) {
        self.init(
            providerGameID: game.providerGameID,
            officialProviderGameID: game.officialProviderGameID,
            publicGameID: game.publicGameID,
            officialGameID: game.officialGameCenterID,
            referer: nil
        )
    }

    func with(officialGameID: String? = nil, referer: String? = nil) -> OfficialKBORequestDebugContext {
        OfficialKBORequestDebugContext(
            providerGameID: providerGameID,
            officialProviderGameID: officialProviderGameID,
            publicGameID: publicGameID,
            officialGameID: officialGameID ?? self.officialGameID,
            referer: referer ?? self.referer
        )
    }
}

struct OfficialKBOResponseDiagnostic: Sendable {
    let requestURL: String
    let providerGameID: String?
    let officialProviderGameID: String?
    let publicGameID: String?
    let officialGameID: String?
    let httpStatus: Int?
    let contentType: String?
    let bodyPreview: String
    let parseFailureReason: String?

    func with(parseFailureReason: String?) -> OfficialKBOResponseDiagnostic {
        OfficialKBOResponseDiagnostic(
            requestURL: requestURL,
            providerGameID: providerGameID,
            officialProviderGameID: officialProviderGameID,
            publicGameID: publicGameID,
            officialGameID: officialGameID,
            httpStatus: httpStatus,
            contentType: contentType,
            bodyPreview: bodyPreview,
            parseFailureReason: parseFailureReason
        )
    }

    var debugDescription: String {
        [
            "url=\(requestURL)",
            "providerGameID=\(providerGameID ?? "<nil>")",
            "officialProviderGameID=\(officialProviderGameID ?? "<nil>")",
            "publicGameID=\(publicGameID ?? "<nil>")",
            "officialGameID=\(officialGameID ?? "<nil>")",
            "status=\(httpStatus.map(String.init) ?? "<nil>")",
            "contentType=\(contentType ?? "<nil>")",
            "parseFailureReason=\(parseFailureReason ?? "<nil>")",
            "bodyPreview=\(bodyPreview)"
        ].joined(separator: " ")
    }
}

enum OfficialKBOGameCenterError: Error, CustomStringConvertible {
    case invalidURL
    case invalidResponse(OfficialKBOResponseDiagnostic)
    case decodingFailed(OfficialKBOResponseDiagnostic)
    case officialError(message: String, diagnostic: OfficialKBOResponseDiagnostic)

    var description: String {
        switch self {
        case .invalidURL:
            return "invalidURL"
        case .invalidResponse(let diagnostic):
            return "invalidResponse(\(diagnostic.debugDescription))"
        case .decodingFailed(let diagnostic):
            return "decodingFailed(\(diagnostic.debugDescription))"
        case .officialError(let message, let diagnostic):
            return "officialError(message=\(message), \(diagnostic.debugDescription))"
        }
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

    var gameCenterPlainRecordText: String {
        replacingOccurrences(of: "</br>", with: " ")
            .replacingOccurrences(of: "<br />", with: " ")
            .replacingOccurrences(of: "<br/>", with: " ")
            .replacingOccurrences(of: "<br>", with: " ")
            .normalizedGridText
    }

    var gameCenterParenthesizedRecordText: String {
        firstGameCenterRegexCapture(pattern: #"\((.*?)\)"#) ?? gameCenterPlainRecordText
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

    func gameCenterFirstCapture(_ pattern: String) -> String? {
        firstGameCenterRegexCapture(pattern: pattern)
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
