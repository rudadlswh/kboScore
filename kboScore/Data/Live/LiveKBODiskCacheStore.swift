//
//  LiveKBODiskCacheStore.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

private struct BootstrapCachePayload: Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case payload
    }

    let payload: KBOBootstrapDTO

    nonisolated init(value: KBOBootstrapData) {
        payload = KBOBootstrapDTO(
            teams: value.teams.map(Self.makeTeamDTO),
            games: value.games.map(Self.makeGameDTO),
            notifications: value.notifications.map(Self.makeNotificationDTO),
            settings: value.settings
        )
    }

    nonisolated init(payload: KBOBootstrapDTO) {
        self.payload = payload
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        payload = try container.decode(KBOBootstrapDTO.self, forKey: .payload)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(payload, forKey: .payload)
    }

    nonisolated var bootstrapData: KBOBootstrapData {
        KBODataMapper.mapBootstrap(payload)
    }

    nonisolated fileprivate static func makeTeamDTO(from team: Team) -> KBOTeamDTO {
        KBOTeamDTO(
            id: team.id,
            name: team.name,
            shortName: team.shortName,
            englishName: team.englishName,
            markText: team.markText
        )
    }

    nonisolated fileprivate static func makeGameDTO(from game: GameDetail) -> KBOGameDTO {
        KBOGameDTO(
            id: game.id,
            providerGameID: game.providerGameID,
            scheduledStart: game.scheduledStart,
            venue: game.venue,
            awayTeamID: game.awayTeam.id,
            homeTeamID: game.homeTeam.id,
            awayScore: game.awayScore,
            homeScore: game.homeScore,
            statusCode: statusCode(for: game.status),
            statusText: game.status.title,
            seasonClassification: game.seasonClassification.rawValue,
            inningText: game.inningText,
            bases: game.bases.map { KBORunnerStateDTO(first: $0.first, second: $0.second, third: $0.third) },
            balls: game.balls,
            strikes: game.strikes,
            outs: game.outs,
            highlightText: game.highlightText,
            events: game.events.map {
                KBOGameEventDTO(
                    id: $0.id,
                    type: $0.type.rawValue,
                    headline: $0.headline,
                    inningText: $0.inningText,
                    timestamp: $0.timestamp
                )
            },
            note: game.note,
            awayStartingPitcherName: game.awayStartingPitcherName,
            homeStartingPitcherName: game.homeStartingPitcherName,
            currentPitcherName: game.currentPitcherName,
            currentBatterName: game.currentBatterName
        )
    }

    nonisolated fileprivate static func makeNotificationDTO(from item: NotificationItem) -> KBONotificationDTO {
        KBONotificationDTO(
            id: item.id,
            type: item.type.rawValue,
            title: item.title,
            body: item.body,
            sentAt: item.sentAt,
            isRead: item.isRead,
            relatedGameID: item.relatedGameID,
            relatedTeamIDs: item.relatedTeamIDs
        )
    }

    nonisolated private static func statusCode(for status: GameStatus) -> String {
        switch status {
        case .upcoming:
            "PRE"
        case .live:
            "LIVE"
        case .final:
            "FINAL"
        case .rainDelay:
            "DELAY"
        case .cancelled:
            "CANCELLED"
        }
    }
}

private struct TeamRanksDiskCacheEntry: Codable, Sendable {
    let value: [TeamRankRow]
    let timestamp: Date

    private enum CodingKeys: String, CodingKey {
        case value
        case timestamp
    }

    nonisolated init(value: [TeamRankRow], timestamp: Date) {
        self.value = value
        self.timestamp = timestamp
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode([TeamRankRow].self, forKey: .value)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

private struct GamesCachePayload: Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case teams
        case games
    }

    let teams: [KBOTeamDTO]
    let games: [KBOGameDTO]

    nonisolated init(games value: [GameDetail]) {
        let uniqueTeams = value
            .flatMap { [$0.awayTeam, $0.homeTeam] }
            .reduce(into: [String: Team]()) { partialResult, team in
                partialResult[team.id] = team
            }
        teams = uniqueTeams.values
            .sorted { $0.id < $1.id }
            .map(BootstrapCachePayload.makeTeamDTO)
        games = value.map(BootstrapCachePayload.makeGameDTO)
    }

    nonisolated init(teams: [KBOTeamDTO], games: [KBOGameDTO]) {
        self.teams = teams
        self.games = games
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teams = try container.decode([KBOTeamDTO].self, forKey: .teams)
        games = try container.decode([KBOGameDTO].self, forKey: .games)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(teams, forKey: .teams)
        try container.encode(games, forKey: .games)
    }

    nonisolated var domainGames: [GameDetail] {
        KBODataMapper.mapGames(games, teams: teams.map(KBODataMapper.mapTeam))
    }
}

private struct NotificationsCachePayload: Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case notifications
    }

    let notifications: [KBONotificationDTO]

    nonisolated init(notifications value: [NotificationItem]) {
        notifications = value.map(BootstrapCachePayload.makeNotificationDTO)
    }

    nonisolated init(notifications: [KBONotificationDTO]) {
        self.notifications = notifications
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notifications = try container.decode([KBONotificationDTO].self, forKey: .notifications)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(notifications, forKey: .notifications)
    }

    nonisolated var domainNotifications: [NotificationItem] {
        KBODataMapper.mapNotifications(notifications)
    }
}

private struct BootstrapDiskCacheEntry: Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case value
        case timestamp
    }

    let value: BootstrapCachePayload
    let timestamp: Date

    nonisolated init(value: BootstrapCachePayload, timestamp: Date) {
        self.value = value
        self.timestamp = timestamp
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(BootstrapCachePayload.self, forKey: .value)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

private struct GamesDiskCacheEntry: Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case value
        case timestamp
    }

    let value: GamesCachePayload
    let timestamp: Date

    nonisolated init(value: GamesCachePayload, timestamp: Date) {
        self.value = value
        self.timestamp = timestamp
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(GamesCachePayload.self, forKey: .value)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

private struct NotificationsDiskCacheEntry: Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case value
        case timestamp
    }

    let value: NotificationsCachePayload
    let timestamp: Date

    nonisolated init(value: NotificationsCachePayload, timestamp: Date) {
        self.value = value
        self.timestamp = timestamp
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(NotificationsCachePayload.self, forKey: .value)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

actor RepositoryDiskCache {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directoryURL: URL?, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? Self.defaultDirectory(fileManager: fileManager)
    }

    func loadBootstrap() -> RepositoryCacheEntry<KBOBootstrapData>? {
        guard let entry = loadBootstrapEntry(fileName: "bootstrap.json") else {
            return nil
        }
        return RepositoryCacheEntry(value: entry.value.bootstrapData, timestamp: entry.timestamp)
    }

    func loadGames() -> RepositoryCacheEntry<[GameDetail]>? {
        loadGamesEntry(fileName: "games.json").map {
            RepositoryCacheEntry(value: $0.value.domainGames, timestamp: $0.timestamp)
        }
    }

    func loadNotifications() -> RepositoryCacheEntry<[NotificationItem]>? {
        loadNotificationsEntry(fileName: "notifications.json").map {
            RepositoryCacheEntry(value: $0.value.domainNotifications, timestamp: $0.timestamp)
        }
    }

    func loadMonthlySchedule(for month: KBOMonthScheduleKey) -> RepositoryCacheEntry<[GameDetail]>? {
        loadGamesEntry(fileName: monthlyScheduleFileName(for: month)).map {
            RepositoryCacheEntry(
                value: $0.value.domainGames.sorted { $0.scheduledStart < $1.scheduledStart },
                timestamp: $0.timestamp
            )
        }
    }

    func loadTeamRanks(season: Int) -> RepositoryCacheEntry<[TeamRankRow]>? {
        let fileURL = directoryURL.appendingPathComponent(teamRanksFileName(season: season))
        guard let data = try? Data(contentsOf: fileURL),
              let entry = try? decoder.decode(TeamRanksDiskCacheEntry.self, from: data) else {
            return nil
        }
        return RepositoryCacheEntry(value: entry.value.sorted { $0.rank < $1.rank }, timestamp: entry.timestamp)
    }

    func storeBootstrap(_ value: KBOBootstrapData, timestamp: Date) {
        store(BootstrapDiskCacheEntry(value: BootstrapCachePayload(value: value), timestamp: timestamp), fileName: "bootstrap.json")
    }

    func storeGames(_ value: [GameDetail], timestamp: Date) {
        store(GamesDiskCacheEntry(value: GamesCachePayload(games: value), timestamp: timestamp), fileName: "games.json")
    }

    func storeNotifications(_ value: [NotificationItem], timestamp: Date) {
        store(
            NotificationsDiskCacheEntry(value: NotificationsCachePayload(notifications: value), timestamp: timestamp),
            fileName: "notifications.json"
        )
    }

    func storeMonthlySchedule(_ value: [GameDetail], for month: KBOMonthScheduleKey, timestamp: Date) {
        store(
            GamesDiskCacheEntry(value: GamesCachePayload(games: value), timestamp: timestamp),
            fileName: monthlyScheduleFileName(for: month)
        )
    }

    func storeTeamRanks(_ value: [TeamRankRow], season: Int, timestamp: Date) {
        store(
            TeamRanksDiskCacheEntry(value: value.sorted { $0.rank < $1.rank }, timestamp: timestamp),
            fileName: teamRanksFileName(season: season)
        )
    }

    private func loadBootstrapEntry(fileName: String) -> BootstrapDiskCacheEntry? {
        let fileURL = directoryURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(BootstrapDiskCacheEntry.self, from: data)
    }

    private func loadGamesEntry(fileName: String) -> GamesDiskCacheEntry? {
        let fileURL = directoryURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(GamesDiskCacheEntry.self, from: data)
    }

    private func loadNotificationsEntry(fileName: String) -> NotificationsDiskCacheEntry? {
        let fileURL = directoryURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(NotificationsDiskCacheEntry.self, from: data)
    }

    private func store<Value: Codable & Sendable>(_ value: Value, fileName: String) {
        let fileURL = directoryURL.appendingPathComponent(fileName)
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            try RepositoryFileSecurity.applyProtection(toDirectory: directoryURL, fileManager: fileManager)
            let data = try encoder.encode(value)
            try data.write(to: fileURL, options: .atomic)
            try RepositoryFileSecurity.applyProtection(to: fileURL, fileManager: fileManager)
        } catch {
            #if DEBUG
            print("[RepositoryDiskCache] write failed file=\(fileName) error=\(error)")
            #endif
        }
    }

    nonisolated private static func defaultDirectory(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ??
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseURL
            .appendingPathComponent("kboScore", isDirectory: true)
            .appendingPathComponent("RepositoryCache-v1", isDirectory: true)
    }

    private func monthlyScheduleFileName(for month: KBOMonthScheduleKey) -> String {
        "schedule-\(month.yearMonthText).json"
    }

    private func teamRanksFileName(season: Int) -> String {
        "team-ranks-\(season).json"
    }
}
