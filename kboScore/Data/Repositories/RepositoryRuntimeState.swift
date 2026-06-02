//
//  RepositoryRuntimeState.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

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
