//
//  Repository.swift
//  kboScore
//  기능 설명: 앱 데이터 저장소들이 구현해야 하는 공통 프로토콜과 요청 모델을 정의합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 3/25/26.
//

import Foundation

// KBOMonthScheduleKey 구조체는 KBOMonthScheduleKey 타입의 역할과 값을 정의합니다.
nonisolated struct KBOMonthScheduleKey: Hashable, Sendable, Codable {
    let year: Int
    let month: Int

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
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
    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [GameDetail]
}

protocol KBONotificationDataSource: Sendable {
    // fetchNotifications 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchNotifications() async throws -> [NotificationItem]
}

protocol KBOMonthScheduleDataSource: Sendable {
    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail]
    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey, bypassingCache: Bool) async throws -> [GameDetail]
}

extension KBOMonthScheduleDataSource {
    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey, bypassingCache: Bool) async throws -> [GameDetail] {
        try await fetchMonthlySchedule(for: month)
    }
}

protocol KBOScheduleTabMonthDataSource: Sendable {
    // fetchScheduleTabMonth 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchScheduleTabMonth(for month: KBOMonthScheduleKey, bypassingCache: Bool) async throws -> [GameDetail]
}

protocol KBODailyScheduleDataSource: Sendable {
    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail]
    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail]
}

protocol KBOFavoriteTeamScheduleDataSource: Sendable {
    // fetchFavoriteTeamSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchFavoriteTeamSchedule(
        date: Date,
        favoriteTeamId: Team.ID,
        bypassingCache: Bool
    ) async throws -> [GameDetail]
}

extension KBODailyScheduleDataSource where Self: KBOMonthScheduleDataSource {
    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        try await fetchSchedule(for: date, bypassingCache: false)
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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
    // fetchStandings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot]
}

protocol KBOStandingsGameDataSource: Sendable {
    // fetchStandingsSource 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchStandingsSource(season: Int) async throws -> [GameDetail]
}

protocol KBOTeamRankDataSource: Sendable {
    // fetchTeamRanks 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchTeamRanks(season: Int) async throws -> [TeamRankRow]
}

protocol KBOLocalTeamRankCacheDataSource: Sendable {
    // fetchLocalTeamRanks 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchLocalTeamRanks(season: Int) async -> [TeamRankRow]
}

protocol KBOLocalTeamRankCacheUpserting: Sendable {
    // replaceLocalTeamRanks 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    nonisolated func replaceLocalTeamRanks(_ ranks: [TeamRankRow], season: Int) async -> Int
}

extension KBOStandingsDataSource {
    // fetchStandings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        []
    }
}

protocol KBORepository: KBOGameDataSource, KBONotificationDataSource, KBOMonthScheduleDataSource, KBODailyScheduleDataSource, KBOStandingsDataSource, Sendable {
    // fetchBootstrapData 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData
}

protocol KBOGameDetailSnapshotDataSource: Sendable {
    // fetchGameDetailSnapshot 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailSnapshot(
        for game: GameDetail,
        identity: String,
        cachedTeams: [Team]
    ) async throws -> GameDetail?
}

// GameDetailSnapshotFetchResult 구조체는 GameDetailSnapshotFetchResult 타입의 역할과 값을 정의합니다.
struct GameDetailSnapshotFetchResult: Sendable {
    let game: GameDetail
    let rawSupabaseGameID: UUID?
    let providerGameID: String?
    let publicGameID: String?
    var snapshotCreatedAt: Date? = nil
    var snapshotUpdatedAt: Date? = nil
}

protocol KBOGameDetailSnapshotResultDataSource: KBOGameDetailSnapshotDataSource {
    // fetchGameDetailSnapshotResult 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailSnapshotResult(
        for game: GameDetail,
        identity: String,
        cachedTeams: [Team]
    ) async throws -> GameDetailSnapshotFetchResult?
}

protocol KBOGameDetailLatestSnapshotDataSource: Sendable {
    nonisolated func fetchLatestGameSnapshotResult(
        gameID: UUID,
        fallbackGame: GameDetail
    ) async throws -> GameDetailSnapshotFetchResult?
}

protocol KBOGameIdentityResolutionDataSource: Sendable {
    // fetchGameDetailIdentitySnapshot 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailIdentitySnapshot(
        identity: String,
        cachedTeams: [Team]
    ) async throws -> GameDetail?
}

protocol KBOGameDetailDatabaseRecordDataSource: Sendable {
    // fetchGameDetailDatabaseReview 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailDatabaseReview(for game: GameDetail) async throws -> GameCenterReview?
}

// GameDetailDatabaseReviewFetchResult 구조체는 GameDetailDatabaseReviewFetchResult 타입의 역할과 값을 정의합니다.
struct GameDetailDatabaseReviewFetchResult: Sendable {
    nonisolated static let liveRecordFreshnessThreshold: TimeInterval = 30

    let review: GameCenterReview?
    let inputLocalGameID: UUID
    let rawSupabaseGameID: UUID?
    let resolvedSupabaseGameID: UUID?
    let providerGameID: String?
    let publicGameID: String?
    let publicBatterRawRowCount: Int
    let publicPitcherRawRowCount: Int
    let eventRawRowCount: Int
    var latestRecordUpdatedAt: Date? = nil

    var mappedBatterCount: Int {
        (review?.awayBatting.lines.count ?? 0) + (review?.homeBatting.lines.count ?? 0)
    }

    var mappedPitcherCount: Int {
        (review?.awayPitching.lines.count ?? 0) + (review?.homePitching.lines.count ?? 0)
    }

    func hasFreshLiveRecords(now: Date = Date()) -> Bool {
        guard mappedBatterCount > 0 || mappedPitcherCount > 0,
              let latestRecordUpdatedAt else {
            return false
        }
        return now.timeIntervalSince(latestRecordUpdatedAt) <= Self.liveRecordFreshnessThreshold
    }
}

protocol KBOGameDetailDatabaseRecordDiagnosticDataSource: KBOGameDetailDatabaseRecordDataSource {
    // fetchGameDetailDatabaseReviewResult 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailDatabaseReviewResult(for game: GameDetail) async throws -> GameDetailDatabaseReviewFetchResult?
    // fetchGameDetailDatabaseReview 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailDatabaseReview(
        providerGameID: String?,
        publicGameID: String?,
        invokedFrom: String
    ) async throws -> GameDetailDatabaseReviewFetchResult?
    // fetchGameDetailDatabaseReview 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailDatabaseReview(
        supabaseGameId: UUID,
        providerGameID: String?,
        publicGameID: String?,
        invokedFrom: String
    ) async throws -> GameDetailDatabaseReviewFetchResult?
}

// KBOScheduleMissingGamesResult 구조체는 KBOScheduleMissingGamesResult 타입의 역할과 값을 정의합니다.
struct KBOScheduleMissingGamesResult: Sendable {
    let remoteCount: Int
    let games: [GameDetail]
}

// KBOScheduleSyncError 열거형는 실패 상황을 구분하고 호출자에게 전달합니다.
enum KBOScheduleSyncError: Error, Sendable {
    case unsupported
}

protocol KBOScheduleRemoteSyncDataSource: Sendable {
    // fetchRemoteGameCount 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchRemoteGameCount() async throws -> Int
    // fetchMissingScheduleGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMissingScheduleGames(excludingKnownGames knownGames: [GameDetail]) async throws -> KBOScheduleMissingGamesResult
}

protocol KBOLocalGameCacheUpserting: Sendable {
    // upsertLocalGames 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    nonisolated func upsertLocalGames(_ games: [GameDetail]) async -> (inserted: Int, updated: Int, skippedExisting: Int)
}

// KBOBootstrapData 구조체는 KBOBootstrapData 타입의 역할과 값을 정의합니다.
nonisolated struct KBOBootstrapData: Sendable {
    let teams: [Team]
    let games: [GameDetail]
    let notifications: [NotificationItem]
    let settings: AppSettings
}
