//
//  OfficialKBOGameCenterClient.swift
//  kboScore
//
//  Created by Codex on 4/8/26.
//

import Foundation

struct GameCenterDetailPayload: Sendable {
    let summary: GameCenterSummary
    let lineScore: GameCenterLineScore?
    let review: GameCenterReview?
    let preview: GameCenterPreview?
}

struct GameCenterSummary: Sendable {
    let officialGameID: String
    let dateText: String
    let stadium: String?
    let startTime: String?
    let endTime: String?
    let durationText: String?
    let crowdText: String?
    let status: GameStatus
    let inningText: String?
    let awayScore: Int?
    let homeScore: Int?
    let balls: Int?
    let strikes: Int?
    let outs: Int?
    let bases: RunnerState?
    let baseRunners: GameCenterBaseRunners?
    let probableStarters: GameCenterProbableStarters?
    let winningPitcher: String?
    let losingPitcher: String?
    let savePitcher: String?
}

struct GameCenterBaseRunners: Hashable, Sendable {
    let first: String?
    let second: String?
    let third: String?
}

struct GameCenterProbableStarters: Sendable {
    let away: String?
    let home: String?
}

struct GameCenterLineScore: Sendable {
    let inningLabels: [String]
    let awayInnings: [String]
    let homeInnings: [String]
    let awayTotals: GameCenterTeamLineTotals
    let homeTotals: GameCenterTeamLineTotals
}

struct GameCenterTeamLineTotals: Sendable {
    let runs: String?
    let hits: String?
    let errors: String?
    let walks: String?
}

struct GameCenterReview: Sendable {
    let summaryItems: [GameCenterSummaryItem]
    let awayBatting: GameCenterBattingSection
    let homeBatting: GameCenterBattingSection
    let awayPitching: GameCenterPitchingSection
    let homePitching: GameCenterPitchingSection
}

private struct GameCenterBoxScorePayload: Sendable {
    let summaryItems: [GameCenterSummaryItem]
    let battingSections: [GameCenterBattingSection]
    let pitchingSections: [GameCenterPitchingSection]

    var review: GameCenterReview? {
        guard battingSections.count == 2, pitchingSections.count == 2 else {
            return nil
        }

        return GameCenterReview(
            summaryItems: summaryItems,
            awayBatting: battingSections[0],
            homeBatting: battingSections[1],
            awayPitching: pitchingSections[0],
            homePitching: pitchingSections[1]
        )
    }
}

struct GameCenterSummaryItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    let title: String
    let value: String
}

struct GameCenterBattingSection: Sendable {
    let lines: [GameCenterBattingLine]
    let totals: GameCenterBattingTotals?
}

struct GameCenterBattingLine: Identifiable, Hashable, Sendable {
    let id = UUID()
    let battingOrder: String
    let position: String
    let name: String
    let atBats: String?
    let hits: String?
    let runsBattedIn: String?
    let runs: String?
    let average: String?

    var battingOrderNumber: String? {
        battingOrder.battingOrderNumber
    }
}

struct GameCenterBattingTotals: Sendable {
    let atBats: String?
    let hits: String?
    let runsBattedIn: String?
    let runs: String?
    let average: String?
}

struct GameCenterPitchingSection: Sendable {
    let lines: [GameCenterPitchingLine]
}

struct GameCenterPitchingLine: Identifiable, Hashable, Sendable {
    let id = UUID()
    let name: String
    let role: String?
    let result: String?
    let innings: String?
    let pitches: String?
    let hitsAllowed: String?
    let walksAllowed: String?
    let strikeouts: String?
    let runsAllowed: String?
    let earnedRuns: String?
    let earnedRunAverage: String?
}

struct GameCenterPreview: Sendable {
    let probableStarters: GameCenterProbableStarters?
    let awayMatchup: GameCenterMatchupSnapshot?
    let homeMatchup: GameCenterMatchupSnapshot?
}

struct GameCenterMatchupSnapshot: Sendable {
    let teamName: String
    let seasonRecord: String?
    let recentFive: String?
    let teamERA: String?
    let battingAverage: String?
    let runsScored: String?
    let runsAllowed: String?
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
        guard let context = try await fetchContext(for: game) else {
            return nil
        }

        async let scoreboard = fetchScoreboardIfNeeded(for: context)
        async let boxScore = fetchBoxScoreIfNeeded(for: context)
        async let lineupBattingSections = fetchLineupBattingSectionsIfNeeded(for: context)
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
            review: context.entry.status == .final ? boxScoreValue?.review : nil,
            preview: try await preview
        )
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
                      let title = row.cells[0].text.nilIfBlank,
                      let value = row.cells[1].text.nilIfBlank else {
                    return nil
                }
                return GameCenterSummaryItem(title: title, value: value)
            } ?? []

            let battingSections = payload.battingTables.compactMap(makeBattingSection(from:))
            let pitchingSections = payload.pitchingTables.compactMap(makePitchingSection(from:))

            guard battingSections.count == 2 else {
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

        return makeBattingSection(orderTable: orderTable, summaryTable: tableGroup.summaryTable.flatMap(decodeGridTable(from:)))
    }

    private func makeBattingSection(fromRawTable rawTable: String) -> GameCenterBattingSection? {
        guard let orderTable = decodeGridTable(from: rawTable) else {
            return nil
        }
        return makeBattingSection(orderTable: orderTable, summaryTable: nil)
    }

    private func makeBattingSection(orderTable: OfficialGridTable, summaryTable: OfficialGridTable?) -> GameCenterBattingSection? {
        let lines = orderTable.rows.indices.compactMap { index -> GameCenterBattingLine? in
            let orderRow = orderTable.rows[index]
            let summaryRow = summaryTable?.rows[safe: index]
            guard orderRow.cells.count >= 3,
                  orderRow.cells[0].text.battingOrderNumber != nil,
                  orderRow.cells[2].text.nilIfBlank != nil else {
                return nil
            }

            return GameCenterBattingLine(
                battingOrder: orderRow.cells[0].text,
                position: orderRow.cells[1].text,
                name: orderRow.cells[2].text,
                atBats: summaryRow?.cells[safe: 0]?.text.nilIfBlank,
                hits: summaryRow?.cells[safe: 1]?.text.nilIfBlank,
                runsBattedIn: summaryRow?.cells[safe: 2]?.text.nilIfBlank,
                runs: summaryRow?.cells[safe: 3]?.text.nilIfBlank,
                average: summaryRow?.cells[safe: 4]?.text.nilIfBlank
            )
        }

        let totals = summaryTable?.tfoot.first.map { footer in
            GameCenterBattingTotals(
                atBats: footer.cells[safe: 0]?.text.nilIfBlank,
                hits: footer.cells[safe: 1]?.text.nilIfBlank,
                runsBattedIn: footer.cells[safe: 2]?.text.nilIfBlank,
                runs: footer.cells[safe: 3]?.text.nilIfBlank,
                average: footer.cells[safe: 4]?.text.nilIfBlank
            )
        }

        return GameCenterBattingSection(lines: lines, totals: totals)
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

        let lines = table.rows.compactMap { row -> GameCenterPitchingLine? in
            guard let name = row.cells[safe: 0]?.text.nilIfBlank else {
                return nil
            }

            return GameCenterPitchingLine(
                name: name,
                role: row.cells[safe: 1]?.text.nilIfBlank,
                result: row.cells[safe: 2]?.text.nilIfBlank,
                innings: row.cells[safe: 6]?.text.nilIfBlank,
                pitches: row.cells[safe: 8]?.text.nilIfBlank,
                hitsAllowed: row.cells[safe: 10]?.text.nilIfBlank,
                walksAllowed: row.cells[safe: 12]?.text.nilIfBlank,
                strikeouts: row.cells[safe: 13]?.text.nilIfBlank,
                runsAllowed: row.cells[safe: 14]?.text.nilIfBlank,
                earnedRuns: row.cells[safe: 15]?.text.nilIfBlank,
                earnedRunAverage: row.cells[safe: 16]?.text.nilIfBlank
            )
        }

        return GameCenterPitchingSection(lines: lines)
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
                hits: nil,
                runsBattedIn: nil,
                runs: nil,
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

private struct OfficialFlexibleCodingKey: CodingKey, Hashable, Sendable {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private enum OfficialKBOGameCenterError: Error {
    case invalidURL
    case invalidResponse
}

private struct OfficialGameListResponse: Decodable {
    let game: [OfficialGameEntry]
}

private struct OfficialGameEntry: Decodable, Sendable {
    let leagueID: Int
    let seriesID: Int
    let seasonID: Int
    let gameDate: String
    let displayDateText: String
    let gameID: String
    let startTime: String
    let stadiumName: String?
    let awayTeamCode: String
    let homeTeamCode: String
    let awayTeamName: String
    let homeTeamName: String
    let awayProbablePitcherName: String?
    let homeProbablePitcherName: String?
    let winningPitcherName: String?
    let losingPitcherName: String?
    let savePitcherName: String?
    let gameStateCode: String
    let cancelName: String?
    let inningNumber: Int?
    let inningHalfText: String?
    let awayScoreText: String?
    let homeScoreText: String?
    let strikeCount: Int?
    let ballCount: Int?
    let outCount: Int?
    let firstBaseOccupancy: Int?
    let secondBaseOccupancy: Int?
    let thirdBaseOccupancy: Int?
    private let decodedBaseOrderSourceKeys: [String]

    private enum CodingKeys: String, CodingKey {
        case leagueID = "LE_ID"
        case seriesID = "SR_ID"
        case seasonID = "SEASON_ID"
        case gameDate = "G_DT"
        case displayDateText = "G_DT_TXT"
        case gameID = "G_ID"
        case startTime = "G_TM"
        case stadiumName = "S_NM"
        case awayTeamCode = "AWAY_ID"
        case homeTeamCode = "HOME_ID"
        case awayTeamName = "AWAY_NM"
        case homeTeamName = "HOME_NM"
        case awayProbablePitcherName = "T_PIT_P_NM"
        case homeProbablePitcherName = "B_PIT_P_NM"
        case winningPitcherName = "W_PIT_P_NM"
        case losingPitcherName = "L_PIT_P_NM"
        case savePitcherName = "SV_PIT_P_NM"
        case gameStateCode = "GAME_STATE_SC"
        case cancelName = "CANCEL_SC_NM"
        case inningNumber = "GAME_INN_NO"
        case inningHalfText = "GAME_TB_SC_NM"
        case awayScoreText = "T_SCORE_CN"
        case homeScoreText = "B_SCORE_CN"
        case strikeCount = "STRIKE_CN"
        case ballCount = "BALL_CN"
        case outCount = "OUT_CN"
        case firstBaseOccupancy = "B1_BAT_ORDER_NO"
        case secondBaseOccupancy = "B2_BAT_ORDER_NO"
        case thirdBaseOccupancy = "B3_BAT_ORDER_NO"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        leagueID = try container.decode(Int.self, forKey: .leagueID)
        seriesID = try container.decode(Int.self, forKey: .seriesID)
        seasonID = try container.decode(Int.self, forKey: .seasonID)
        gameDate = try container.decode(String.self, forKey: .gameDate)
        displayDateText = try container.decode(String.self, forKey: .displayDateText)
        gameID = try container.decode(String.self, forKey: .gameID)
        startTime = try container.decode(String.self, forKey: .startTime)
        stadiumName = try container.decodeIfPresent(String.self, forKey: .stadiumName)
        awayTeamCode = try container.decode(String.self, forKey: .awayTeamCode)
        homeTeamCode = try container.decode(String.self, forKey: .homeTeamCode)
        awayTeamName = try container.decode(String.self, forKey: .awayTeamName)
        homeTeamName = try container.decode(String.self, forKey: .homeTeamName)
        awayProbablePitcherName = try container.decodeIfPresent(String.self, forKey: .awayProbablePitcherName)
        homeProbablePitcherName = try container.decodeIfPresent(String.self, forKey: .homeProbablePitcherName)
        winningPitcherName = try container.decodeIfPresent(String.self, forKey: .winningPitcherName)
        losingPitcherName = try container.decodeIfPresent(String.self, forKey: .losingPitcherName)
        savePitcherName = try container.decodeIfPresent(String.self, forKey: .savePitcherName)
        gameStateCode = try container.decode(String.self, forKey: .gameStateCode)
        cancelName = try container.decodeIfPresent(String.self, forKey: .cancelName)
        inningNumber = try container.decodeIfPresent(Int.self, forKey: .inningNumber)
        inningHalfText = try container.decodeIfPresent(String.self, forKey: .inningHalfText)
        awayScoreText = try container.decodeIfPresent(String.self, forKey: .awayScoreText)
        homeScoreText = try container.decodeIfPresent(String.self, forKey: .homeScoreText)
        strikeCount = try container.decodeIfPresent(Int.self, forKey: .strikeCount)
        ballCount = try container.decodeIfPresent(Int.self, forKey: .ballCount)
        outCount = try container.decodeIfPresent(Int.self, forKey: .outCount)

        let first = try Self.decodeInt(from: decoder, keys: ["B1_BAT_ORDER_NO", "B1BATORDERNO", "BASE1_BAT_ORDER_NO"])
        let second = try Self.decodeInt(from: decoder, keys: ["B2_BAT_ORDER_NO", "B2BATORDERNO", "BASE2_BAT_ORDER_NO"])
        let third = try Self.decodeInt(from: decoder, keys: ["B3_BAT_ORDER_NO", "B3BATORDERNO", "BASE3_BAT_ORDER_NO"])
        firstBaseOccupancy = first.value
        secondBaseOccupancy = second.value
        thirdBaseOccupancy = third.value
        decodedBaseOrderSourceKeys = [first.key, second.key, third.key].compactMap { $0 }
    }

    private static func decodeInt(
        from decoder: any Decoder,
        keys: [String]
    ) throws -> (value: Int?, key: String?) {
        let container = try decoder.container(keyedBy: OfficialFlexibleCodingKey.self)
        for key in keys {
            let codingKey = OfficialFlexibleCodingKey(key)
            if let value = try? container.decodeIfPresent(Int.self, forKey: codingKey) {
                return (value, key)
            }
            if let value = try? container.decodeIfPresent(String.self, forKey: codingKey),
               let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return (intValue, key)
            }
        }
        return (nil, nil)
    }

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

    var baseOrderSourceKeys: [String] {
        decodedBaseOrderSourceKeys
    }

    var probableStarters: GameCenterProbableStarters {
        GameCenterProbableStarters(
            away: awayProbablePitcherName?.nilIfBlank,
            home: homeProbablePitcherName?.nilIfBlank
        )
    }
}

private struct OfficialScoreboardResponse: Decodable {
    let stadiumName: String?
    let crowdText: String?
    let startTime: String?
    let endTime: String?
    let durationText: String?
    let inningTable: String
    let totalsTable: String

    private enum CodingKeys: String, CodingKey {
        case stadiumName = "S_NM"
        case crowdText = "CROWD_CN"
        case startTime = "START_TM"
        case endTime = "END_TM"
        case durationText = "USE_TM"
        case inningTable = "table2"
        case totalsTable = "table3"
    }
}

private struct OfficialBoxScoreResponse: Decodable {
    let summaryTable: String
    let battingTables: [OfficialBattingTableGroup]
    let pitchingTables: [OfficialPitchingTableGroup]

    private enum CodingKeys: String, CodingKey {
        case summaryTable = "tableEtc"
        case battingTables = "arrHitter"
        case pitchingTables = "arrPitcher"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summaryTable = try container.decodeIfPresent(String.self, forKey: .summaryTable) ?? ""
        battingTables = try container.decodeIfPresent([OfficialBattingTableGroup].self, forKey: .battingTables) ?? []
        pitchingTables = try container.decodeIfPresent([OfficialPitchingTableGroup].self, forKey: .pitchingTables) ?? []
    }
}

private struct OfficialBattingTableGroup: Decodable {
    let orderTable: String
    let detailTable: String?
    let summaryTable: String?

    private enum CodingKeys: String, CodingKey {
        case orderTable = "table1"
        case detailTable = "table2"
        case summaryTable = "table3"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        orderTable = try container.decodeIfPresent(String.self, forKey: .orderTable) ?? ""
        detailTable = try container.decodeIfPresent(String.self, forKey: .detailTable)
        summaryTable = try container.decodeIfPresent(String.self, forKey: .summaryTable)
    }
}

private struct OfficialPitchingTableGroup: Decodable {
    let table: String
}

private struct OfficialPreviewRecordResponse: Decodable {
    let rows: [OfficialPreviewRecordRow]
}

private struct OfficialPreviewRecordRow: Decodable {
    let row: [OfficialPreviewRecordCell]
}

private struct OfficialPreviewRecordCell: Decodable {
    let text: String

    private enum CodingKeys: String, CodingKey {
        case text = "Text"
    }

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
