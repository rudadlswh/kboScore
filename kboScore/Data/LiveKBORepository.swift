//
//  LiveKBORepository.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import Foundation

private enum RepositoryFileSecurity {
    nonisolated static let protectionType = FileProtectionType.completeUntilFirstUserAuthentication

    nonisolated static func applyProtection(
        to fileURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.setAttributes(
            [.protectionKey: protectionType],
            ofItemAtPath: fileURL.path
        )
    }

    nonisolated static func applyProtection(
        toDirectory directoryURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.setAttributes(
            [.protectionKey: protectionType],
            ofItemAtPath: directoryURL.path
        )
    }

    nonisolated static func excludeFromBackup(_ fileURL: URL) throws {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableFileURL = fileURL
        try mutableFileURL.setResourceValues(resourceValues)
    }
}

enum RepositoryDataSourceKind: String, Sendable {
    case supabase = "Supabase"
    case mock = "목 데이터"
    case live = "실데이터"
    case mockFallback = "목 데이터 폴백"
}

enum RepositoryDeliverySourceKind: String, Sendable {
    case supabase = "Supabase 응답"
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

struct BootstrapRefreshStateStore: Sendable {
    nonisolated(unsafe) private let defaults: UserDefaults
    private let storageKey: String

    init(
        baseURL: URL,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.storageKey = "kbo_live_bootstrap_refresh_state::\(baseURL.absoluteString)"
    }

    nonisolated func load(isEnabled: Bool) -> BootstrapRefreshDebugSnapshot {
        guard let data = defaults.data(forKey: storageKey),
              let persisted = persistedState(from: data) else {
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

    nonisolated func save(_ snapshot: BootstrapRefreshDebugSnapshot) {
        guard let data = encodedState(from: snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }

    nonisolated private func persistedState(from data: Data) -> (
        etag: String?,
        lastFetchAt: Date?,
        lastWriteAt: Date?,
        lastResult: BootstrapRefreshResultKind
    )? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let lastResultText = root["lastResult"] as? String
        let lastResult = lastResultText.flatMap(BootstrapRefreshResultKind.init(rawValue:)) ?? .idle

        return (
            etag: root["etag"] as? String,
            lastFetchAt: Self.parseDate(root["lastFetchAt"] as? String),
            lastWriteAt: Self.parseDate(root["lastWriteAt"] as? String),
            lastResult: lastResult
        )
    }

    nonisolated private func encodedState(from snapshot: BootstrapRefreshDebugSnapshot) -> Data? {
        var root: [String: Any] = [
            "lastResult": snapshot.lastResult.rawValue
        ]
        if let etag = snapshot.etag {
            root["etag"] = etag
        }
        if let lastFetchAt = snapshot.lastFetchAt {
            root["lastFetchAt"] = Self.formatDate(lastFetchAt)
        }
        if let lastWriteAt = snapshot.lastWriteAt {
            root["lastWriteAt"] = Self.formatDate(lastWriteAt)
        }
        return try? JSONSerialization.data(withJSONObject: root, options: [])
    }

    nonisolated private static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    nonisolated private static func parseDate(_ value: String?) -> Date? {
        guard let value, value.isEmpty == false else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: value) {
            return parsed
        }

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        return fallbackFormatter.date(from: value)
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
            case .supabase:
                .supabase
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
    let supabaseConfiguration: SupabaseConfiguration?

    nonisolated init(
        backendBaseURL: URL? = nil,
        supabaseConfiguration: SupabaseConfiguration?
    ) {
        _ = backendBaseURL
        self.supabaseConfiguration = supabaseConfiguration
    }

    nonisolated static func fromEnvironment(
        processInfo: ProcessInfo = .processInfo,
        bundle: Bundle = .main
    ) -> AppRepositoryConfiguration {
        let supabaseEnvironmentValue = processInfo.environment["SUPABASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let supabaseInfoDictionaryValue = (bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let supabaseKeyEnvironmentValue = processInfo.environment["SUPABASE_PUBLISHABLE_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let supabaseKeyInfoDictionaryValue = (bundle.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let supabaseConfiguration = firstValidSupabaseConfiguration(
            candidates: [
                (url: supabaseEnvironmentValue, publishableKey: supabaseKeyEnvironmentValue),
                (url: supabaseInfoDictionaryValue, publishableKey: supabaseKeyInfoDictionaryValue)
            ]
        )
#if DEBUG
        print("[SupabaseConfig] environmentURLPresent=\(hasValue(supabaseEnvironmentValue))")
        print("[SupabaseConfig] plistURLPresent=\(hasValue(supabaseInfoDictionaryValue))")
        print("[SupabaseConfig] environmentKeyPresent=\(hasValue(supabaseKeyEnvironmentValue))")
        print("[SupabaseConfig] plistKeyPresent=\(hasValue(supabaseKeyInfoDictionaryValue))")
        print("[SupabaseConfig] finalRuntimeHost=\(debugHostValue(supabaseConfiguration))")
#endif
        return AppRepositoryConfiguration(
            supabaseConfiguration: supabaseConfiguration
        )
    }

    private nonisolated static func backendURL(from rawValue: String?) -> URL? {
        guard let rawValue,
              let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              host.isEmpty == false else {
            return nil
        }
#if DEBUG
        guard ["http", "https"].contains(scheme) else {
            return nil
        }
#else
        guard scheme == "https",
              releaseApprovedHosts.contains(host) else {
            return nil
        }
#endif
        return url
    }

    private nonisolated static func firstValidSupabaseConfiguration(
        candidates: [(url: String?, publishableKey: String?)]
    ) -> SupabaseConfiguration? {
        for candidate in candidates {
            if let configuration = supabaseConfiguration(
                urlRawValue: candidate.url,
                publishableKeyRawValue: candidate.publishableKey
            ) {
                return configuration
            }
        }
        return nil
    }

#if !DEBUG
    private nonisolated static let releaseApprovedHosts: Set<String> = [
        "pbfancqzynkialupleys.supabase.co"
    ]
#endif

    private nonisolated static func supabaseConfiguration(
        urlRawValue: String?,
        publishableKeyRawValue: String?
    ) -> SupabaseConfiguration? {
        guard let url = backendURL(from: urlRawValue),
              let publishableKey = publishableKeyRawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              publishableKey.isEmpty == false else {
            return nil
        }
        return SupabaseConfiguration(url: url, publishableKey: publishableKey)
    }

#if DEBUG
    private nonisolated static func hasValue(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        return value.isEmpty == false
    }

    private nonisolated static func debugHostValue(_ configuration: SupabaseConfiguration?) -> String {
        configuration?.url.host ?? "<none>"
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
        let runtimeState = RepositoryRuntimeState(
            activeSource: configuration.supabaseConfiguration == nil ? .mock : .supabase,
            baseURL: configuration.supabaseConfiguration?.url.absoluteString,
            deliverySource: configuration.supabaseConfiguration == nil ? .mock : .supabase,
            bootstrapRefreshSnapshot: BootstrapRefreshDebugSnapshot(
                isEnabled: false,
                etag: nil,
                lastFetchAt: nil,
                lastWriteAt: nil,
                lastResult: .disabled
            )
        )
        let repository = BundledJSONKBORepository(
            runtimeState: runtimeState,
            runtimeSource: configuration.supabaseConfiguration == nil ? .mock : .mockFallback,
            runtimeDelivery: configuration.supabaseConfiguration == nil ? .mock : .mockFallback
        )
        let wrappedRepository = makeSupabaseWrappedRepository(
            baseRepository: repository,
            configuration: configuration,
            runtimeState: runtimeState
        )
        let startupOptimizedRepository: any KBORepository
        if configuration.supabaseConfiguration != nil {
            let cached = CachedKBORepository(
                base: AnyKBORepository(wrappedRepository),
                configuration: .supabaseStartup,
                runtimeState: runtimeState
            )
            startupOptimizedRepository = AnyKBORepository(cached)
        } else {
            startupOptimizedRepository = wrappedRepository
        }

        return AppRepositoryBundle(
            repository: startupOptimizedRepository,
            runtimeState: runtimeState
        )
    }

    private static func makeSupabaseWrappedRepository<Base: KBORepository>(
        baseRepository: Base,
        configuration: AppRepositoryConfiguration,
        runtimeState: RepositoryRuntimeState?
    ) -> any KBORepository {
        guard let supabaseConfiguration = configuration.supabaseConfiguration else {
            return baseRepository
        }

        #if canImport(Supabase)
        #if DEBUG
        print("[SupabaseConfig] supabase-swift linked=true")
        print("[SupabaseKBO] enabled=true host=\(supabaseConfiguration.url.host ?? "<none>")")
        #endif
        let repository = SupabaseBackedKBORepository(
            base: baseRepository,
            source: SupabaseKBORepository(configuration: supabaseConfiguration),
            runtimeState: runtimeState
        )
        return AnyKBORepository(repository)
        #else
        #if DEBUG
        print("[SupabaseConfig] configuration present but supabase-swift is not linked. Falling back to local bundled repository.")
        #endif
        return baseRepository
        #endif
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
        monthlyScheduleTTL: 60 * 60 * 24,
        diskCacheDirectory: nil
    )

    nonisolated static let supabaseStartup = RepositoryCacheConfiguration(
        bootstrapTTL: 60 * 10,
        gamesTTL: 20,
        notificationsTTL: 20,
        monthlyScheduleTTL: 60 * 60 * 24,
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

private actor RepositoryResponseCache {
    private let diskCache: RepositoryDiskCache
    private var bootstrapEntry: RepositoryCacheEntry<KBOBootstrapData>?
    private var gamesEntry: RepositoryCacheEntry<[GameDetail]>?
    private var notificationsEntry: RepositoryCacheEntry<[NotificationItem]>?
    private var monthlyScheduleEntries: [KBOMonthScheduleKey: RepositoryCacheEntry<[GameDetail]>] = [:]
    private var teamRankEntries: [Int: RepositoryCacheEntry<[TeamRankRow]>] = [:]

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

    func upsertGames(_ incomingGames: [GameDetail]) async -> (inserted: Int, updated: Int, skippedExisting: Int) {
        guard incomingGames.isEmpty == false else {
            return (0, 0, 0)
        }

        let now = Date()
        let existingGames = (await cachedGamesEntry())?.value ?? []
        let result = Self.upsert(incomingGames: incomingGames, into: existingGames)
        await storeGames(result.games.sorted { $0.scheduledStart > $1.scheduledStart }, timestamp: now)

        if let bootstrapEntry = await cachedBootstrapEntry() {
            let bootstrapResult = Self.upsert(incomingGames: incomingGames, into: bootstrapEntry.value.games)
            let updatedBootstrap = KBOBootstrapData(
                teams: bootstrapEntry.value.teams,
                games: bootstrapResult.games.sorted { $0.scheduledStart > $1.scheduledStart },
                notifications: bootstrapEntry.value.notifications,
                settings: bootstrapEntry.value.settings
            )
            await storeBootstrap(updatedBootstrap, timestamp: now)
        }

        let affectedMonths = Set(incomingGames.map { KBOMonthScheduleKey(date: $0.scheduledStart) })
        for month in affectedMonths {
            if let monthlyEntry = await cachedMonthlyScheduleEntry(for: month) {
                let monthlyResult = Self.upsert(incomingGames: incomingGames, into: monthlyEntry.value)
                await storeMonthlySchedule(
                    monthlyResult.games.sorted { $0.scheduledStart < $1.scheduledStart },
                    for: month,
                    timestamp: now
                )
            }
        }

        return (result.inserted, result.updated, result.skippedExisting)
    }

    func localTeamRanks(season: Int) async -> [TeamRankRow] {
        let rows = await cachedTeamRankEntry(season: season)?.value ?? []
        return rows.sorted { $0.rank < $1.rank }
    }

    func replaceTeamRanks(_ ranks: [TeamRankRow], season: Int) async -> Int {
        let sorted = ranks.sorted { $0.rank < $1.rank }
        await storeTeamRanks(sorted, season: season, timestamp: .now)
        return sorted.count
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

    private func cachedTeamRankEntry(season: Int) async -> RepositoryCacheEntry<[TeamRankRow]>? {
        if let entry = teamRankEntries[season] {
            return entry
        }

        let diskEntry = await diskCache.loadTeamRanks(season: season)
        teamRankEntries[season] = diskEntry
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

    private func storeTeamRanks(_ value: [TeamRankRow], season: Int, timestamp: Date) async {
        teamRankEntries[season] = RepositoryCacheEntry(value: value, timestamp: timestamp)
        await diskCache.storeTeamRanks(value, season: season, timestamp: timestamp)
    }

    private static func upsert(
        incomingGames: [GameDetail],
        into existingGames: [GameDetail]
    ) -> (games: [GameDetail], inserted: Int, updated: Int, skippedExisting: Int) {
        var updatedGames = existingGames
        var inserted = 0
        var updated = 0
        var skippedExisting = 0

        for candidate in incomingGames {
            let candidateAliases = candidate.gameIdentityAliases
            if let existingIndex = updatedGames.firstIndex(where: { existing in
                existing.gameIdentityAliases.isDisjoint(with: candidateAliases) == false
            }) {
                let merged = merge(existing: updatedGames[existingIndex], candidate: candidate)
                if merged != updatedGames[existingIndex] {
                    updatedGames[existingIndex] = merged
                    updated += 1
                } else {
                    skippedExisting += 1
                }
            } else {
                updatedGames.append(candidate)
                inserted += 1
            }
        }

        return (updatedGames, inserted, updated, skippedExisting)
    }

    private static func merge(existing: GameDetail, candidate: GameDetail) -> GameDetail {
        let stateSource = preferredStateSource(existing: existing, candidate: candidate)
        let supplementalSource = stateSource == candidate ? existing : candidate

        return GameDetail(
            id: existing.id,
            scheduledStart: stateSource.scheduledStart,
            venue: nonBlank(candidate.venue) ?? existing.venue,
            awayTeam: preferredTeam(candidate.awayTeam, fallback: existing.awayTeam),
            homeTeam: preferredTeam(candidate.homeTeam, fallback: existing.homeTeam),
            awayScore: stateSource.awayScore ?? supplementalSource.awayScore,
            homeScore: stateSource.homeScore ?? supplementalSource.homeScore,
            status: stateSource.status,
            seasonClassification: stateSource.seasonClassification == .unknown ? existing.seasonClassification : stateSource.seasonClassification,
            inningText: nonBlank(stateSource.inningText) ?? supplementalSource.inningText,
            bases: stateSource.bases,
            balls: stateSource.balls,
            strikes: stateSource.strikes,
            outs: stateSource.outs,
            highlightText: nonBlank(candidate.highlightText) ?? existing.highlightText,
            events: candidate.events.isEmpty ? existing.events : candidate.events,
            note: mergedNote(existing: existing.note, candidate: candidate.note),
            providerGameID: nonBlank(candidate.providerGameID) ?? existing.providerGameID,
            awayStartingPitcherName: nonBlank(candidate.awayStartingPitcherName) ?? existing.awayStartingPitcherName,
            homeStartingPitcherName: nonBlank(candidate.homeStartingPitcherName) ?? existing.homeStartingPitcherName,
            currentPitcherName: nonBlank(stateSource.currentPitcherName),
            currentBatterName: nonBlank(stateSource.currentBatterName)
        )
    }

    private static func preferredStateSource(existing: GameDetail, candidate: GameDetail) -> GameDetail {
        let candidatePriority = statePriority(candidate)
        let existingPriority = statePriority(existing)
        if candidatePriority != existingPriority {
            return candidatePriority > existingPriority ? candidate : existing
        }
        let candidateFreshness = freshnessDate(candidate)
        let existingFreshness = freshnessDate(existing)
        if let candidateFreshness, let existingFreshness, candidateFreshness != existingFreshness {
            return candidateFreshness > existingFreshness ? candidate : existing
        }
        if candidateFreshness != nil, existingFreshness == nil {
            return candidate
        }
        if candidate.hasCompleteFinalScore != existing.hasCompleteFinalScore {
            return candidate.hasCompleteFinalScore ? candidate : existing
        }
        return candidate
    }

    private static func statePriority(_ game: GameDetail) -> Int {
        switch game.status {
        case .final, .cancelled:
            return 3
        case .live, .rainDelay:
            return 2
        case .upcoming:
            return 1
        }
    }

    private static func preferredTeam(_ candidate: Team, fallback: Team) -> Team {
        candidate.id.hasPrefix("unknown-") ? fallback : candidate
    }

    private static func mergedNote(existing: String?, candidate: String?) -> String? {
        let components = [candidate, existing]
            .compactMap(nonBlank)
        guard components.isEmpty == false else { return nil }

        var seen: Set<String> = []
        let merged = components
            .flatMap { $0.split(separator: " ").map(String.init) }
            .filter { seen.insert($0).inserted }
            .joined(separator: " ")
        return nonBlank(merged)
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func freshnessDate(_ game: GameDetail) -> Date? {
        let values = [
            noteValue("live_last_checked_at", in: game.note),
            noteValue("updated_at", in: game.note),
            noteValue("source_updated_at", in: game.note)
        ]
        return values.compactMap(SupabaseDateParser.parseTimestamp).max()
    }

    private static func noteValue(_ key: String, in note: String?) -> String? {
        guard let note,
              let range = note.range(of: "\(key)=") else {
            return nil
        }
        let suffix = note[range.upperBound...]
        return suffix.split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map(String.init)
    }
}

struct AnyKBORepository: KBORepository, KBOFavoriteTeamScheduleDataSource, KBOStandingsGameDataSource, KBOTeamRankDataSource, KBOLocalTeamRankCacheDataSource, KBOLocalTeamRankCacheUpserting, KBOScheduleRemoteSyncDataSource, KBOLocalGameCacheUpserting, KBOGameDetailSnapshotDataSource, KBOGameIdentityResolutionDataSource, Sendable {
    private let fetchBootstrapDataBlock: @Sendable () async throws -> KBOBootstrapData
    private let fetchGamesBlock: @Sendable () async throws -> [GameDetail]
    private let fetchNotificationsBlock: @Sendable () async throws -> [NotificationItem]
    private let fetchMonthlyScheduleBlock: @Sendable (KBOMonthScheduleKey) async throws -> [GameDetail]
    private let fetchScheduleByDateBlock: @Sendable (Date, Bool) async throws -> [GameDetail]
    private let fetchStandingsBlock: @Sendable () async throws -> [TeamStandingsSnapshot]
    private let fetchStandingsSourceBlock: (@Sendable (Int) async throws -> [GameDetail])?
    private let fetchTeamRanksBlock: (@Sendable (Int) async throws -> [TeamRankRow])?
    private let fetchLocalTeamRanksBlock: (@Sendable (Int) async -> [TeamRankRow])?
    private let replaceLocalTeamRanksBlock: (@Sendable ([TeamRankRow], Int) async -> Int)?
    private let fetchFavoriteTeamScheduleBlock: (@Sendable (Date, Team.ID, Bool) async throws -> [GameDetail])?
    private let fetchGameDetailSnapshotBlock: (@Sendable (GameDetail, String, [Team]) async throws -> GameDetail?)?
    private let fetchGameDetailIdentitySnapshotBlock: (@Sendable (String, [Team]) async throws -> GameDetail?)?
    private let fetchRemoteGameCountBlock: (@Sendable () async throws -> Int)?
    private let fetchMissingScheduleGamesBlock: (@Sendable ([GameDetail]) async throws -> KBOScheduleMissingGamesResult)?
    private let upsertLocalGamesBlock: (@Sendable ([GameDetail]) async -> (inserted: Int, updated: Int, skippedExisting: Int))?

    init(_ base: any KBORepository) {
        fetchBootstrapDataBlock = { try await base.fetchBootstrapData() }
        fetchGamesBlock = { try await base.fetchGames() }
        fetchNotificationsBlock = { try await base.fetchNotifications() }
        fetchMonthlyScheduleBlock = { month in try await base.fetchMonthlySchedule(for: month) }
        fetchScheduleByDateBlock = { date, bypassingCache in
            try await base.fetchSchedule(for: date, bypassingCache: bypassingCache)
        }
        fetchStandingsBlock = { try await base.fetchStandings() }
        if let standingsGameSource = base as? any KBOStandingsGameDataSource {
            fetchStandingsSourceBlock = { season in
                try await standingsGameSource.fetchStandingsSource(season: season)
            }
        } else {
            fetchStandingsSourceBlock = nil
        }
        if let teamRankSource = base as? any KBOTeamRankDataSource {
            fetchTeamRanksBlock = { season in try await teamRankSource.fetchTeamRanks(season: season) }
        } else {
            fetchTeamRanksBlock = nil
        }
        if let localTeamRankCache = base as? any KBOLocalTeamRankCacheDataSource {
            fetchLocalTeamRanksBlock = { season in await localTeamRankCache.fetchLocalTeamRanks(season: season) }
        } else {
            fetchLocalTeamRanksBlock = nil
        }
        if let localTeamRankUpserting = base as? any KBOLocalTeamRankCacheUpserting {
            replaceLocalTeamRanksBlock = { ranks, season in
                await localTeamRankUpserting.replaceLocalTeamRanks(ranks, season: season)
            }
        } else {
            replaceLocalTeamRanksBlock = nil
        }
        if let favoriteTeamScheduleSource = base as? any KBOFavoriteTeamScheduleDataSource {
            fetchFavoriteTeamScheduleBlock = { date, favoriteTeamID, bypassingCache in
                try await favoriteTeamScheduleSource.fetchFavoriteTeamSchedule(
                    date: date,
                    favoriteTeamId: favoriteTeamID,
                    bypassingCache: bypassingCache
                )
            }
        } else {
            fetchFavoriteTeamScheduleBlock = nil
        }
        if let detailSource = base as? any KBOGameDetailSnapshotDataSource {
            fetchGameDetailSnapshotBlock = { game, identity, cachedTeams in
                try await detailSource.fetchGameDetailSnapshot(for: game, identity: identity, cachedTeams: cachedTeams)
            }
        } else {
            fetchGameDetailSnapshotBlock = nil
        }
        if let identitySource = base as? any KBOGameIdentityResolutionDataSource {
            fetchGameDetailIdentitySnapshotBlock = { identity, cachedTeams in
                try await identitySource.fetchGameDetailIdentitySnapshot(identity: identity, cachedTeams: cachedTeams)
            }
        } else {
            fetchGameDetailIdentitySnapshotBlock = nil
        }
        if let scheduleSyncSource = base as? any KBOScheduleRemoteSyncDataSource {
            fetchRemoteGameCountBlock = { try await scheduleSyncSource.fetchRemoteGameCount() }
            fetchMissingScheduleGamesBlock = { knownGames in
                try await scheduleSyncSource.fetchMissingScheduleGames(excludingKnownGames: knownGames)
            }
        } else {
            fetchRemoteGameCountBlock = nil
            fetchMissingScheduleGamesBlock = nil
        }
        if let localStore = base as? any KBOLocalGameCacheUpserting {
            upsertLocalGamesBlock = { games in
                await localStore.upsertLocalGames(games)
            }
        } else {
            upsertLocalGamesBlock = nil
        }
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

    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        try await fetchScheduleByDateBlock(date, false)
    }

    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        try await fetchScheduleByDateBlock(date, bypassingCache)
    }

    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        try await fetchStandingsBlock()
    }

    nonisolated func fetchStandingsSource(season: Int) async throws -> [GameDetail] {
        guard let fetchStandingsSourceBlock else {
            return try await fetchGames()
                .filter { $0.isRegularSeason && $0.hasCompleteFinalScore }
        }
        return try await fetchStandingsSourceBlock(season)
    }

    nonisolated func fetchTeamRanks(season: Int) async throws -> [TeamRankRow] {
        guard let fetchTeamRanksBlock else { return [] }
        return try await fetchTeamRanksBlock(season)
    }

    nonisolated func fetchLocalTeamRanks(season: Int) async -> [TeamRankRow] {
        guard let fetchLocalTeamRanksBlock else { return [] }
        return await fetchLocalTeamRanksBlock(season)
    }

    nonisolated func replaceLocalTeamRanks(_ ranks: [TeamRankRow], season: Int) async -> Int {
        guard let replaceLocalTeamRanksBlock else { return 0 }
        return await replaceLocalTeamRanksBlock(ranks, season)
    }

    nonisolated func fetchFavoriteTeamSchedule(
        date: Date,
        favoriteTeamId: Team.ID,
        bypassingCache: Bool
    ) async throws -> [GameDetail] {
        guard let fetchFavoriteTeamScheduleBlock else {
            return try await fetchSchedule(for: date, bypassingCache: bypassingCache)
                .filter { $0.involves(teamID: favoriteTeamId) }
        }
        return try await fetchFavoriteTeamScheduleBlock(date, favoriteTeamId, bypassingCache)
    }

    nonisolated func fetchGameDetailSnapshot(
        for game: GameDetail,
        identity: String,
        cachedTeams: [Team]
    ) async throws -> GameDetail? {
        guard let fetchGameDetailSnapshotBlock else { return nil }
        return try await fetchGameDetailSnapshotBlock(game, identity, cachedTeams)
    }

    nonisolated func fetchGameDetailIdentitySnapshot(
        identity: String,
        cachedTeams: [Team]
    ) async throws -> GameDetail? {
        guard let fetchGameDetailIdentitySnapshotBlock else { return nil }
        return try await fetchGameDetailIdentitySnapshotBlock(identity, cachedTeams)
    }

    nonisolated func fetchRemoteGameCount() async throws -> Int {
        guard let fetchRemoteGameCountBlock else {
            throw KBOScheduleSyncError.unsupported
        }
        return try await fetchRemoteGameCountBlock()
    }

    nonisolated func fetchMissingScheduleGames(excludingKnownGames knownGames: [GameDetail]) async throws -> KBOScheduleMissingGamesResult {
        guard let fetchMissingScheduleGamesBlock else {
            throw KBOScheduleSyncError.unsupported
        }
        return try await fetchMissingScheduleGamesBlock(knownGames)
    }

    nonisolated func upsertLocalGames(_ games: [GameDetail]) async -> (inserted: Int, updated: Int, skippedExisting: Int) {
        guard let upsertLocalGamesBlock else {
            return (0, 0, games.count)
        }
        return await upsertLocalGamesBlock(games)
    }
}

struct RuntimeStateReportingRepository<Base: KBORepository>: KBORepository, KBOStandingsGameDataSource, KBOGameDetailSnapshotDataSource, KBOGameIdentityResolutionDataSource, Sendable {
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

    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        let value = try await base.fetchSchedule(for: date)
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }

    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        let value = try await base.fetchSchedule(for: date, bypassingCache: bypassingCache)
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }

    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        let value = try await base.fetchStandings()
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }

    nonisolated func fetchStandingsSource(season: Int) async throws -> [GameDetail] {
        guard let standingsGameSource = base as? any KBOStandingsGameDataSource else {
            return try await base.fetchGames()
                .filter { $0.isRegularSeason && $0.hasCompleteFinalScore }
        }
        let value = try await standingsGameSource.fetchStandingsSource(season: season)
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }

    nonisolated func fetchGameDetailSnapshot(
        for game: GameDetail,
        identity: String,
        cachedTeams: [Team]
    ) async throws -> GameDetail? {
        guard let detailSource = base as? any KBOGameDetailSnapshotDataSource else {
            return nil
        }
        let value = try await detailSource.fetchGameDetailSnapshot(for: game, identity: identity, cachedTeams: cachedTeams)
        if value != nil {
            await runtimeState?.record(source: source, delivery: delivery)
        }
        return value
    }

    nonisolated func fetchGameDetailIdentitySnapshot(
        identity: String,
        cachedTeams: [Team]
    ) async throws -> GameDetail? {
        guard let identitySource = base as? any KBOGameIdentityResolutionDataSource else {
            return nil
        }
        let value = try await identitySource.fetchGameDetailIdentitySnapshot(identity: identity, cachedTeams: cachedTeams)
        if value != nil {
            await runtimeState?.record(source: source, delivery: delivery)
        }
        return value
    }
}

struct CachedKBORepository<Base: KBORepository>: KBORepository, KBOFavoriteTeamScheduleDataSource, KBOStandingsGameDataSource, KBOTeamRankDataSource, KBOLocalTeamRankCacheDataSource, KBOLocalTeamRankCacheUpserting, KBOScheduleRemoteSyncDataSource, KBOLocalGameCacheUpserting, KBOGameDetailSnapshotDataSource, KBOGameIdentityResolutionDataSource, Sendable {
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

    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        try await base.fetchSchedule(for: date)
    }

    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        try await base.fetchSchedule(for: date, bypassingCache: bypassingCache)
    }

    nonisolated func fetchFavoriteTeamSchedule(
        date: Date,
        favoriteTeamId: Team.ID,
        bypassingCache: Bool
    ) async throws -> [GameDetail] {
        guard let favoriteTeamScheduleSource = base as? any KBOFavoriteTeamScheduleDataSource else {
            return try await base.fetchSchedule(for: date, bypassingCache: bypassingCache)
                .filter { $0.involves(teamID: favoriteTeamId) }
        }
        return try await favoriteTeamScheduleSource.fetchFavoriteTeamSchedule(
            date: date,
            favoriteTeamId: favoriteTeamId,
            bypassingCache: bypassingCache
        )
    }

    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        try await base.fetchStandings()
    }

    nonisolated func fetchStandingsSource(season: Int) async throws -> [GameDetail] {
        guard let standingsGameSource = base as? any KBOStandingsGameDataSource else {
            return try await base.fetchGames()
                .filter { $0.isRegularSeason && $0.hasCompleteFinalScore }
        }
        return try await standingsGameSource.fetchStandingsSource(season: season)
    }

    nonisolated func fetchTeamRanks(season: Int) async throws -> [TeamRankRow] {
        guard let teamRankSource = base as? any KBOTeamRankDataSource else {
            return []
        }
        return try await teamRankSource.fetchTeamRanks(season: season)
    }

    nonisolated func fetchLocalTeamRanks(season: Int) async -> [TeamRankRow] {
        await cache.localTeamRanks(season: season)
    }

    nonisolated func replaceLocalTeamRanks(_ ranks: [TeamRankRow], season: Int) async -> Int {
        await cache.replaceTeamRanks(ranks, season: season)
    }

    nonisolated func fetchGameDetailSnapshot(
        for game: GameDetail,
        identity: String,
        cachedTeams: [Team]
    ) async throws -> GameDetail? {
        guard let detailSource = base as? any KBOGameDetailSnapshotDataSource else {
            return nil
        }
        return try await detailSource.fetchGameDetailSnapshot(for: game, identity: identity, cachedTeams: cachedTeams)
    }

    nonisolated func fetchGameDetailIdentitySnapshot(
        identity: String,
        cachedTeams: [Team]
    ) async throws -> GameDetail? {
        guard let identitySource = base as? any KBOGameIdentityResolutionDataSource else {
            return nil
        }
        return try await identitySource.fetchGameDetailIdentitySnapshot(identity: identity, cachedTeams: cachedTeams)
    }

    nonisolated func fetchRemoteGameCount() async throws -> Int {
        guard let scheduleSyncSource = base as? any KBOScheduleRemoteSyncDataSource else {
            throw KBOScheduleSyncError.unsupported
        }
        return try await scheduleSyncSource.fetchRemoteGameCount()
    }

    nonisolated func fetchMissingScheduleGames(excludingKnownGames knownGames: [GameDetail]) async throws -> KBOScheduleMissingGamesResult {
        guard let scheduleSyncSource = base as? any KBOScheduleRemoteSyncDataSource else {
            throw KBOScheduleSyncError.unsupported
        }
        return try await scheduleSyncSource.fetchMissingScheduleGames(excludingKnownGames: knownGames)
    }

    nonisolated func upsertLocalGames(_ games: [GameDetail]) async -> (inserted: Int, updated: Int, skippedExisting: Int) {
        await cache.upsertGames(games)
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

    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        try await base.fetchSchedule(for: date)
    }

    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        try await base.fetchSchedule(for: date, bypassingCache: bypassingCache)
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
            print("[BootstrapRefresh] refresh failed errorType=\(String(describing: type(of: error)))")
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
        try RepositoryFileSecurity.applyProtection(
            toDirectory: fileURL.deletingLastPathComponent(),
            fileManager: fileManager
        )
        try data.write(to: fileURL, options: .atomic)
        try RepositoryFileSecurity.applyProtection(to: fileURL, fileManager: fileManager)
        try RepositoryFileSecurity.excludeFromBackup(fileURL)

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
        print("[LiveAPI] request endpoint=v1/bootstrap method=GET")
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

    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        let month = KBOMonthScheduleKey(date: date)
        let calendar = Calendar(identifier: .gregorian)
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: date)
        return try await fetchMonthlySchedule(for: month).filter { game in
            let components = calendar.dateComponents([.year, .month, .day], from: game.scheduledStart)
            return components.year == dayComponents.year &&
                components.month == dayComponents.month &&
                components.day == dayComponents.day
        }
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
            print("[LiveAPI] transportError endpoint=\(endpoint.path) errorType=\(String(describing: type(of: error)))")
            #endif
            throw error
        }
        #if DEBUG
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("[LiveAPI] response endpoint=\(endpoint.path) status=\(statusCode) bytes=\(data.count)")
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
            print("[LiveAPI] decodingError endpoint=\(endpoint.path) errorType=\(String(describing: type(of: error)))")
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
        let bodyBytes = request.httpBody?.count ?? 0
        print("[LiveAPI] request endpoint=\(endpoint.path) method=\(method) bodyBytes=\(bodyBytes)")
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

    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        do {
            return try await primary.fetchSchedule(for: date)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let result = try await fallback.fetchSchedule(for: date)
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        do {
            return try await primary.fetchSchedule(for: date, bypassingCache: bypassingCache)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let result = try await fallback.fetchSchedule(for: date, bypassingCache: bypassingCache)
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
