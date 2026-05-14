//
//  LiveKBORepository.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import Foundation

enum RepositoryDataSourceKind: String, Sendable {
    case supabase = "Supabase"
    case mock = "목 데이터"
    case live = "실데이터"
    case mockFallback = "목 데이터 폴백"
}

enum RepositoryDeliverySourceKind: String, Sendable {
    case supabase = "Supabase 응답"
    case mock = "목 데이터"
    case live = "실시간 응답"
    case cache = "로컬 캐시"
    case mockFallback = "목 데이터 폴백"
}

enum LocalBootstrapSourceKind: String, Sendable {
    case documents = "문서 JSON"
    case bundled = "번들 JSON"
}

enum BootstrapRefreshResultKind: String, Sendable, Codable {
    case idle = "대기"
    case updated = "업데이트됨"
    case notModified = "변경 없음"
    case failed = "실패"
    case disabled = "비활성"
}

struct BootstrapRefreshDebugSnapshot: Sendable {
    let isEnabled: Bool
    let etag: String?
    let lastFetchAt: Date?
    let lastWriteAt: Date?
    let lastResult: BootstrapRefreshResultKind
}

struct RepositoryDebugSnapshot: Sendable {
    let activeSource: RepositoryDataSourceKind
    let deliverySource: RepositoryDeliverySourceKind
    let baseURL: String?
    let lastRefreshAt: Date?
    let isUsingStaleCache: Bool
    let localBootstrapSource: LocalBootstrapSourceKind?
    let localBootstrapMessage: String?
    let localBootstrapResolvedPath: String?
    let localBootstrapLoadedAt: Date?
    let bootstrapAPIEnabled: Bool
    let bootstrapRefreshETag: String?
    let bootstrapLastFetchAt: Date?
    let bootstrapLastWriteAt: Date?
    let bootstrapLastResult: BootstrapRefreshResultKind
}

struct LiveKBORepository: KBORepository, Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let runtimeState: RepositoryRuntimeState?
    private let nowProvider: @Sendable () -> Date

    init(
        baseURL: URL,
        session: URLSession = .shared,
        runtimeState: RepositoryRuntimeState? = nil,
        nowProvider: @escaping @Sendable () -> Date = { .now }
    ) {
        if baseURL.absoluteString.hasSuffix("/") {
            self.baseURL = baseURL
        } else {
            self.baseURL = URL(string: baseURL.absoluteString + "/") ?? baseURL
        }
        self.session = session
        self.runtimeState = runtimeState
        self.nowProvider = nowProvider
    }

    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        if isOfficialKBOHost {
            let payload = try await fetchNormalizedPayload(.games).asBootstrapDTO()
            await runtimeState?.record(source: .live, delivery: .live)
            return KBODataMapper.mapBootstrap(
                KBOBootstrapDTO(
                    teams: payload.teams,
                    games: payload.games,
                    notifications: [],
                    settings: nil
                )
            )
        }

        do {
            let payload = try await fetchNormalizedPayload(.bootstrap).asBootstrapDTO()
            await runtimeState?.record(source: .live, delivery: .live)
            return KBODataMapper.mapBootstrap(payload)
        } catch {
            #if DEBUG
            print("[LiveAPI] bootstrap primary endpoint failed. falling back to monthly schedule. error=\(error)")
            #endif

            let month = KBOMonthScheduleKey(date: nowProvider())
            let fallbackPayload = try await fetchNormalizedPayload(.monthlySchedule(month))
            let fallbackBootstrap = KBOBootstrapDTO(
                teams: fallbackPayload.teams,
                games: fallbackPayload.games,
                notifications: [],
                settings: nil
            )
            #if DEBUG
            print("[LiveAPI] bootstrap fallback active endpoint=api/v1/games/month month=\(month.year)-\(month.month)")
            #endif
            await runtimeState?.record(source: .live, delivery: .live)
            return KBODataMapper.mapBootstrap(fallbackBootstrap)
        }
    }

    nonisolated func fetchGames() async throws -> [GameDetail] {
        let payload = try await fetchNormalizedPayload(.games)
        let teams = payload.teams.isEmpty ? try await fetchTeams() : payload.teams.map(KBODataMapper.mapTeam)
        await runtimeState?.record(source: .live, delivery: .live)
        return KBODataMapper.mapGames(payload.games, teams: teams)
    }

    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        let payload = try await fetchNormalizedPayload(.notifications)
        await runtimeState?.record(source: .live, delivery: .live)
        return KBODataMapper.mapNotifications(payload.notifications)
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        let payload = try await fetchNormalizedPayload(.monthlySchedule(month))
        let teams = payload.teams.isEmpty ? try await fetchTeams() : payload.teams.map(KBODataMapper.mapTeam)
        await runtimeState?.record(source: .live, delivery: .live)
        return KBODataMapper.mapGames(payload.games, teams: teams)
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        let month = KBOMonthScheduleKey(date: date)
        let calendar = Calendar(identifier: .gregorian)
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: date)
        return try await fetchMonthlySchedule(for: month).filter { game in
            let components = calendar.dateComponents([.year, .month, .day], from: game.scheduledStart)
            return components.year == dayComponents.year &&
                components.month == dayComponents.month &&
                components.day == dayComponents.day
        }
    }

    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        let request = try makeRequest(for: .standings)
#if DEBUG
        logRequest(request, endpoint: .standings)
#endif
        let (data, response) = try await session.data(for: request)
        try validate(response: response, endpoint: .standings)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(KBOStandingsResponseDTO.self, from: data)
        let teams = try await fetchTeams()
        await runtimeState?.record(source: .live, delivery: .live)
        return KBODataMapper.mapStandings(payload, teams: teams)
    }

    private func fetchTeams() async throws -> [Team] {
        let payload = try await fetchNormalizedPayload(.teams)
        return payload.teams.map(KBODataMapper.mapTeam)
    }

    private func fetchNormalizedPayload(_ endpoint: Endpoint) async throws -> KBOExternalNormalizedPayload {
        let request = try makeRequest(for: endpoint)
        #if DEBUG
        logRequest(request, endpoint: endpoint)
        #endif
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            #if DEBUG
            print("[LiveAPI] transportError endpoint=\(endpoint.path) errorType=\(String(describing: type(of: error)))")
            #endif
            throw error
        }
        #if DEBUG
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("[LiveAPI] response endpoint=\(endpoint.path) status=\(statusCode) bytes=\(data.count)")
        #endif
        try validate(response: response, endpoint: endpoint)

        do {
            let payload = try KBOExternalResponseAdapter.normalize(data: data)
            #if DEBUG
            print(
                "[LiveAPI] decoded endpoint=\(endpoint.path) teams=\(payload.teams.count) games=\(payload.games.count) notifications=\(payload.notifications.count)"
            )
            #endif
            return payload
        } catch {
            #if DEBUG
            print("[LiveAPI] decodingError endpoint=\(endpoint.path) errorType=\(String(describing: type(of: error)))")
            #endif
            throw LiveRepositoryError.decoding(endpoint: endpoint.path, underlying: error)
        }
    }

    nonisolated private func makeRequest(for endpoint: Endpoint) throws -> URLRequest {
        switch endpoint {
        case .games where isOfficialKBOHost:
            let contract = try OfficialKBOLiveGamesRequestContract(baseURL: baseURL, date: nowProvider())
            guard let url = contract.url else {
                throw LiveRepositoryError.invalidBaseURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue(contract.contentType, forHTTPHeaderField: "Content-Type")
            request.setValue(contract.accept, forHTTPHeaderField: "Accept")
            request.setValue(contract.requestedWith, forHTTPHeaderField: "X-Requested-With")
            request.httpBody = contract.bodyData
            return request
        case .monthlySchedule(let month) where isOfficialKBOHost:
            let contract = try OfficialKBOMonthlyScheduleRequestContract(baseURL: baseURL, month: month)
            guard let url = contract.url else {
                throw LiveRepositoryError.invalidBaseURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue(contract.contentType, forHTTPHeaderField: "Content-Type")
            request.setValue(contract.accept, forHTTPHeaderField: "Accept")
            request.setValue(contract.requestedWith, forHTTPHeaderField: "X-Requested-With")
            request.httpBody = contract.bodyData
            return request
        default:
            guard let url = URL(string: endpoint.path, relativeTo: baseURL)?.absoluteURL else {
                throw LiveRepositoryError.invalidBaseURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            return request
        }
    }

    nonisolated private var isOfficialKBOHost: Bool {
        baseURL.host?.contains("koreabaseball.com") == true
    }

    nonisolated private func validate(response: URLResponse, endpoint: Endpoint) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LiveRepositoryError.invalidResponse(endpoint: endpoint.path)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw LiveRepositoryError.httpStatus(code: httpResponse.statusCode, endpoint: endpoint.path)
        }
    }

#if DEBUG
    nonisolated private func logRequest(_ request: URLRequest, endpoint: Endpoint) {
        let method = request.httpMethod ?? "GET"
        let bodyBytes = request.httpBody?.count ?? 0
        print("[LiveAPI] request endpoint=\(endpoint.path) method=\(method) bodyBytes=\(bodyBytes)")
    }
#endif

    private enum Endpoint {
        case bootstrap
        case games
        case notifications
        case standings
        case teams
        case monthlySchedule(KBOMonthScheduleKey)

        nonisolated var path: String {
            switch self {
            case .bootstrap:
                "v1/bootstrap"
            case .games:
                "v1/games"
            case .notifications:
                "notifications"
            case .standings:
                "v1/standings"
            case .teams:
                "v1/teams"
            case .monthlySchedule(let month):
                "api/v1/games/month?year=\(month.year)&month=\(month.month)"
            }
        }
    }
}

enum LiveRepositoryError: LocalizedError, Sendable {
    case invalidBaseURL
    case invalidResponse(endpoint: String)
    case httpStatus(code: Int, endpoint: String)
    case decoding(endpoint: String, underlying: Error)

    var isDecodingFailure: Bool {
        if case .decoding = self {
            return true
        }
        return false
    }
}
