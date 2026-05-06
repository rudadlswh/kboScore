//
//  Repository.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import Foundation

struct KBOMonthScheduleKey: Hashable, Sendable, Codable {
    let year: Int
    let month: Int

    nonisolated init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    nonisolated init(date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) {
        let components = calendar.dateComponents([.year, .month], from: date)
        self.year = components.year ?? 1970
        self.month = components.month ?? 1
    }

    nonisolated var yearMonthText: String {
        String(format: "%04d%02d", year, month)
    }
}

protocol KBOGameDataSource: Sendable {
    nonisolated func fetchGames() async throws -> [GameDetail]
}

protocol KBONotificationDataSource: Sendable {
    nonisolated func fetchNotifications() async throws -> [NotificationItem]
}

protocol KBOMonthScheduleDataSource: Sendable {
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail]
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey, bypassingCache: Bool) async throws -> [GameDetail]
}

extension KBOMonthScheduleDataSource {
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey, bypassingCache: Bool) async throws -> [GameDetail] {
        try await fetchMonthlySchedule(for: month)
    }
}

protocol KBODailyScheduleDataSource: Sendable {
    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail]
    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail]
}

protocol KBOFavoriteTeamScheduleDataSource: Sendable {
    nonisolated func fetchFavoriteTeamSchedule(
        date: Date,
        favoriteTeamId: Team.ID,
        bypassingCache: Bool
    ) async throws -> [GameDetail]
}

extension KBODailyScheduleDataSource where Self: KBOMonthScheduleDataSource {
    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        try await fetchSchedule(for: date, bypassingCache: false)
    }

    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        let calendar = Calendar(identifier: .gregorian)
        let month = KBOMonthScheduleKey(date: date, calendar: calendar)
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: date)
        return try await fetchMonthlySchedule(for: month, bypassingCache: bypassingCache)
            .filter {
                let components = calendar.dateComponents([.year, .month, .day], from: $0.scheduledStart)
                return components.year == dayComponents.year &&
                    components.month == dayComponents.month &&
                    components.day == dayComponents.day
            }
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }
}

protocol KBOStandingsDataSource: Sendable {
    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot]
}

protocol KBOStandingsGameDataSource: Sendable {
    nonisolated func fetchStandingsSource(season: Int) async throws -> [GameDetail]
}

protocol KBOTeamRankDataSource: Sendable {
    nonisolated func fetchTeamRanks(season: Int) async throws -> [TeamRankRow]
}

protocol KBOLocalTeamRankCacheDataSource: Sendable {
    nonisolated func fetchLocalTeamRanks(season: Int) async -> [TeamRankRow]
}

protocol KBOLocalTeamRankCacheUpserting: Sendable {
    nonisolated func replaceLocalTeamRanks(_ ranks: [TeamRankRow], season: Int) async -> Int
}

extension KBOStandingsDataSource {
    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        []
    }
}

protocol KBORepository: KBOGameDataSource, KBONotificationDataSource, KBOMonthScheduleDataSource, KBODailyScheduleDataSource, KBOStandingsDataSource, Sendable {
    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData
}

protocol KBOGameDetailSnapshotDataSource: Sendable {
    nonisolated func fetchGameDetailSnapshot(
        for game: GameDetail,
        identity: String,
        cachedTeams: [Team]
    ) async throws -> GameDetail?
}

struct KBOScheduleMissingGamesResult: Sendable {
    let remoteCount: Int
    let games: [GameDetail]
}

enum KBOScheduleSyncError: Error, Sendable {
    case unsupported
}

protocol KBOScheduleRemoteSyncDataSource: Sendable {
    nonisolated func fetchRemoteGameCount() async throws -> Int
    nonisolated func fetchMissingScheduleGames(excludingKnownGames knownGames: [GameDetail]) async throws -> KBOScheduleMissingGamesResult
}

protocol KBOLocalGameCacheUpserting: Sendable {
    nonisolated func upsertLocalGames(_ games: [GameDetail]) async -> (inserted: Int, updated: Int, skippedExisting: Int)
}

struct KBOBootstrapData: Sendable {
    let teams: [Team]
    let games: [GameDetail]
    let notifications: [NotificationItem]
    let settings: AppSettings
}
