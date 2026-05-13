//
//  SupabaseKBOModels.swift
//  kboScore
//
//  Created by Codex on 4/24/26.
//

import Foundation

struct SupabaseConfiguration: Sendable {
    nonisolated static let exposedSchema = "kbo_crawler_api"

    let url: URL
    let publishableKey: String
}

struct SupabaseTeamRow: Decodable, Sendable {
    let id: UUID
    let code: String
    let name: String
    let shortName: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case code = "team_code"
        case name
        case shortName = "short_name"
    }

    init(
        id: UUID,
        code: String,
        name: String,
        shortName: String?
    ) {
        self.id = id
        self.code = code
        self.name = name
        self.shortName = shortName
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        code = try container.decodeIfPresent(String.self, forKey: .code) ??
            container.decode(String.self, forKey: .code)
        name = try container.decode(String.self, forKey: .name)
        shortName = try container.decodeIfPresent(String.self, forKey: .shortName)
    }
}

struct SupabaseGameRow: Codable, Sendable {
    let id: UUID
    let publicGameID: String?
    let provider: String?
    let providerGameID: String?
    let gameDate: String
    let scheduledAt: Date?
    let stadium: String?
    let status: String?
    let homeTeamID: UUID
    let awayTeamID: UUID
    let homeScore: Int?
    let awayScore: Int?
    let inningState: String?
    let isCancelled: Bool?
    let isPostponed: Bool?
    let sourceUpdatedAt: Date?
    let updatedAt: Date?
    let statusReason: String?
    let finalConfirmedAt: Date?
    let liveLastCheckedAt: Date?
    let stadiumCode: String?
    let officialProviderGameID: String?
    let homeStartingPitcherName: String?
    let awayStartingPitcherName: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case publicGameID = "public_game_id"
        case provider
        case providerGameID = "provider_game_id"
        case gameDate = "game_date"
        case scheduledAt = "scheduled_at"
        case stadium
        case status
        case homeTeamID = "home_team_id"
        case awayTeamID = "away_team_id"
        case homeScore = "home_score"
        case awayScore = "away_score"
        case inningState = "inning_state"
        case isCancelled = "is_cancelled"
        case isPostponed = "is_postponed"
        case sourceUpdatedAt = "source_updated_at"
        case updatedAt = "updated_at"
        case statusReason = "status_reason"
        case finalConfirmedAt = "final_confirmed_at"
        case liveLastCheckedAt = "live_last_checked_at"
        case stadiumCode = "stadium_code"
        case officialProviderGameID = "official_provider_game_id"
        case homeStartingPitcherName = "home_starting_pitcher_name"
        case awayStartingPitcherName = "away_starting_pitcher_name"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        publicGameID = try container.decodeIfPresent(String.self, forKey: .publicGameID)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        providerGameID = try container.decodeIfPresent(String.self, forKey: .providerGameID)
        gameDate = try container.decode(String.self, forKey: .gameDate)
        scheduledAt = (try? container.decodeIfPresent(Date.self, forKey: .scheduledAt)) ??
            SupabaseDateParser.parseTimestamp(try? container.decodeIfPresent(String.self, forKey: .scheduledAt))
        stadium = try container.decodeIfPresent(String.self, forKey: .stadium)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        homeTeamID = try container.decode(UUID.self, forKey: .homeTeamID)
        awayTeamID = try container.decode(UUID.self, forKey: .awayTeamID)
        homeScore = try container.decodeIfPresent(Int.self, forKey: .homeScore)
        awayScore = try container.decodeIfPresent(Int.self, forKey: .awayScore)
        inningState = try container.decodeIfPresent(String.self, forKey: .inningState)
        isCancelled = try container.decodeIfPresent(Bool.self, forKey: .isCancelled)
        isPostponed = try container.decodeIfPresent(Bool.self, forKey: .isPostponed)
        sourceUpdatedAt = (try? container.decodeIfPresent(Date.self, forKey: .sourceUpdatedAt)) ??
            SupabaseDateParser.parseTimestamp(try? container.decodeIfPresent(String.self, forKey: .sourceUpdatedAt))
        updatedAt = (try? container.decodeIfPresent(Date.self, forKey: .updatedAt)) ??
            SupabaseDateParser.parseTimestamp(try? container.decodeIfPresent(String.self, forKey: .updatedAt))
        statusReason = try container.decodeIfPresent(String.self, forKey: .statusReason)
        finalConfirmedAt = (try? container.decodeIfPresent(Date.self, forKey: .finalConfirmedAt)) ??
            SupabaseDateParser.parseTimestamp(try? container.decodeIfPresent(String.self, forKey: .finalConfirmedAt))
        liveLastCheckedAt = (try? container.decodeIfPresent(Date.self, forKey: .liveLastCheckedAt)) ??
            SupabaseDateParser.parseTimestamp(try? container.decodeIfPresent(String.self, forKey: .liveLastCheckedAt))
        stadiumCode = try container.decodeIfPresent(String.self, forKey: .stadiumCode)
        officialProviderGameID = try container.decodeIfPresent(String.self, forKey: .officialProviderGameID)
        homeStartingPitcherName = try container.decodeIfPresent(String.self, forKey: .homeStartingPitcherName)
        awayStartingPitcherName = try container.decodeIfPresent(String.self, forKey: .awayStartingPitcherName)
    }
}

struct SupabaseLatestGameSnapshotRow: Decodable, Sendable {
    nonisolated static let selectColumns = "*"

    let gameID: UUID
    let inningLabel: String?
    let balls: Int?
    let strikes: Int?
    let outs: Int?
    let runnerOnFirst: Bool?
    let runnerOnSecond: Bool?
    let runnerOnThird: Bool?
    let firstBaseRunnerName: String?
    let secondBaseRunnerName: String?
    let thirdBaseRunnerName: String?
    let currentPitcherName: String?
    let currentBatterName: String?
#if DEBUG
    let debugAvailableFieldNames: Set<String>
#endif

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        gameID = try container.decode(UUID.self, forKey: DynamicCodingKey("game_id"))
        inningLabel = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("inning_label"))
        balls = try container.decodeIfPresent(Int.self, forKey: DynamicCodingKey("balls"))
        strikes = try container.decodeIfPresent(Int.self, forKey: DynamicCodingKey("strikes"))
        outs = try container.decodeIfPresent(Int.self, forKey: DynamicCodingKey("outs"))
        runnerOnFirst = try container.decodeIfPresent(Bool.self, forKey: DynamicCodingKey("runner_on_first"))
        runnerOnSecond = try container.decodeIfPresent(Bool.self, forKey: DynamicCodingKey("runner_on_second"))
        runnerOnThird = try container.decodeIfPresent(Bool.self, forKey: DynamicCodingKey("runner_on_third"))
        firstBaseRunnerName = try Self.firstNonBlankString(
            in: container,
            keys: ["first_base_runner_name", "firstBaseRunnerName"]
        )
        secondBaseRunnerName = try Self.firstNonBlankString(
            in: container,
            keys: ["second_base_runner_name", "secondBaseRunnerName"]
        )
        thirdBaseRunnerName = try Self.firstNonBlankString(
            in: container,
            keys: ["third_base_runner_name", "thirdBaseRunnerName"]
        )
        currentPitcherName = try Self.firstNonBlankString(
            in: container,
            keys: ["current_pitcher_name", "pitcher_name", "pitcher", "currentPitcherName", "pitcherName"]
        )
        currentBatterName = try Self.firstNonBlankString(
            in: container,
            keys: ["current_batter_name", "batter_name", "current_hitter_name", "hitter_name", "batter", "hitter", "currentBatterName", "batterName"]
        )
#if DEBUG
        debugAvailableFieldNames = Set(container.allKeys.map(\.stringValue))
#endif
    }

    private static func firstNonBlankString(
        in container: KeyedDecodingContainer<DynamicCodingKey>,
        keys: [String]
    ) throws -> String? {
        for key in keys {
            let value = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey(key))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let value, value.isEmpty == false {
                return value
            }
        }
        return nil
    }
}

private struct DynamicCodingKey: CodingKey, Hashable, Sendable {
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

enum SupabaseKBOMapper {
    nonisolated static func mapTeam(_ row: SupabaseTeamRow) -> Team {
        let normalizedCode = normalizeTeamCode(row.code)
        let identity = TeamIdentity.catalog[normalizedCode]
        let resolvedShortName = row.shortName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ??
            identity?.shortLabel ??
            row.name

        return Team(
            id: normalizedCode,
            name: row.name,
            shortName: resolvedShortName,
            englishName: identity?.displayName ?? row.name,
            markText: identity?.monogram ?? String(resolvedShortName.prefix(3)).uppercased()
        )
    }

    nonisolated static func mapTeams(_ rows: [SupabaseTeamRow]) -> [Team] {
        rows
            .map(mapTeam)
            .sorted { $0.id < $1.id }
    }

    nonisolated static func mapGames(
        gameRows: [SupabaseGameRow],
        teamRows: [SupabaseTeamRow],
        snapshotRows: [SupabaseLatestGameSnapshotRow] = []
    ) -> [GameDetail] {
        let teamsByUUID = Dictionary(uniqueKeysWithValues: teamRows.map { ($0.id, mapTeam($0)) })
        let snapshotsByGameID = Dictionary(uniqueKeysWithValues: snapshotRows.map { ($0.gameID, $0) })
        let classifiedRows = gameRows.map(classifiedRow(from:))
#if DEBUG
        debugLogSeasonClassificationSummary(classifiedRows)
#endif
        let payload = classifiedRows.map { classifiedRow in
            mapGameDTO(
                classifiedRow,
                teamsByUUID: teamsByUUID,
                snapshot: snapshotsByGameID[classifiedRow.row.id]
            )
        }
        return KBODataMapper.mapGames(payload, teams: Array(teamsByUUID.values))
    }

    nonisolated static func mapGame(
        row: SupabaseGameRow,
        teamRows: [SupabaseTeamRow],
        snapshot: SupabaseLatestGameSnapshotRow?,
        fallbackGame: GameDetail
    ) -> GameDetail {
        var teamsByUUID: [UUID: Team] = [
            row.awayTeamID: fallbackGame.awayTeam,
            row.homeTeamID: fallbackGame.homeTeam
        ]
        for teamRow in teamRows {
            teamsByUUID[teamRow.id] = mapTeam(teamRow)
        }

        let classifiedRow = classifiedRow(from: row)
#if DEBUG
        debugLogSeasonClassificationSummary([classifiedRow])
#endif
        let payload = [mapGameDTO(classifiedRow, teamsByUUID: teamsByUUID, snapshot: snapshot)]
        return KBODataMapper.mapGames(payload, teams: Array(teamsByUUID.values)).first ?? fallbackGame
    }

    nonisolated static func mapBootstrap(
        teamRows: [SupabaseTeamRow],
        gameRows: [SupabaseGameRow],
        notifications: [NotificationItem] = [],
        settings: AppSettings = .default
    ) -> KBOBootstrapData {
        let teams = mapTeams(teamRows)
        return KBOBootstrapData(
            teams: teams,
            games: mapGames(gameRows: gameRows, teamRows: teamRows),
            notifications: notifications,
            settings: settings
        )
    }

    nonisolated private static func mapGameDTO(
        _ classifiedRow: ClassifiedSupabaseGameRow,
        teamsByUUID: [UUID: Team],
        snapshot: SupabaseLatestGameSnapshotRow?
    ) -> KBOGameDTO {
        let row = classifiedRow.row
        let awayTeam = teamsByUUID[row.awayTeamID] ?? makeUnknownTeam(id: row.awayTeamID)
        let homeTeam = teamsByUUID[row.homeTeamID] ?? makeUnknownTeam(id: row.homeTeamID)

        let resolvedStatus = statusText(for: row)
        let scheduledStart = row.scheduledAt ?? SupabaseDateParser.parseGameDate(row.gameDate) ?? .distantPast
        let venue = row.stadium?.nilIfBlank ?? "장소 미정"
        let inningText = snapshot?.inningLabel?.nilIfBlank ?? row.inningState?.nilIfBlank
        let bases = snapshot.map {
            KBORunnerStateDTO(
                first: $0.runnerOnFirst ?? false,
                second: $0.runnerOnSecond ?? false,
                third: $0.runnerOnThird ?? false
            )
        }
        let currentPitcherName = snapshot?.currentPitcherName?.nilIfBlank
        let currentBatterName = snapshot?.currentBatterName?.nilIfBlank
        let baseRunners = snapshot.map {
            KBOBaseRunnersDTO(
                first: $0.firstBaseRunnerName?.nilIfBlank,
                second: $0.secondBaseRunnerName?.nilIfBlank,
                third: $0.thirdBaseRunnerName?.nilIfBlank
            )
        }
#if DEBUG
        if let snapshot {
            print("[BaseRunners] snapshot names first=\(snapshot.firstBaseRunnerName ?? "<nil>") second=\(snapshot.secondBaseRunnerName ?? "<nil>") third=\(snapshot.thirdBaseRunnerName ?? "<nil>")")
        }
#endif

        return KBOGameDTO(
            id: row.id,
            providerGameID: classifiedRow.providerGameID,
            scheduledStart: scheduledStart,
            venue: venue,
            awayTeamID: awayTeam.id,
            homeTeamID: homeTeam.id,
            awayScore: row.awayScore,
            homeScore: row.homeScore,
            statusCode: nil,
            statusText: resolvedStatus,
            seasonClassification: classifiedRow.seasonClassification.rawValue,
            inningText: inningText,
            bases: bases,
            baseRunners: baseRunners,
            balls: snapshot?.balls,
            strikes: snapshot?.strikes,
            outs: snapshot?.outs,
            highlightText: nil,
            events: [],
            note: makeNote(
                provider: row.provider,
                publicGameID: row.publicGameID,
                providerGameID: classifiedRow.providerGameID,
                sourceUpdatedAt: row.sourceUpdatedAt,
                updatedAt: row.updatedAt,
                liveLastCheckedAt: row.liveLastCheckedAt,
                finalConfirmedAt: row.finalConfirmedAt,
                statusReason: row.statusReason
            ),
            awayStartingPitcherName: row.awayStartingPitcherName?.nilIfBlank,
            homeStartingPitcherName: row.homeStartingPitcherName?.nilIfBlank,
            currentPitcherName: currentPitcherName,
            currentBatterName: currentBatterName
        )
    }

    nonisolated private static func makeUnknownTeam(id: UUID) -> Team {
        let fallbackID = "unknown-\(id.uuidString.lowercased())"
        return Team(
            id: fallbackID,
            name: "알 수 없는 팀",
            shortName: "미정",
            englishName: "Unknown Team",
            markText: "UNK"
        )
    }

    nonisolated private static func makeNote(
        provider: String?,
        publicGameID: String?,
        providerGameID: String?,
        sourceUpdatedAt: Date?,
        updatedAt: Date?,
        liveLastCheckedAt: Date?,
        finalConfirmedAt: Date?,
        statusReason: String?
    ) -> String? {
        var components: [String] = []
        if let provider = provider?.nilIfBlank {
            components.append("provider=\(provider)")
        }
        if let publicGameID = publicGameID?.nilIfBlank {
            components.append("public_game_id=\(publicGameID)")
        }
        if let providerGameID = providerGameID?.nilIfBlank {
            components.append("provider_game_id=\(providerGameID)")
        }
        if let sourceUpdatedAt {
            components.append("source_updated_at=\(SupabaseDateParser.debugTimestamp(sourceUpdatedAt))")
        }
        if let updatedAt {
            components.append("updated_at=\(SupabaseDateParser.debugTimestamp(updatedAt))")
        }
        if let liveLastCheckedAt {
            components.append("live_last_checked_at=\(SupabaseDateParser.debugTimestamp(liveLastCheckedAt))")
        }
        if let finalConfirmedAt {
            components.append("final_confirmed_at=\(SupabaseDateParser.debugTimestamp(finalConfirmedAt))")
        }
        if let statusReason = statusReason?.nilIfBlank {
            components.append("status_reason=\(statusReason)")
        }
        return components.isEmpty ? nil : components.joined(separator: " ")
    }

    nonisolated private static func statusText(for row: SupabaseGameRow) -> String? {
        if row.isCancelled == true || row.isPostponed == true {
            return "cancelled"
        }
        return row.status?.nilIfBlank ?? row.inningState?.nilIfBlank
    }

    nonisolated private static func classifiedRow(from row: SupabaseGameRow) -> ClassifiedSupabaseGameRow {
        let providerGameID = resolvedProviderGameID(for: row)
        return ClassifiedSupabaseGameRow(
            row: row,
            providerGameID: providerGameID,
            seasonClassification: inferredSeasonClassification(for: row, providerGameID: providerGameID)
        )
    }

    nonisolated private static func resolvedProviderGameID(for row: SupabaseGameRow) -> String? {
        row.providerGameID?.nilIfBlank ?? row.officialProviderGameID?.nilIfBlank
    }

    nonisolated private static func inferredSeasonClassification(
        for row: SupabaseGameRow,
        providerGameID: String?
    ) -> GameSeasonClassification {
        let searchableText = [
            providerGameID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            row.publicGameID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            row.provider?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ]
            .compactMap { $0 }
            .joined(separator: " ")

        if searchableText.contains("kbo_pre") ||
            searchableText.contains("preseason") ||
            searchableText.contains("exhibition") ||
            searchableText.contains("시범경기") {
            return .exhibitionPreseason
        }

        if searchableText.contains("wildcard") ||
            searchableText.contains("wild_card") ||
            searchableText.contains("playoff") ||
            searchableText.contains("semi_playoff") ||
            searchableText.contains("koreanseries") ||
            searchableText.contains("korean_series") ||
            searchableText.contains("postseason") ||
            searchableText.contains("준플레이오프") ||
            searchableText.contains("플레이오프") ||
            searchableText.contains("한국시리즈") {
            return .postseason
        }

        let normalizedProvider = row.provider?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedProvider == "kbo",
           SupabaseDateParser.parseGameDate(row.gameDate) != nil {
            return .regularSeason
        }

        if let providerGameID = providerGameID?.trimmingCharacters(in: .whitespacesAndNewlines),
           providerGameID.count >= 8,
           providerGameID.prefix(8).allSatisfy(\.isNumber) {
            return .regularSeason
        }

        if let publicGameID = row.publicGameID?.trimmingCharacters(in: .whitespacesAndNewlines),
           publicGameID.count >= 8,
           publicGameID.prefix(8).allSatisfy(\.isNumber) {
            return .regularSeason
        }

        return .unknown
    }

#if DEBUG
    nonisolated private static func debugLogSeasonClassificationSummary(_ rows: [ClassifiedSupabaseGameRow]) {
        let regularSeasonCount = rows.filter { $0.seasonClassification == .regularSeason }.count
        let preseasonCount = rows.filter { $0.seasonClassification == .exhibitionPreseason }.count
        let postseasonCount = rows.filter { $0.seasonClassification == .postseason }.count
        let unknownRows = rows.filter { $0.seasonClassification == .unknown }

        print(
            "[SupabaseKBO] classification counts total=\(rows.count) regularSeason=\(regularSeasonCount) preseason=\(preseasonCount) postseason=\(postseasonCount) unknown=\(unknownRows.count)"
        )

        for (index, row) in unknownRows.prefix(5).enumerated() {
            print(
                "[SupabaseKBO] unknown classification sample index=\(index + 1) provider=\(row.row.provider ?? "<nil>") provider_game_id=\(row.providerGameID ?? "<nil>") public_game_id=\(row.row.publicGameID ?? "<nil>") game_date=\(row.row.gameDate) status=\(row.row.status ?? row.row.inningState ?? "<nil>")"
            )
        }
    }
#endif

    private struct ClassifiedSupabaseGameRow: Sendable {
        let row: SupabaseGameRow
        let providerGameID: String?
        let seasonClassification: GameSeasonClassification
    }

    nonisolated static func normalizeTeamCode(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

enum SupabaseDateParser {
    nonisolated static func parseGameDate(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    nonisolated static func parseTimestamp(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            return nil
        }

        let iso8601WithFractional = ISO8601DateFormatter()
        iso8601WithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = iso8601WithFractional.date(from: value) {
            return parsed
        }

        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime]
        if let parsed = iso8601.date(from: value) {
            return parsed
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value)
    }

    nonisolated static func debugTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

private extension String {
    nonisolated var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
