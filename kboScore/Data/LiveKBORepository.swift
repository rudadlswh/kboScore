//
//  LiveKBORepository.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import Foundation

enum RepositoryDataSourceKind: String, Sendable {
    case mock = "목 데이터"
    case live = "실데이터"
    case mockFallback = "목 데이터 폴백"
}

enum RepositoryDeliverySourceKind: String, Sendable {
    case mock = "목 데이터"
    case live = "실시간 응답"
    case cache = "로컬 캐시"
    case mockFallback = "목 데이터 폴백"
}

enum LocalBootstrapSourceKind: String, Sendable {
    case documents = "문서 JSON"
    case bundled = "번들 JSON"
}

enum BootstrapRefreshResultKind: String, Sendable, Codable {
    case idle = "대기"
    case updated = "업데이트됨"
    case notModified = "변경 없음"
    case failed = "실패"
    case disabled = "비활성"
}

struct BootstrapRefreshDebugSnapshot: Sendable {
    let isEnabled: Bool
    let etag: String?
    let lastFetchAt: Date?
    let lastWriteAt: Date?
    let lastResult: BootstrapRefreshResultKind
}

private struct PersistedBootstrapRefreshState: Codable, Sendable {
    let etag: String?
    let lastFetchAt: Date?
    let lastWriteAt: Date?
    let lastResult: BootstrapRefreshResultKind
}

struct BootstrapRefreshStateStore: Sendable {
    private let defaults: UserDefaults
    private let storageKey: String

    init(
        baseURL: URL,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.storageKey = "kbo_live_bootstrap_refresh_state::\(baseURL.absoluteString)"
    }

    func load(isEnabled: Bool) -> BootstrapRefreshDebugSnapshot {
        guard let data = defaults.data(forKey: storageKey),
              let persisted = try? JSONDecoder().decode(PersistedBootstrapRefreshState.self, from: data) else {
            return BootstrapRefreshDebugSnapshot(
                isEnabled: isEnabled,
                etag: nil,
                lastFetchAt: nil,
                lastWriteAt: nil,
                lastResult: isEnabled ? .idle : .disabled
            )
        }

        return BootstrapRefreshDebugSnapshot(
            isEnabled: isEnabled,
            etag: persisted.etag,
            lastFetchAt: persisted.lastFetchAt,
            lastWriteAt: persisted.lastWriteAt,
            lastResult: isEnabled ? persisted.lastResult : .disabled
        )
    }

    func save(_ snapshot: BootstrapRefreshDebugSnapshot) {
        let persisted = PersistedBootstrapRefreshState(
            etag: snapshot.etag,
            lastFetchAt: snapshot.lastFetchAt,
            lastWriteAt: snapshot.lastWriteAt,
            lastResult: snapshot.lastResult
        )
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct RepositoryDebugSnapshot: Sendable {
    let activeSource: RepositoryDataSourceKind
    let deliverySource: RepositoryDeliverySourceKind
    let baseURL: String?
    let lastRefreshAt: Date?
    let isUsingStaleCache: Bool
    let localBootstrapSource: LocalBootstrapSourceKind?
    let localBootstrapMessage: String?
    let localBootstrapResolvedPath: String?
    let localBootstrapLoadedAt: Date?
    let bootstrapAPIEnabled: Bool
    let bootstrapRefreshETag: String?
    let bootstrapLastFetchAt: Date?
    let bootstrapLastWriteAt: Date?
    let bootstrapLastResult: BootstrapRefreshResultKind
}

actor RepositoryRuntimeState {
    private(set) var activeSource: RepositoryDataSourceKind
    private(set) var deliverySource: RepositoryDeliverySourceKind
    let baseURL: String?
    private(set) var lastRefreshAt: Date?
    private(set) var isUsingStaleCache: Bool
    private(set) var localBootstrapSource: LocalBootstrapSourceKind?
    private(set) var localBootstrapMessage: String?
    private(set) var localBootstrapResolvedPath: String?
    private(set) var localBootstrapLoadedAt: Date?
    private(set) var bootstrapAPIEnabled: Bool
    private(set) var bootstrapRefreshETag: String?
    private(set) var bootstrapLastFetchAt: Date?
    private(set) var bootstrapLastWriteAt: Date?
    private(set) var bootstrapLastResult: BootstrapRefreshResultKind

    init(
        activeSource: RepositoryDataSourceKind,
        baseURL: String?,
        deliverySource: RepositoryDeliverySourceKind? = nil,
        bootstrapRefreshSnapshot: BootstrapRefreshDebugSnapshot? = nil
    ) {
        self.activeSource = activeSource
        self.baseURL = baseURL
        self.deliverySource = deliverySource ?? {
            switch activeSource {
            case .mock:
                .mock
            case .live:
                .live
            case .mockFallback:
                .mockFallback
            }
        }()
        self.lastRefreshAt = nil
        self.isUsingStaleCache = false
        self.localBootstrapSource = nil
        self.localBootstrapMessage = nil
        self.localBootstrapResolvedPath = nil
        self.localBootstrapLoadedAt = nil
        self.bootstrapAPIEnabled = bootstrapRefreshSnapshot?.isEnabled ?? false
        self.bootstrapRefreshETag = bootstrapRefreshSnapshot?.etag
        self.bootstrapLastFetchAt = bootstrapRefreshSnapshot?.lastFetchAt
        self.bootstrapLastWriteAt = bootstrapRefreshSnapshot?.lastWriteAt
        self.bootstrapLastResult = bootstrapRefreshSnapshot?.lastResult ?? (baseURL == nil ? .disabled : .idle)
    }

    func record(
        source: RepositoryDataSourceKind,
        delivery: RepositoryDeliverySourceKind,
        refreshedAt: Date = .now,
        isUsingStaleCache: Bool = false,
        localBootstrapSource: LocalBootstrapSourceKind? = nil,
        localBootstrapMessage: String? = nil,
        localBootstrapResolvedPath: String? = nil,
        localBootstrapLoadedAt: Date? = nil
    ) {
        activeSource = source
        deliverySource = delivery
        lastRefreshAt = refreshedAt
        self.isUsingStaleCache = isUsingStaleCache
        if let localBootstrapSource {
            self.localBootstrapSource = localBootstrapSource
        }
        if localBootstrapMessage != nil {
            self.localBootstrapMessage = localBootstrapMessage?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == true ? nil : localBootstrapMessage
        }
        if let localBootstrapResolvedPath {
            self.localBootstrapResolvedPath = localBootstrapResolvedPath
        }
        if let localBootstrapLoadedAt {
            self.localBootstrapLoadedAt = localBootstrapLoadedAt
        }
    }

    func recordCacheHit(refreshedAt: Date, isStale: Bool) {
        deliverySource = .cache
        lastRefreshAt = refreshedAt
        isUsingStaleCache = isStale
    }

    func recordBootstrapRefresh(_ snapshot: BootstrapRefreshDebugSnapshot) {
        bootstrapAPIEnabled = snapshot.isEnabled
        bootstrapRefreshETag = snapshot.etag
        bootstrapLastFetchAt = snapshot.lastFetchAt
        bootstrapLastWriteAt = snapshot.lastWriteAt
        bootstrapLastResult = snapshot.lastResult
        lastRefreshAt = snapshot.lastFetchAt ?? lastRefreshAt
    }

    func snapshot() -> RepositoryDebugSnapshot {
        RepositoryDebugSnapshot(
            activeSource: activeSource,
            deliverySource: deliverySource,
            baseURL: baseURL,
            lastRefreshAt: lastRefreshAt,
            isUsingStaleCache: isUsingStaleCache,
            localBootstrapSource: localBootstrapSource,
            localBootstrapMessage: localBootstrapMessage,
            localBootstrapResolvedPath: localBootstrapResolvedPath,
            localBootstrapLoadedAt: localBootstrapLoadedAt,
            bootstrapAPIEnabled: bootstrapAPIEnabled,
            bootstrapRefreshETag: bootstrapRefreshETag,
            bootstrapLastFetchAt: bootstrapLastFetchAt,
            bootstrapLastWriteAt: bootstrapLastWriteAt,
            bootstrapLastResult: bootstrapLastResult
        )
    }
}

struct AppRepositoryBundle {
    let repository: any KBORepository
    let runtimeState: RepositoryRuntimeState?
}

struct AppRepositoryConfiguration: Sendable {
    let backendBaseURL: URL?

    nonisolated static func fromEnvironment(
        processInfo: ProcessInfo = .processInfo,
        bundle: Bundle = .main
    ) -> AppRepositoryConfiguration {
        let environmentValue = processInfo.environment["KBO_BACKEND_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let infoDictionaryValue = (bundle.object(forInfoDictionaryKey: "KBOBackendBaseURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawValue: String? = {
            if let environmentValue, environmentValue.isEmpty == false {
                return environmentValue
            }
            if let infoDictionaryValue, infoDictionaryValue.isEmpty == false {
                return infoDictionaryValue
            }
            return nil
        }()
        let backendBaseURL = backendURL(from: rawValue)
#if DEBUG
        print("[BackendConfig] environment KBO_BACKEND_BASE_URL=\(debugValue(environmentValue))")
        print("[BackendConfig] plist KBOBackendBaseURL=\(debugValue(infoDictionaryValue))")
        print("[BackendConfig] persisted backend base URL=<none: no persisted backend URL store>")
        print("[BackendConfig] final runtime base URL=\(debugValue(backendBaseURL?.absoluteString))")
#endif
        return AppRepositoryConfiguration(
            backendBaseURL: backendBaseURL
        )
    }

    private nonisolated static func backendURL(from rawValue: String?) -> URL? {
        guard let rawValue,
              let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

#if DEBUG
    private nonisolated static func debugValue(_ value: String?) -> String {
        guard let value, value.isEmpty == false else {
            return "<none>"
        }
        return value
    }
#endif
}

enum KBORepositoryFactory {
    static func makeAppRepository() -> any KBORepository {
        makeAppRepositoryBundle().repository
    }

    static func makeAppRepositoryBundle(
        configuration: AppRepositoryConfiguration = .fromEnvironment()
    ) -> AppRepositoryBundle {
        if let backendBaseURL = configuration.backendBaseURL {
#if DEBUG
            print("[BackendConfig] repository runtime base URL=\(backendBaseURL.absoluteString)")
#endif
            let bootstrapStateStore = BootstrapRefreshStateStore(baseURL: backendBaseURL)
            let runtimeState = RepositoryRuntimeState(
                activeSource: .live,
                baseURL: backendBaseURL.absoluteString,
                deliverySource: .live,
                bootstrapRefreshSnapshot: bootstrapStateStore.load(isEnabled: true)
            )
            let localBootstrapRepository = BundledJSONKBORepository(
                runtimeState: runtimeState,
                runtimeSource: .live,
                runtimeDelivery: .cache
            )
            let liveRepository = LiveKBORepository(
                baseURL: backendBaseURL,
                runtimeState: runtimeState
            )
            let cachedRepository = CachedKBORepository(
                base: liveRepository,
                configuration: .default,
                runtimeState: runtimeState
            )
            let bootstrapRepository = BootstrapRefreshingKBORepository(
                base: cachedRepository,
                localBootstrapRepository: localBootstrapRepository,
                bootstrapBaseURL: backendBaseURL,
                runtimeState: runtimeState,
                stateStore: bootstrapStateStore
            )
            let repository = FallbackKBORepository(
                primary: bootstrapRepository,
                fallback: localBootstrapRepository,
                runtimeState: runtimeState
            )
            return AppRepositoryBundle(
                repository: repository,
                runtimeState: runtimeState
            )
        }

#if DEBUG
        print("[BackendConfig] repository runtime base URL=<none>")
#endif
        let runtimeState = RepositoryRuntimeState(
            activeSource: .mock,
            baseURL: nil,
            deliverySource: .mock,
            bootstrapRefreshSnapshot: BootstrapRefreshDebugSnapshot(
                isEnabled: false,
                etag: nil,
                lastFetchAt: nil,
                lastWriteAt: nil,
                lastResult: .disabled
            )
        )
        let repository = BundledJSONKBORepository(
            runtimeState: runtimeState
        )

        return AppRepositoryBundle(
            repository: repository,
            runtimeState: runtimeState
        )
    }
}

struct RepositoryCacheConfiguration: Sendable {
    let bootstrapTTL: TimeInterval
    let gamesTTL: TimeInterval
    let notificationsTTL: TimeInterval
    let monthlyScheduleTTL: TimeInterval
    let diskCacheDirectory: URL?

    init(
        bootstrapTTL: TimeInterval,
        gamesTTL: TimeInterval,
        notificationsTTL: TimeInterval,
        monthlyScheduleTTL: TimeInterval,
        diskCacheDirectory: URL? = nil
    ) {
        self.bootstrapTTL = bootstrapTTL
        self.gamesTTL = gamesTTL
        self.notificationsTTL = notificationsTTL
        self.monthlyScheduleTTL = monthlyScheduleTTL
        self.diskCacheDirectory = diskCacheDirectory
    }

    nonisolated static let `default` = RepositoryCacheConfiguration(
        bootstrapTTL: 15,
        gamesTTL: 12,
        notificationsTTL: 20,
        monthlyScheduleTTL: 300,
        diskCacheDirectory: nil
    )
}

private struct RepositoryCacheEntry<Value: Sendable>: Sendable {
    let value: Value
    let timestamp: Date
}

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
            note: game.note
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

private actor RepositoryDiskCache {
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
            let data = try encoder.encode(value)
            try data.write(to: fileURL, options: .atomic)
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
}

private actor RepositoryResponseCache {
    private let diskCache: RepositoryDiskCache
    private var bootstrapEntry: RepositoryCacheEntry<KBOBootstrapData>?
    private var gamesEntry: RepositoryCacheEntry<[GameDetail]>?
    private var notificationsEntry: RepositoryCacheEntry<[NotificationItem]>?
    private var monthlyScheduleEntries: [KBOMonthScheduleKey: RepositoryCacheEntry<[GameDetail]>] = [:]

    private var bootstrapTask: Task<KBOBootstrapData, Error>?
    private var gamesTask: Task<[GameDetail], Error>?
    private var notificationsTask: Task<[NotificationItem], Error>?
    private var monthlyScheduleTasks: [KBOMonthScheduleKey: Task<[GameDetail], Error>] = [:]

    init(configuration: RepositoryCacheConfiguration) {
        self.diskCache = RepositoryDiskCache(directoryURL: configuration.diskCacheDirectory)
    }

    func bootstrapValue(
        ttl: TimeInterval,
        fetch: @escaping @Sendable () async throws -> KBOBootstrapData
    ) async throws -> (value: KBOBootstrapData, cachedAt: Date, isCacheHit: Bool, isStale: Bool) {
        let now = Date()
        if let bootstrapEntry = await cachedBootstrapEntry(), now.timeIntervalSince(bootstrapEntry.timestamp) < ttl {
            return (bootstrapEntry.value, bootstrapEntry.timestamp, true, false)
        }

        if let bootstrapTask {
            let value = try await bootstrapTask.value
            let cachedAt = bootstrapEntry?.timestamp ?? .now
            return (value, cachedAt, false, false)
        }

        let task = Task {
            let value = try await fetch()
            await self.storeBootstrap(value, timestamp: .now)
            return value
        }
        bootstrapTask = task
        defer { bootstrapTask = nil }

        do {
            let value = try await task.value
            return (value, bootstrapEntry?.timestamp ?? .now, false, false)
        } catch {
            if let bootstrapEntry = await cachedBootstrapEntry() {
                return (bootstrapEntry.value, bootstrapEntry.timestamp, true, true)
            }
            throw error
        }
    }

    func gamesValue(
        ttl: TimeInterval,
        fetch: @escaping @Sendable () async throws -> [GameDetail]
    ) async throws -> (value: [GameDetail], cachedAt: Date, isCacheHit: Bool, isStale: Bool) {
        let now = Date()
        if let gamesEntry = await cachedGamesEntry(), now.timeIntervalSince(gamesEntry.timestamp) < ttl {
            return (gamesEntry.value, gamesEntry.timestamp, true, false)
        }

        if let gamesTask {
            let value = try await gamesTask.value
            let cachedAt = gamesEntry?.timestamp ?? .now
            return (value, cachedAt, false, false)
        }

        let task = Task {
            let value = try await fetch()
            await self.storeGames(value, timestamp: .now)
            return value
        }
        gamesTask = task
        defer { gamesTask = nil }

        do {
            let value = try await task.value
            return (value, gamesEntry?.timestamp ?? .now, false, false)
        } catch {
            if let gamesEntry = await cachedGamesEntry() {
                return (gamesEntry.value, gamesEntry.timestamp, true, true)
            }
            throw error
        }
    }

    func notificationsValue(
        ttl: TimeInterval,
        fetch: @escaping @Sendable () async throws -> [NotificationItem]
    ) async throws -> (value: [NotificationItem], cachedAt: Date, isCacheHit: Bool, isStale: Bool) {
        let now = Date()
        if let notificationsEntry = await cachedNotificationsEntry(), now.timeIntervalSince(notificationsEntry.timestamp) < ttl {
            return (notificationsEntry.value, notificationsEntry.timestamp, true, false)
        }

        if let notificationsTask {
            let value = try await notificationsTask.value
            let cachedAt = notificationsEntry?.timestamp ?? .now
            return (value, cachedAt, false, false)
        }

        let task = Task {
            let value = try await fetch()
            await self.storeNotifications(value, timestamp: .now)
            return value
        }
        notificationsTask = task
        defer { notificationsTask = nil }

        do {
            let value = try await task.value
            return (value, notificationsEntry?.timestamp ?? .now, false, false)
        } catch {
            if let notificationsEntry = await cachedNotificationsEntry() {
                return (notificationsEntry.value, notificationsEntry.timestamp, true, true)
            }
            throw error
        }
    }

    func monthlyScheduleValue(
        for month: KBOMonthScheduleKey,
        ttl: TimeInterval,
        fetch: @escaping @Sendable () async throws -> [GameDetail]
    ) async throws -> (value: [GameDetail], cachedAt: Date, isCacheHit: Bool, isStale: Bool) {
        let now = Date()
        if let entry = await cachedMonthlyScheduleEntry(for: month), now.timeIntervalSince(entry.timestamp) < ttl {
            return (entry.value, entry.timestamp, true, false)
        }

        if let task = monthlyScheduleTasks[month] {
            let value = try await task.value
            let cachedAt = monthlyScheduleEntries[month]?.timestamp ?? .now
            return (value, cachedAt, false, false)
        }

        let task = Task {
            let value = try await fetch()
            await self.storeMonthlySchedule(value, for: month, timestamp: .now)
            return value
        }
        monthlyScheduleTasks[month] = task
        defer { monthlyScheduleTasks[month] = nil }

        do {
            let value = try await task.value
            return (value, monthlyScheduleEntries[month]?.timestamp ?? .now, false, false)
        } catch {
            if let entry = await cachedMonthlyScheduleEntry(for: month) {
                return (entry.value, entry.timestamp, true, true)
            }
            throw error
        }
    }

    func refreshMonthlyScheduleValue(
        for month: KBOMonthScheduleKey,
        fetch: @escaping @Sendable () async throws -> [GameDetail]
    ) async throws -> (value: [GameDetail], cachedAt: Date, isCacheHit: Bool, isStale: Bool) {
        if let task = monthlyScheduleTasks[month] {
            let value = try await task.value
            let cachedAt = monthlyScheduleEntries[month]?.timestamp ?? .now
            return (value, cachedAt, false, false)
        }

        let task = Task {
            let value = try await fetch()
            await self.storeMonthlySchedule(value, for: month, timestamp: .now)
            return value
        }
        monthlyScheduleTasks[month] = task
        defer { monthlyScheduleTasks[month] = nil }

        do {
            let value = try await task.value
            return (value, .now, false, false)
        } catch {
            if let entry = await cachedMonthlyScheduleEntry(for: month) {
                return (entry.value, entry.timestamp, true, true)
            }
            throw error
        }
    }

    private func cachedBootstrapEntry() async -> RepositoryCacheEntry<KBOBootstrapData>? {
        if let bootstrapEntry {
            return bootstrapEntry
        }

        let diskEntry = await diskCache.loadBootstrap()
        bootstrapEntry = diskEntry
        return diskEntry
    }

    private func cachedGamesEntry() async -> RepositoryCacheEntry<[GameDetail]>? {
        if let gamesEntry {
            return gamesEntry
        }

        let diskEntry = await diskCache.loadGames()
        gamesEntry = diskEntry
        return diskEntry
    }

    private func cachedNotificationsEntry() async -> RepositoryCacheEntry<[NotificationItem]>? {
        if let notificationsEntry {
            return notificationsEntry
        }

        let diskEntry = await diskCache.loadNotifications()
        notificationsEntry = diskEntry
        return diskEntry
    }

    private func cachedMonthlyScheduleEntry(for month: KBOMonthScheduleKey) async -> RepositoryCacheEntry<[GameDetail]>? {
        if let entry = monthlyScheduleEntries[month] {
            return entry
        }

        let diskEntry = await diskCache.loadMonthlySchedule(for: month)
        monthlyScheduleEntries[month] = diskEntry
        return diskEntry
    }

    private func storeBootstrap(_ value: KBOBootstrapData, timestamp: Date) async {
        bootstrapEntry = RepositoryCacheEntry(value: value, timestamp: timestamp)
        await diskCache.storeBootstrap(value, timestamp: timestamp)
    }

    private func storeGames(_ value: [GameDetail], timestamp: Date) async {
        gamesEntry = RepositoryCacheEntry(value: value, timestamp: timestamp)
        await diskCache.storeGames(value, timestamp: timestamp)
    }

    private func storeNotifications(_ value: [NotificationItem], timestamp: Date) async {
        notificationsEntry = RepositoryCacheEntry(value: value, timestamp: timestamp)
        await diskCache.storeNotifications(value, timestamp: timestamp)
    }

    private func storeMonthlySchedule(_ value: [GameDetail], for month: KBOMonthScheduleKey, timestamp: Date) async {
        monthlyScheduleEntries[month] = RepositoryCacheEntry(value: value, timestamp: timestamp)
        await diskCache.storeMonthlySchedule(value, for: month, timestamp: timestamp)
    }
}

struct AnyKBORepository: KBORepository, Sendable {
    private let fetchBootstrapDataBlock: @Sendable () async throws -> KBOBootstrapData
    private let fetchGamesBlock: @Sendable () async throws -> [GameDetail]
    private let fetchNotificationsBlock: @Sendable () async throws -> [NotificationItem]
    private let fetchMonthlyScheduleBlock: @Sendable (KBOMonthScheduleKey) async throws -> [GameDetail]
    private let fetchStandingsBlock: @Sendable () async throws -> [TeamStandingsSnapshot]

    init(_ base: any KBORepository) {
        fetchBootstrapDataBlock = { try await base.fetchBootstrapData() }
        fetchGamesBlock = { try await base.fetchGames() }
        fetchNotificationsBlock = { try await base.fetchNotifications() }
        fetchMonthlyScheduleBlock = { month in try await base.fetchMonthlySchedule(for: month) }
        fetchStandingsBlock = { try await base.fetchStandings() }
    }

    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        try await fetchBootstrapDataBlock()
    }

    nonisolated func fetchGames() async throws -> [GameDetail] {
        try await fetchGamesBlock()
    }

    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        try await fetchNotificationsBlock()
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        try await fetchMonthlyScheduleBlock(month)
    }

    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        try await fetchStandingsBlock()
    }
}

struct RuntimeStateReportingRepository<Base: KBORepository>: KBORepository, Sendable {
    let base: Base
    let source: RepositoryDataSourceKind
    let delivery: RepositoryDeliverySourceKind
    let runtimeState: RepositoryRuntimeState?

    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        let value = try await base.fetchBootstrapData()
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }

    nonisolated func fetchGames() async throws -> [GameDetail] {
        let value = try await base.fetchGames()
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }

    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        let value = try await base.fetchNotifications()
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        let value = try await base.fetchMonthlySchedule(for: month)
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }

    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        let value = try await base.fetchStandings()
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }
}

struct CachedKBORepository<Base: KBORepository>: KBORepository, Sendable {
    let base: Base
    let configuration: RepositoryCacheConfiguration
    let runtimeState: RepositoryRuntimeState?

    private let cache: RepositoryResponseCache

    init(
        base: Base,
        configuration: RepositoryCacheConfiguration,
        runtimeState: RepositoryRuntimeState?
    ) {
        self.base = base
        self.configuration = configuration
        self.runtimeState = runtimeState
        self.cache = RepositoryResponseCache(configuration: configuration)
    }

    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        let result = try await cache.bootstrapValue(ttl: configuration.bootstrapTTL) {
            try await base.fetchBootstrapData()
        }
        if result.isCacheHit {
            await runtimeState?.recordCacheHit(refreshedAt: result.cachedAt, isStale: result.isStale)
        }
        return result.value
    }

    nonisolated func fetchGames() async throws -> [GameDetail] {
        let result = try await cache.gamesValue(ttl: configuration.gamesTTL) {
            try await base.fetchGames()
        }
        if result.isCacheHit {
            await runtimeState?.recordCacheHit(refreshedAt: result.cachedAt, isStale: result.isStale)
        }
        return result.value
    }

    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        let result = try await cache.notificationsValue(ttl: configuration.notificationsTTL) {
            try await base.fetchNotifications()
        }
        if result.isCacheHit {
            await runtimeState?.recordCacheHit(refreshedAt: result.cachedAt, isStale: result.isStale)
        }
        return result.value
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        let result = try await cache.monthlyScheduleValue(for: month, ttl: configuration.monthlyScheduleTTL) {
            try await base.fetchMonthlySchedule(for: month)
        }
        if result.isCacheHit {
            await runtimeState?.recordCacheHit(refreshedAt: result.cachedAt, isStale: result.isStale)
#if DEBUG
            print("[RepositorySource] monthlySchedule source=monthly cache month=\(month.yearMonthText) stale=\(result.isStale) count=\(result.value.count)")
#endif
        }
        return result.value
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey, bypassingCache: Bool) async throws -> [GameDetail] {
        guard bypassingCache else {
            return try await fetchMonthlySchedule(for: month)
        }

        let result = try await cache.refreshMonthlyScheduleValue(for: month) {
            try await base.fetchMonthlySchedule(for: month, bypassingCache: true)
        }
        if result.isCacheHit {
            await runtimeState?.recordCacheHit(refreshedAt: result.cachedAt, isStale: result.isStale)
#if DEBUG
            print("[RepositorySource] monthlySchedule source=monthly cache month=\(month.yearMonthText) stale=true count=\(result.value.count)")
#endif
        } else {
#if DEBUG
            print("[RepositorySource] monthlySchedule source=live backend month=\(month.yearMonthText) count=\(result.value.count)")
#endif
        }
        return result.value
    }

    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        try await base.fetchStandings()
    }
}

struct BootstrapRefreshingKBORepository<Base: KBORepository>: KBORepository, Sendable {
    let base: Base
    let localBootstrapRepository: BundledJSONKBORepository
    let bootstrapBaseURL: URL
    let session: URLSession
    let runtimeState: RepositoryRuntimeState?
    let stateStore: BootstrapRefreshStateStore
    let fileManager: FileManager
    private let nowProvider: @Sendable () -> Date

    init(
        base: Base,
        localBootstrapRepository: BundledJSONKBORepository,
        bootstrapBaseURL: URL,
        session: URLSession = .shared,
        runtimeState: RepositoryRuntimeState? = nil,
        stateStore: BootstrapRefreshStateStore,
        fileManager: FileManager = .default,
        nowProvider: @escaping @Sendable () -> Date = { .now }
    ) {
        self.base = base
        self.localBootstrapRepository = localBootstrapRepository
        self.bootstrapBaseURL = bootstrapBaseURL
        self.session = session
        self.runtimeState = runtimeState
        self.stateStore = stateStore
        self.fileManager = fileManager
        self.nowProvider = nowProvider
    }

    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        await refreshBootstrapSnapshotIfNeeded()
        let value = try await localBootstrapRepository.fetchBootstrapData()
#if DEBUG
        let snapshot = stateStore.load(isEnabled: true)
        print(
            "[RepositorySource] bootstrap source=LocalBootstrapData.json " +
            "refreshResult=\(snapshot.lastResult.rawValue) teams=\(value.teams.count) games=\(value.games.count)"
        )
#endif
        return value
    }

    nonisolated func fetchGames() async throws -> [GameDetail] {
        try await base.fetchGames()
    }

    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        try await base.fetchNotifications()
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        try await base.fetchMonthlySchedule(for: month)
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey, bypassingCache: Bool) async throws -> [GameDetail] {
        try await base.fetchMonthlySchedule(for: month, bypassingCache: bypassingCache)
    }

    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        try await base.fetchStandings()
    }

    private func refreshBootstrapSnapshotIfNeeded() async {
        let fetchedAt = nowProvider()
        let existingSnapshot = stateStore.load(isEnabled: true)
        var request: URLRequest

        do {
            request = try makeBootstrapRequest(etag: existingSnapshot.etag)
        } catch {
            let failedSnapshot = BootstrapRefreshDebugSnapshot(
                isEnabled: true,
                etag: existingSnapshot.etag,
                lastFetchAt: fetchedAt,
                lastWriteAt: existingSnapshot.lastWriteAt,
                lastResult: .failed
            )
            stateStore.save(failedSnapshot)
            await runtimeState?.recordBootstrapRefresh(failedSnapshot)
            return
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LiveRepositoryError.invalidResponse(endpoint: "v1/bootstrap")
            }

            switch httpResponse.statusCode {
            case 200:
                try await handleUpdatedBootstrapResponse(
                    data: data,
                    response: httpResponse,
                    fetchedAt: fetchedAt
                )
            case 304:
                let snapshot = BootstrapRefreshDebugSnapshot(
                    isEnabled: true,
                    etag: httpResponse.value(forHTTPHeaderField: "ETag") ?? existingSnapshot.etag,
                    lastFetchAt: fetchedAt,
                    lastWriteAt: existingSnapshot.lastWriteAt,
                    lastResult: .notModified
                )
                stateStore.save(snapshot)
                await runtimeState?.recordBootstrapRefresh(snapshot)
            default:
                throw LiveRepositoryError.httpStatus(code: httpResponse.statusCode, endpoint: "v1/bootstrap")
            }
        } catch {
            let failedSnapshot = BootstrapRefreshDebugSnapshot(
                isEnabled: true,
                etag: existingSnapshot.etag,
                lastFetchAt: fetchedAt,
                lastWriteAt: existingSnapshot.lastWriteAt,
                lastResult: .failed
            )
            stateStore.save(failedSnapshot)
            await runtimeState?.recordBootstrapRefresh(failedSnapshot)
#if DEBUG
            print("[BootstrapRefresh] refresh failed error=\(error)")
#endif
        }
    }

    private func handleUpdatedBootstrapResponse(
        data: Data,
        response: HTTPURLResponse,
        fetchedAt: Date
    ) async throws {
        _ = try BundledJSONKBORepository.decodeBootstrapData(from: data)
        guard let fileURL = localBootstrapRepository.localBootstrapFileURL else {
            throw LiveRepositoryError.invalidBaseURL
        }

        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: fileURL, options: .atomic)

        let snapshot = BootstrapRefreshDebugSnapshot(
            isEnabled: true,
            etag: response.value(forHTTPHeaderField: "ETag"),
            lastFetchAt: fetchedAt,
            lastWriteAt: fetchedAt,
            lastResult: .updated
        )
        stateStore.save(snapshot)
        await runtimeState?.recordBootstrapRefresh(snapshot)
    }

    private func makeBootstrapRequest(etag: String?) throws -> URLRequest {
        guard let url = URL(string: "v1/bootstrap", relativeTo: normalizedBaseURL)?.absoluteURL else {
            throw LiveRepositoryError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag, etag.isEmpty == false {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
#if DEBUG
        print("[LiveAPI] request endpoint=v1/bootstrap method=GET url=\(url.absoluteString)")
#endif
        return request
    }

    private var normalizedBaseURL: URL {
        if bootstrapBaseURL.absoluteString.hasSuffix("/") {
            return bootstrapBaseURL
        }
        return URL(string: bootstrapBaseURL.absoluteString + "/") ?? bootstrapBaseURL
    }
}

struct LiveKBORepository: KBORepository, Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let runtimeState: RepositoryRuntimeState?
    private let nowProvider: @Sendable () -> Date

    init(
        baseURL: URL,
        session: URLSession = .shared,
        runtimeState: RepositoryRuntimeState? = nil,
        nowProvider: @escaping @Sendable () -> Date = { .now }
    ) {
        if baseURL.absoluteString.hasSuffix("/") {
            self.baseURL = baseURL
        } else {
            self.baseURL = URL(string: baseURL.absoluteString + "/") ?? baseURL
        }
        self.session = session
        self.runtimeState = runtimeState
        self.nowProvider = nowProvider
    }

    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        if isOfficialKBOHost {
            let payload = try await fetchNormalizedPayload(.games).asBootstrapDTO()
            await runtimeState?.record(source: .live, delivery: .live)
            return KBODataMapper.mapBootstrap(
                KBOBootstrapDTO(
                    teams: payload.teams,
                    games: payload.games,
                    notifications: [],
                    settings: nil
                )
            )
        }

        do {
            let payload = try await fetchNormalizedPayload(.bootstrap).asBootstrapDTO()
            await runtimeState?.record(source: .live, delivery: .live)
            return KBODataMapper.mapBootstrap(payload)
        } catch {
            #if DEBUG
            print("[LiveAPI] bootstrap primary endpoint failed. falling back to monthly schedule. error=\(error)")
            #endif

            let month = KBOMonthScheduleKey(date: nowProvider())
            let fallbackPayload = try await fetchNormalizedPayload(.monthlySchedule(month))
            let fallbackBootstrap = KBOBootstrapDTO(
                teams: fallbackPayload.teams,
                games: fallbackPayload.games,
                notifications: [],
                settings: nil
            )
            #if DEBUG
            print("[LiveAPI] bootstrap fallback active endpoint=api/v1/games/month month=\(month.year)-\(month.month)")
            #endif
            await runtimeState?.record(source: .live, delivery: .live)
            return KBODataMapper.mapBootstrap(fallbackBootstrap)
        }
    }

    nonisolated func fetchGames() async throws -> [GameDetail] {
        let payload = try await fetchNormalizedPayload(.games)
        let teams = payload.teams.isEmpty ? try await fetchTeams() : payload.teams.map(KBODataMapper.mapTeam)
        await runtimeState?.record(source: .live, delivery: .live)
        return KBODataMapper.mapGames(payload.games, teams: teams)
    }

    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        let payload = try await fetchNormalizedPayload(.notifications)
        await runtimeState?.record(source: .live, delivery: .live)
        return KBODataMapper.mapNotifications(payload.notifications)
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        let payload = try await fetchNormalizedPayload(.monthlySchedule(month))
        let teams = payload.teams.isEmpty ? try await fetchTeams() : payload.teams.map(KBODataMapper.mapTeam)
        await runtimeState?.record(source: .live, delivery: .live)
        return KBODataMapper.mapGames(payload.games, teams: teams)
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        let request = try makeRequest(for: .standings)
#if DEBUG
        logRequest(request, endpoint: .standings)
#endif
        let (data, response) = try await session.data(for: request)
        try validate(response: response, endpoint: .standings)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(KBOStandingsResponseDTO.self, from: data)
        let teams = try await fetchTeams()
        await runtimeState?.record(source: .live, delivery: .live)
        return KBODataMapper.mapStandings(payload, teams: teams)
    }

    private func fetchTeams() async throws -> [Team] {
        let payload = try await fetchNormalizedPayload(.teams)
        return payload.teams.map(KBODataMapper.mapTeam)
    }

    private func fetchNormalizedPayload(_ endpoint: Endpoint) async throws -> KBOExternalNormalizedPayload {
        let request = try makeRequest(for: endpoint)
        #if DEBUG
        logRequest(request, endpoint: endpoint)
        #endif
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            #if DEBUG
            print("[LiveAPI] transportError endpoint=\(endpoint.path) error=\(error)")
            #endif
            throw error
        }
        #if DEBUG
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        let preview = rawBody.count > 4_000 ? String(rawBody.prefix(4_000)) + "...(truncated)" : rawBody
        print("[LiveAPI] response endpoint=\(endpoint.path) status=\(statusCode)")
        print("[LiveAPI] rawResponseBody endpoint=\(endpoint.path) body=\(preview)")
        #endif
        try validate(response: response, endpoint: endpoint)

        do {
            let payload = try KBOExternalResponseAdapter.normalize(data: data)
            #if DEBUG
            print(
                "[LiveAPI] decoded endpoint=\(endpoint.path) teams=\(payload.teams.count) games=\(payload.games.count) notifications=\(payload.notifications.count)"
            )
            #endif
            return payload
        } catch {
            #if DEBUG
            print("[LiveAPI] decodingError endpoint=\(endpoint.path) error=\(error)")
            #endif
            throw LiveRepositoryError.decoding(endpoint: endpoint.path, underlying: error)
        }
    }

    nonisolated private func makeRequest(for endpoint: Endpoint) throws -> URLRequest {
        switch endpoint {
        case .games where isOfficialKBOHost:
            let contract = try OfficialKBOLiveGamesRequestContract(baseURL: baseURL, date: nowProvider())
            guard let url = contract.url else {
                throw LiveRepositoryError.invalidBaseURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue(contract.contentType, forHTTPHeaderField: "Content-Type")
            request.setValue(contract.accept, forHTTPHeaderField: "Accept")
            request.setValue(contract.requestedWith, forHTTPHeaderField: "X-Requested-With")
            request.httpBody = contract.bodyData
            return request
        case .monthlySchedule(let month) where isOfficialKBOHost:
            let contract = try OfficialKBOMonthlyScheduleRequestContract(baseURL: baseURL, month: month)
            guard let url = contract.url else {
                throw LiveRepositoryError.invalidBaseURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue(contract.contentType, forHTTPHeaderField: "Content-Type")
            request.setValue(contract.accept, forHTTPHeaderField: "Accept")
            request.setValue(contract.requestedWith, forHTTPHeaderField: "X-Requested-With")
            request.httpBody = contract.bodyData
            return request
        default:
            guard let url = URL(string: endpoint.path, relativeTo: baseURL)?.absoluteURL else {
                throw LiveRepositoryError.invalidBaseURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            return request
        }
    }

    nonisolated private var isOfficialKBOHost: Bool {
        baseURL.host?.contains("koreabaseball.com") == true
    }

    nonisolated private func validate(response: URLResponse, endpoint: Endpoint) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LiveRepositoryError.invalidResponse(endpoint: endpoint.path)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw LiveRepositoryError.httpStatus(code: httpResponse.statusCode, endpoint: endpoint.path)
        }
    }

#if DEBUG
    nonisolated private func logRequest(_ request: URLRequest, endpoint: Endpoint) {
        let method = request.httpMethod ?? "GET"
        let urlText = request.url?.absoluteString ?? "nil"
        print("[LiveAPI] request endpoint=\(endpoint.path) method=\(method) url=\(urlText)")
    }
#endif

    private enum Endpoint {
        case bootstrap
        case games
        case notifications
        case standings
        case teams
        case monthlySchedule(KBOMonthScheduleKey)

        nonisolated var path: String {
            switch self {
            case .bootstrap:
                "v1/bootstrap"
            case .games:
                "v1/games"
            case .notifications:
                "notifications"
            case .standings:
                "v1/standings"
            case .teams:
                "v1/teams"
            case .monthlySchedule(let month):
                "api/v1/games/month?year=\(month.year)&month=\(month.month)"
            }
        }
    }
}

struct OfficialKBOMonthlyScheduleRequestContract: Sendable {
    let month: KBOMonthScheduleKey
    let url: URL?

    let contentType = "application/x-www-form-urlencoded; charset=UTF-8"
    let accept = "application/json"
    let requestedWith = "XMLHttpRequest"

    nonisolated init(baseURL: URL, month: KBOMonthScheduleKey) throws {
        self.month = month
        self.url = URL(string: "ws/Schedule.asmx/GetScheduleList", relativeTo: baseURL)?.absoluteURL
        if url == nil {
            throw LiveRepositoryError.invalidBaseURL
        }
    }

    nonisolated var seriesIDList: String {
        month.month == 3 ? "0,9" : "0"
    }

    nonisolated var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "leId", value: "1"),
            URLQueryItem(name: "srIdList", value: seriesIDList),
            URLQueryItem(name: "seasonId", value: String(month.year)),
            URLQueryItem(name: "gameMonth", value: String(format: "%02d", month.month)),
            URLQueryItem(name: "teamId", value: "")
        ]
    }

    nonisolated var bodyString: String {
        var components = URLComponents()
        components.queryItems = queryItems
        return components.percentEncodedQuery ?? ""
    }

    nonisolated var bodyData: Data {
        Data(bodyString.utf8)
    }
}

struct OfficialKBOLiveGamesRequestContract: Sendable {
    let date: Date
    let url: URL?

    let contentType = "application/x-www-form-urlencoded; charset=UTF-8"
    let accept = "application/json"
    let requestedWith = "XMLHttpRequest"

    nonisolated init(baseURL: URL, date: Date) throws {
        self.date = date
        self.url = URL(string: "ws/Main.asmx/GetKboGameList", relativeTo: baseURL)?.absoluteURL
        if url == nil {
            throw LiveRepositoryError.invalidBaseURL
        }
    }

    nonisolated var seriesIDList: String {
        if kboDate >= "20241026" {
            return "0,1,3,4,5,6,7,8,9"
        }
        if kboDate.prefix(4) >= "2021" {
            return "0,1,3,4,5,6,7,9"
        }
        return "0,1,3,4,5,7,9"
    }

    nonisolated var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "leId", value: "1"),
            URLQueryItem(name: "srId", value: seriesIDList),
            URLQueryItem(name: "date", value: kboDate)
        ]
    }

    nonisolated var bodyString: String {
        var components = URLComponents()
        components.queryItems = queryItems
        return components.percentEncodedQuery ?? ""
    }

    nonisolated var bodyData: Data {
        Data(bodyString.utf8)
    }

    nonisolated private var kboDate: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }
}

struct FallbackKBORepository<Primary: KBORepository, Fallback: KBORepository>: KBORepository, Sendable {
    let primary: Primary
    let fallback: Fallback
    let runtimeState: RepositoryRuntimeState?

    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        do {
            return try await primary.fetchBootstrapData()
        } catch {
            let result = try await fallback.fetchBootstrapData()
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    nonisolated func fetchGames() async throws -> [GameDetail] {
        do {
            return try await primary.fetchGames()
        } catch {
            let result = try await fallback.fetchGames()
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        do {
            return try await primary.fetchNotifications()
        } catch {
            let result = try await fallback.fetchNotifications()
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        do {
            return try await primary.fetchMonthlySchedule(for: month)
        } catch {
            let result = try await fallback.fetchMonthlySchedule(for: month)
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey, bypassingCache: Bool) async throws -> [GameDetail] {
        do {
            return try await primary.fetchMonthlySchedule(for: month, bypassingCache: bypassingCache)
        } catch {
            let result = try await fallback.fetchMonthlySchedule(for: month, bypassingCache: bypassingCache)
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        do {
            return try await primary.fetchStandings()
        } catch {
            let result = try await fallback.fetchStandings()
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }
}

enum LiveRepositoryError: LocalizedError, Sendable {
    case invalidBaseURL
    case invalidResponse(endpoint: String)
    case httpStatus(code: Int, endpoint: String)
    case decoding(endpoint: String, underlying: Error)

    var isDecodingFailure: Bool {
        if case .decoding = self {
            return true
        }
        return false
    }
}
