//
//  AnyKBORepository.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

struct AnyKBORepository: KBORepository, KBOFavoriteTeamScheduleDataSource, KBOStandingsGameDataSource, KBOTeamRankDataSource, KBOLocalTeamRankCacheDataSource, KBOLocalTeamRankCacheUpserting, KBOScheduleRemoteSyncDataSource, KBOLocalGameCacheUpserting, KBOGameDetailSnapshotDataSource, KBOGameDetailSnapshotResultDataSource, KBOGameIdentityResolutionDataSource, KBOGameDetailDatabaseRecordDataSource, KBOGameDetailDatabaseRecordDiagnosticDataSource, Sendable {
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
    private let fetchGameDetailSnapshotResultBlock: (@Sendable (GameDetail, String, [Team]) async throws -> GameDetailSnapshotFetchResult?)?
    private let fetchGameDetailIdentitySnapshotBlock: (@Sendable (String, [Team]) async throws -> GameDetail?)?
    private let fetchGameDetailDatabaseReviewBlock: (@Sendable (GameDetail) async throws -> GameCenterReview?)?
    private let fetchGameDetailDatabaseReviewResultBlock: (@Sendable (GameDetail) async throws -> GameDetailDatabaseReviewFetchResult?)?
    private let fetchGameDetailDatabaseReviewForProviderBlock: (@Sendable (String?, String?, String) async throws -> GameDetailDatabaseReviewFetchResult?)?
    private let fetchGameDetailDatabaseReviewForSupabaseGameIDBlock: (@Sendable (UUID, String?, String?, String) async throws -> GameDetailDatabaseReviewFetchResult?)?
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
        if let detailSource = base as? any KBOGameDetailSnapshotResultDataSource {
            fetchGameDetailSnapshotResultBlock = { game, identity, cachedTeams in
                try await detailSource.fetchGameDetailSnapshotResult(for: game, identity: identity, cachedTeams: cachedTeams)
            }
        } else {
            fetchGameDetailSnapshotResultBlock = nil
        }
        if let identitySource = base as? any KBOGameIdentityResolutionDataSource {
            fetchGameDetailIdentitySnapshotBlock = { identity, cachedTeams in
                try await identitySource.fetchGameDetailIdentitySnapshot(identity: identity, cachedTeams: cachedTeams)
            }
        } else {
            fetchGameDetailIdentitySnapshotBlock = nil
        }
        if let databaseRecordSource = base as? any KBOGameDetailDatabaseRecordDataSource {
            fetchGameDetailDatabaseReviewBlock = { game in
                try await databaseRecordSource.fetchGameDetailDatabaseReview(for: game)
            }
        } else {
            fetchGameDetailDatabaseReviewBlock = nil
        }
        if let databaseRecordSource = base as? any KBOGameDetailDatabaseRecordDiagnosticDataSource {
            fetchGameDetailDatabaseReviewResultBlock = { game in
                try await databaseRecordSource.fetchGameDetailDatabaseReviewResult(for: game)
            }
            fetchGameDetailDatabaseReviewForProviderBlock = { providerGameID, publicGameID, invokedFrom in
                try await databaseRecordSource.fetchGameDetailDatabaseReview(
                    providerGameID: providerGameID,
                    publicGameID: publicGameID,
                    invokedFrom: invokedFrom
                )
            }
            fetchGameDetailDatabaseReviewForSupabaseGameIDBlock = { supabaseGameId, providerGameID, publicGameID, invokedFrom in
                try await databaseRecordSource.fetchGameDetailDatabaseReview(
                    supabaseGameId: supabaseGameId,
                    providerGameID: providerGameID,
                    publicGameID: publicGameID,
                    invokedFrom: invokedFrom
                )
            }
        } else {
            fetchGameDetailDatabaseReviewResultBlock = nil
            fetchGameDetailDatabaseReviewForProviderBlock = nil
            fetchGameDetailDatabaseReviewForSupabaseGameIDBlock = nil
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

    nonisolated func fetchGameDetailSnapshotResult(
        for game: GameDetail,
        identity: String,
        cachedTeams: [Team]
    ) async throws -> GameDetailSnapshotFetchResult? {
        if let fetchGameDetailSnapshotResultBlock {
            return try await fetchGameDetailSnapshotResultBlock(game, identity, cachedTeams)
        }
        guard let game = try await fetchGameDetailSnapshotBlock?(game, identity, cachedTeams) else { return nil }
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
        guard let fetchGameDetailIdentitySnapshotBlock else { return nil }
        return try await fetchGameDetailIdentitySnapshotBlock(identity, cachedTeams)
    }

    nonisolated func fetchGameDetailDatabaseReview(for game: GameDetail) async throws -> GameCenterReview? {
        guard let fetchGameDetailDatabaseReviewBlock else { return nil }
        return try await fetchGameDetailDatabaseReviewBlock(game)
    }

    nonisolated func fetchGameDetailDatabaseReviewResult(for game: GameDetail) async throws -> GameDetailDatabaseReviewFetchResult? {
        if let fetchGameDetailDatabaseReviewResultBlock {
            return try await fetchGameDetailDatabaseReviewResultBlock(game)
        }
        guard let review = try await fetchGameDetailDatabaseReviewBlock?(game) else { return nil }
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
        guard let fetchGameDetailDatabaseReviewForProviderBlock else { return nil }
        return try await fetchGameDetailDatabaseReviewForProviderBlock(
            providerGameID,
            publicGameID,
            invokedFrom
        )
    }

    nonisolated func fetchGameDetailDatabaseReview(
        supabaseGameId: UUID,
        providerGameID: String?,
        publicGameID: String?,
        invokedFrom: String
    ) async throws -> GameDetailDatabaseReviewFetchResult? {
        guard let fetchGameDetailDatabaseReviewForSupabaseGameIDBlock else { return nil }
        return try await fetchGameDetailDatabaseReviewForSupabaseGameIDBlock(
            supabaseGameId,
            providerGameID,
            publicGameID,
            invokedFrom
        )
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
