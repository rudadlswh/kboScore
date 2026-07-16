//
//  SupabaseKBORepository.swift
//  kboScore
//  기능 설명: Supabase 공개 API에서 KBO 팀, 경기, 순위, 상세 기록 데이터를 조회합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 4/24/26.
//

import Foundation

// SupabaseGameLookup 열거형는 SupabaseGameLookup 타입의 역할과 값을 정의합니다.
enum SupabaseGameLookup: Sendable, Equatable {
    case providerGameID(String)
    case officialProviderGameID(String)
    case publicGameID(String)
    case databaseID(UUID)
    case dateTeamIDs(gameDate: String, awayTeamID: UUID, homeTeamID: UUID)
    case dateTeamVenue(gameDate: String, awayTeamID: UUID, homeTeamID: UUID, stadium: String)

    nonisolated var debugKey: String {
        switch self {
        case .providerGameID:
            return "provider_game_id"
        case .officialProviderGameID:
            return "official_provider_game_id"
        case .publicGameID:
            return "public_game_id"
        case .databaseID:
            return "id"
        case .dateTeamIDs:
            return "game_date+away_team_id+home_team_id"
        case .dateTeamVenue:
            return "game_date+away_team_id+home_team_id+stadium"
        }
    }

    nonisolated var debugValue: String {
        switch self {
        case .providerGameID(let value), .officialProviderGameID(let value), .publicGameID(let value):
            return value
        case .databaseID(let id):
            return id.uuidString
        case .dateTeamIDs(let gameDate, let awayTeamID, let homeTeamID):
            return "\(gameDate)|\(awayTeamID.uuidString)|\(homeTeamID.uuidString)"
        case .dateTeamVenue(let gameDate, let awayTeamID, let homeTeamID, let stadium):
            return "\(gameDate)|\(awayTeamID.uuidString)|\(homeTeamID.uuidString)|\(stadium)"
        }
    }
}

protocol SupabaseKBOReading: Sendable {
    // fetchTeams 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchTeams() async throws -> [SupabaseTeamRow]
    // fetchGameCount 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameCount() async throws -> Int
    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [SupabaseGameRow]
    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(excludingProviderGameIDs providerGameIDs: Set<String>) async throws -> [SupabaseGameRow]
    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(month: KBOMonthScheduleKey) async throws -> [SupabaseGameRow]
    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(date: Date) async throws -> [SupabaseGameRow]
    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(date: Date, favoriteTeamID: String) async throws -> [SupabaseGameRow]
    // fetchGamesForStandings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGamesForStandings(season: Int) async throws -> [SupabaseGameRow]
    // fetchTeamRanks2026 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchTeamRanks2026() async throws -> [TeamRankRow]
    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(teamID: String) async throws -> [SupabaseGameRow]
    // fetchGame 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGame(lookup: SupabaseGameLookup) async throws -> [SupabaseGameRow]
    // fetchLatestSnapshots 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchLatestSnapshots(gameIDs: [UUID]) async throws -> [SupabaseLatestGameSnapshotRow]
    // fetchLatestSnapshot 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchLatestSnapshot(gameID: UUID) async throws -> SupabaseLatestGameSnapshotRow?
    // fetchGameBatterRecords 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameBatterRecords(gameID: UUID) async throws -> [SupabaseGameBatterRecordRow]
    // fetchGamePitcherRecords 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGamePitcherRecords(gameID: UUID) async throws -> [SupabaseGamePitcherRecordRow]
    // fetchGameEvents 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameEvents(gameID: UUID) async throws -> [SupabaseGameEventRow]
}

extension SupabaseKBOReading {
    // fetchTeamRanks2026 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchTeamRanks2026() async throws -> [TeamRankRow] {
        []
    }

    // fetchGameBatterRecords 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameBatterRecords(gameID: UUID) async throws -> [SupabaseGameBatterRecordRow] {
        []
    }

    // fetchGamePitcherRecords 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGamePitcherRecords(gameID: UUID) async throws -> [SupabaseGamePitcherRecordRow] {
        []
    }

    // fetchGameEvents 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameEvents(gameID: UUID) async throws -> [SupabaseGameEventRow] {
        []
    }
}

actor SupabaseTeamRowCache {
    private var rows: [SupabaseTeamRow]?
    private var fetchTask: Task<[SupabaseTeamRow], Error>?

    // teams 메서드는 이 타입의 주요 동작을 수행합니다.
    func teams(fetch: @escaping @Sendable () async throws -> [SupabaseTeamRow]) async throws -> [SupabaseTeamRow] {
        if let rows {
            return rows
        }
        if let fetchTask {
            return try await fetchTask.value
        }

        let task = Task {
            try await fetch()
        }
        fetchTask = task
        defer { fetchTask = nil }

        let fetchedRows = try await task.value
        rows = fetchedRows
        return fetchedRows
    }
}

// Read-only overlay: the iOS app only selects public data from Supabase.
// Inserts/updates/deletes must stay in trusted backend, admin, or scheduled jobs.
// SupabaseBackedKBORepository 구조체는 KBO 데이터 조회와 저장소 접근 흐름을 담당합니다.
struct SupabaseBackedKBORepository<Base: KBORepository, Source: SupabaseKBOReading>: KBORepository, KBOScheduleTabMonthDataSource, KBOFavoriteTeamScheduleDataSource, KBOStandingsGameDataSource, KBOTeamRankDataSource, Sendable {
    let base: Base
    let source: Source
    let runtimeState: RepositoryRuntimeState?
    let teamCache = SupabaseTeamRowCache()

    // fetchBootstrapData 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        #if DEBUG
        print("[SupabaseKBO] fetchBootstrapData start source=localFirst")
        #endif
        do {
            let localBootstrap = try await base.fetchBootstrapData()
            if localBootstrap.games.isEmpty == false {
                let remoteCount = (try? await source.fetchGameCount()) ?? localBootstrap.games.count
                if localBootstrap.games.count < remoteCount {
                    #if DEBUG
                    print("staleBootstrapIgnored reason=lowerGameCount local=\(localBootstrap.games.count) remote=\(remoteCount)")
                    #endif
                    return try await fetchRemoteBootstrap()
                }
                #if DEBUG
                print("[SupabaseKBO] fetchBootstrapData localFirst success teams=\(localBootstrap.teams.count) games=\(localBootstrap.games.count)")
                #endif
                return localBootstrap
            }

            #if DEBUG
            print("[SupabaseKBO] fetchBootstrapData localFirst empty fallback=remoteBootstrap")
            #endif
            return try await fetchRemoteBootstrap()
        } catch {
            #if DEBUG
            print("[SupabaseRepository] local bootstrap failed, attempting remote bootstrap. error=\(error)")
            #endif
            return try await fetchRemoteBootstrap()
        }
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [GameDetail] {
        #if DEBUG
        print("[SupabaseKBO] fetchGames start")
        #endif
        do {
            let games = try await fetchSupabaseGames()
            await runtimeState?.record(source: .supabase, delivery: .supabase)
            #if DEBUG
            print("[SupabaseKBO] fetchGames success count=\(games.count)")
            #endif
            return games
        } catch {
            #if DEBUG
            print("[SupabaseRepository] fetchGames failed, falling back to base repository. error=\(error)")
            #endif
            return try await base.fetchGames()
        }
    }

    // fetchNotifications 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        try await base.fetchNotifications()
    }

    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        try await fetchMonthlySchedule(for: month, bypassingCache: false)
    }

    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMonthlySchedule(
        for month: KBOMonthScheduleKey,
        bypassingCache: Bool
    ) async throws -> [GameDetail] {
        #if DEBUG
        print("[SupabaseKBO] fetchMonthlySchedule start month=\(month.yearMonthText)")
        #endif
        do {
            return try await fetchSupabaseMonthlySchedule(for: month)
        } catch is CancellationError {
            #if DEBUG
            print("[SupabaseKBO] fetchMonthlySchedule cancelled month=\(month.yearMonthText)")
            #endif
            throw CancellationError()
        } catch {
            #if DEBUG
            print("[SupabaseRepository] monthly schedule failed for \(month.yearMonthText), falling back to base repository. error=\(error)")
            #endif
            return try await base.fetchMonthlySchedule(for: month, bypassingCache: bypassingCache)
        }
    }

    // fetchScheduleTabMonth 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchScheduleTabMonth(
        for month: KBOMonthScheduleKey,
        bypassingCache _: Bool
    ) async throws -> [GameDetail] {
        #if DEBUG
        print("[SupabaseKBO] fetchScheduleTabMonth start month=\(month.yearMonthText) fallbackSuppressed=true officialRequestsAvoided=true")
        #endif
        do {
            return try await fetchSupabaseMonthlySchedule(for: month)
        } catch is CancellationError {
            #if DEBUG
            print("[SupabaseKBO] fetchScheduleTabMonth cancelled month=\(month.yearMonthText)")
            #endif
            throw CancellationError()
        } catch {
            #if DEBUG
            print("[SupabaseKBO] fetchScheduleTabMonth failed month=\(month.yearMonthText) fallbackSuppressed=true officialRequestsAvoided=true error=\(error)")
            #endif
            throw error
        }
    }

    // fetchSupabaseMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated private func fetchSupabaseMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        let teamsTask = Task { try await cachedTeamRows() }
        let games = try await source.fetchGames(month: month)
        let teams = try await teamsTask.value
        let mapped = SupabaseKBOMapper.mapGames(gameRows: games, teamRows: teams)
            .sorted { $0.scheduledStart < $1.scheduledStart }
        await runtimeState?.record(source: .supabase, delivery: .supabase)
        #if DEBUG
        print("[SupabaseKBO] fetchMonthlySchedule success month=\(month.yearMonthText) count=\(mapped.count)")
        #endif
        return mapped
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        try await fetchSchedule(for: date, bypassingCache: false)
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        #if DEBUG
        print("[SupabaseKBO] fetchSchedule(date:) start date=\(date.ISO8601Format())")
        #endif
        do {
            let teamsTask = Task { try await cachedTeamRows() }
            let games = try await source.fetchGames(date: date)
            let snapshots = try await source.fetchLatestSnapshots(gameIDs: games.map(\.id))
            let teams = try await teamsTask.value
            let mapped = SupabaseKBOMapper.mapGames(gameRows: games, teamRows: teams, snapshotRows: snapshots)
                .sorted { $0.scheduledStart < $1.scheduledStart }
            await runtimeState?.record(source: .supabase, delivery: .supabase)
            #if DEBUG
            print("[SupabaseKBO] fetchSchedule(date:) success count=\(mapped.count) snapshots=\(snapshots.count)")
            #endif
            return mapped
        } catch is CancellationError {
            #if DEBUG
            print("[SupabaseKBO] fetchSchedule(date:) cancelled")
            #endif
            throw CancellationError()
        } catch {
            #if DEBUG
            if let missingColumn = supabaseSchemaMismatchColumn(from: error) {
                print("[SupabaseKBO] schemaMismatch code=42703 missingColumn=\(missingColumn) errorType=\(String(describing: type(of: error)))")
            }
            #endif
            if bypassingCache {
                #if DEBUG
                print("[SupabaseRepository] daily schedule failed for \(date). bypassingCache=true fallbackSuppressed=true errorType=\(String(describing: type(of: error)))")
                #endif
                throw error
            }
            #if DEBUG
            print("[SupabaseRepository] daily schedule failed for \(date). falling back to base repository. errorType=\(String(describing: type(of: error)))")
            #endif
            let fallback = try await base.fetchSchedule(for: date, bypassingCache: bypassingCache)
            #if DEBUG
            print("[SupabaseKBO] fetchSchedule(date:) fallback count=\(fallback.count)")
            #endif
            return fallback
        }
    }

    // fetchFavoriteTeamSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchFavoriteTeamSchedule(
        date: Date,
        favoriteTeamId: Team.ID,
        bypassingCache: Bool
    ) async throws -> [GameDetail] {
        let day = supabaseGameDateString(for: date)
        #if DEBUG
        print("HomeFavoriteGameRefresh start date=\(day) favoriteTeamId=\(favoriteTeamId)")
        #endif
        do {
            let teamsTask = Task { try await cachedTeamRows() }
            let games = try await source.fetchGames(date: date, favoriteTeamID: favoriteTeamId)
            let snapshots = try await source.fetchLatestSnapshots(gameIDs: games.map(\.id))
            let teams = try await teamsTask.value
            let mapped = SupabaseKBOMapper.mapGames(gameRows: games, teamRows: teams, snapshotRows: snapshots)
                .sorted { $0.scheduledStart < $1.scheduledStart }
            await runtimeState?.record(source: .supabase, delivery: .supabase)
            #if DEBUG
            print("HomeFavoriteGameRefresh gamesFetched=\(mapped.count) snapshotsFetched=\(snapshots.count)")
            #endif
            return mapped
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if bypassingCache {
                throw error
            }
            let fallback = try await base.fetchSchedule(for: date, bypassingCache: false)
                .filter { $0.involves(teamID: favoriteTeamId) }
                .sorted { $0.scheduledStart < $1.scheduledStart }
            #if DEBUG
            print("HomeFavoriteGameRefresh fallback gamesFetched=\(fallback.count) snapshotsFetched=0 error=\(error)")
            #endif
            return fallback
        }
    }

    // fetchStandings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        try await base.fetchStandings()
    }

    // fetchStandingsSource 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchStandingsSource(season: Int) async throws -> [GameDetail] {
        #if DEBUG
        print("[SupabaseKBO] fetchStandingsSource start season=\(season)")
        #endif
        do {
            let teamsTask = Task { try await cachedTeamRows() }
            let games = try await source.fetchGamesForStandings(season: season)
            let teams = try await teamsTask.value
            var mapped = SupabaseKBOMapper.mapGames(gameRows: games, teamRows: teams)
                .filter { $0.isRegularSeason && $0.hasCompleteFinalScore }
                .sorted { $0.scheduledStart < $1.scheduledStart }
            if mapped.isEmpty {
                #if DEBUG
                print("[SupabaseKBO] fetchStandingsSource filteredEmpty=true fallback=allSeason")
                #endif
                mapped = try await fetchSupabaseGames()
                    .filter { $0.isRegularSeason && $0.hasCompleteFinalScore }
                    .sorted { $0.scheduledStart < $1.scheduledStart }
            }
            await runtimeState?.record(source: .supabase, delivery: .supabase)
            #if DEBUG
            print("[SupabaseKBO] fetchStandingsSource success season=\(season) count=\(mapped.count)")
            #endif
            return mapped
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            #if DEBUG
            print("[SupabaseKBO] fetchStandingsSource failed season=\(season) fallback=none strictSupabaseOnly=true officialRequestsAvoided=true error=\(error)")
            #endif
            throw error
        }
    }

    // fetchTeamRanks 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchTeamRanks(season: Int) async throws -> [TeamRankRow] {
        guard season == 2026 else {
            return []
        }
        let teamsTask = Task { try await cachedTeamRows() }
        let rows = try await source.fetchTeamRanks2026()
        let teamRows = try await teamsTask.value
        let teamCodeByID = Dictionary(uniqueKeysWithValues: teamRows.map { ($0.id, SupabaseKBOMapper.normalizeTeamCode($0.code)) })
        let enriched = rows
            .map { row in
                TeamRankRow(
                    season: row.season,
                    teamID: row.teamID,
                    teamCode: teamCodeByID[row.teamID] ?? row.teamCode,
                    rank: row.rank,
                    teamName: row.teamName,
                    gamesPlayed: row.gamesPlayed,
                    wins: row.wins,
                    losses: row.losses,
                    draws: row.draws,
                    winningPercentage: row.winningPercentage,
                    gamesBehind: row.gamesBehind,
                    streakType: row.streakType,
                    streakCount: row.streakCount,
                    streakText: row.streakText,
                    lastGameDate: row.lastGameDate,
                    calculatedAt: row.calculatedAt,
                    updatedAt: row.updatedAt,
                    createdAt: row.createdAt
                )
            }
            .sorted { $0.rank < $1.rank }
        await runtimeState?.record(source: .supabase, delivery: .supabase)
        return enriched
    }

    // fetchSupabaseBootstrap 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated private func fetchSupabaseBootstrap() async throws -> KBOBootstrapData {
        let teamsTask = Task { try await cachedTeamRows() }
        let gamesTask = Task { try await source.fetchGames() }
        let teams = try await teamsTask.value
        let games = try await gamesTask.value
        return SupabaseKBOMapper.mapBootstrap(teamRows: teams, gameRows: games)
    }

    // fetchRemoteBootstrap 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated private func fetchRemoteBootstrap() async throws -> KBOBootstrapData {
        let supabaseBootstrap = try await fetchSupabaseBootstrap()
        await runtimeState?.record(source: .supabase, delivery: .supabase)
        #if DEBUG
        print("[SupabaseKBO] fetchBootstrapData remote success teams=\(supabaseBootstrap.teams.count) games=\(supabaseBootstrap.games.count)")
        #endif
        return KBOBootstrapData(
            teams: supabaseBootstrap.teams,
            games: supabaseBootstrap.games,
            notifications: [],
            settings: .default
        )
    }

    // fetchSupabaseGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated private func fetchSupabaseGames() async throws -> [GameDetail] {
        let teamsTask = Task { try await cachedTeamRows() }
        let gamesTask = Task { try await source.fetchGames() }
        let teams = try await teamsTask.value
        let games = try await gamesTask.value
        return SupabaseKBOMapper.mapGames(gameRows: games, teamRows: teams)
    }

    // cachedTeamRows 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func cachedTeamRows() async throws -> [SupabaseTeamRow] {
        try await teamCache.teams {
            try await source.fetchTeams()
        }
    }

}

extension SupabaseBackedKBORepository: KBOGameDetailSnapshotDataSource, KBOGameDetailSnapshotResultDataSource, KBOGameDetailLatestSnapshotDataSource, KBOGameIdentityResolutionDataSource, KBOGameDetailDatabaseRecordDataSource, KBOGameDetailDatabaseRecordDiagnosticDataSource {
    // fetchGameDetailDatabaseReview 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailDatabaseReview(for game: GameDetail) async throws -> GameCenterReview? {
        try await fetchGameDetailDatabaseReviewResult(for: game)?.review
    }

    // fetchGameDetailDatabaseReviewResult 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailDatabaseReviewResult(for game: GameDetail) async throws -> GameDetailDatabaseReviewFetchResult? {
        guard game.status == .final || game.status.isLiveLike else {
            #if DEBUG
            print("[GameDetailDBRecords] selectedRecordSource=none reason=nonRecordStatus status=\(game.status.rawValue) inputLocalGameId=\(game.id.uuidString)")
            #endif
            return nil
        }
        #if DEBUG
        print("[GameDetailDBRecords] dbRecordFetch inputLocalGameId=\(game.id.uuidString) publicGameID=\(game.publicGameID ?? "<nil>") providerGameID=\(game.providerGameID ?? "<nil>")")
        #endif
        guard let gameRow = try await resolveSupabaseGameRowForDatabaseRecords(for: game) else {
            #if DEBUG
            print("[GameDetailDBRecords] selectedRecordSource=none reason=missingGameRow inputLocalGameId=\(game.id.uuidString) providerGameID=\(game.providerGameID ?? "<nil>")")
            #endif
            return nil
        }
        let recordGameID = gameRow.id
        #if DEBUG
        print("[GameDetailDBRecords] dbRecordFetch resolvedSupabaseGameId=\(recordGameID.uuidString) inputLocalGameId=\(game.id.uuidString) providerGameID=\(gameRow.providerGameID ?? game.providerGameID ?? "<nil>")")
        #endif

        async let batterRowsTask = source.fetchGameBatterRecords(gameID: recordGameID)
        async let pitcherRowsTask = source.fetchGamePitcherRecords(gameID: recordGameID)
        async let eventRowsTask = fetchGameEventsIfAllowed(gameID: recordGameID)
        let batterRows = try await batterRowsTask
        let pitcherRows = try await pitcherRowsTask
        let eventRows = await eventRowsTask

        #if DEBUG
        print("[GameDetailDBRecords] DB batter count=\(batterRows.count) gameID=\(recordGameID.uuidString)")
        print("[GameDetailDBRecords] DB pitcher count=\(pitcherRows.count) gameID=\(recordGameID.uuidString)")
        print("[GameDetailDBRecords] DB event count=\(eventRows.count) gameID=\(recordGameID.uuidString)")
        #endif

        let mappedReview = await SupabaseKBOMapper.mapDetailedRecordReview(
            game: game,
            recordGameID: recordGameID,
            awayTeamDatabaseID: gameRow.awayTeamID,
            homeTeamDatabaseID: gameRow.homeTeamID,
            batterRows: batterRows,
            pitcherRows: pitcherRows,
            eventRows: eventRows
        )
        let latestRecordUpdatedAt = Self.latestRecordUpdatedAt(batterRows: batterRows, pitcherRows: pitcherRows)
        let review = Self.reviewForStatus(game.status, review: mappedReview, latestRecordUpdatedAt: latestRecordUpdatedAt)
        #if DEBUG
        print("[GameDetailDBRecords] dbRecordFetch resolvedSupabaseGameId=\(recordGameID.uuidString) providerGameID=\(gameRow.providerGameID ?? game.providerGameID ?? "<nil>") batterCount=\(batterRows.count) pitcherCount=\(pitcherRows.count) eventCount=\(eventRows.count) latestRecordUpdatedAt=\(latestRecordUpdatedAt.map(SupabaseDateParser.debugTimestamp) ?? "<nil>") selectedRecordSource=\(review?.recordSource.rawValue ?? "none")")
        #endif
        return GameDetailDatabaseReviewFetchResult(
            review: review,
            inputLocalGameID: game.id,
            rawSupabaseGameID: recordGameID,
            resolvedSupabaseGameID: recordGameID,
            providerGameID: gameRow.providerGameID ?? game.providerGameID,
            publicGameID: gameRow.publicGameID ?? game.publicGameID,
            publicBatterRawRowCount: batterRows.count,
            publicPitcherRawRowCount: pitcherRows.count,
            eventRawRowCount: eventRows.count,
            latestRecordUpdatedAt: latestRecordUpdatedAt
        )
    }

    // fetchGameDetailDatabaseReview 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailDatabaseReview(
        providerGameID: String?,
        publicGameID: String?,
        invokedFrom: String
    ) async throws -> GameDetailDatabaseReviewFetchResult? {
        #if DEBUG
        print("[GameDetailDBRecords] providerDbRecordFetch invokedFrom=\(invokedFrom) providerGameID=\(providerGameID ?? "<nil>") publicGameID=\(publicGameID ?? "<nil>")")
        #endif
        let lookups = databaseRecordProviderLookups(
            providerGameID: providerGameID,
            publicGameID: publicGameID
        )
        for lookup in lookups {
            let rows = try await source.fetchGame(lookup: lookup)
            #if DEBUG
            print("[GameDetailDBRecords] providerDbRecordFetch lookup key=\(lookup.debugKey) value=\(lookup.debugValue) count=\(rows.count)")
            #endif
            guard let row = rows.first else { continue }
            return try await fetchGameDetailDatabaseReview(
                supabaseGameId: row.id,
                providerGameID: row.providerGameID ?? providerGameID,
                publicGameID: row.publicGameID ?? publicGameID,
                invokedFrom: invokedFrom
            )
        }
        #if DEBUG
        print("[GameDetailDBRecords] selectedRecordSource=none reason=missingProviderResolvedGameRow providerGameID=\(providerGameID ?? "<nil>") publicGameID=\(publicGameID ?? "<nil>")")
        #endif
        return nil
    }

    // databaseRecordProviderLookups 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func databaseRecordProviderLookups(
        providerGameID: String?,
        publicGameID: String?
    ) -> [SupabaseGameLookup] {
        var lookups: [SupabaseGameLookup] = []
        var seen = Set<String>()

        // append 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
        func append(_ lookup: SupabaseGameLookup) {
            let key = "\(lookup.debugKey)=\(lookup.debugValue)"
            guard seen.insert(key).inserted else { return }
            lookups.append(lookup)
        }

        if let providerGameID = providerGameID?.trimmingCharacters(in: .whitespacesAndNewlines),
           providerGameID.isEmpty == false {
            append(.providerGameID(providerGameID))
            append(.officialProviderGameID(providerGameID))
        }
        if let publicGameID = publicGameID?.trimmingCharacters(in: .whitespacesAndNewlines),
           publicGameID.isEmpty == false {
            append(.publicGameID(publicGameID))
        }
        return lookups
    }

    // fetchGameDetailDatabaseReview 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailDatabaseReview(
        supabaseGameId: UUID,
        providerGameID: String?,
        publicGameID: String?,
        invokedFrom: String
    ) async throws -> GameDetailDatabaseReviewFetchResult? {
        #if DEBUG
        print("[GameDetailDBRecords] explicitDbRecordFetch invokedFrom=\(invokedFrom) rawSupabaseGameId=\(supabaseGameId.uuidString) providerGameID=\(providerGameID ?? "<nil>") publicGameID=\(publicGameID ?? "<nil>")")
        #endif
        let gameRows = try await source.fetchGame(lookup: .databaseID(supabaseGameId))
        guard let gameRow = gameRows.first else {
            #if DEBUG
            print("[GameDetailDBRecords] selectedRecordSource=none reason=missingRawSupabaseGameRow rawSupabaseGameId=\(supabaseGameId.uuidString) providerGameID=\(providerGameID ?? "<nil>")")
            #endif
            return nil
        }
        let teamRows = try await cachedTeamRows()
        let mappedGames = SupabaseKBOMapper.mapGames(gameRows: [gameRow], teamRows: teamRows)
        guard let mappedGame = mappedGames.first else {
            #if DEBUG
            print("[GameDetailDBRecords] selectedRecordSource=none reason=rawSupabaseGameRowMappingFailed rawSupabaseGameId=\(supabaseGameId.uuidString)")
            #endif
            return nil
        }

        async let batterRowsTask = source.fetchGameBatterRecords(gameID: supabaseGameId)
        async let pitcherRowsTask = source.fetchGamePitcherRecords(gameID: supabaseGameId)
        async let eventRowsTask = fetchGameEventsIfAllowed(gameID: supabaseGameId)
        let batterRows = try await batterRowsTask
        let pitcherRows = try await pitcherRowsTask
        let eventRows = await eventRowsTask

        let mappedReview = await SupabaseKBOMapper.mapDetailedRecordReview(
            game: mappedGame,
            recordGameID: supabaseGameId,
            awayTeamDatabaseID: gameRow.awayTeamID,
            homeTeamDatabaseID: gameRow.homeTeamID,
            batterRows: batterRows,
            pitcherRows: pitcherRows,
            eventRows: eventRows
        )
        let latestRecordUpdatedAt = Self.latestRecordUpdatedAt(batterRows: batterRows, pitcherRows: pitcherRows)
        let review = Self.reviewForStatus(mappedGame.status, review: mappedReview, latestRecordUpdatedAt: latestRecordUpdatedAt)

        #if DEBUG
        print("[GameDetailDBRecords] explicitDbRecordFetch invokedFrom=\(invokedFrom) rawSupabaseGameId=\(supabaseGameId.uuidString) batterCount=\(batterRows.count) pitcherCount=\(pitcherRows.count) eventCount=\(eventRows.count) latestRecordUpdatedAt=\(latestRecordUpdatedAt.map(SupabaseDateParser.debugTimestamp) ?? "<nil>") selectedRecordSource=\(review?.recordSource.rawValue ?? "none")")
        #endif
        return GameDetailDatabaseReviewFetchResult(
            review: review,
            inputLocalGameID: mappedGame.id,
            rawSupabaseGameID: supabaseGameId,
            resolvedSupabaseGameID: supabaseGameId,
            providerGameID: gameRow.providerGameID ?? providerGameID,
            publicGameID: gameRow.publicGameID ?? publicGameID,
            publicBatterRawRowCount: batterRows.count,
            publicPitcherRawRowCount: pitcherRows.count,
            eventRawRowCount: eventRows.count,
            latestRecordUpdatedAt: latestRecordUpdatedAt
        )
    }

    nonisolated private static func reviewForStatus(
        _ status: GameStatus,
        review: GameCenterReview?,
        latestRecordUpdatedAt: Date?,
        now: Date = Date()
    ) -> GameCenterReview? {
        guard let review else { return nil }
        guard status.isLiveLike else { return review }
        guard let latestRecordUpdatedAt,
              now.timeIntervalSince(latestRecordUpdatedAt) <= GameDetailDatabaseReviewFetchResult.liveRecordFreshnessThreshold else {
            return review.withRecordSource(
                .staleDbRecordsIgnored,
                recordUpdatedAt: latestRecordUpdatedAt
            )
        }
        return review.withRecordSource(
            .dbLiveRecordsFresh,
            recordUpdatedAt: latestRecordUpdatedAt
        )
    }

    nonisolated private static func latestRecordUpdatedAt(
        batterRows: [SupabaseGameBatterRecordRow],
        pitcherRows: [SupabaseGamePitcherRecordRow]
    ) -> Date? {
        let dates = batterRows.compactMap { recordUpdatedAt(sourceUpdatedAt: $0.sourceUpdatedAt, updatedAt: $0.updatedAt) } +
            pitcherRows.compactMap { recordUpdatedAt(sourceUpdatedAt: $0.sourceUpdatedAt, updatedAt: $0.updatedAt) }
        return dates.max()
    }

    nonisolated private static func recordUpdatedAt(sourceUpdatedAt: String?, updatedAt: String?) -> Date? {
        [sourceUpdatedAt, updatedAt]
            .compactMap { $0 }
            .compactMap(SupabaseDateParser.parseTimestamp)
            .max()
    }

    // resolveSupabaseGameRowForDatabaseRecords 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    nonisolated private func resolveSupabaseGameRowForDatabaseRecords(for game: GameDetail) async throws -> SupabaseGameRow? {
        let directLookups = databaseRecordDetailLookups(for: game)
        for lookup in directLookups {
            let rows = try await source.fetchGame(lookup: lookup)
            guard let row = rows.first else { continue }
            return row
        }

        let teamRows = try await cachedTeamRows()
        for lookup in teamFallbackDetailLookups(for: game, teamRows: teamRows) {
            let rows = try await source.fetchGame(lookup: lookup)
            guard let row = rows.first else { continue }
            return row
        }

        return nil
    }

    // databaseRecordDetailLookups 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func databaseRecordDetailLookups(for game: GameDetail) -> [SupabaseGameLookup] {
        var lookups = directDetailLookups(for: game, identity: game.stableDetailIdentity)
        var seen = Set(lookups.map { "\($0.debugKey)=\($0.debugValue)" })

        // append 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
        func append(_ lookup: SupabaseGameLookup) {
            let key = "\(lookup.debugKey)=\(lookup.debugValue)"
            guard seen.insert(key).inserted else { return }
            lookups.append(lookup)
        }

        if let publicGameID = game.publicGameID?.trimmingCharacters(in: .whitespacesAndNewlines),
           publicGameID.isEmpty == false {
            append(.publicGameID(publicGameID))
        }
        if let officialProviderGameID = game.officialProviderGameID?.trimmingCharacters(in: .whitespacesAndNewlines),
           officialProviderGameID.isEmpty == false {
            append(.officialProviderGameID(officialProviderGameID))
        }
        append(.databaseID(game.id))
        return lookups
    }

    // fetchGameEventsIfAllowed 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated private func fetchGameEventsIfAllowed(gameID: UUID) async -> [SupabaseGameEventRow] {
        do {
            return try await source.fetchGameEvents(gameID: gameID)
        } catch {
            #if DEBUG
            print("[GameDetailDBRecords] DB event fetch skipped gameID=\(gameID.uuidString) reason=unavailableOrPolicy error=\(error)")
            #endif
            return []
        }
    }

    // fetchGameDetailIdentitySnapshot 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailIdentitySnapshot(
        identity: String,
        cachedTeams: [Team]
    ) async throws -> GameDetail? {
        let lookups = identityFallbackDetailLookups(for: identity)
        guard lookups.isEmpty == false else { return nil }
        let fetchedTeamRows = try await cachedTeamRows()

        for lookup in lookups {
            #if DEBUG
            print("[GameDetailFetch] fallback query key=\(lookup.debugKey) value=\(lookup.debugValue)")
            #endif
            let rows = try await source.fetchGame(lookup: lookup)
            #if DEBUG
            print("[GameDetailFetch] fallback fetched count=\(rows.count)")
            #endif
            guard let row = rows.first else { continue }
            let mappedGames = SupabaseKBOMapper.mapGames(gameRows: [row], teamRows: fetchedTeamRows)
            guard let baseMapped = mappedGames.first else { continue }
            let snapshot = try await latestSnapshotIfNeeded(for: row, fallbackGame: baseMapped)
            let mapped = SupabaseKBOMapper.mapGame(
                row: row,
                teamRows: fetchedTeamRows,
                snapshot: snapshot,
                fallbackGame: baseMapped
            )
            await runtimeState?.record(source: .supabase, delivery: .supabase)
            #if DEBUG
            print("[GameDetailFetch] fallback success publicGameID=\(mapped.publicGameID ?? "<nil>") providerGameID=\(mapped.providerGameID ?? "<nil>") officialProviderGameID=\(mapped.officialProviderGameID ?? "<nil>")")
            #endif
            return mapped
        }

        #if DEBUG
        print("[GameDetailFetch] fallback failure selectedIdentity=\(identity)")
        #endif
        return nil
    }

    // fetchGameDetailSnapshot 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailSnapshot(
        for game: GameDetail,
        identity: String,
        cachedTeams: [Team]
    ) async throws -> GameDetail? {
        try await fetchGameDetailSnapshotResult(
            for: game,
            identity: identity,
            cachedTeams: cachedTeams
        )?.game
    }

    // fetchGameDetailSnapshotResult 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameDetailSnapshotResult(
        for game: GameDetail,
        identity: String,
        cachedTeams: [Team]
    ) async throws -> GameDetailSnapshotFetchResult? {
        let directLookups = directDetailLookups(for: game, identity: identity)
        var fetchedTeamRows: [SupabaseTeamRow] = []

        #if DEBUG
        print("fetchGameDetail(single:) start identity=\(identity) selected=\(game.supabaseDebugIdentifier)")
        print("[GameDetailFetch] mode=singleGame selectedIdentity=\(identity) selected=\(game.supabaseDebugIdentifier) cachedTeams=\(cachedTeams.count)")
        #endif

        for lookup in directLookups {
            let rows = try await source.fetchGame(lookup: lookup)
            #if DEBUG
            print("[GameDetailFetch] query key=\(lookup.debugKey) value=\(lookup.debugValue)")
            print("[GameDetailFetch] fetched count=\(rows.count)")
            for row in rows {
                print("[GameDetailFetch] row id=\(row.id.uuidString) provider_game_id=\(row.providerGameID ?? "<nil>") public_game_id=\(row.publicGameID ?? "<nil>") status=\(row.status ?? "<nil>") score=\(row.awayScore.map(String.init) ?? "-"):\(row.homeScore.map(String.init) ?? "-") inning=\(row.inningState ?? "<nil>") stadium=\(row.stadium ?? "<nil>")")
            }
            #endif
            guard let row = rows.first else { continue }
            let snapshot = try await latestSnapshotIfNeeded(for: row, fallbackGame: game)
            await runtimeState?.record(source: .supabase, delivery: .supabase)
            let mapped = SupabaseKBOMapper.mapGame(row: row, teamRows: fetchedTeamRows, snapshot: snapshot, fallbackGame: game)
            #if DEBUG
            print("[GameDetailSnapshot] game_id=\(row.id.uuidString) inning=\(snapshot?.inningLabel ?? "<nil>") balls=\(snapshot?.balls.map(String.init) ?? "-") strikes=\(snapshot?.strikes.map(String.init) ?? "-") outs=\(snapshot?.outs.map(String.init) ?? "-") bases=\((snapshot?.runnerOnFirst ?? false) ? "1" : "-")\((snapshot?.runnerOnSecond ?? false) ? "2" : "-")\((snapshot?.runnerOnThird ?? false) ? "3" : "-") currentPitcher=\(supabaseDebugText(snapshot?.currentPitcherName)) batter=\(supabaseDebugText(snapshot?.currentBatterName))")
            print("fetchGameDetail(single:) success identity=\(identity) id=\(mapped.supabaseDebugIdentifier)")
            #endif
            return GameDetailSnapshotFetchResult(
                game: mapped,
                rawSupabaseGameID: row.id,
                providerGameID: row.providerGameID ?? mapped.providerGameID,
                publicGameID: row.publicGameID ?? mapped.publicGameID
            )
        }

        fetchedTeamRows = try await cachedTeamRows()
        for lookup in teamFallbackDetailLookups(for: game, teamRows: fetchedTeamRows) {
            let rows = try await source.fetchGame(lookup: lookup)
            #if DEBUG
            print("[GameDetailFetch] query key=\(lookup.debugKey) value=\(lookup.debugValue)")
            print("[GameDetailFetch] fetched count=\(rows.count)")
            for row in rows {
                print("[GameDetailFetch] row id=\(row.id.uuidString) provider_game_id=\(row.providerGameID ?? "<nil>") public_game_id=\(row.publicGameID ?? "<nil>") status=\(row.status ?? "<nil>") score=\(row.awayScore.map(String.init) ?? "-"):\(row.homeScore.map(String.init) ?? "-") inning=\(row.inningState ?? "<nil>") stadium=\(row.stadium ?? "<nil>")")
            }
            #endif
            guard let row = rows.first else { continue }
            let snapshot = try await latestSnapshotIfNeeded(for: row, fallbackGame: game)
            await runtimeState?.record(source: .supabase, delivery: .supabase)
            let mapped = SupabaseKBOMapper.mapGame(row: row, teamRows: fetchedTeamRows, snapshot: snapshot, fallbackGame: game)
            #if DEBUG
            print("[GameDetailSnapshot] game_id=\(row.id.uuidString) inning=\(snapshot?.inningLabel ?? "<nil>") balls=\(snapshot?.balls.map(String.init) ?? "-") strikes=\(snapshot?.strikes.map(String.init) ?? "-") outs=\(snapshot?.outs.map(String.init) ?? "-") bases=\((snapshot?.runnerOnFirst ?? false) ? "1" : "-")\((snapshot?.runnerOnSecond ?? false) ? "2" : "-")\((snapshot?.runnerOnThird ?? false) ? "3" : "-") currentPitcher=\(supabaseDebugText(snapshot?.currentPitcherName)) batter=\(supabaseDebugText(snapshot?.currentBatterName))")
            print("fetchGameDetail(single:) success identity=\(identity) id=\(mapped.supabaseDebugIdentifier)")
            #endif
            return GameDetailSnapshotFetchResult(
                game: mapped,
                rawSupabaseGameID: row.id,
                providerGameID: row.providerGameID ?? mapped.providerGameID,
                publicGameID: row.publicGameID ?? mapped.publicGameID
            )
        }

        return nil
    }

    // latestSnapshotIfNeeded 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func latestSnapshotIfNeeded(
        for row: SupabaseGameRow,
        fallbackGame: GameDetail
    ) async throws -> SupabaseLatestGameSnapshotRow? {
        let snapshot = try await source.fetchLatestSnapshot(gameID: row.id)
        #if DEBUG
        let status = row.status.map {
            KBODataMapper.mapGameStatus(code: $0, text: nil)
        } ?? fallbackGame.status
        print("[GameDetailFetch] latestSnapshot fetched game_id=\(row.id.uuidString) publicGameID=\(row.publicGameID ?? "<nil>") providerGameID=\(row.providerGameID ?? "<nil>") rowStatus=\(status.rawValue) snapshotStatus=\(snapshot == nil ? "<nil>" : "present") score=\(row.awayScore.map(String.init) ?? "-"):\(row.homeScore.map(String.init) ?? "-") inning=\(snapshot?.inningLabel ?? row.inningState ?? "<nil>")")
        #endif
        return snapshot
    }

    nonisolated func fetchLatestGameSnapshotResult(
        gameID: UUID,
        fallbackGame: GameDetail
    ) async throws -> GameDetailSnapshotFetchResult? {
        let snapshot = try await source.fetchLatestSnapshot(gameID: gameID)
        guard let snapshot else { return nil }
        #if DEBUG
        print("[GameDetailLiveSituation] latest snapshot-only fetched source=public_latest_game_snapshots game_id=\(gameID.uuidString) created_at=\(snapshot.createdAt.map(SupabaseDateParser.debugTimestamp) ?? "<nil>") updated_at=\((snapshot.updatedAt ?? snapshot.sourceUpdatedAt ?? snapshot.fetchedAt).map(SupabaseDateParser.debugTimestamp) ?? "<nil>")")
        #endif
        return GameDetailSnapshotFetchResult(
            game: fallbackGame.applyingLatestSupabaseSnapshot(snapshot),
            rawSupabaseGameID: gameID,
            providerGameID: fallbackGame.providerGameID,
            publicGameID: fallbackGame.publicGameID,
            snapshotCreatedAt: snapshot.createdAt,
            snapshotUpdatedAt: snapshot.updatedAt ?? snapshot.sourceUpdatedAt ?? snapshot.fetchedAt
        )
    }

    // identityFallbackDetailLookups 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func identityFallbackDetailLookups(for identity: String) -> [SupabaseGameLookup] {
        let trimmed = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }
        var lookups: [SupabaseGameLookup] = []
        var seen: Set<String> = []

        // append 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
        func append(_ lookup: SupabaseGameLookup) {
            let key = "\(lookup.debugKey)=\(lookup.debugValue)"
            guard seen.insert(key).inserted else { return }
            lookups.append(lookup)
        }

        if trimmed.hasPrefix("public:") {
            let value = String(trimmed.dropFirst("public:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty == false {
                append(.publicGameID(value))
            }
            return lookups
        }

        if trimmed.hasPrefix("provider:") {
            let value = String(trimmed.dropFirst("provider:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty == false {
                append(.providerGameID(value))
                append(.officialProviderGameID(value))
            }
            return lookups
        }

        if trimmed.hasPrefix("id:") {
            let value = String(trimmed.dropFirst("id:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let id = UUID(uuidString: value) {
                append(.databaseID(id))
            }
            return lookups
        }

        if let id = UUID(uuidString: trimmed) {
            append(.databaseID(id))
            return lookups
        }

        if trimmed.hasPrefix("sched-") {
            append(.providerGameID(trimmed))
            append(.officialProviderGameID(trimmed))
            return lookups
        }

        if trimmed.contains("-") {
            append(.publicGameID(trimmed))
            append(.providerGameID(trimmed))
            append(.officialProviderGameID(trimmed))
            return lookups
        }

        append(.providerGameID(trimmed))
        append(.officialProviderGameID(trimmed))
        append(.publicGameID(trimmed))
        return lookups
    }

    // directDetailLookups 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func directDetailLookups(for game: GameDetail, identity: String) -> [SupabaseGameLookup] {
        var lookups: [SupabaseGameLookup] = []
        var seen: Set<String> = []

        // append 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
        func append(_ lookup: SupabaseGameLookup) {
            let key = "\(lookup.debugKey)=\(lookup.debugValue)"
            guard seen.insert(key).inserted else { return }
            lookups.append(lookup)
        }

        if let providerGameID = game.providerGameID?.trimmingCharacters(in: .whitespacesAndNewlines),
           providerGameID.isEmpty == false {
            append(.providerGameID(providerGameID))
        }
        if let officialProviderGameID = game.officialProviderGameID?.trimmingCharacters(in: .whitespacesAndNewlines),
           officialProviderGameID.isEmpty == false {
            append(.providerGameID(officialProviderGameID))
        }
        if let publicGameID = game.supabaseNoteToken("public_game_id") {
            append(.publicGameID(publicGameID))
        }
        if identity.hasPrefix("provider:") {
            let providerGameID = String(identity.dropFirst("provider:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if providerGameID.isEmpty == false {
                append(.providerGameID(providerGameID))
            }
        }
        if identity.hasPrefix("public:") {
            let publicGameID = String(identity.dropFirst("public:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if publicGameID.isEmpty == false {
                append(.publicGameID(publicGameID))
            }
        }
        if identity.contains("-") && UUID(uuidString: identity) == nil {
            append(.publicGameID(identity))
        }
        return lookups
    }

    // teamFallbackDetailLookups 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func teamFallbackDetailLookups(
        for game: GameDetail,
        teamRows: [SupabaseTeamRow]
    ) -> [SupabaseGameLookup] {
        let rowsByCode = Dictionary(uniqueKeysWithValues: teamRows.map { (SupabaseKBOMapper.normalizeTeamCode($0.code), $0) })
        guard let awayTeamID = rowsByCode[SupabaseKBOMapper.normalizeTeamCode(game.awayTeam.id)]?.id,
              let homeTeamID = rowsByCode[SupabaseKBOMapper.normalizeTeamCode(game.homeTeam.id)]?.id else {
            return []
        }

        let gameDate = supabaseGameDateString(for: game.scheduledStart)
        var lookups: [SupabaseGameLookup] = [
            .dateTeamIDs(gameDate: gameDate, awayTeamID: awayTeamID, homeTeamID: homeTeamID)
        ]
        let stadium = game.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        if stadium.isEmpty == false {
            lookups.append(.dateTeamVenue(gameDate: gameDate, awayTeamID: awayTeamID, homeTeamID: homeTeamID, stadium: stadium))
        }
        return lookups
    }

    // supabaseGameDateString 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func supabaseGameDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

extension SupabaseBackedKBORepository: KBOScheduleRemoteSyncDataSource {
    // fetchRemoteGameCount 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchRemoteGameCount() async throws -> Int {
        try await source.fetchGameCount()
    }

    // fetchMissingScheduleGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMissingScheduleGames(excludingKnownGames knownGames: [GameDetail]) async throws -> KBOScheduleMissingGamesResult {
        let knownProviderIDs = Set(
            knownGames.compactMap { game in
                game.officialGameCenterID?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { $0.isEmpty == false }
        )
        let teamsTask = Task { try await cachedTeamRows() }
        let gameRows = try await source.fetchGames(excludingProviderGameIDs: knownProviderIDs)
        let teams = try await teamsTask.value
        let games = SupabaseKBOMapper.mapGames(gameRows: gameRows, teamRows: teams)
            .sorted { $0.scheduledStart < $1.scheduledStart }
        return KBOScheduleMissingGamesResult(remoteCount: games.count, games: games)
    }
}

private extension GameDetail {
    nonisolated func applyingLatestSupabaseSnapshot(_ snapshot: SupabaseLatestGameSnapshotRow) -> GameDetail {
        let bases = RunnerState(
            first: snapshot.runnerOnFirst ?? false,
            second: snapshot.runnerOnSecond ?? false,
            third: snapshot.runnerOnThird ?? false
        )
        let snapshotAwayScore: Int? = snapshot.awayScore ?? awayScore
        let snapshotHomeScore: Int? = snapshot.homeScore ?? homeScore
        let snapshotInningText: String? = Self.cleanSnapshotText(snapshot.inningLabel) ?? inningText
        let snapshotBaseRunners = GameBaseRunners(
            first: bases.first ? Self.cleanSnapshotText(snapshot.firstBaseRunnerName) : nil,
            second: bases.second ? Self.cleanSnapshotText(snapshot.secondBaseRunnerName) : nil,
            third: bases.third ? Self.cleanSnapshotText(snapshot.thirdBaseRunnerName) : nil
        )
        let snapshotCurrentPitcherName: String? = Self.cleanSnapshotText(snapshot.currentPitcherName)
        let snapshotCurrentBatterName: String? = Self.cleanSnapshotText(snapshot.currentBatterName)
        return GameDetail(
            id: id,
            scheduledStart: scheduledStart,
            venue: venue,
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: snapshotAwayScore,
            homeScore: snapshotHomeScore,
            status: status,
            seasonClassification: seasonClassification,
            inningText: snapshotInningText,
            bases: bases,
            baseRunners: snapshotBaseRunners,
            balls: snapshot.balls,
            strikes: snapshot.strikes,
            outs: snapshot.outs,
            highlightText: highlightText,
            events: events,
            note: note,
            providerGameID: providerGameID,
            awayStartingPitcherName: awayStartingPitcherName,
            homeStartingPitcherName: homeStartingPitcherName,
            currentPitcherName: snapshotCurrentPitcherName,
            currentBatterName: snapshotCurrentBatterName
        )
    }

    nonisolated static func cleanSnapshotText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // supabaseNoteToken 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated func supabaseNoteToken(_ key: String) -> String? {
        guard let note,
              let range = note.range(of: "\(key)=") else {
            return nil
        }
        let suffix = note[range.upperBound...]
        return suffix.split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map(String.init)
    }
}

#if DEBUG
// supabaseDebugText 메서드는 이 타입의 주요 동작을 수행합니다.
private nonisolated func supabaseDebugText(_ value: String?) -> String {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? "<nil>" : trimmed
}

// baseDebugText 메서드는 이 타입의 주요 동작을 수행합니다.
private nonisolated func baseDebugText(_ bases: RunnerState?) -> String {
    guard let bases else { return "---" }
    return "\(bases.first ? "1" : "-")\(bases.second ? "2" : "-")\(bases.third ? "3" : "-")"
}

// supabaseSchemaMismatchColumn 메서드는 이 타입의 주요 동작을 수행합니다.
private nonisolated func supabaseSchemaMismatchColumn(from error: any Error) -> String? {
    let text = String(describing: error)
    guard text.contains("42703") || text.localizedCaseInsensitiveContains("does not exist") else {
        return nil
    }

    if text.contains("games.stadium_code") {
        return "stadium_code"
    }

    guard let range = text.range(of: "column games.") else {
        return "<unknown>"
    }

    let suffix = text[range.upperBound...]
    let column = suffix
        .split(whereSeparator: { character in
            character == " " || character == "\"" || character == "'" || character == "\n"
        })
        .first
        .map(String.init)
    return column?.isEmpty == false ? column : "<unknown>"
}

private extension GameDetail {
    nonisolated var supabaseDebugIdentifier: String {
        supabaseNoteToken("public_game_id") ?? officialGameCenterID ?? id.uuidString
    }
}
#endif

#if canImport(Supabase)
import Supabase

// Read-only client for public KBO views exposed through Supabase's HTTP API layer.
// SupabaseKBORepository 구조체는 KBO 데이터 조회와 저장소 접근 흐름을 담당합니다.
struct SupabaseKBORepository: SupabaseKBOReading, Sendable {
    private let baseURL: URL
    private let schemaName: String
    private let client: SupabaseClient
    private let calendar: Calendar
    private let teamCache = SupabaseTeamRowCache()
    nonisolated var configuredSchemaName: String {
        schemaName
    }
    nonisolated static let gameSelectColumns = [
        "id",
        "public_game_id",
        "provider",
        "provider_game_id",
        "official_provider_game_id",
        "game_date",
        "scheduled_at",
        "stadium",
        "status",
        "status_reason",
        "home_team_id",
        "away_team_id",
        "home_score",
        "away_score",
        "inning_state",
        "is_cancelled",
        "is_postponed",
        "source_updated_at",
        "updated_at",
        "final_confirmed_at",
        "live_last_checked_at",
        "away_starting_pitcher_name",
        "home_starting_pitcher_name"
    ].joined(separator: ",")
    nonisolated static let batterRecordSelectColumns = [
        "id",
        "game_id",
        "team_id",
        "source_order",
        "batting_order",
        "position",
        "player_name",
        "at_bats",
        "runs",
        "hits",
        "rbi",
        "home_runs",
        "walks",
        "strikeouts",
        "stolen_bases",
        "grounded_into_double_play",
        "errors",
        "batting_average",
        "updated_at"
    ].joined(separator: ",")
    nonisolated static let pitcherRecordSelectColumns = [
        "id",
        "game_id",
        "team_id",
        "source_order",
        "pitching_order",
        "player_name",
        "appearance",
        "decision_result",
        "wins",
        "losses",
        "saves",
        "innings_pitched",
        "batters_faced",
        "pitch_count",
        "at_bats",
        "hits",
        "home_runs",
        "walks_or_hit_by_pitch",
        "strikeouts",
        "runs",
        "earned_runs",
        "era",
        "updated_at"
    ].joined(separator: ",")
    nonisolated static let gameEventSelectColumns = [
        "id",
        "game_id",
        "provider_event_id",
        "sequence_number",
        "inning",
        "inning_half",
        "event_type",
        "event_text"
    ].joined(separator: ",")

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(configuration: SupabaseConfiguration) {
        self.baseURL = configuration.url
        self.schemaName = configuration.schema
        self.client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey,
            options: .init(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        self.calendar = calendar

        #if DEBUG
        print("[SupabaseConfig] client initialized host=\(configuration.url.host ?? "<none>") schema=\(schemaName)")
        #endif
    }

    // fetchTeams 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchTeams() async throws -> [SupabaseTeamRow] {
        try await teamCache.teams {
            try await fetchTeamsFromDatabase()
        }
    }

    // fetchTeamsFromDatabase 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated private func fetchTeamsFromDatabase() async throws -> [SupabaseTeamRow] {
        #if DEBUG
        print("[SupabaseKBO] fetchTeams start schema=\(schemaName) view=public_teams baseURL=\(baseURL.absoluteString)")
        #endif
        let rows: [SupabaseTeamRow] = try await database
            .from("public_teams")
            .select()
            .order("team_code", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchTeams success schema=\(schemaName) view=public_teams count=\(rows.count)")
        #endif
        return rows
    }

    // fetchGameCount 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameCount() async throws -> Int {
        #if DEBUG
        print("[SupabaseKBO] fetchGameCount query start schema=\(schemaName) view=public_games")
        #endif
        let count = try await database
            .from("public_games")
            .select(head: true, count: .exact)
            .execute()
            .count ?? 0
        #if DEBUG
        print("[SupabaseKBO] fetchGameCount success schema=\(schemaName) view=public_games count=\(count)")
        #endif
        return count
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [SupabaseGameRow] {
        #if DEBUG
        print("[SupabaseKBO] fetchGames query start schema=\(schemaName) view=public_games dateRange=all")
        print("[SupabaseKBO] gamesSelect columns=\(Self.gameSelectColumns)")
        #endif
        let rows: [SupabaseGameRow] = try await database
            .from("public_games")
            .select(Self.gameSelectColumns)
            .order("game_date", ascending: true)
            .order("scheduled_at", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchGames success schema=\(schemaName) view=public_games count=\(rows.count)")
        #endif
        return rows
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(excludingProviderGameIDs providerGameIDs: Set<String>) async throws -> [SupabaseGameRow] {
        let excludedIDs = providerGameIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false && $0.contains(",") == false && $0.contains("(") == false && $0.contains(")") == false }
            .sorted()

        #if DEBUG
        print("[SupabaseKBO] fetchGames(excluding:) query start schema=\(schemaName) view=public_games excludedProviderIDs=\(excludedIDs.count)")
        print("[SupabaseKBO] gamesSelect columns=\(Self.gameSelectColumns)")
        #endif

        let query = database
            .from("public_games")
            .select(Self.gameSelectColumns)
        if excludedIDs.isEmpty == false {
            _ = query.not("provider_game_id", operator: .in, value: "(\(excludedIDs.joined(separator: ",")))")
        }

        let rows: [SupabaseGameRow] = try await query
            .order("game_date", ascending: true)
            .order("scheduled_at", ascending: true)
            .execute()
            .value

        #if DEBUG
        print("[SupabaseKBO] fetchGames(excluding:) success schema=\(schemaName) view=public_games count=\(rows.count)")
        #endif
        return rows
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(month: KBOMonthScheduleKey) async throws -> [SupabaseGameRow] {
        let interval = monthInterval(for: month)
        AppLog.info(.supabase, "[SupabaseKBO] fetchGames(month:) start schema=\(schemaName) view=public_games month=\(month.yearMonthText)")
        #if DEBUG
        print(
            "[SupabaseKBO] fetchGames(month:) query start schema=\(schemaName) view=public_games month=\(month.yearMonthText) dateRange=\(gameDateString(interval.start))...\(gameDateString(interval.end))"
        )
        print("[SupabaseKBO] gamesSelect columns=\(Self.gameSelectColumns)")
        #endif
        let rows: [SupabaseGameRow] = try await database
            .from("public_games")
            .select(Self.gameSelectColumns)
            .gte("game_date", value: gameDateString(interval.start))
            .lte("game_date", value: gameDateString(interval.end))
            .order("game_date", ascending: true)
            .order("scheduled_at", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchGames(month:) success schema=\(schemaName) view=public_games month=\(month.yearMonthText) count=\(rows.count)")
        #endif
        AppLog.info(.supabase, "[SupabaseKBO] fetchGames(month:) success schema=\(schemaName) view=public_games month=\(month.yearMonthText) count=\(rows.count)")
        return rows
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(date: Date) async throws -> [SupabaseGameRow] {
        AppLog.info(.supabase, "[SupabaseKBO] fetchGames(date:) start schema=\(schemaName) view=public_games date=\(gameDateString(date))")
        #if DEBUG
        print("[SupabaseKBO] fetchGames(date:) query start schema=\(schemaName) view=public_games date=\(gameDateString(date))")
        print("[SupabaseKBO] gamesSelect columns=\(Self.gameSelectColumns)")
        #endif
        let rows: [SupabaseGameRow] = try await database
            .from("public_games")
            .select(Self.gameSelectColumns)
            .eq("game_date", value: gameDateString(date))
            .order("scheduled_at", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchGames(date:) success schema=\(schemaName) view=public_games date=\(gameDateString(date)) count=\(rows.count)")
        #endif
        AppLog.info(.supabase, "[SupabaseKBO] fetchGames(date:) success schema=\(schemaName) view=public_games date=\(gameDateString(date)) count=\(rows.count)")
        return rows
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(date: Date, favoriteTeamID: String) async throws -> [SupabaseGameRow] {
        let teams = try await fetchTeams()
        let normalizedFavoriteTeamID = SupabaseKBOMapper.normalizeTeamCode(favoriteTeamID)
        guard let teamUUID = teams.first(where: {
            SupabaseKBOMapper.normalizeTeamCode($0.code) == normalizedFavoriteTeamID
        })?.id else {
            return []
        }

        #if DEBUG
        print("[SupabaseKBO] fetchGames(favoriteTeamDate:) query start schema=\(schemaName) view=public_games date=\(gameDateString(date)) favoriteTeamID=\(favoriteTeamID)")
        print("[SupabaseKBO] gamesSelect columns=\(Self.gameSelectColumns)")
        #endif
        let rows: [SupabaseGameRow] = try await database
            .from("public_games")
            .select(Self.gameSelectColumns)
            .eq("game_date", value: gameDateString(date))
            .or("home_team_id.eq.\(teamUUID.uuidString),away_team_id.eq.\(teamUUID.uuidString)")
            .order("scheduled_at", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchGames(favoriteTeamDate:) success schema=\(schemaName) view=public_games date=\(gameDateString(date)) count=\(rows.count)")
        #endif
        return rows
    }

    // fetchGamesForStandings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGamesForStandings(season: Int) async throws -> [SupabaseGameRow] {
        let dateRange = standingsSeasonDateRange(for: season)
        let startDate = gameDateString(dateRange.start)
        let endDate = gameDateString(dateRange.end)
        #if DEBUG
        print("[SupabaseKBO] fetchGames(standings:) query start schema=\(schemaName) view=public_games season=\(season) dateRange=\(startDate)...\(endDate)")
        print("[SupabaseKBO] gamesSelect columns=\(Self.gameSelectColumns)")
        #endif
        let rows: [SupabaseGameRow] = try await database
            .from("public_games")
            .select(Self.gameSelectColumns)
            .gte("game_date", value: startDate)
            .lte("game_date", value: endDate)
            .eq("status", value: "final")
            .eq("is_cancelled", value: false)
            .eq("is_postponed", value: false)
            .order("game_date", ascending: true)
            .order("scheduled_at", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchGames(standings:) success schema=\(schemaName) view=public_games season=\(season) count=\(rows.count)")
        #endif
        return rows
    }

    // fetchTeamRanks2026 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchTeamRanks2026() async throws -> [TeamRankRow] {
        #if DEBUG
        print("[SupabaseKBO] fetchTeamRanks query start schema=\(schemaName) view=team_rank_2026")
        #endif
        let rows: [TeamRankRow] = try await database
            .from("team_rank_2026")
            .select("*")
            .order("rank", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchTeamRanks success schema=\(schemaName) view=team_rank_2026 count=\(rows.count)")
        #endif
        return rows
    }

    // fetchGame 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGame(lookup: SupabaseGameLookup) async throws -> [SupabaseGameRow] {
        AppLog.info(.supabase, "[SupabaseKBO] fetchGame(single:) start schema=\(schemaName) view=public_games key=\(lookup.debugKey) value=\(lookup.debugValue)")
        #if DEBUG
        print("[SupabaseKBO] fetchGame(single:) query start schema=\(schemaName) view=public_games key=\(lookup.debugKey) value=\(lookup.debugValue)")
        print("[SupabaseKBO] gamesSelect columns=\(Self.gameSelectColumns)")
        #endif

        let rows: [SupabaseGameRow]
        switch lookup {
        case .providerGameID(let providerGameID):
            rows = try await database
                .from("public_games")
                .select(Self.gameSelectColumns)
                .eq("provider_game_id", value: providerGameID)
                .limit(1)
                .execute()
                .value
        case .officialProviderGameID(let officialProviderGameID):
            rows = try await database
                .from("public_games")
                .select(Self.gameSelectColumns)
                .eq("official_provider_game_id", value: officialProviderGameID)
                .limit(1)
                .execute()
                .value
        case .publicGameID(let publicGameID):
            rows = try await database
                .from("public_games")
                .select(Self.gameSelectColumns)
                .eq("public_game_id", value: publicGameID)
                .limit(1)
                .execute()
                .value
        case .databaseID(let id):
            rows = try await database
                .from("public_games")
                .select(Self.gameSelectColumns)
                .eq("id", value: id.uuidString)
                .limit(1)
                .execute()
                .value
        case .dateTeamIDs(let gameDate, let awayTeamID, let homeTeamID):
            rows = try await database
                .from("public_games")
                .select(Self.gameSelectColumns)
                .eq("game_date", value: gameDate)
                .eq("away_team_id", value: awayTeamID.uuidString)
                .eq("home_team_id", value: homeTeamID.uuidString)
                .limit(1)
                .execute()
                .value
        case .dateTeamVenue(let gameDate, let awayTeamID, let homeTeamID, let stadium):
            rows = try await database
                .from("public_games")
                .select(Self.gameSelectColumns)
                .eq("game_date", value: gameDate)
                .eq("away_team_id", value: awayTeamID.uuidString)
                .eq("home_team_id", value: homeTeamID.uuidString)
                .eq("stadium", value: stadium)
                .limit(1)
                .execute()
                .value
        }

        #if DEBUG
        print("[SupabaseKBO] fetchGame(single:) success schema=\(schemaName) view=public_games key=\(lookup.debugKey) count=\(rows.count)")
        #endif
        AppLog.info(.supabase, "[SupabaseKBO] fetchGame(single:) success schema=\(schemaName) view=public_games key=\(lookup.debugKey) count=\(rows.count)")
        return rows
    }

    // fetchLatestSnapshots 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchLatestSnapshots(gameIDs: [UUID]) async throws -> [SupabaseLatestGameSnapshotRow] {
        let ids = Array(Set(gameIDs)).map(\.uuidString).sorted()
        guard ids.isEmpty == false else {
            return []
        }
        AppLog.debug(.supabase, "[SupabaseKBO] fetchLatestSnapshots start schema=\(schemaName) view=public_latest_game_snapshots count=\(ids.count)")
        #if DEBUG
        print("[SupabaseKBO] fetchLatestSnapshots query start schema=\(schemaName) view=public_latest_game_snapshots count=\(ids.count)")
        #endif
        let rows: [SupabaseLatestGameSnapshotRow] = try await database
            .from("public_latest_game_snapshots")
            .select(SupabaseLatestGameSnapshotRow.selectColumns)
            .in("game_id", values: ids)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchLatestSnapshots success schema=\(schemaName) view=public_latest_game_snapshots count=\(rows.count)")
        logLatestSnapshotFieldDiagnostics(rows, context: "batch")
        #endif
        AppLog.info(.supabase, "[SupabaseKBO] fetchLatestSnapshots success schema=\(schemaName) view=public_latest_game_snapshots count=\(rows.count)")
        logLatestSnapshotOperationalDiagnostics(rows, context: "batch")
        return rows
    }

    // fetchLatestSnapshot 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchLatestSnapshot(gameID: UUID) async throws -> SupabaseLatestGameSnapshotRow? {
        AppLog.debug(.supabase, "[SupabaseKBO] fetchLatestSnapshot start schema=\(schemaName) view=public_latest_game_snapshots game_id=\(gameID.uuidString)")
        #if DEBUG
        print("[SupabaseKBO] fetchLatestSnapshot query start schema=\(schemaName) view=public_latest_game_snapshots game_id=\(gameID.uuidString)")
        #endif
        let rows: [SupabaseLatestGameSnapshotRow] = try await database
            .from("public_latest_game_snapshots")
            .select(SupabaseLatestGameSnapshotRow.selectColumns)
            .eq("game_id", value: gameID.uuidString)
            .limit(1)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchLatestSnapshot success schema=\(schemaName) view=public_latest_game_snapshots game_id=\(gameID.uuidString) count=\(rows.count)")
        logLatestSnapshotFieldDiagnostics(rows, context: "single")
        #endif
        AppLog.info(.supabase, "[SupabaseKBO] fetchLatestSnapshot success schema=\(schemaName) view=public_latest_game_snapshots game_id=\(gameID.uuidString) count=\(rows.count)")
        logLatestSnapshotOperationalDiagnostics(rows, context: "single")
        return rows.first
    }

    // fetchGameBatterRecords 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameBatterRecords(gameID: UUID) async throws -> [SupabaseGameBatterRecordRow] {
        #if DEBUG
        print("[GameDetailDBRecords] DB detailed record fetch start schema=\(schemaName) view=public_game_batter_records game_id=\(gameID.uuidString)")
        #endif
        let rows: [SupabaseGameBatterRecordRow] = try await database
            .from("public_game_batter_records")
            .select(Self.batterRecordSelectColumns)
            .eq("game_id", value: gameID.uuidString)
            .order("source_order", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[GameDetailDBRecords] DB batter count=\(rows.count) source=public_game_batter_records game_id=\(gameID.uuidString)")
        #endif
        return rows
    }

    // fetchGamePitcherRecords 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGamePitcherRecords(gameID: UUID) async throws -> [SupabaseGamePitcherRecordRow] {
        #if DEBUG
        print("[GameDetailDBRecords] DB detailed record fetch start schema=\(schemaName) view=public_game_pitcher_records game_id=\(gameID.uuidString)")
        #endif
        let rows: [SupabaseGamePitcherRecordRow] = try await database
            .from("public_game_pitcher_records")
            .select(Self.pitcherRecordSelectColumns)
            .eq("game_id", value: gameID.uuidString)
            .order("pitching_order", ascending: true)
            .order("source_order", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[GameDetailDBRecords] DB pitcher count=\(rows.count) source=public_game_pitcher_records game_id=\(gameID.uuidString)")
        #endif
        return rows
    }

    // fetchGameEvents 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGameEvents(gameID: UUID) async throws -> [SupabaseGameEventRow] {
        #if DEBUG
        print("[GameDetailDBRecords] DB detailed record fetch start schema=\(schemaName) view=public_game_events game_id=\(gameID.uuidString)")
        #endif
        let rows: [SupabaseGameEventRow] = try await database
            .from("public_game_events")
            .select(Self.gameEventSelectColumns)
            .eq("game_id", value: gameID.uuidString)
            .order("sequence_number", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[GameDetailDBRecords] DB event count=\(rows.count) source=public_game_events game_id=\(gameID.uuidString)")
        #endif
        return rows
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames(teamID: String) async throws -> [SupabaseGameRow] {
        let teams = try await fetchTeams()
        guard let teamUUID = teams.first(where: { $0.code.caseInsensitiveCompare(teamID) == .orderedSame })?.id else {
            return []
        }

        #if DEBUG
        print("[SupabaseKBO] fetchGames(teamID:) query start schema=\(schemaName) view=public_games teamID=\(teamID)")
        print("[SupabaseKBO] gamesSelect columns=\(Self.gameSelectColumns)")
        #endif
        let rows: [SupabaseGameRow] = try await database
            .from("public_games")
            .select(Self.gameSelectColumns)
            .or("home_team_id.eq.\(teamUUID.uuidString),away_team_id.eq.\(teamUUID.uuidString)")
            .order("game_date", ascending: true)
            .order("scheduled_at", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchGames(teamID:) success schema=\(schemaName) view=public_games teamID=\(teamID) count=\(rows.count)")
        #endif
        return rows
    }

    nonisolated private var database: PostgrestClient {
        client.schema(schemaName)
    }

    // monthInterval 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func monthInterval(for month: KBOMonthScheduleKey) -> DateInterval {
        let startComponents = DateComponents(calendar: calendar, year: month.year, month: month.month, day: 1)
        let start = calendar.date(from: startComponents) ?? .distantPast
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    // standingsSeasonDateRange 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func standingsSeasonDateRange(for season: Int) -> (start: Date, end: Date) {
        let start = calendar.date(from: DateComponents(calendar: calendar, year: season, month: 3, day: 1)) ?? .distantPast
        let end = calendar.date(from: DateComponents(calendar: calendar, year: season, month: 11, day: 30)) ?? start
        return (start, end)
    }

    // gameDateString 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private func gameDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
#endif

// logLatestSnapshotOperationalDiagnostics 메서드는 snapshot 수신 여부와 핵심 경기 진행값만 운영 로그로 남깁니다.
private nonisolated func logLatestSnapshotOperationalDiagnostics(
    _ rows: [SupabaseLatestGameSnapshotRow],
    context: String
) {
    for row in rows.prefix(5) {
        AppLog.info(
            .supabase,
            "[SupabaseKBO] latestSnapshot received context=\(context) game_id=\(row.gameID.uuidString) inning=\(row.inningLabel ?? "<nil>") count=\(row.balls.map(String.init) ?? "-")/\(row.strikes.map(String.init) ?? "-")/\(row.outs.map(String.init) ?? "-") fetchedAt=\(supabaseOperationalTimestamp(row.fetchedAt)) createdAt=\(supabaseOperationalTimestamp(row.createdAt))"
        )
    }
}

// supabaseOperationalTimestamp 메서드는 로그에 사용할 timestamp를 축약합니다.
private nonisolated func supabaseOperationalTimestamp(_ date: Date?) -> String {
    guard let date else { return "<nil>" }
    return SupabaseDateParser.debugTimestamp(date)
}

#if DEBUG
// logLatestSnapshotFieldDiagnostics 메서드는 이 타입의 주요 동작을 수행합니다.
private nonisolated func logLatestSnapshotFieldDiagnostics(
    _ rows: [SupabaseLatestGameSnapshotRow],
    context: String
) {
    let batterFieldNames: Set<String> = [
        "current_batter_name",
        "batter_name",
        "current_hitter_name",
        "hitter_name",
        "batter",
        "hitter",
        "currentBatterName",
        "batterName"
    ]
    let pitcherFieldNames: Set<String> = [
        "current_pitcher_name",
        "pitcher_name",
        "pitcher",
        "currentPitcherName",
        "pitcherName"
    ]

    for row in rows.prefix(5) {
        let batterFields = row.debugAvailableFieldNames.intersection(batterFieldNames).sorted()
        let pitcherFields = row.debugAvailableFieldNames.intersection(pitcherFieldNames).sorted()
        print(
            "[SupabaseKBO] latestSnapshotFields context=\(context) game_id=\(row.gameID.uuidString) " +
            "pitcherFields=\(pitcherFields.isEmpty ? "missing" : pitcherFields.joined(separator: "|")) " +
            "batterFields=\(batterFields.isEmpty ? "missing" : batterFields.joined(separator: "|")) " +
            "currentPitcher=\(supabaseDebugText(row.currentPitcherName)) batter=\(supabaseDebugText(row.currentBatterName))"
        )
    }
}
#endif
