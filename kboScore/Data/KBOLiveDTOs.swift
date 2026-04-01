//
//  KBOLiveDTOs.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import Foundation

struct KBOTeamDTO: Codable, Sendable {
    let id: String
    let name: String
    let shortName: String
    let englishName: String
    let markText: String

    nonisolated init(
        id: String,
        name: String,
        shortName: String,
        englishName: String,
        markText: String
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.englishName = englishName
        self.markText = markText
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id.uppercased()
        shortName = try container.decodeIfPresent(String.self, forKey: .shortName) ?? name
        englishName = try container.decodeIfPresent(String.self, forKey: .englishName) ?? name
        markText = try container.decodeIfPresent(String.self, forKey: .markText) ?? String(shortName.prefix(3)).uppercased()
    }
}

struct KBORunnerStateDTO: Codable, Sendable {
    let first: Bool
    let second: Bool
    let third: Bool

    nonisolated init(first: Bool, second: Bool, third: Bool) {
        self.first = first
        self.second = second
        self.third = third
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        first = try container.decodeIfPresent(Bool.self, forKey: .first) ?? false
        second = try container.decodeIfPresent(Bool.self, forKey: .second) ?? false
        third = try container.decodeIfPresent(Bool.self, forKey: .third) ?? false
    }
}

struct KBOGameEventDTO: Codable, Sendable {
    let id: UUID
    let type: String
    let headline: String
    let inningText: String?
    let timestamp: Date

    nonisolated init(
        id: UUID,
        type: String,
        headline: String,
        inningText: String?,
        timestamp: Date
    ) {
        self.id = id
        self.type = type
        self.headline = headline
        self.inningText = inningText
        self.timestamp = timestamp
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "note"
        headline = try container.decodeIfPresent(String.self, forKey: .headline) ?? "상황 업데이트"
        inningText = try container.decodeIfPresent(String.self, forKey: .inningText)
        timestamp = try container.decodeFlexibleDate(forKey: .timestamp) ?? .distantPast
    }
}

struct KBOGameDTO: Codable, Sendable {
    let id: UUID
    let scheduledStart: Date
    let venue: String?
    let awayTeamID: String
    let homeTeamID: String
    let awayScore: Int?
    let homeScore: Int?
    let statusCode: String?
    let statusText: String?
    let inningText: String?
    let bases: KBORunnerStateDTO?
    let outs: Int?
    let highlightText: String?
    let events: [KBOGameEventDTO]
    let note: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case scheduledStart
        case venue
        case awayTeamID
        case homeTeamID
        case awayTeamId
        case homeTeamId
        case awayScore
        case homeScore
        case statusCode
        case statusText
        case inningText
        case bases
        case outs
        case highlightText
        case events
        case note
    }

    nonisolated init(
        id: UUID,
        scheduledStart: Date,
        venue: String?,
        awayTeamID: String,
        homeTeamID: String,
        awayScore: Int?,
        homeScore: Int?,
        statusCode: String?,
        statusText: String?,
        inningText: String?,
        bases: KBORunnerStateDTO?,
        outs: Int?,
        highlightText: String?,
        events: [KBOGameEventDTO],
        note: String?
    ) {
        self.id = id
        self.scheduledStart = scheduledStart
        self.venue = venue
        self.awayTeamID = awayTeamID
        self.homeTeamID = homeTeamID
        self.awayScore = awayScore
        self.homeScore = homeScore
        self.statusCode = statusCode
        self.statusText = statusText
        self.inningText = inningText
        self.bases = bases
        self.outs = outs
        self.highlightText = highlightText
        self.events = events
        self.note = note
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        scheduledStart = try container.decodeFlexibleDate(forKey: .scheduledStart) ?? .distantPast
        venue = try container.decodeIfPresent(String.self, forKey: .venue)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        let providerTeamIDs = Self.providerTeamIDs(from: note)
        let decodedAwayTeamID = (try container.decodeIfPresent(String.self, forKey: .awayTeamID))?.nilIfBlank
        let decodedAwayTeamId = (try container.decodeIfPresent(String.self, forKey: .awayTeamId))?.nilIfBlank
        let nestedAwayTeamID = Self.nestedTeamIdentifier(from: decoder, keyCandidates: ["awayTeam", "away"])
        awayTeamID = decodedAwayTeamID ?? decodedAwayTeamId ?? nestedAwayTeamID ?? providerTeamIDs?.away ?? ""
        let decodedHomeTeamID = (try container.decodeIfPresent(String.self, forKey: .homeTeamID))?.nilIfBlank
        let decodedHomeTeamId = (try container.decodeIfPresent(String.self, forKey: .homeTeamId))?.nilIfBlank
        let nestedHomeTeamID = Self.nestedTeamIdentifier(from: decoder, keyCandidates: ["homeTeam", "home"])
        homeTeamID = decodedHomeTeamID ?? decodedHomeTeamId ?? nestedHomeTeamID ?? providerTeamIDs?.home ?? ""
        awayScore = try container.decodeIfPresent(Int.self, forKey: .awayScore)
        homeScore = try container.decodeIfPresent(Int.self, forKey: .homeScore)
        statusCode = try container.decodeIfPresent(String.self, forKey: .statusCode)
        statusText = try container.decodeIfPresent(String.self, forKey: .statusText)
        inningText = try container.decodeIfPresent(String.self, forKey: .inningText)
        bases = try container.decodeIfPresent(KBORunnerStateDTO.self, forKey: .bases)
        outs = try container.decodeIfPresent(Int.self, forKey: .outs)
        highlightText = try container.decodeIfPresent(String.self, forKey: .highlightText)
        events = try container.decodeIfPresent([KBOGameEventDTO].self, forKey: .events) ?? []
    }

    private nonisolated static func providerTeamIDs(from note: String?) -> (away: String, home: String)? {
        guard let note else { return nil }
        guard let range = note.range(of: "provider_game_id=") else { return nil }
        let suffix = note[range.upperBound...]
        let token = suffix.split(whereSeparator: { $0 == " " || $0 == "\n" }).first ?? ""
        let parts = token.split(separator: "_")
        guard parts.count >= 2 else { return nil }
        return (String(parts[parts.count - 2]), String(parts[parts.count - 1]))
    }

    private nonisolated static func nestedTeamIdentifier(
        from decoder: any Decoder,
        keyCandidates: [String]
    ) -> String? {
        guard let container = try? decoder.container(keyedBy: AnyCodingKey.self) else { return nil }
        for keyName in keyCandidates {
            guard let key = AnyCodingKey(stringValue: keyName),
                  let nested = try? container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: key) else {
                continue
            }

            let idKeys = ["id", "teamID", "teamId", "code"]
            for idKeyName in idKeys {
                guard let idKey = AnyCodingKey(stringValue: idKeyName),
                      let value = try? nested.decodeIfPresent(String.self, forKey: idKey),
                      let resolved = value.nilIfBlank else {
                    continue
                }
                return resolved
            }
        }
        return nil
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(scheduledStart, forKey: .scheduledStart)
        try container.encodeIfPresent(venue, forKey: .venue)
        try container.encode(awayTeamID, forKey: .awayTeamID)
        try container.encode(homeTeamID, forKey: .homeTeamID)
        try container.encodeIfPresent(awayScore, forKey: .awayScore)
        try container.encodeIfPresent(homeScore, forKey: .homeScore)
        try container.encodeIfPresent(statusCode, forKey: .statusCode)
        try container.encodeIfPresent(statusText, forKey: .statusText)
        try container.encodeIfPresent(inningText, forKey: .inningText)
        try container.encodeIfPresent(bases, forKey: .bases)
        try container.encodeIfPresent(outs, forKey: .outs)
        try container.encodeIfPresent(highlightText, forKey: .highlightText)
        try container.encode(events, forKey: .events)
        try container.encodeIfPresent(note, forKey: .note)
    }
}

struct KBONotificationDTO: Codable, Sendable {
    let id: UUID
    let type: String
    let title: String?
    let body: String
    let sentAt: Date
    let isRead: Bool
    let relatedGameID: UUID?
    let relatedTeamIDs: [String]

    nonisolated init(
        id: UUID,
        type: String,
        title: String?,
        body: String,
        sentAt: Date,
        isRead: Bool,
        relatedGameID: UUID?,
        relatedTeamIDs: [String]
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.sentAt = sentAt
        self.isRead = isRead
        self.relatedGameID = relatedGameID
        self.relatedTeamIDs = relatedTeamIDs
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "scoreChange"
        title = try container.decodeIfPresent(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        sentAt = try container.decodeFlexibleDate(forKey: .sentAt) ?? .distantPast
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        relatedGameID = try container.decodeIfPresent(UUID.self, forKey: .relatedGameID)
        relatedTeamIDs = try container.decodeIfPresent([String].self, forKey: .relatedTeamIDs) ?? []
    }
}

struct KBOBootstrapDTO: Codable, Sendable {
    let teams: [KBOTeamDTO]
    let games: [KBOGameDTO]
    let notifications: [KBONotificationDTO]
    let settings: AppSettings?

    nonisolated init(
        teams: [KBOTeamDTO],
        games: [KBOGameDTO],
        notifications: [KBONotificationDTO],
        settings: AppSettings?
    ) {
        self.teams = teams
        self.games = games
        self.notifications = notifications
        self.settings = settings
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teams = try container.decodeIfPresent([KBOTeamDTO].self, forKey: .teams) ?? []
        games = try container.decodeIfPresent([KBOGameDTO].self, forKey: .games) ?? []
        notifications = try container.decodeIfPresent([KBONotificationDTO].self, forKey: .notifications) ?? []
        settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings)
    }
}

enum KBODataMapper {
    nonisolated static func mapBootstrap(_ payload: KBOBootstrapDTO) -> KBOBootstrapData {
        let teams = payload.teams.map(mapTeam)
        let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { (normalizedTeamID($0.id), $0) })

        return KBOBootstrapData(
            teams: teams,
            games: payload.games.compactMap { mapGame($0, teamsByID: teamsByID) }
                .sorted { $0.scheduledStart > $1.scheduledStart },
            notifications: payload.notifications.map(mapNotification)
                .sorted { $0.sentAt > $1.sentAt },
            settings: payload.settings ?? .default
        )
    }

    nonisolated static func mapGames(_ payload: [KBOGameDTO], teams: [Team]) -> [GameDetail] {
        let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { (normalizedTeamID($0.id), $0) })
        return payload.compactMap { mapGame($0, teamsByID: teamsByID) }
            .sorted { $0.scheduledStart > $1.scheduledStart }
    }

    nonisolated static func mapNotifications(_ payload: [KBONotificationDTO]) -> [NotificationItem] {
        payload.map(mapNotification)
            .sorted { $0.sentAt > $1.sentAt }
    }

    nonisolated static func mapGameStatus(code: String?, text: String?, inningText: String? = nil) -> GameStatus {
        let normalized = [code, text, inningText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " ")

        if normalized.contains("cancel") || normalized.contains("취소") {
            return .cancelled
        }

        if normalized.contains("rain") || normalized.contains("우천") || normalized.contains("delay") || normalized.contains("중단") {
            return .rainDelay
        }

        if normalized.contains("final") || normalized.contains("ended") || normalized.contains("종료") || normalized.contains("경기종료") {
            return .final
        }

        if normalized.contains("live") || normalized.contains("inprogress") || normalized.contains("progress") || normalized.contains("진행") || normalized.contains("회") {
            return .live
        }

        return .upcoming
    }

    nonisolated static func mapTeam(_ dto: KBOTeamDTO) -> Team {
        let normalizedID = normalizedTeamID(dto.id)
        return Team(
            id: normalizedID,
            name: dto.name,
            shortName: dto.shortName,
            englishName: dto.englishName,
            markText: dto.markText
        )
    }

    nonisolated private static func mapGame(_ dto: KBOGameDTO, teamsByID: [String: Team]) -> GameDetail? {
        guard let awayTeam = resolvedTeam(id: dto.awayTeamID, teamsByID: teamsByID),
              let homeTeam = resolvedTeam(id: dto.homeTeamID, teamsByID: teamsByID) else {
            return nil
        }

        let status = mapGameStatus(code: dto.statusCode, text: dto.statusText, inningText: dto.inningText)
        let inningText = dto.inningText?.nilIfBlank
        let note = sanitizedNote(dto.note)
        let highlight = dto.highlightText?.nilIfBlank

        return GameDetail(
            id: dto.id,
            scheduledStart: dto.scheduledStart,
            venue: dto.venue?.nilIfBlank ?? "장소 미정",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: status == .upcoming ? nil : dto.awayScore,
            homeScore: status == .upcoming ? nil : dto.homeScore,
            status: status,
            inningText: inningText,
            bases: dto.bases.map { RunnerState(first: $0.first, second: $0.second, third: $0.third) },
            outs: dto.outs,
            highlightText: highlight,
            events: dto.events.map(mapEvent).sorted { $0.timestamp > $1.timestamp },
            note: note
        )
    }

    nonisolated private static func mapEvent(_ dto: KBOGameEventDTO) -> GameEvent {
        GameEvent(
            id: dto.id,
            type: mapEventType(dto.type),
            headline: dto.headline,
            inningText: dto.inningText?.nilIfBlank ?? "상황 업데이트",
            timestamp: dto.timestamp
        )
    }

    nonisolated private static func mapNotification(_ dto: KBONotificationDTO) -> NotificationItem {
        let type = mapNotificationType(dto.type)
        return NotificationItem(
            id: dto.id,
            type: type,
            title: dto.title?.nilIfBlank ?? type.title,
            body: dto.body,
            sentAt: dto.sentAt,
            isRead: dto.isRead,
            relatedGameID: dto.relatedGameID,
            relatedTeamIDs: dto.relatedTeamIDs.map(normalizedTeamID)
        )
    }

    nonisolated private static func resolvedTeam(id: String, teamsByID: [String: Team]) -> Team? {
        let normalizedID = normalizedTeamID(id)
        return teamsByID[normalizedID] ?? Team(
            id: normalizedID,
            name: "알 수 없는 팀",
            shortName: normalizedID.uppercased(),
            englishName: normalizedID.uppercased(),
            markText: String(normalizedID.prefix(3)).uppercased()
        )
    }

    nonisolated private static func normalizedTeamID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated private static func sanitizedNote(
        _ raw: String?
    ) -> String? {
        guard let raw, let note = raw.nilIfBlank else { return nil }
        // Keep provider identifiers intact so higher layers can recover team IDs when needed.
        return note
    }

    nonisolated private static func mapEventType(_ rawValue: String) -> GameEventType {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "score", "scorechange", "득점":
            .score
        case "pitching", "strikeout", "투구":
            .pitching
        case "weather", "rain", "우천":
            .weather
        case "keyplay", "play", "주요장면":
            .keyPlay
        default:
            .note
        }
    }

    nonisolated private static func mapNotificationType(_ rawValue: String) -> NotificationType {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "scorechange", "score", "득점":
            .scoreChange
        case "gamestart", "start", "시작":
            .gameStart
        case "leadchange", "lead", "역전":
            .leadChange
        case "gameend", "final", "종료":
            .gameEnd
        case "raindelay", "cancelled", "rain", "우천", "취소":
            .rainDelay
        default:
            .scoreChange
        }
    }
}

private extension String {
    nonisolated var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension KeyedDecodingContainer {
    nonisolated func decodeFlexibleDate(forKey key: Key) throws -> Date? {
        if let timestamp = try? decodeIfPresent(Date.self, forKey: key) {
            return timestamp
        }

        if let seconds = try? decodeIfPresent(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: seconds)
        }

        if let milliseconds = try? decodeIfPresent(Int64.self, forKey: key) {
            if milliseconds > 2_000_000_000 {
                return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
            }
            return Date(timeIntervalSince1970: TimeInterval(milliseconds))
        }

        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return FlexibleDateParser.parse(text)
        }

        return nil
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

enum FlexibleDateParser {
    nonisolated private static func makeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }

    nonisolated static func parse(_ value: String) -> Date? {
        let iso8601WithFractional = ISO8601DateFormatter()
        iso8601WithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601WithFractional.date(from: value) {
            return date
        }

        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime]
        if let date = iso8601.date(from: value) {
            return date
        }

        return makeFormatter().date(from: value)
    }
}
