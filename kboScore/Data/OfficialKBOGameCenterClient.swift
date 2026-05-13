//
//  OfficialKBOGameCenterClient.swift
//  kboScore
//
//  Created by Codex on 4/8/26.
//

import Foundation

private struct GameCenterBoxScorePayload: Sendable {
    let summaryItems: [GameCenterSummaryItem]
    let battingSections: [GameCenterBattingSection]
    let pitchingSections: [GameCenterPitchingSection]

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
            homePitching: pitchingSections[safe: 1] ?? emptyPitching
        )
    }
}

private enum OfficialBattingTableInterpretation: String {
    case lineup
    case aggregateBattingStats
    case plateAppearanceResults
    case unknown
}

private struct PlateAppearanceDerivedStats: Sendable, Equatable {
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
            review: boxScoreValue?.review?.enrichingBatterPositions(from: lineupBattingSectionsValue),
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
        return boxScoreValue?.review?.enrichingBatterPositions(from: lineupBattingSectionsValue)
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
        let payload = try await fetchGameList(for: officialDateText(for: game))

        guard let entry = resolveEntry(in: payload.game, game: game) else {
            return nil
        }

        return OfficialGameLookupContext(entry: entry)
    }

    private func fetchEntries(for dateText: String) async throws -> [OfficialGameEntry] {
        try await fetchGameList(for: dateText).game
    }

    private func fetchGameList(for dateText: String) async throws -> OfficialGameListResponse {
        try await post(
            endpoint: "ws/Main.asmx/GetKboGameList",
            form: [
                "leId": "1",
                "srId": "0,1,3,4,5,6,7,8,9",
                "date": dateText
            ],
            as: OfficialGameListResponse.self
        )
    }

    private func fetchScoreboardIfNeeded(
        for context: OfficialGameLookupContext
    ) async throws -> OfficialScoreboardPayload? {
        guard context.entry.status != .upcoming else { return nil }

        let payload = try await post(
            endpoint: "ws/Schedule.asmx/GetScoreBoardScroll",
            form: [
                "leId": String(context.entry.leagueID),
                "srId": String(context.entry.seriesID),
                "seasonId": String(context.entry.seasonID),
                "gameId": context.entry.gameID
            ],
            as: OfficialScoreboardResponse.self
        )

        return OfficialScoreboardPayload(
            stadium: payload.stadiumName?.nilIfBlank,
            startTime: payload.startTime?.nilIfBlank,
            endTime: payload.endTime?.nilIfBlank,
            durationText: payload.durationText?.nilIfBlank,
            crowdText: payload.crowdText?.nilIfBlank,
            lineScore: makeLineScore(from: payload)
        )
    }

    private func fetchBoxScoreIfNeeded(
        for context: OfficialGameLookupContext
    ) async throws -> GameCenterBoxScorePayload? {
        guard context.entry.status == .live || context.entry.status == .rainDelay || context.entry.status == .final else {
            return nil
        }

        do {
            let data = try await postData(
                endpoint: "ws/Schedule.asmx/GetBoxScoreScroll",
                form: [
                    "leId": String(context.entry.leagueID),
                    "srId": String(context.entry.seriesID),
                    "seasonId": String(context.entry.seasonID),
                    "gameId": context.entry.gameID
                ]
            )
            debugLogOfficialBoxScoreStructure(data)
            let payload = try JSONDecoder().decode(OfficialBoxScoreResponse.self, from: data)

            let summaryItems: [GameCenterSummaryItem] = decodeGridTable(from: payload.summaryTable)?.rows.compactMap { row in
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

            let battingSections = payload.battingTables.compactMap(makeBattingSection(from:))
            let pitchingSections = payload.pitchingTables.compactMap(makePitchingSection(from:))

            guard battingSections.count >= 2 || pitchingSections.count >= 2 else {
                #if DEBUG
                print("[BaseRunners] source=official skipped=missingBattingSections source=boxscore count=\(battingSections.count)")
                #endif
                return nil
            }

            return GameCenterBoxScorePayload(
                summaryItems: summaryItems,
                battingSections: battingSections,
                pitchingSections: pitchingSections
            )
        } catch {
            if context.entry.status == .final {
                throw error
            }
            return nil
        }
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
                ]
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
            as: OfficialPreviewRecordResponse.self
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

    private func makeLineScore(from payload: OfficialScoreboardResponse) -> GameCenterLineScore? {
        guard let inningTable = decodeGridTable(from: payload.inningTable),
              let totalsTable = decodeGridTable(from: payload.totalsTable),
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

    private func makeTotals(from row: OfficialGridRow) -> GameCenterTeamLineTotals {
        GameCenterTeamLineTotals(
            runs: row.cells[safe: 0]?.text.nilIfBlank,
            hits: row.cells[safe: 1]?.text.nilIfBlank,
            errors: row.cells[safe: 2]?.text.nilIfBlank,
            walks: row.cells[safe: 3]?.text.nilIfBlank
        )
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

    private func makeBattingSection(fromRawTable rawTable: String) -> GameCenterBattingSection? {
        guard let orderTable = decodeGridTable(from: rawTable) else {
            return nil
        }
        return makeBattingSection(orderTable: orderTable, detailTable: nil, summaryTable: nil)
    }

    private func makeBattingSection(
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

    private func plateAppearanceDerivedStats(
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

    private func plateAppearanceTotals(table: OfficialGridTable?) -> PlateAppearanceDerivedStats? {
        guard table?.battingTableInterpretation == .plateAppearanceResults,
              let rows = table?.rows,
              rows.isEmpty == false else {
            return nil
        }

        return rows
            .compactMap { plateAppearanceDerivedStats(table: table, row: $0) }
            .reduce(PlateAppearanceDerivedStats()) { $0 + $1 }
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
            guard let index = columnIndex(in: table, labels: labels),
                  let value = row?.cells[safe: index]?.text.nilIfBlank else {
                return nil
            }
            guard requireInteger == false || value.isIntegerStatValue else {
                return nil
            }
            return value
        }.first
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

    private func makeLineupBattingSections(from data: Data) -> [GameCenterBattingSection] {
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

    private func makePitchingSection(from tableGroup: OfficialPitchingTableGroup) -> GameCenterPitchingSection? {
        guard let table = decodeGridTable(from: tableGroup.table) else {
            return nil
        }

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
        let labels = table.headers.first?.cells.map { normalizeStatLabel($0.text) }.joined(separator: ",") ?? "<none>"
        let rowSample = table.rows.first?.cells.prefix(17).map(\.text).joined(separator: ",") ?? "<none>"
        let hbpColumn = columnIndex(in: table, labels: ["사구", "HBP"]) ?? 12
        print("[GameDetailStats] arrPitcher labels=\(labels) row0=\(rowSample) hbpColumn=\(hbpColumn)")
        #endif
    }

    private func pitchingStat(_ table: OfficialGridTable, row: OfficialGridRow, labels: [String], fallbackIndex: Int?) -> String? {
        if let index = columnIndex(in: table, labels: labels),
           let value = row.cells[safe: index]?.text.nilIfBlank {
            return value
        }
        guard let fallbackIndex else { return nil }
        return row.cells[safe: fallbackIndex]?.text.nilIfBlank
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

    private func makeMatchupSnapshot(from row: OfficialPreviewRecordRow) -> GameCenterMatchupSnapshot? {
        guard row.row.count >= 7 else { return nil }

        let cells = row.row.map { $0.normalizedText }
        guard let teamName = cells[safe: 0]?.nilIfBlank else {
            return nil
        }

        return GameCenterMatchupSnapshot(
            teamName: teamName,
            seasonRecord: cells[safe: 1]?.nilIfBlank,
            recentFive: cells[safe: 2]?.nilIfBlank,
            teamERA: cells[safe: 3]?.nilIfBlank,
            battingAverage: cells[safe: 4]?.nilIfBlank,
            runsScored: cells[safe: 5]?.nilIfBlank,
            runsAllowed: cells[safe: 6]?.nilIfBlank
        )
    }

    private func decodeGridTable(from rawValue: String) -> OfficialGridTable? {
        guard let data = rawValue.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(OfficialGridTableDTO.self, from: data).table
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

    private func battingSectionCandidates(in value: Any, path: String = "$") -> [BattingSectionCandidate] {
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

    private func post<Response: Decodable>(
        endpoint: String,
        form: [String: String],
        as type: Response.Type
    ) async throws -> Response {
        let data = try await postData(endpoint: endpoint, form: form)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func postData(
        endpoint: String,
        form: [String: String]
    ) async throws -> Data {
        guard let url = URL(string: endpoint, relativeTo: baseURL)?.absoluteURL else {
            throw OfficialKBOGameCenterError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.httpBody = Self.formEncodedBody(from: form)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw OfficialKBOGameCenterError.invalidResponse
        }

        return data
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

private struct OfficialGameLookupContext: Sendable {
    let entry: OfficialGameEntry
}

private struct OfficialScoreboardPayload: Sendable {
    let stadium: String?
    let startTime: String?
    let endTime: String?
    let durationText: String?
    let crowdText: String?
    let lineScore: GameCenterLineScore?
}

private struct BattingSectionCandidate {
    let path: String
    let section: GameCenterBattingSection
}

private struct BattingLineGroup {
    let label: String
    let lines: [GameCenterBattingLine]
}

private enum OfficialKBOGameCenterError: Error {
    case invalidURL
    case invalidResponse
}

private extension OfficialGameEntry {
    var status: GameStatus {
        switch gameStateCode {
        case "1":
            return GameStatus.upcoming
        case "2":
            return GameStatus.live
        case "3":
            return GameStatus.final
        case "5":
            return GameStatus.rainDelay
        default:
            if cancelName?.contains("취소") == true {
                return GameStatus.cancelled
            }
            if cancelName?.contains("우천") == true || cancelName?.contains("중단") == true {
                return GameStatus.rainDelay
            }
            return GameStatus.upcoming
        }
    }

    var inningText: String? {
        switch status {
        case .upcoming:
            return nil
        case .final:
            return "종료"
        case .cancelled:
            return "취소"
        case .rainDelay:
            if let inningNumber, let inningHalfText {
                return "\(inningNumber)회\(inningHalfText)"
            }
            return status.title
        case .live:
            guard let inningNumber, let inningHalfText else { return status.title }
            return "\(inningNumber)회\(inningHalfText)"
        }
    }

    var awayScore: Int? {
        Int(awayScoreText ?? "")
    }

    var homeScore: Int? {
        Int(homeScoreText ?? "")
    }

    var balls: Int? {
        ballCount
    }

    var strikes: Int? {
        strikeCount
    }

    var outs: Int? {
        outCount
    }

    var bases: RunnerState? {
        guard firstBaseOccupancy != nil || secondBaseOccupancy != nil || thirdBaseOccupancy != nil else {
            return nil
        }

        return RunnerState(
            first: (firstBaseOccupancy ?? 0) > 0,
            second: (secondBaseOccupancy ?? 0) > 0,
            third: (thirdBaseOccupancy ?? 0) > 0
        )
    }

    func baseRunners(from battingSections: [GameCenterBattingSection]?) -> GameCenterBaseRunners? {
        let occupiedOrders = [firstBaseOccupancy, secondBaseOccupancy, thirdBaseOccupancy]
            .compactMap { $0 }
            .filter { $0 > 0 }
        guard occupiedOrders.isEmpty == false else {
            #if DEBUG
            let reason = firstBaseOccupancy == nil && secondBaseOccupancy == nil && thirdBaseOccupancy == nil
                ? "missingBaseOrderFields"
                : "noOccupiedBases"
            print("[BaseRunners] source=official skipped=\(reason) baseOrderKeys=\(baseOrderSourceKeys.joined(separator: ","))")
            #endif
            return nil
        }

        guard let battingSections, battingSections.count >= 2 else {
            #if DEBUG
            print("[BaseRunners] source=official skipped=missingBattingSections count=\(battingSections?.count ?? 0) baseOrderKeys=\(baseOrderSourceKeys.joined(separator: ","))")
            #endif
            return nil
        }

        let lineGroups = battingLineGroupsForCurrentHalf(from: battingSections)
        guard lineGroups.isEmpty == false else {
            #if DEBUG
            print("[BaseRunners] source=official skipped=missingBattingSections reason=unknownInningHalf inningHalf=\(inningHalfText ?? "<nil>")")
            #endif
            return nil
        }

        let first = runnerName(order: firstBaseOccupancy, in: lineGroups, baseLabel: "1B")
        let second = runnerName(order: secondBaseOccupancy, in: lineGroups, baseLabel: "2B")
        let third = runnerName(order: thirdBaseOccupancy, in: lineGroups, baseLabel: "3B")

        #if DEBUG
        let reason = first == nil && second == nil && third == nil ? "battingSectionsFoundButNoMatchingOrder " : ""
        print("[BaseRunners] source=official \(reason)mapped first=\(first ?? "<nil>") second=\(second ?? "<nil>") third=\(third ?? "<nil>") baseOrderKeys=\(baseOrderSourceKeys.joined(separator: ","))")
        #endif

        guard first != nil || second != nil || third != nil else {
            return nil
        }

        return GameCenterBaseRunners(first: first, second: second, third: third)
    }

    private func battingLineGroupsForCurrentHalf(from battingSections: [GameCenterBattingSection]) -> [BattingLineGroup] {
        let normalizedHalf = inningHalfText?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedHalf?.contains("초") == true || normalizedHalf?.contains("top") == true {
            return [BattingLineGroup(label: "away", lines: battingSections[0].lines)]
        }
        if normalizedHalf?.contains("말") == true || normalizedHalf?.contains("bottom") == true || normalizedHalf?.contains("bot") == true {
            return [BattingLineGroup(label: "home", lines: battingSections[1].lines)]
        }

        return [
            BattingLineGroup(label: "away", lines: battingSections[0].lines),
            BattingLineGroup(label: "home", lines: battingSections[1].lines)
        ]
    }

    private func runnerName(order: Int?, in lineGroups: [BattingLineGroup], baseLabel: String) -> String? {
        guard let order, order > 0 else {
            return nil
        }

        let orderText = String(order)
        let matches = lineGroups.flatMap { group in
            group.lines
                .filter { $0.battingOrderNumber == orderText }
                .compactMap { line -> (String, String)? in
                    guard let name = line.name.nilIfBlank else { return nil }
                    return (group.label, name)
                }
        }

        guard matches.count <= 1 else {
            #if DEBUG
            print("[BaseRunners] source=official skipped=ambiguousBattingOrderMatch base=\(baseLabel) order=\(orderText) matches=\(matches.map { "\($0.0):\($0.1)" }.joined(separator: ","))")
            #endif
            return nil
        }

        return matches.first?.1
    }

    var probableStarters: GameCenterProbableStarters {
        GameCenterProbableStarters(
            away: awayProbablePitcherName?.nilIfBlank,
            home: homeProbablePitcherName?.nilIfBlank
        )
    }
}

private extension OfficialPreviewRecordCell {
    var normalizedText: String {
        text.normalizedGridText
    }
}

private struct OfficialGridTableDTO: Decodable {
    let headers: [OfficialGridRowDTO]
    let rows: [OfficialGridRowDTO]
    let tfoot: [OfficialGridRowDTO]

    var table: OfficialGridTable {
        OfficialGridTable(
            headers: headers.map(\.row),
            rows: rows.map(\.row),
            tfoot: tfoot.map(\.row)
        )
    }
}

private struct OfficialGridRowDTO: Decodable {
    let row: OfficialGridRow
}

private struct OfficialGridRow: Decodable {
    let cells: [OfficialGridCell]

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawCells = try container.decode([OfficialGridCellDTO].self)
        cells = rawCells.map { OfficialGridCell(text: $0.text.normalizedGridText) }
    }
}

private struct OfficialGridCellDTO: Decodable {
    let text: String

    private enum CodingKeys: String, CodingKey {
        case text = "Text"
    }
}

private struct OfficialGridCell: Sendable {
    let text: String
}

private struct OfficialGridTable: Sendable {
    let headers: [OfficialGridRow]
    let rows: [OfficialGridRow]
    let tfoot: [OfficialGridRow]

    var battingTableInterpretation: OfficialBattingTableInterpretation {
        let labels = headers.first?.cells.map { $0.text.normalizedKeyStatLabel } ?? []
        let aggregateLabels: Set<String> = ["타수", "AB", "득점", "R", "안타", "H", "타점", "RBI", "홈런", "HR", "HRA", "볼넷", "BB", "4구", "삼진", "SO", "K"]
            .map(\.normalizedKeyStatLabel)
            .reduce(into: Set<String>()) { $0.insert($1) }
        if labels.contains(where: aggregateLabels.contains) {
            return .aggregateBattingStats
        }

        if rows.contains(where: \.isCurrentKBOBattingAggregateRow) || tfoot.contains(where: \.isCurrentKBOBattingAggregateRow) {
            return .aggregateBattingStats
        }

        if let firstRow = rows.first,
           firstRow.cells.count == 3,
           firstRow.cells[0].text.battingOrderNumber != nil,
           firstRow.cells[2].text.nilIfBlank != nil {
            return .lineup
        }

        let sampleValues = rows.prefix(3).flatMap { $0.cells.map(\.text) }
        if sampleValues.contains(where: { $0.nilIfBlank != nil && $0.isIntegerStatValue == false }) {
            return .plateAppearanceResults
        }

        return .unknown
    }
}

private extension OfficialGridRow {
    var isCurrentKBOBattingAggregateRow: Bool {
        guard cells.count >= 5 else { return false }
        return cells[0].text.isIntegerStatValue &&
            cells[1].text.isIntegerStatValue &&
            cells[2].text.isIntegerStatValue &&
            cells[3].text.isIntegerStatValue &&
            cells[4].text.isDecimalStatValue
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
