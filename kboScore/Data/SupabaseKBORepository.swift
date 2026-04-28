//
//  SupabaseKBORepository.swift
//  kboScore
//
//  Created by Codex on 4/24/26.
//

import Foundation

protocol SupabaseKBOReading: Sendable {
    nonisolated func fetchTeams() async throws -> [SupabaseTeamRow]
    nonisolated func fetchGameCount() async throws -> Int
    nonisolated func fetchGames() async throws -> [SupabaseGameRow]
    nonisolated func fetchGames(excludingProviderGameIDs providerGameIDs: Set<String>) async throws -> [SupabaseGameRow]
    nonisolated func fetchGames(month: KBOMonthScheduleKey) async throws -> [SupabaseGameRow]
    nonisolated func fetchGames(date: Date) async throws -> [SupabaseGameRow]
    nonisolated func fetchGames(teamID: String) async throws -> [SupabaseGameRow]
}

// Read-only overlay: the iOS app only selects public data from Supabase.
// Inserts/updates/deletes must stay in trusted backend, admin, or scheduled jobs.
struct SupabaseBackedKBORepository<Base: KBORepository, Source: SupabaseKBOReading>: KBORepository, Sendable {
    let base: Base
    let source: Source
    let runtimeState: RepositoryRuntimeState?

    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        #if DEBUG
        print("[SupabaseKBO] fetchBootstrapData start source=localFirst")
        #endif
        do {
            let localBootstrap = try await base.fetchBootstrapData()
            if localBootstrap.games.isEmpty == false {
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
            let teamsTask = Task { try await source.fetchTeams() }
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
            let teamsTask = Task { try await source.fetchTeams() }
            let games = try await source.fetchGames(date: date)
            let teams = try await teamsTask.value
            let mapped = SupabaseKBOMapper.mapGames(gameRows: games, teamRows: teams)
                .sorted { $0.scheduledStart < $1.scheduledStart }
            await runtimeState?.record(source: .supabase, delivery: .supabase)
            #if DEBUG
            print("[SupabaseKBO] fetchSchedule(date:) success count=\(mapped.count)")
            #endif
            return mapped
        } catch is CancellationError {
            #if DEBUG
            print("[SupabaseKBO] fetchSchedule(date:) cancelled")
            #endif
            throw CancellationError()
        } catch {
            #if DEBUG
            print("[SupabaseRepository] daily schedule failed for \(date). falling back to base repository. error=\(error)")
            #endif
            return try await base.fetchSchedule(for: date, bypassingCache: bypassingCache)
        }
    }

    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        try await base.fetchStandings()
    }

    nonisolated private func fetchSupabaseBootstrap() async throws -> KBOBootstrapData {
        let teamsTask = Task { try await source.fetchTeams() }
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
        let teamsTask = Task { try await source.fetchTeams() }
        let gamesTask = Task { try await source.fetchGames() }
        let teams = try await teamsTask.value
        let games = try await gamesTask.value
        return SupabaseKBOMapper.mapGames(gameRows: games, teamRows: teams)
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
        let teamsTask = Task { try await source.fetchTeams() }
        let gameRows = try await source.fetchGames(excludingProviderGameIDs: knownProviderIDs)
        let teams = try await teamsTask.value
        let games = SupabaseKBOMapper.mapGames(gameRows: gameRows, teamRows: teams)
            .sorted { $0.scheduledStart < $1.scheduledStart }
        return KBOScheduleMissingGamesResult(remoteCount: games.count, games: games)
    }
}

#if canImport(Supabase)
import Supabase

// Read-only client for public KBO tables exposed through Supabase's HTTP API layer.
struct SupabaseKBORepository: SupabaseKBOReading, Sendable {
    private let baseURL: URL
    private let schemaName: String
    private let client: SupabaseClient
    private let calendar: Calendar

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
        #endif
        let rows: [SupabaseGameRow] = try await database
            .from("games")
            .select()
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
        #endif

        let query = database
            .from("games")
            .select()
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
        #endif
        let rows: [SupabaseGameRow] = try await database
            .from("games")
            .select()
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
        #endif
        let rows: [SupabaseGameRow] = try await database
            .from("games")
            .select()
            .eq("game_date", value: gameDateString(date))
            .order("scheduled_at", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchGames(date:) success schema=\(schemaName) table=games date=\(gameDateString(date)) count=\(rows.count)")
        #endif
        return rows
    }

    nonisolated func fetchGames(teamID: String) async throws -> [SupabaseGameRow] {
        let teams = try await fetchTeams()
        guard let teamUUID = teams.first(where: { $0.code.caseInsensitiveCompare(teamID) == .orderedSame })?.id else {
            return []
        }

        #if DEBUG
        print("[SupabaseKBO] fetchGames(teamID:) query start schema=\(schemaName) table=games teamID=\(teamID)")
        #endif
        let rows: [SupabaseGameRow] = try await database
            .from("games")
            .select()
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
