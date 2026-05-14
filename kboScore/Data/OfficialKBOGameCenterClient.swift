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

private enum OfficialKBOGameCenterError: Error {
    case invalidURL
    case invalidResponse
}

private extension OfficialPreviewRecordCell {
    var normalizedText: String {
        text.normalizedGridText
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
