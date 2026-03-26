//
//  LiveKBORepository.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import Foundation

enum RepositoryDataSourceKind: String, Sendable {
    case mock = "목 데이터"
    case live = "실데이터"
    case mockFallback = "목 데이터 폴백"
}

enum RepositoryDeliverySourceKind: String, Sendable {
    case mock = "목 데이터"
    case live = "실시간 응답"
    case cache = "메모리 캐시"
    case mockFallback = "목 데이터 폴백"
}

struct RepositoryDebugSnapshot: Sendable {
    let activeSource: RepositoryDataSourceKind
    let deliverySource: RepositoryDeliverySourceKind
    let baseURL: String?
    let lastRefreshAt: Date?
    let isUsingStaleCache: Bool
}

actor RepositoryRuntimeState {
    private(set) var activeSource: RepositoryDataSourceKind
    private(set) var deliverySource: RepositoryDeliverySourceKind
    let baseURL: String?
    private(set) var lastRefreshAt: Date?
    private(set) var isUsingStaleCache: Bool

    init(
        activeSource: RepositoryDataSourceKind,
        baseURL: String?,
        deliverySource: RepositoryDeliverySourceKind? = nil
    ) {
        self.activeSource = activeSource
        self.baseURL = baseURL
        self.deliverySource = deliverySource ?? {
            switch activeSource {
            case .mock:
                .mock
            case .live:
                .live
            case .mockFallback:
                .mockFallback
            }
        }()
        self.lastRefreshAt = nil
        self.isUsingStaleCache = false
    }

    func record(
        source: RepositoryDataSourceKind,
        delivery: RepositoryDeliverySourceKind,
        refreshedAt: Date = .now,
        isUsingStaleCache: Bool = false
    ) {
        activeSource = source
        deliverySource = delivery
        lastRefreshAt = refreshedAt
        self.isUsingStaleCache = isUsingStaleCache
    }

    func recordCacheHit(refreshedAt: Date, isStale: Bool) {
        deliverySource = .cache
        lastRefreshAt = refreshedAt
        isUsingStaleCache = isStale
    }

    func snapshot() -> RepositoryDebugSnapshot {
        RepositoryDebugSnapshot(
            activeSource: activeSource,
            deliverySource: deliverySource,
            baseURL: baseURL,
            lastRefreshAt: lastRefreshAt,
            isUsingStaleCache: isUsingStaleCache
        )
    }
}

struct AppRepositoryBundle {
    let repository: any KBORepository
    let runtimeState: RepositoryRuntimeState?
}

struct KBORepositoryConfiguration: Sendable {
    let liveBaseURL: URL?
    let timeout: TimeInterval
    let useMockFallback: Bool
    let cacheConfiguration: RepositoryCacheConfiguration

    nonisolated static func current(
        processInfo: ProcessInfo = .processInfo,
        bundle: Bundle = .main
    ) -> KBORepositoryConfiguration {
        let environmentURL = processInfo.environment["KBO_LIVE_API_BASE_URL"]
        let bundleURL = bundle.object(forInfoDictionaryKey: "KBOLiveAPIBaseURL") as? String
        let timeoutText = processInfo.environment["KBO_LIVE_API_TIMEOUT"] ??
            (bundle.object(forInfoDictionaryKey: "KBOLiveAPITimeout") as? String)
        let fallbackText = processInfo.environment["KBO_LIVE_USE_MOCK_FALLBACK"] ??
            (bundle.object(forInfoDictionaryKey: "KBOLiveUseMockFallback") as? String)

        return KBORepositoryConfiguration(
            liveBaseURL: URL(string: environmentURL ?? bundleURL ?? ""),
            timeout: TimeInterval(timeoutText ?? "") ?? 8,
            useMockFallback: fallbackText.map(Self.parseBool) ?? true,
            cacheConfiguration: .default
        )
    }

    nonisolated private static func parseBool(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "0", "false", "no", "off":
            false
        default:
            true
        }
    }
}

enum KBORepositoryFactory {
    static func makeAppRepository(configuration: KBORepositoryConfiguration = .current()) -> any KBORepository {
        makeAppRepositoryBundle(configuration: configuration).repository
    }

    static func makeAppRepositoryBundle(configuration: KBORepositoryConfiguration = .current()) -> AppRepositoryBundle {
        let mockRepository = MockKBORepository()

        guard let liveBaseURL = configuration.liveBaseURL else {
            let runtimeState = RepositoryRuntimeState(
                activeSource: .mock,
                baseURL: nil,
                deliverySource: .mock
            )
            return AppRepositoryBundle(
                repository: CachedKBORepository(
                    base: RuntimeStateReportingRepository(
                        base: mockRepository,
                        source: .mock,
                        delivery: .mock,
                        runtimeState: runtimeState
                    ),
                    configuration: configuration.cacheConfiguration,
                    runtimeState: runtimeState
                ),
                runtimeState: runtimeState
            )
        }

        let runtimeState = RepositoryRuntimeState(
            activeSource: .live,
            baseURL: liveBaseURL.absoluteString,
            deliverySource: .live
        )
        let liveRepository = LiveKBORepository(
            baseURL: liveBaseURL,
            session: Self.makeSession(timeout: configuration.timeout),
            runtimeState: runtimeState
        )

        let baseRepository: any KBORepository
        guard configuration.useMockFallback else {
            baseRepository = liveRepository
            return AppRepositoryBundle(
                repository: CachedKBORepository(
                    base: AnyKBORepository(baseRepository),
                    configuration: configuration.cacheConfiguration,
                    runtimeState: runtimeState
                ),
                runtimeState: runtimeState
            )
        }

        baseRepository = FallbackKBORepository(primary: liveRepository, fallback: mockRepository, runtimeState: runtimeState)
        return AppRepositoryBundle(
            repository: CachedKBORepository(
                base: AnyKBORepository(baseRepository),
                configuration: configuration.cacheConfiguration,
                runtimeState: runtimeState
            ),
            runtimeState: runtimeState
        )
    }

    static func makeSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }
}

struct RepositoryCacheConfiguration: Sendable {
    let bootstrapTTL: TimeInterval
    let gamesTTL: TimeInterval
    let notificationsTTL: TimeInterval
    let monthlyScheduleTTL: TimeInterval

    nonisolated static let `default` = RepositoryCacheConfiguration(
        bootstrapTTL: 15,
        gamesTTL: 12,
        notificationsTTL: 20,
        monthlyScheduleTTL: 300
    )
}

private struct RepositoryCacheEntry<Value: Sendable>: Sendable {
    let value: Value
    let timestamp: Date
}

private actor RepositoryResponseCache {
    private var bootstrapEntry: RepositoryCacheEntry<KBOBootstrapData>?
    private var gamesEntry: RepositoryCacheEntry<[GameDetail]>?
    private var notificationsEntry: RepositoryCacheEntry<[NotificationItem]>?
    private var monthlyScheduleEntries: [KBOMonthScheduleKey: RepositoryCacheEntry<[GameDetail]>] = [:]

    private var bootstrapTask: Task<KBOBootstrapData, Error>?
    private var gamesTask: Task<[GameDetail], Error>?
    private var notificationsTask: Task<[NotificationItem], Error>?
    private var monthlyScheduleTasks: [KBOMonthScheduleKey: Task<[GameDetail], Error>] = [:]

    func bootstrapValue(
        ttl: TimeInterval,
        fetch: @escaping @Sendable () async throws -> KBOBootstrapData
    ) async throws -> (value: KBOBootstrapData, cachedAt: Date, isCacheHit: Bool, isStale: Bool) {
        let now = Date()
        if let bootstrapEntry, now.timeIntervalSince(bootstrapEntry.timestamp) < ttl {
            return (bootstrapEntry.value, bootstrapEntry.timestamp, true, false)
        }

        if let bootstrapTask {
            let value = try await bootstrapTask.value
            let cachedAt = bootstrapEntry?.timestamp ?? .now
            return (value, cachedAt, false, false)
        }

        let task = Task {
            let value = try await fetch()
            storeBootstrap(value, timestamp: .now)
            return value
        }
        bootstrapTask = task
        defer { bootstrapTask = nil }

        do {
            let value = try await task.value
            return (value, bootstrapEntry?.timestamp ?? .now, false, false)
        } catch {
            if let bootstrapEntry {
                return (bootstrapEntry.value, bootstrapEntry.timestamp, true, true)
            }
            throw error
        }
    }

    func gamesValue(
        ttl: TimeInterval,
        fetch: @escaping @Sendable () async throws -> [GameDetail]
    ) async throws -> (value: [GameDetail], cachedAt: Date, isCacheHit: Bool, isStale: Bool) {
        let now = Date()
        if let gamesEntry, now.timeIntervalSince(gamesEntry.timestamp) < ttl {
            return (gamesEntry.value, gamesEntry.timestamp, true, false)
        }

        if let gamesTask {
            let value = try await gamesTask.value
            let cachedAt = gamesEntry?.timestamp ?? .now
            return (value, cachedAt, false, false)
        }

        let task = Task {
            let value = try await fetch()
            storeGames(value, timestamp: .now)
            return value
        }
        gamesTask = task
        defer { gamesTask = nil }

        do {
            let value = try await task.value
            return (value, gamesEntry?.timestamp ?? .now, false, false)
        } catch {
            if let gamesEntry {
                return (gamesEntry.value, gamesEntry.timestamp, true, true)
            }
            throw error
        }
    }

    func notificationsValue(
        ttl: TimeInterval,
        fetch: @escaping @Sendable () async throws -> [NotificationItem]
    ) async throws -> (value: [NotificationItem], cachedAt: Date, isCacheHit: Bool, isStale: Bool) {
        let now = Date()
        if let notificationsEntry, now.timeIntervalSince(notificationsEntry.timestamp) < ttl {
            return (notificationsEntry.value, notificationsEntry.timestamp, true, false)
        }

        if let notificationsTask {
            let value = try await notificationsTask.value
            let cachedAt = notificationsEntry?.timestamp ?? .now
            return (value, cachedAt, false, false)
        }

        let task = Task {
            let value = try await fetch()
            storeNotifications(value, timestamp: .now)
            return value
        }
        notificationsTask = task
        defer { notificationsTask = nil }

        do {
            let value = try await task.value
            return (value, notificationsEntry?.timestamp ?? .now, false, false)
        } catch {
            if let notificationsEntry {
                return (notificationsEntry.value, notificationsEntry.timestamp, true, true)
            }
            throw error
        }
    }

    func monthlyScheduleValue(
        for month: KBOMonthScheduleKey,
        ttl: TimeInterval,
        fetch: @escaping @Sendable () async throws -> [GameDetail]
    ) async throws -> (value: [GameDetail], cachedAt: Date, isCacheHit: Bool, isStale: Bool) {
        let now = Date()
        if let entry = monthlyScheduleEntries[month], now.timeIntervalSince(entry.timestamp) < ttl {
            return (entry.value, entry.timestamp, true, false)
        }

        if let task = monthlyScheduleTasks[month] {
            let value = try await task.value
            let cachedAt = monthlyScheduleEntries[month]?.timestamp ?? .now
            return (value, cachedAt, false, false)
        }

        let task = Task {
            let value = try await fetch()
            storeMonthlySchedule(value, for: month, timestamp: .now)
            return value
        }
        monthlyScheduleTasks[month] = task
        defer { monthlyScheduleTasks[month] = nil }

        do {
            let value = try await task.value
            return (value, monthlyScheduleEntries[month]?.timestamp ?? .now, false, false)
        } catch {
            if let entry = monthlyScheduleEntries[month] {
                return (entry.value, entry.timestamp, true, true)
            }
            throw error
        }
    }

    private func storeBootstrap(_ value: KBOBootstrapData, timestamp: Date) {
        bootstrapEntry = RepositoryCacheEntry(value: value, timestamp: timestamp)
    }

    private func storeGames(_ value: [GameDetail], timestamp: Date) {
        gamesEntry = RepositoryCacheEntry(value: value, timestamp: timestamp)
    }

    private func storeNotifications(_ value: [NotificationItem], timestamp: Date) {
        notificationsEntry = RepositoryCacheEntry(value: value, timestamp: timestamp)
    }

    private func storeMonthlySchedule(_ value: [GameDetail], for month: KBOMonthScheduleKey, timestamp: Date) {
        monthlyScheduleEntries[month] = RepositoryCacheEntry(value: value, timestamp: timestamp)
    }
}

struct AnyKBORepository: KBORepository, Sendable {
    private let fetchBootstrapDataBlock: @Sendable () async throws -> KBOBootstrapData
    private let fetchGamesBlock: @Sendable () async throws -> [GameDetail]
    private let fetchNotificationsBlock: @Sendable () async throws -> [NotificationItem]
    private let fetchMonthlyScheduleBlock: @Sendable (KBOMonthScheduleKey) async throws -> [GameDetail]

    init(_ base: any KBORepository) {
        fetchBootstrapDataBlock = { try await base.fetchBootstrapData() }
        fetchGamesBlock = { try await base.fetchGames() }
        fetchNotificationsBlock = { try await base.fetchNotifications() }
        fetchMonthlyScheduleBlock = { month in try await base.fetchMonthlySchedule(for: month) }
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
}

struct RuntimeStateReportingRepository<Base: KBORepository>: KBORepository, Sendable {
    let base: Base
    let source: RepositoryDataSourceKind
    let delivery: RepositoryDeliverySourceKind
    let runtimeState: RepositoryRuntimeState?

    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        let value = try await base.fetchBootstrapData()
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }

    nonisolated func fetchGames() async throws -> [GameDetail] {
        let value = try await base.fetchGames()
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }

    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        let value = try await base.fetchNotifications()
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        let value = try await base.fetchMonthlySchedule(for: month)
        await runtimeState?.record(source: source, delivery: delivery)
        return value
    }
}

struct CachedKBORepository<Base: KBORepository>: KBORepository, Sendable {
    let base: Base
    let configuration: RepositoryCacheConfiguration
    let runtimeState: RepositoryRuntimeState?

    private let cache = RepositoryResponseCache()

    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        let result = try await cache.bootstrapValue(ttl: configuration.bootstrapTTL) {
            try await base.fetchBootstrapData()
        }
        if result.isCacheHit {
            await runtimeState?.recordCacheHit(refreshedAt: result.cachedAt, isStale: result.isStale)
        }
        return result.value
    }

    nonisolated func fetchGames() async throws -> [GameDetail] {
        let result = try await cache.gamesValue(ttl: configuration.gamesTTL) {
            try await base.fetchGames()
        }
        if result.isCacheHit {
            await runtimeState?.recordCacheHit(refreshedAt: result.cachedAt, isStale: result.isStale)
        }
        return result.value
    }

    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        let result = try await cache.notificationsValue(ttl: configuration.notificationsTTL) {
            try await base.fetchNotifications()
        }
        if result.isCacheHit {
            await runtimeState?.recordCacheHit(refreshedAt: result.cachedAt, isStale: result.isStale)
        }
        return result.value
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        let result = try await cache.monthlyScheduleValue(for: month, ttl: configuration.monthlyScheduleTTL) {
            try await base.fetchMonthlySchedule(for: month)
        }
        if result.isCacheHit {
            await runtimeState?.recordCacheHit(refreshedAt: result.cachedAt, isStale: result.isStale)
        }
        return result.value
    }
}

struct LiveKBORepository: KBORepository, Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let runtimeState: RepositoryRuntimeState?

    init(baseURL: URL, session: URLSession = .shared, runtimeState: RepositoryRuntimeState? = nil) {
        if baseURL.absoluteString.hasSuffix("/") {
            self.baseURL = baseURL
        } else {
            self.baseURL = URL(string: baseURL.absoluteString + "/") ?? baseURL
        }
        self.session = session
        self.runtimeState = runtimeState
    }

    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        let payload = try await fetchNormalizedPayload(.bootstrap).asBootstrapDTO()
        await runtimeState?.record(source: .live, delivery: .live)
        return KBODataMapper.mapBootstrap(payload)
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

    private func fetchTeams() async throws -> [Team] {
        let payload = try await fetchNormalizedPayload(.teams)
        return payload.teams.map(KBODataMapper.mapTeam)
    }

    private func fetchNormalizedPayload(_ endpoint: Endpoint) async throws -> KBOExternalNormalizedPayload {
        let request = try makeRequest(for: endpoint)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, endpoint: endpoint)

        do {
            return try KBOExternalResponseAdapter.normalize(data: data)
        } catch {
            throw LiveRepositoryError.decoding(endpoint: endpoint.path, underlying: error)
        }
    }

    private func makeRequest(for endpoint: Endpoint) throws -> URLRequest {
        switch endpoint {
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

    private var isOfficialKBOHost: Bool {
        baseURL.host?.contains("koreabaseball.com") == true
    }

    private func validate(response: URLResponse, endpoint: Endpoint) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LiveRepositoryError.invalidResponse(endpoint: endpoint.path)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw LiveRepositoryError.httpStatus(code: httpResponse.statusCode, endpoint: endpoint.path)
        }
    }
    private enum Endpoint {
        case bootstrap
        case games
        case notifications
        case teams
        case monthlySchedule(KBOMonthScheduleKey)

        var path: String {
            switch self {
            case .bootstrap:
                "bootstrap"
            case .games:
                "games"
            case .notifications:
                "notifications"
            case .teams:
                "teams"
            case .monthlySchedule(let month):
                "schedule?year=\(month.year)&month=\(String(format: "%02d", month.month))"
            }
        }
    }
}

struct OfficialKBOMonthlyScheduleRequestContract: Sendable {
    let month: KBOMonthScheduleKey
    let url: URL?

    let contentType = "application/x-www-form-urlencoded; charset=UTF-8"
    let accept = "application/json"
    let requestedWith = "XMLHttpRequest"

    init(baseURL: URL, month: KBOMonthScheduleKey) throws {
        self.month = month
        self.url = URL(string: "ws/Schedule.asmx/GetScheduleList", relativeTo: baseURL)?.absoluteURL
        if url == nil {
            throw LiveRepositoryError.invalidBaseURL
        }
    }

    var seriesIDList: String {
        month.month == 3 ? "0,9" : "0"
    }

    var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "leId", value: "1"),
            URLQueryItem(name: "srIdList", value: seriesIDList),
            URLQueryItem(name: "seasonId", value: String(month.year)),
            URLQueryItem(name: "gameMonth", value: String(format: "%02d", month.month)),
            URLQueryItem(name: "teamId", value: "")
        ]
    }

    var bodyString: String {
        var components = URLComponents()
        components.queryItems = queryItems
        return components.percentEncodedQuery ?? ""
    }

    var bodyData: Data {
        Data(bodyString.utf8)
    }
}

struct FallbackKBORepository<Primary: KBORepository, Fallback: KBORepository>: KBORepository, Sendable {
    let primary: Primary
    let fallback: Fallback
    let runtimeState: RepositoryRuntimeState?

    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        do {
            let result = try await primary.fetchBootstrapData()
            await runtimeState?.record(source: .live, delivery: .live)
            return result
        } catch {
            let result = try await fallback.fetchBootstrapData()
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    nonisolated func fetchGames() async throws -> [GameDetail] {
        do {
            let result = try await primary.fetchGames()
            await runtimeState?.record(source: .live, delivery: .live)
            return result
        } catch {
            let result = try await fallback.fetchGames()
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        do {
            let result = try await primary.fetchNotifications()
            await runtimeState?.record(source: .live, delivery: .live)
            return result
        } catch {
            let result = try await fallback.fetchNotifications()
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
        }
    }

    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        do {
            let result = try await primary.fetchMonthlySchedule(for: month)
            await runtimeState?.record(source: .live, delivery: .live)
            return result
        } catch {
            let result = try await fallback.fetchMonthlySchedule(for: month)
            await runtimeState?.record(source: .mockFallback, delivery: .mockFallback)
            return result
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
