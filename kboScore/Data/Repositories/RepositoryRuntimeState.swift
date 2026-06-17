//
//  RepositoryRuntimeState.swift
//  kboScore
//  기능 설명: 현재 데이터 소스, 전달 경로, 캐시 상태를 디버그용으로 추적합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
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

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
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

    // record 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
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

    // recordCacheHit 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func recordCacheHit(refreshedAt: Date, isStale: Bool) {
        deliverySource = .cache
        lastRefreshAt = refreshedAt
        isUsingStaleCache = isStale
    }

    // recordBootstrapRefresh 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func recordBootstrapRefresh(_ snapshot: BootstrapRefreshDebugSnapshot) {
        bootstrapAPIEnabled = snapshot.isEnabled
        bootstrapRefreshETag = snapshot.etag
        bootstrapLastFetchAt = snapshot.lastFetchAt
        bootstrapLastWriteAt = snapshot.lastWriteAt
        bootstrapLastResult = snapshot.lastResult
        lastRefreshAt = snapshot.lastFetchAt ?? lastRefreshAt
    }

    // snapshot 메서드는 이 타입의 주요 동작을 수행합니다.
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

// RuntimeStateReportingRepository 구조체는 KBO 데이터 조회와 저장소 접근 흐름을 담당합니다.
struct RuntimeStateReportingRepository<Base: KBORepository>: KBORepository, KBOStandingsGameDataSource, KBOGameDetailSnapshotDataSource, KBOGameIdentityResolutionDataSource, Sendable {
    let base: Base
    let source: RepositoryDataSourceKind
    let delivery: RepositoryDeliverySourceKind
    let runtimeState: RepositoryRuntimeState?

    // fetchBootstrapData 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        let value = try await base.fetchBootstrapData()
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [GameDetail] {
        let value = try await base.fetchGames()
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }

    // fetchNotifications 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        let value = try await base.fetchNotifications()
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }

    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        let value = try await base.fetchMonthlySchedule(for: month)
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        let value = try await base.fetchSchedule(for: date)
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        let value = try await base.fetchSchedule(for: date, bypassingCache: bypassingCache)
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }

    // fetchStandings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        let value = try await base.fetchStandings()
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }

    // fetchStandingsSource 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchStandingsSource(season: Int) async throws -> [GameDetail] {
        guard let standingsGameSource = base as? any KBOStandingsGameDataSource else {
            return try await base.fetchGames()
                .filter { $0.isRegularSeason && $0.hasCompleteFinalScore }
        }
        let value = try await standingsGameSource.fetchStandingsSource(season: season)
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }

    // fetchGameDetailSnapshot 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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

    // fetchGameDetailIdentitySnapshot 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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
