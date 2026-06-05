//
//  LiveKBOCachedRepository.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

struct CachedKBORepository<Base: KBORepository>: KBORepository, KBOFavoriteTeamScheduleDataSource, KBOStandingsGameDataSource, KBOTeamRankDataSource, KBOLocalTeamRankCacheDataSource, KBOLocalTeamRankCacheUpserting, KBOScheduleRemoteSyncDataSource, KBOLocalGameCacheUpserting, KBOGameDetailSnapshotDataSource, KBOGameDetailSnapshotResultDataSource, KBOGameIdentityResolutionDataSource, KBOGameDetailDatabaseRecordDataSource, KBOGameDetailDatabaseRecordDiagnosticDataSource, Sendable {
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

    nonisolated func fetchGameDetailIdentitySnapshot(
        identity: String,
        cachedTeams: [Team]
    ) async throws -> GameDetail? {
        guard let identitySource = base as? any KBOGameIdentityResolutionDataSource else {
            return nil
        }
        return try await identitySource.fetchGameDetailIdentitySnapshot(identity: identity, cachedTeams: cachedTeams)
    }

    nonisolated func fetchGameDetailDatabaseReview(for game: GameDetail) async throws -> GameCenterReview? {
        guard let recordSource = base as? any KBOGameDetailDatabaseRecordDataSource else {
            return nil
        }
        return try await recordSource.fetchGameDetailDatabaseReview(for: game)
    }

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
