//
//  LiveKBOCachedRepository.swift
//  kboScore
//  기능 설명: 실시간 KBO 저장소 응답을 메모리/디스크 캐시와 함께 제공하는 래퍼입니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 5/14/26.
//

import Foundation

// CachedKBORepository 구조체는 KBO 데이터 조회와 저장소 접근 흐름을 담당합니다.
struct CachedKBORepository<Base: KBORepository>: KBORepository, KBOScheduleTabMonthDataSource, KBOFavoriteTeamScheduleDataSource, KBOStandingsGameDataSource, KBOTeamRankDataSource, KBOLocalTeamRankCacheDataSource, KBOLocalTeamRankCacheUpserting, KBOScheduleRemoteSyncDataSource, KBOLocalGameCacheUpserting, KBOLocalMonthlyScheduleCacheDataSource, KBOGameDetailSnapshotDataSource, KBOGameDetailSnapshotResultDataSource, KBOGameIdentityResolutionDataSource, KBOGameDetailDatabaseRecordDataSource, KBOGameDetailDatabaseRecordDiagnosticDataSource, Sendable {
    let base: Base
    let configuration: RepositoryCacheConfiguration
    let runtimeState: RepositoryRuntimeState?

    private let cache: RepositoryResponseCache

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
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

    // fetchBootstrapData 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        let result = try await cache.bootstrapValue(ttl: configuration.bootstrapTTL) {
            try await base.fetchBootstrapData()
        }
        if result.isCacheHit {
            await runtimeState?.recordCacheHit(refreshedAt: result.cachedAt, isStale: result.isStale)
        }
        return result.value
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [GameDetail] {
        let result = try await cache.gamesValue(ttl: configuration.gamesTTL) {
            try await base.fetchGames()
        }
        if result.isCacheHit {
            await runtimeState?.recordCacheHit(refreshedAt: result.cachedAt, isStale: result.isStale)
        }
        return result.value
    }

    // fetchNotifications 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        let result = try await cache.notificationsValue(ttl: configuration.notificationsTTL) {
            try await base.fetchNotifications()
        }
        if result.isCacheHit {
            await runtimeState?.recordCacheHit(refreshedAt: result.cachedAt, isStale: result.isStale)
        }
        return result.value
    }

    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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

    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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

    // fetchScheduleTabMonth 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchScheduleTabMonth(for month: KBOMonthScheduleKey, bypassingCache: Bool) async throws -> [GameDetail] {
        let fetchFromBase: @Sendable () async throws -> [GameDetail] = {
            if let scheduleTabMonthSource = base as? any KBOScheduleTabMonthDataSource {
                return try await scheduleTabMonthSource.fetchScheduleTabMonth(
                    for: month,
                    bypassingCache: bypassingCache
                )
            }
            return try await base.fetchMonthlySchedule(for: month, bypassingCache: bypassingCache)
        }

        if bypassingCache {
            let result = try await cache.refreshMonthlyScheduleValue(for: month, fetch: fetchFromBase)
            if result.isCacheHit {
                await runtimeState?.recordCacheHit(refreshedAt: result.cachedAt, isStale: result.isStale)
            }
            return result.value
        }

        let result = try await cache.monthlyScheduleValue(for: month, ttl: configuration.monthlyScheduleTTL, fetch: fetchFromBase)
        if result.isCacheHit {
            await runtimeState?.recordCacheHit(refreshedAt: result.cachedAt, isStale: result.isStale)
        }
        return result.value
    }

    nonisolated func fetchCachedMonthlySchedule(for month: KBOMonthScheduleKey) async -> [GameDetail]? {
        guard let result = await cache.cachedMonthlyScheduleValue(for: month) else {
            return nil
        }
        await runtimeState?.recordCacheHit(refreshedAt: result.cachedAt, isStale: true)
#if DEBUG
        print("[RepositorySource] monthlySchedule displayCacheUsed repositoryHit=true \(result.source)Hit=true month=\(month.yearMonthText) count=\(result.value.count)")
#endif
        return result.value
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        try await base.fetchSchedule(for: date)
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        try await base.fetchSchedule(for: date, bypassingCache: bypassingCache)
    }

    // fetchFavoriteTeamSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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

    // fetchStandings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        try await base.fetchStandings()
    }

    // fetchStandingsSource 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchStandingsSource(season: Int) async throws -> [GameDetail] {
        guard let standingsGameSource = base as? any KBOStandingsGameDataSource else {
            return try await base.fetchGames()
                .filter { $0.isRegularSeason && $0.hasCompleteFinalScore }
        }
        return try await standingsGameSource.fetchStandingsSource(season: season)
    }

    // fetchTeamRanks 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchTeamRanks(season: Int) async throws -> [TeamRankRow] {
        guard let teamRankSource = base as? any KBOTeamRankDataSource else {
            return []
        }
        return try await teamRankSource.fetchTeamRanks(season: season)
    }

    // fetchLocalTeamRanks 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchLocalTeamRanks(season: Int) async -> [TeamRankRow] {
        await cache.localTeamRanks(season: season)
    }

    // replaceLocalTeamRanks 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    nonisolated func replaceLocalTeamRanks(_ ranks: [TeamRankRow], season: Int) async -> Int {
        await cache.replaceTeamRanks(ranks, season: season)
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
        return try await detailSource.fetchGameDetailSnapshot(for: game, identity: identity, cachedTeams: cachedTeams)
    }

    // fetchGameDetailSnapshotResult 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailSnapshotResult(
        for game: GameDetail,
        identity: String,
        cachedTeams: [Team]
    ) async throws -> GameDetailSnapshotFetchResult? {
        if let detailSource = base as? any KBOGameDetailSnapshotResultDataSource {
            return try await detailSource.fetchGameDetailSnapshotResult(
                for: game,
                identity: identity,
                cachedTeams: cachedTeams
            )
        }
        guard let game = try await fetchGameDetailSnapshot(
            for: game,
            identity: identity,
            cachedTeams: cachedTeams
        ) else {
            return nil
        }
        return GameDetailSnapshotFetchResult(
            game: game,
            rawSupabaseGameID: nil,
            providerGameID: game.providerGameID,
            publicGameID: game.publicGameID
        )
    }

    // fetchGameDetailIdentitySnapshot 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailIdentitySnapshot(
        identity: String,
        cachedTeams: [Team]
    ) async throws -> GameDetail? {
        guard let identitySource = base as? any KBOGameIdentityResolutionDataSource else {
            return nil
        }
        return try await identitySource.fetchGameDetailIdentitySnapshot(identity: identity, cachedTeams: cachedTeams)
    }

    // fetchGameDetailDatabaseReview 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailDatabaseReview(for game: GameDetail) async throws -> GameCenterReview? {
        guard let recordSource = base as? any KBOGameDetailDatabaseRecordDataSource else {
            return nil
        }
        return try await recordSource.fetchGameDetailDatabaseReview(for: game)
    }

    // fetchGameDetailDatabaseReviewResult 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailDatabaseReviewResult(for game: GameDetail) async throws -> GameDetailDatabaseReviewFetchResult? {
        if let recordSource = base as? any KBOGameDetailDatabaseRecordDiagnosticDataSource {
            return try await recordSource.fetchGameDetailDatabaseReviewResult(for: game)
        }
        guard let review = try await fetchGameDetailDatabaseReview(for: game) else {
            return nil
        }
        return GameDetailDatabaseReviewFetchResult(
            review: review,
            inputLocalGameID: game.id,
            rawSupabaseGameID: nil,
            resolvedSupabaseGameID: nil,
            providerGameID: game.providerGameID,
            publicGameID: game.publicGameID,
            publicBatterRawRowCount: review.awayBatting.lines.count + review.homeBatting.lines.count,
            publicPitcherRawRowCount: review.awayPitching.lines.count + review.homePitching.lines.count,
            eventRawRowCount: 0
        )
    }

    // fetchGameDetailDatabaseReview 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailDatabaseReview(
        providerGameID: String?,
        publicGameID: String?,
        invokedFrom: String
    ) async throws -> GameDetailDatabaseReviewFetchResult? {
        guard let recordSource = base as? any KBOGameDetailDatabaseRecordDiagnosticDataSource else {
            return nil
        }
        return try await recordSource.fetchGameDetailDatabaseReview(
            providerGameID: providerGameID,
            publicGameID: publicGameID,
            invokedFrom: invokedFrom
        )
    }

    // fetchGameDetailDatabaseReview 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailDatabaseReview(
        supabaseGameId: UUID,
        providerGameID: String?,
        publicGameID: String?,
        invokedFrom: String
    ) async throws -> GameDetailDatabaseReviewFetchResult? {
        guard let recordSource = base as? any KBOGameDetailDatabaseRecordDiagnosticDataSource else {
            return nil
        }
        return try await recordSource.fetchGameDetailDatabaseReview(
            supabaseGameId: supabaseGameId,
            providerGameID: providerGameID,
            publicGameID: publicGameID,
            invokedFrom: invokedFrom
        )
    }

    // fetchRemoteGameCount 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchRemoteGameCount() async throws -> Int {
        guard let scheduleSyncSource = base as? any KBOScheduleRemoteSyncDataSource else {
            throw KBOScheduleSyncError.unsupported
        }
        return try await scheduleSyncSource.fetchRemoteGameCount()
    }

    // fetchMissingScheduleGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMissingScheduleGames(excludingKnownGames knownGames: [GameDetail]) async throws -> KBOScheduleMissingGamesResult {
        guard let scheduleSyncSource = base as? any KBOScheduleRemoteSyncDataSource else {
            throw KBOScheduleSyncError.unsupported
        }
        return try await scheduleSyncSource.fetchMissingScheduleGames(excludingKnownGames: knownGames)
    }

    // upsertLocalGames 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    nonisolated func upsertLocalGames(_ games: [GameDetail]) async -> (inserted: Int, updated: Int, skippedExisting: Int) {
        await cache.upsertGames(games)
    }
}
