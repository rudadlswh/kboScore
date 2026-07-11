//
//  FallbackKBORepository.swift
//  kboScore
//  기능 설명: 주 저장소 실패 시 보조 저장소로 데이터를 가져오는 fallback 래퍼입니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 5/14/26.
//

import Foundation

// FallbackKBORepository 구조체는 KBO 데이터 조회와 저장소 접근 흐름을 담당합니다.
struct FallbackKBORepository<Primary: KBORepository, Fallback: KBORepository>: KBORepository, Sendable {
    let primary: Primary
    let fallback: Fallback
    let runtimeState: RepositoryRuntimeState?

    // fetchBootstrapData 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        do {
            return try await primary.fetchBootstrapData()
        } catch {
            let result = try await fallback.fetchBootstrapData()
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [GameDetail] {
        do {
            return try await primary.fetchGames()
        } catch {
            let result = try await fallback.fetchGames()
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    // fetchNotifications 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        do {
            return try await primary.fetchNotifications()
        } catch {
            let result = try await fallback.fetchNotifications()
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        do {
            return try await primary.fetchMonthlySchedule(for: month)
        } catch {
            let result = try await fallback.fetchMonthlySchedule(for: month)
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey, bypassingCache: Bool) async throws -> [GameDetail] {
        do {
            return try await primary.fetchMonthlySchedule(for: month, bypassingCache: bypassingCache)
        } catch {
            let result = try await fallback.fetchMonthlySchedule(for: month, bypassingCache: bypassingCache)
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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

    // fetchStandings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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
