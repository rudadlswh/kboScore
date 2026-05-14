//
//  LiveKBORepository.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import Foundation

enum RepositoryFileSecurity {
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

struct RepositoryCacheEntry<Value: Sendable>: Sendable {
    let value: Value
    let timestamp: Date
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
