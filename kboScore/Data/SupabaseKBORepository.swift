//
//  SupabaseKBORepository.swift
//  kboScore
//
//  Created by Codex on 4/24/26.
//

import Foundation

protocol SupabaseKBOReading: Sendable {
    nonisolated func fetchTeams() async throws -> [SupabaseTeamRow]
    nonisolated func fetchGames() async throws -> [SupabaseGameRow]
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
        print("[SupabaseKBO] fetchBootstrapData start")
        #endif
        do {
            let supabaseBootstrap = try await fetchSupabaseBootstrap()
            let fallbackBootstrap = try? await base.fetchBootstrapData()
            await runtimeState?.record(source: .supabase, delivery: .supabase)
            #if DEBUG
            print("[SupabaseKBO] fetchBootstrapData success teams=\(supabaseBootstrap.teams.count) games=\(supabaseBootstrap.games.count)")
            #endif

            return KBOBootstrapData(
                teams: supabaseBootstrap.teams,
                games: supabaseBootstrap.games,
                notifications: fallbackBootstrap?.notifications ?? [],
                settings: fallbackBootstrap?.settings ?? .default
            )
        } catch {
            #if DEBUG
            print("[SupabaseRepository] bootstrap failed, falling back to base repository. error=\(error)")
            #endif
            return try await base.fetchBootstrapData()
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
        } catch {
            #if DEBUG
            print("[SupabaseRepository] monthly schedule failed for \(month.yearMonthText), falling back to base repository. error=\(error)")
            #endif
            return try await base.fetchMonthlySchedule(for: month, bypassingCache: bypassingCache)
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

    nonisolated private func fetchSupabaseGames() async throws -> [GameDetail] {
        let teamsTask = Task { try await source.fetchTeams() }
        let gamesTask = Task { try await source.fetchGames() }
        let teams = try await teamsTask.value
        let games = try await gamesTask.value
        return SupabaseKBOMapper.mapGames(gameRows: games, teamRows: teams)
    }
}

#if canImport(Supabase)
import Supabase

// Read-only client for public KBO tables exposed through Supabase's HTTP API layer.
struct SupabaseKBORepository: SupabaseKBOReading, Sendable {
    private let client: SupabaseClient
    private let calendar: Calendar

    init(configuration: SupabaseConfiguration) {
        self.client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        self.calendar = calendar

        #if DEBUG
        print("[SupabaseConfig] client initialized host=\(configuration.url.host ?? "<none>")")
        #endif
    }

    nonisolated func fetchTeams() async throws -> [SupabaseTeamRow] {
        #if DEBUG
        print("[SupabaseKBO] fetchTeams start")
        #endif
        let rows: [SupabaseTeamRow] = try await client
            .from("teams")
            .select()
            .order("team_code", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchTeams success count=\(rows.count)")
        #endif
        return rows
    }

    nonisolated func fetchGames() async throws -> [SupabaseGameRow] {
        #if DEBUG
        print("[SupabaseKBO] fetchGames query start")
        #endif
        let rows: [SupabaseGameRow] = try await client
            .from("games")
            .select()
            .order("game_date", ascending: true)
            .order("scheduled_at", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchGames success count=\(rows.count)")
        #endif
        return rows
    }

    nonisolated func fetchGames(month: KBOMonthScheduleKey) async throws -> [SupabaseGameRow] {
        let interval = monthInterval(for: month)
        #if DEBUG
        print("[SupabaseKBO] fetchGames(month:) query start month=\(month.yearMonthText)")
        #endif
        let rows: [SupabaseGameRow] = try await client
            .from("games")
            .select()
            .gte("game_date", value: gameDateString(interval.start))
            .lte("game_date", value: gameDateString(interval.end))
            .order("game_date", ascending: true)
            .order("scheduled_at", ascending: true)
            .execute()
            .value
        #if DEBUG
        print("[SupabaseKBO] fetchGames(month:) success month=\(month.yearMonthText) count=\(rows.count)")
        #endif
        return rows
    }

    nonisolated func fetchGames(date: Date) async throws -> [SupabaseGameRow] {
        let rows: [SupabaseGameRow] = try await client
            .from("games")
            .select()
            .eq("game_date", value: gameDateString(date))
            .order("scheduled_at", ascending: true)
            .execute()
            .value
        return rows
    }

    nonisolated func fetchGames(teamID: String) async throws -> [SupabaseGameRow] {
        let teams = try await fetchTeams()
        guard let teamUUID = teams.first(where: { $0.code.caseInsensitiveCompare(teamID) == .orderedSame })?.id else {
            return []
        }

        let rows: [SupabaseGameRow] = try await client
            .from("games")
            .select()
            .or("home_team_id.eq.\(teamUUID.uuidString),away_team_id.eq.\(teamUUID.uuidString)")
            .order("game_date", ascending: true)
            .order("scheduled_at", ascending: true)
            .execute()
            .value
        return rows
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
