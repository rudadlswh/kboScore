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
    let probableStarters: GameCenterProbableStarters?
    let winningPitcher: String?
    let losingPitcher: String?
    let savePitcher: String?
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
        async let review = fetchReviewIfNeeded(for: context)
        async let preview = fetchPreviewIfNeeded(for: context)

        let scoreboardValue = try await scoreboard
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
                probableStarters: context.entry.probableStarters,
                winningPitcher: context.entry.winningPitcherName,
                losingPitcher: context.entry.losingPitcherName,
                savePitcher: context.entry.savePitcherName
            ),
            lineScore: scoreboardValue?.lineScore,
            review: try await review,
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

    private func fetchReviewIfNeeded(
        for context: OfficialGameLookupContext
    ) async throws -> GameCenterReview? {
        guard context.entry.status == .final else { return nil }

        let payload = try await post(
            endpoint: "ws/Schedule.asmx/GetBoxScoreScroll",
            form: [
                "leId": String(context.entry.leagueID),
                "srId": String(context.entry.seriesID),
                "seasonId": String(context.entry.seasonID),
                "gameId": context.entry.gameID
            ],
            as: OfficialBoxScoreResponse.self
        )

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
            providerGameID: game.providerGameID
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
        guard let orderTable = decodeGridTable(from: tableGroup.orderTable),
              let summaryTable = decodeGridTable(from: tableGroup.summaryTable) else {
            return nil
        }

        let count = min(orderTable.rows.count, summaryTable.rows.count)
        let lines = (0..<count).compactMap { index -> GameCenterBattingLine? in
            let orderRow = orderTable.rows[index]
            let summaryRow = summaryTable.rows[index]
            guard orderRow.cells.count >= 3 else { return nil }

            return GameCenterBattingLine(
                battingOrder: orderRow.cells[0].text,
                position: orderRow.cells[1].text,
                name: orderRow.cells[2].text,
                atBats: summaryRow.cells[safe: 0]?.text.nilIfBlank,
                hits: summaryRow.cells[safe: 1]?.text.nilIfBlank,
                runsBattedIn: summaryRow.cells[safe: 2]?.text.nilIfBlank,
                runs: summaryRow.cells[safe: 3]?.text.nilIfBlank,
                average: summaryRow.cells[safe: 4]?.text.nilIfBlank
            )
        }

        let totals = summaryTable.tfoot.first.map { footer in
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

    private func post<Response: Decodable>(
        endpoint: String,
        form: [String: String],
        as type: Response.Type
    ) async throws -> Response {
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

        return try JSONDecoder().decode(Response.self, from: data)
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
}

private struct OfficialBattingTableGroup: Decodable {
    let orderTable: String
    let detailTable: String
    let summaryTable: String

    private enum CodingKeys: String, CodingKey {
        case orderTable = "table1"
        case detailTable = "table2"
        case summaryTable = "table3"
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
