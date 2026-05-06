//
//  SupabaseKBORepository.swift
//  kboScore
//
//  Created by Codex on 4/24/26.
//

import Foundation

enum SupabaseGameLookup: Sendable, Equatable {
    case providerGameID(String)
    case publicGameID(String)
    case databaseID(UUID)
    case dateTeamIDs(gameDate: String, awayTeamID: UUID, homeTeamID: UUID)
    case dateTeamVenue(gameDate: String, awayTeamID: UUID, homeTeamID: UUID, stadium: String)

    nonisolated var debugKey: String {
        switch self {
        case .providerGameID:
            return "provider_game_id"
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
        case .providerGameID(let value), .publicGameID(let value):
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
    nonisolated func fetchTeams() async throws -> [SupabaseTeamRow]
    nonisolated func fetchGameCount() async throws -> Int
    nonisolated func fetchGames() async throws -> [SupabaseGameRow]
    nonisolated func fetchGames(excludingProviderGameIDs providerGameIDs: Set<String>) async throws -> [SupabaseGameRow]
    nonisolated func fetchGames(month: KBOMonthScheduleKey) async throws -> [SupabaseGameRow]
    nonisolated func fetchGames(date: Date) async throws -> [SupabaseGameRow]
    nonisolated func fetchGames(date: Date, favoriteTeamID: String) async throws -> [SupabaseGameRow]
    nonisolated func fetchGamesForStandings(season: Int) async throws -> [SupabaseGameRow]
    nonisolated func fetchTeamRanks2026() async throws -> [TeamRankRow]
    nonisolated func fetchGames(teamID: String) async throws -> [SupabaseGameRow]
    nonisolated func fetchGame(lookup: SupabaseGameLookup) async throws -> [SupabaseGameRow]
    nonisolated func fetchLatestSnapshots(gameIDs: [UUID]) async throws -> [SupabaseLatestGameSnapshotRow]
    nonisolated func fetchLatestSnapshot(gameID: UUID) async throws -> SupabaseLatestGameSnapshotRow?
}

extension SupabaseKBOReading {
    nonisolated func fetchTeamRanks2026() async throws -> [TeamRankRow] {
        []
    }
}

actor SupabaseTeamRowCache {
    private var rows: [SupabaseTeamRow]?
    private var fetchTask: Task<[SupabaseTeamRow], Error>?

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
struct SupabaseBackedKBORepository<Base: KBORepository, Source: SupabaseKBOReading>: KBORepository, KBOFavoriteTeamScheduleDataSource, KBOStandingsGameDataSource, KBOTeamRankDataSource, Sendable {
    let base: Base
    let source: Source
    let runtimeState: RepositoryRuntimeState?
    let teamCache = SupabaseTeamRowCache()

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

    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        try await base.fetchNotifications()
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        try await fetchMonthlySchedule(for: month, bypassingCache: false)
    }

    nonisolated func fetchMonthlySchedule(
        for month: KBOMonthScheduleKey,
        bypassingCache: Bool
    ) async throws -> [GameDetail] {
        #if DEBUG
        print("[SupabaseKBO] fetchMonthlySchedule start month=\(month.yearMonthText)")
        #endif
        do {
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

    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        try await fetchSchedule(for: date, bypassingCache: false)
    }

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

    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        try await base.fetchStandings()
    }

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
            print("[SupabaseKBO] fetchStandingsSource failed season=\(season) fallback=baseGames error=\(error)")
            #endif
            return try await base.fetchGames()
                .filter { $0.isRegularSeason && $0.hasCompleteFinalScore }
        }
    }

    nonisolated func fetchTeamRanks(season: Int) async throws -> [TeamRankRow] {
        guard season == 2026 else {
            return []
        }
        #if DEBUG
        print("[StandingsRank] remote fetch start view=team_rank_2026")
        #endif
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
        #if DEBUG
        print("[StandingsRank] remote fetch success count=\(enriched.count)")
        #endif
        return enriched
    }

    nonisolated private func fetchSupabaseBootstrap() async throws -> KBOBootstrapData {
        let teamsTask = Task { try await cachedTeamRows() }
        let gamesTask = Task { try await source.fetchGames() }
        let teams = try await teamsTask.value
        let games = try await gamesTask.value
        return SupabaseKBOMapper.mapBootstrap(teamRows: teams, gameRows: games)
    }

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

    nonisolated private func fetchSupabaseGames() async throws -> [GameDetail] {
        let teamsTask = Task { try await cachedTeamRows() }
        let gamesTask = Task { try await source.fetchGames() }
        let teams = try await teamsTask.value
        let games = try await gamesTask.value
        return SupabaseKBOMapper.mapGames(gameRows: games, teamRows: teams)
    }

    nonisolated private func cachedTeamRows() async throws -> [SupabaseTeamRow] {
        try await teamCache.teams {
            try await source.fetchTeams()
        }
    }

}

extension SupabaseBackedKBORepository: KBOGameDetailSnapshotDataSource {
    nonisolated func fetchGameDetailSnapshot(
        for game: GameDetail,
        identity: String,
        cachedTeams: [Team]
    ) async throws -> GameDetail? {
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
            let snapshot = try await source.fetchLatestSnapshot(gameID: row.id)
            await runtimeState?.record(source: .supabase, delivery: .supabase)
            let mapped = SupabaseKBOMapper.mapGame(row: row, teamRows: fetchedTeamRows, snapshot: snapshot, fallbackGame: game)
            #if DEBUG
            print("[GameDetailSnapshot] game_id=\(row.id.uuidString) inning=\(snapshot?.inningLabel ?? "<nil>") balls=\(snapshot?.balls.map(String.init) ?? "-") strikes=\(snapshot?.strikes.map(String.init) ?? "-") outs=\(snapshot?.outs.map(String.init) ?? "-") bases=\((snapshot?.runnerOnFirst ?? false) ? "1" : "-")\((snapshot?.runnerOnSecond ?? false) ? "2" : "-")\((snapshot?.runnerOnThird ?? false) ? "3" : "-") currentPitcher=\(supabaseDebugText(snapshot?.currentPitcherName)) batter=\(supabaseDebugText(snapshot?.currentBatterName))")
            print("fetchGameDetail(single:) success identity=\(identity) id=\(mapped.supabaseDebugIdentifier)")
            #endif
            return mapped
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
            let snapshot = try await source.fetchLatestSnapshot(gameID: row.id)
            await runtimeState?.record(source: .supabase, delivery: .supabase)
            let mapped = SupabaseKBOMapper.mapGame(row: row, teamRows: fetchedTeamRows, snapshot: snapshot, fallbackGame: game)
            #if DEBUG
            print("[GameDetailSnapshot] game_id=\(row.id.uuidString) inning=\(snapshot?.inningLabel ?? "<nil>") balls=\(snapshot?.balls.map(String.init) ?? "-") strikes=\(snapshot?.strikes.map(String.init) ?? "-") outs=\(snapshot?.outs.map(String.init) ?? "-") bases=\((snapshot?.runnerOnFirst ?? false) ? "1" : "-")\((snapshot?.runnerOnSecond ?? false) ? "2" : "-")\((snapshot?.runnerOnThird ?? false) ? "3" : "-") currentPitcher=\(supabaseDebugText(snapshot?.currentPitcherName)) batter=\(supabaseDebugText(snapshot?.currentBatterName))")
            print("fetchGameDetail(single:) success identity=\(identity) id=\(mapped.supabaseDebugIdentifier)")
            #endif
            return mapped
        }

        return nil
    }

    nonisolated private func directDetailLookups(for game: GameDetail, identity: String) -> [SupabaseGameLookup] {
        var lookups: [SupabaseGameLookup] = []
        var seen: Set<String> = []

        func append(_ lookup: SupabaseGameLookup) {
            let key = "\(lookup.debugKey)=\(lookup.debugValue)"
            guard seen.insert(key).inserted else { return }
            lookups.append(lookup)
        }

        if let providerGameID = game.officialGameCenterID?.trimmingCharacters(in: .whitespacesAndNewlines),
           providerGameID.isEmpty == false {
            append(.providerGameID(providerGameID))
        }
        if let publicGameID = game.supabaseNoteToken("public_game_id") {
            append(.publicGameID(publicGameID))
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
    nonisolated func fetchRemoteGameCount() async throws -> Int {
        try await source.fetchGameCount()
    }

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
private nonisolated func supabaseDebugText(_ value: String?) -> String {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? "<nil>" : trimmed
}

private nonisolated func baseDebugText(_ bases: RunnerState?) -> String {
    guard let bases else { return "---" }
    return "\(bases.first ? "1" : "-")\(bases.second ? "2" : "-")\(bases.third ? "3" : "-")"
}

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

// Read-only client for public KBO tables exposed through Supabase's HTTP API layer.
struct SupabaseKBORepository: SupabaseKBOReading, Sendable {
    private let baseURL: URL
    private let schemaName: String
    private let client: SupabaseClient
    private let calendar: Calendar
    private let teamCache = SupabaseTeamRowCache()
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

    init(configuration: SupabaseConfiguration) {
        self.baseURL = configuration.url
        self.schemaName = SupabaseConfiguration.exposedSchema
        self.client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        self.calendar = calendar

        #if DEBUG
        print("[SupabaseConfig] client initialized host=\(configuration.url.host ?? "<none>") schema=\(schemaName)")
        #endif
    }

    nonisolated func fetchTeams() async throws -> [SupabaseTeamRow] {
        try await teamCache.teams {
            try await fetchTeamsFromDatabase()
        }
    }

    nonisolated private func fetchTeamsFromDatabase() async throws -> [SupabaseTeamRow] {
        #if DEBUG
        print("[SupabaseKBO] fetchTeams start schema=\(schemaName) table=teams baseURL=\(baseURL.absoluteString)")
        #endif
        let rows: [SupabaseTeamRow] = try await database
            .from("teams")
            .select()
            .order("team_code", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchTeams success schema=\(schemaName) table=teams count=\(rows.count)")
        #endif
        return rows
    }

    nonisolated func fetchGameCount() async throws -> Int {
        #if DEBUG
        print("[SupabaseKBO] fetchGameCount query start schema=\(schemaName) table=games")
        #endif
        let count = try await database
            .from("games")
            .select(head: true, count: .exact)
            .execute()
            .count ?? 0
        #if DEBUG
        print("[SupabaseKBO] fetchGameCount success schema=\(schemaName) table=games count=\(count)")
        #endif
        return count
    }

    nonisolated func fetchGames() async throws -> [SupabaseGameRow] {
        #if DEBUG
        print("[SupabaseKBO] fetchGames query start schema=\(schemaName) table=games dateRange=all")
        print("[SupabaseKBO] gamesSelect columns=\(Self.gameSelectColumns)")
        #endif
        let rows: [SupabaseGameRow] = try await database
            .from("games")
            .select(Self.gameSelectColumns)
            .order("game_date", ascending: true)
            .order("scheduled_at", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchGames success schema=\(schemaName) table=games count=\(rows.count)")
        #endif
        return rows
    }

    nonisolated func fetchGames(excludingProviderGameIDs providerGameIDs: Set<String>) async throws -> [SupabaseGameRow] {
        let excludedIDs = providerGameIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false && $0.contains(",") == false && $0.contains("(") == false && $0.contains(")") == false }
            .sorted()

        #if DEBUG
        print("[SupabaseKBO] fetchGames(excluding:) query start schema=\(schemaName) table=games excludedProviderIDs=\(excludedIDs.count)")
        print("[SupabaseKBO] gamesSelect columns=\(Self.gameSelectColumns)")
        #endif

        let query = database
            .from("games")
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
        print("[SupabaseKBO] fetchGames(excluding:) success schema=\(schemaName) table=games count=\(rows.count)")
        #endif
        return rows
    }

    nonisolated func fetchGames(month: KBOMonthScheduleKey) async throws -> [SupabaseGameRow] {
        let interval = monthInterval(for: month)
        #if DEBUG
        print(
            "[SupabaseKBO] fetchGames(month:) query start schema=\(schemaName) table=games month=\(month.yearMonthText) dateRange=\(gameDateString(interval.start))...\(gameDateString(interval.end))"
        )
        print("[SupabaseKBO] gamesSelect columns=\(Self.gameSelectColumns)")
        #endif
        let rows: [SupabaseGameRow] = try await database
            .from("games")
            .select(Self.gameSelectColumns)
            .gte("game_date", value: gameDateString(interval.start))
            .lte("game_date", value: gameDateString(interval.end))
            .order("game_date", ascending: true)
            .order("scheduled_at", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchGames(month:) success schema=\(schemaName) table=games month=\(month.yearMonthText) count=\(rows.count)")
        #endif
        return rows
    }

    nonisolated func fetchGames(date: Date) async throws -> [SupabaseGameRow] {
        #if DEBUG
        print("[SupabaseKBO] fetchGames(date:) query start schema=\(schemaName) table=games date=\(gameDateString(date))")
        print("[SupabaseKBO] gamesSelect columns=\(Self.gameSelectColumns)")
        #endif
        let rows: [SupabaseGameRow] = try await database
            .from("games")
            .select(Self.gameSelectColumns)
            .eq("game_date", value: gameDateString(date))
            .order("scheduled_at", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchGames(date:) success schema=\(schemaName) table=games date=\(gameDateString(date)) count=\(rows.count)")
        #endif
        return rows
    }

    nonisolated func fetchGames(date: Date, favoriteTeamID: String) async throws -> [SupabaseGameRow] {
        let teams = try await fetchTeams()
        let normalizedFavoriteTeamID = SupabaseKBOMapper.normalizeTeamCode(favoriteTeamID)
        guard let teamUUID = teams.first(where: {
            SupabaseKBOMapper.normalizeTeamCode($0.code) == normalizedFavoriteTeamID
        })?.id else {
            return []
        }

        #if DEBUG
        print("[SupabaseKBO] fetchGames(favoriteTeamDate:) query start schema=\(schemaName) table=games date=\(gameDateString(date)) favoriteTeamID=\(favoriteTeamID)")
        print("[SupabaseKBO] gamesSelect columns=\(Self.gameSelectColumns)")
        #endif
        let rows: [SupabaseGameRow] = try await database
            .from("games")
            .select(Self.gameSelectColumns)
            .eq("game_date", value: gameDateString(date))
            .or("home_team_id.eq.\(teamUUID.uuidString),away_team_id.eq.\(teamUUID.uuidString)")
            .order("scheduled_at", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchGames(favoriteTeamDate:) success schema=\(schemaName) table=games date=\(gameDateString(date)) count=\(rows.count)")
        #endif
        return rows
    }

    nonisolated func fetchGamesForStandings(season: Int) async throws -> [SupabaseGameRow] {
        let startDate = "\(season)-03-01"
        let endDate = "\(season)-11-30"
        #if DEBUG
        print("[SupabaseKBO] fetchGames(standings:) query start schema=\(schemaName) table=games season=\(season) dateRange=\(startDate)...\(endDate)")
        print("[SupabaseKBO] gamesSelect columns=\(Self.gameSelectColumns)")
        #endif
        let rows: [SupabaseGameRow] = try await database
            .from("games")
            .select(Self.gameSelectColumns)
            .gte("game_date", value: startDate)
            .lte("game_date", value: endDate)
            .or("status.eq.final,status.eq.completed,status.eq.ended,status.eq.game_over,inning_state.eq.final,inning_state.eq.game_over")
            .order("game_date", ascending: true)
            .order("scheduled_at", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchGames(standings:) success schema=\(schemaName) table=games season=\(season) count=\(rows.count)")
        #endif
        return rows
    }

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

    nonisolated func fetchGame(lookup: SupabaseGameLookup) async throws -> [SupabaseGameRow] {
        #if DEBUG
        print("[SupabaseKBO] fetchGame(single:) query start schema=\(schemaName) table=games key=\(lookup.debugKey) value=\(lookup.debugValue)")
        print("[SupabaseKBO] gamesSelect columns=\(Self.gameSelectColumns)")
        #endif

        let rows: [SupabaseGameRow]
        switch lookup {
        case .providerGameID(let providerGameID):
            rows = try await database
                .from("games")
                .select(Self.gameSelectColumns)
                .eq("provider_game_id", value: providerGameID)
                .limit(1)
                .execute()
                .value
        case .publicGameID(let publicGameID):
            rows = try await database
                .from("games")
                .select(Self.gameSelectColumns)
                .eq("public_game_id", value: publicGameID)
                .limit(1)
                .execute()
                .value
        case .databaseID(let id):
            rows = try await database
                .from("games")
                .select(Self.gameSelectColumns)
                .eq("id", value: id.uuidString)
                .limit(1)
                .execute()
                .value
        case .dateTeamIDs(let gameDate, let awayTeamID, let homeTeamID):
            rows = try await database
                .from("games")
                .select(Self.gameSelectColumns)
                .eq("game_date", value: gameDate)
                .eq("away_team_id", value: awayTeamID.uuidString)
                .eq("home_team_id", value: homeTeamID.uuidString)
                .limit(1)
                .execute()
                .value
        case .dateTeamVenue(let gameDate, let awayTeamID, let homeTeamID, let stadium):
            rows = try await database
                .from("games")
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
        print("[SupabaseKBO] fetchGame(single:) success schema=\(schemaName) table=games key=\(lookup.debugKey) count=\(rows.count)")
        #endif
        return rows
    }

    nonisolated func fetchLatestSnapshots(gameIDs: [UUID]) async throws -> [SupabaseLatestGameSnapshotRow] {
        let ids = Array(Set(gameIDs)).map(\.uuidString).sorted()
        guard ids.isEmpty == false else {
            return []
        }
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
        return rows
    }

    nonisolated func fetchLatestSnapshot(gameID: UUID) async throws -> SupabaseLatestGameSnapshotRow? {
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
        return rows.first
    }

    nonisolated func fetchGames(teamID: String) async throws -> [SupabaseGameRow] {
        let teams = try await fetchTeams()
        guard let teamUUID = teams.first(where: { $0.code.caseInsensitiveCompare(teamID) == .orderedSame })?.id else {
            return []
        }

        #if DEBUG
        print("[SupabaseKBO] fetchGames(teamID:) query start schema=\(schemaName) table=games teamID=\(teamID)")
        print("[SupabaseKBO] gamesSelect columns=\(Self.gameSelectColumns)")
        #endif
        let rows: [SupabaseGameRow] = try await database
            .from("games")
            .select(Self.gameSelectColumns)
            .or("home_team_id.eq.\(teamUUID.uuidString),away_team_id.eq.\(teamUUID.uuidString)")
            .order("game_date", ascending: true)
            .order("scheduled_at", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchGames(teamID:) success schema=\(schemaName) table=games teamID=\(teamID) count=\(rows.count)")
        #endif
        return rows
    }

    nonisolated private var database: PostgrestClient {
        client.schema(schemaName)
    }

    nonisolated private func monthInterval(for month: KBOMonthScheduleKey) -> DateInterval {
        let startComponents = DateComponents(calendar: calendar, year: month.year, month: month.month, day: 1)
        let start = calendar.date(from: startComponents) ?? .distantPast
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start
        return DateInterval(start: start, end: end)
    }

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

#if DEBUG
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
