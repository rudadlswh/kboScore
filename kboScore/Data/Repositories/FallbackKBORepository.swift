//
//  FallbackKBORepository.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

struct FallbackKBORepository<Primary: KBORepository, Fallback: KBORepository>: KBORepository, Sendable {
    let primary: Primary
    let fallback: Fallback
    let runtimeState: RepositoryRuntimeState?

    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        do {
            return try await primary.fetchBootstrapData()
        } catch {
            let result = try await fallback.fetchBootstrapData()
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    nonisolated func fetchGames() async throws -> [GameDetail] {
        do {
            return try await primary.fetchGames()
        } catch {
            let result = try await fallback.fetchGames()
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        do {
            return try await primary.fetchNotifications()
        } catch {
            let result = try await fallback.fetchNotifications()
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        do {
            return try await primary.fetchMonthlySchedule(for: month)
        } catch {
            let result = try await fallback.fetchMonthlySchedule(for: month)
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey, bypassingCache: Bool) async throws -> [GameDetail] {
        do {
            return try await primary.fetchMonthlySchedule(for: month, bypassingCache: bypassingCache)
        } catch {
            let result = try await fallback.fetchMonthlySchedule(for: month, bypassingCache: bypassingCache)
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        do {
            return try await primary.fetchSchedule(for: date)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let result = try await fallback.fetchSchedule(for: date)
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        do {
            return try await primary.fetchSchedule(for: date, bypassingCache: bypassingCache)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let result = try await fallback.fetchSchedule(for: date, bypassingCache: bypassingCache)
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        do {
            return try await primary.fetchStandings()
        } catch {
            let result = try await fallback.fetchStandings()
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }
}
