//
//  SupabaseKBOModels.swift
//  kboScore
//
//  Created by Codex on 4/24/26.
//

import Foundation

struct SupabaseConfiguration: Sendable {
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
//        case code
//        case teamCode = "team_code"
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
    let stadiumCode: String?
    let officialProviderGameID: String?

    private enum CodingKeys: String, CodingKey {
        case id
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
        case stadiumCode = "stadium_code"
        case officialProviderGameID = "official_provider_game_id"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        providerGameID = try container.decodeIfPresent(String.self, forKey: .providerGameID)
        gameDate = try container.decode(String.self, forKey: .gameDate)
        scheduledAt = try container.decodeIfPresent(Date.self, forKey: .scheduledAt) ??
            SupabaseDateParser.parseTimestamp(try container.decodeIfPresent(String.self, forKey: .scheduledAt))
        stadium = try container.decodeIfPresent(String.self, forKey: .stadium)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        homeTeamID = try container.decode(UUID.self, forKey: .homeTeamID)
        awayTeamID = try container.decode(UUID.self, forKey: .awayTeamID)
        homeScore = try container.decodeIfPresent(Int.self, forKey: .homeScore)
        awayScore = try container.decodeIfPresent(Int.self, forKey: .awayScore)
        inningState = try container.decodeIfPresent(String.self, forKey: .inningState)
        isCancelled = try container.decodeIfPresent(Bool.self, forKey: .isCancelled)
        isPostponed = try container.decodeIfPresent(Bool.self, forKey: .isPostponed)
        sourceUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .sourceUpdatedAt) ??
            SupabaseDateParser.parseTimestamp(try container.decodeIfPresent(String.self, forKey: .sourceUpdatedAt))
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ??
            SupabaseDateParser.parseTimestamp(try container.decodeIfPresent(String.self, forKey: .updatedAt))
        stadiumCode = try container.decodeIfPresent(String.self, forKey: .stadiumCode)
        officialProviderGameID = try container.decodeIfPresent(String.self, forKey: .officialProviderGameID)
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
        teamRows: [SupabaseTeamRow]
    ) -> [GameDetail] {
        let teamsByUUID = Dictionary(uniqueKeysWithValues: teamRows.map { ($0.id, mapTeam($0)) })
        let payload = gameRows.map { mapGameDTO($0, teamsByUUID: teamsByUUID) }
        return KBODataMapper.mapGames(payload, teams: Array(teamsByUUID.values))
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
        _ row: SupabaseGameRow,
        teamsByUUID: [UUID: Team]
    ) -> KBOGameDTO {
        let awayTeam = teamsByUUID[row.awayTeamID] ?? makeUnknownTeam(id: row.awayTeamID)
        let homeTeam = teamsByUUID[row.homeTeamID] ?? makeUnknownTeam(id: row.homeTeamID)

        let resolvedProviderGameID = row.officialProviderGameID?.nilIfBlank ??
            row.providerGameID?.nilIfBlank
        let resolvedStatus = statusText(for: row)
        let scheduledStart = row.scheduledAt ?? SupabaseDateParser.parseGameDate(row.gameDate) ?? .distantPast
        let venue = row.stadium?.nilIfBlank ?? row.stadiumCode?.nilIfBlank ?? "장소 미정"

        return KBOGameDTO(
            id: row.id,
            providerGameID: resolvedProviderGameID,
            scheduledStart: scheduledStart,
            venue: venue,
            awayTeamID: awayTeam.id,
            homeTeamID: homeTeam.id,
            awayScore: row.awayScore,
            homeScore: row.homeScore,
            statusCode: nil,
            statusText: resolvedStatus,
            seasonClassification: nil,
            inningText: row.inningState?.nilIfBlank,
            bases: nil,
            balls: nil,
            strikes: nil,
            outs: nil,
            highlightText: nil,
            events: [],
            note: makeNote(
                provider: row.provider,
                providerGameID: resolvedProviderGameID,
                updatedAt: row.sourceUpdatedAt ?? row.updatedAt
            )
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
        providerGameID: String?,
        updatedAt: Date?
    ) -> String? {
        var components: [String] = []
        if let provider = provider?.nilIfBlank {
            components.append("provider=\(provider)")
        }
        if let providerGameID = providerGameID?.nilIfBlank {
            components.append("provider_game_id=\(providerGameID)")
        }
        if let updatedAt {
            components.append("source_updated_at=\(SupabaseDateParser.debugTimestamp(updatedAt))")
        }
        return components.isEmpty ? nil : components.joined(separator: " ")
    }

    nonisolated private static func statusText(for row: SupabaseGameRow) -> String? {
        if row.isCancelled == true || row.isPostponed == true {
            return "cancelled"
        }
        return row.status?.nilIfBlank ?? row.inningState?.nilIfBlank
    }

    nonisolated private static func normalizeTeamCode(_ rawValue: String) -> String {
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
