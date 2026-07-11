//
//  LiveKBOBootstrapRefreshingRepository.swift
//  kboScore
//  기능 설명: 앱 부트스트랩 데이터를 백그라운드로 갱신하는 저장소 래퍼입니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 5/14/26.
//

import Foundation

// BootstrapRefreshStateStore 구조체는 BootstrapRefreshStateStore 타입의 역할과 값을 정의합니다.
struct BootstrapRefreshStateStore: Sendable {
    nonisolated(unsafe) private let defaults: UserDefaults
    private let storageKey: String

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(
        baseURL: URL,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.storageKey = "kbo_live_bootstrap_refresh_state::\(baseURL.absoluteString)"
    }

    // load 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func load(isEnabled: Bool) -> BootstrapRefreshDebugSnapshot {
        guard let data = defaults.data(forKey: storageKey),
              let persisted = persistedState(from: data) else {
            return BootstrapRefreshDebugSnapshot(
                isEnabled: isEnabled,
                etag: nil,
                lastFetchAt: nil,
                lastWriteAt: nil,
                lastResult: isEnabled ? .idle : .disabled
            )
        }

        return BootstrapRefreshDebugSnapshot(
            isEnabled: isEnabled,
            etag: persisted.etag,
            lastFetchAt: persisted.lastFetchAt,
            lastWriteAt: persisted.lastWriteAt,
            lastResult: isEnabled ? persisted.lastResult : .disabled
        )
    }

    // save 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    nonisolated func save(_ snapshot: BootstrapRefreshDebugSnapshot) {
        guard let data = encodedState(from: snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }

    // persistedState 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    nonisolated private func persistedState(from data: Data) -> (
        etag: String?,
        lastFetchAt: Date?,
        lastWriteAt: Date?,
        lastResult: BootstrapRefreshResultKind
    )? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let lastResultText = root["lastResult"] as? String
        let lastResult = lastResultText.flatMap(BootstrapRefreshResultKind.init(rawValue:)) ?? .idle

        return (
            etag: root["etag"] as? String,
            lastFetchAt: Self.parseDate(root["lastFetchAt"] as? String),
            lastWriteAt: Self.parseDate(root["lastWriteAt"] as? String),
            lastResult: lastResult
        )
    }

    // encodedState 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private func encodedState(from snapshot: BootstrapRefreshDebugSnapshot) -> Data? {
        var root: [String: Any] = [
            "lastResult": snapshot.lastResult.rawValue
        ]
        if let etag = snapshot.etag {
            root["etag"] = etag
        }
        if let lastFetchAt = snapshot.lastFetchAt {
            root["lastFetchAt"] = Self.formatDate(lastFetchAt)
        }
        if let lastWriteAt = snapshot.lastWriteAt {
            root["lastWriteAt"] = Self.formatDate(lastWriteAt)
        }
        return try? JSONSerialization.data(withJSONObject: root, options: [])
    }

    // formatDate 메서드는 화면 표시와 디버그에 사용할 문구를 구성합니다.
    nonisolated private static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    // parseDate 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func parseDate(_ value: String?) -> Date? {
        guard let value, value.isEmpty == false else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: value) {
            return parsed
        }

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        return fallbackFormatter.date(from: value)
    }
}

// BootstrapRefreshingKBORepository 구조체는 KBO 데이터 조회와 저장소 접근 흐름을 담당합니다.
struct BootstrapRefreshingKBORepository<Base: KBORepository>: KBORepository, Sendable {
    let base: Base
    let localBootstrapRepository: BundledJSONKBORepository
    let bootstrapBaseURL: URL
    let session: URLSession
    let runtimeState: RepositoryRuntimeState?
    let stateStore: BootstrapRefreshStateStore
    let fileManager: FileManager
    private let nowProvider: @Sendable () -> Date

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(
        base: Base,
        localBootstrapRepository: BundledJSONKBORepository,
        bootstrapBaseURL: URL,
        session: URLSession = .shared,
        runtimeState: RepositoryRuntimeState? = nil,
        stateStore: BootstrapRefreshStateStore,
        fileManager: FileManager = .default,
        nowProvider: @escaping @Sendable () -> Date = { .now }
    ) {
        self.base = base
        self.localBootstrapRepository = localBootstrapRepository
        self.bootstrapBaseURL = bootstrapBaseURL
        self.session = session
        self.runtimeState = runtimeState
        self.stateStore = stateStore
        self.fileManager = fileManager
        self.nowProvider = nowProvider
    }

    // fetchBootstrapData 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData {
        await refreshBootstrapSnapshotIfNeeded()
        let value = try await localBootstrapRepository.fetchBootstrapData()
#if DEBUG
        let snapshot = stateStore.load(isEnabled: true)
        print(
            "[RepositorySource] bootstrap source=LocalBootstrapData.json " +
            "refreshResult=\(snapshot.lastResult.rawValue) teams=\(value.teams.count) games=\(value.games.count)"
        )
#endif
        return value
    }

    // fetchGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchGames() async throws -> [GameDetail] {
        try await base.fetchGames()
    }

    // fetchNotifications 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchNotifications() async throws -> [NotificationItem] {
        try await base.fetchNotifications()
    }

    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail] {
        try await base.fetchMonthlySchedule(for: month)
    }

    // fetchMonthlySchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey, bypassingCache: Bool) async throws -> [GameDetail] {
        try await base.fetchMonthlySchedule(for: month, bypassingCache: bypassingCache)
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date) async throws -> [GameDetail] {
        try await base.fetchSchedule(for: date)
    }

    // fetchSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchSchedule(for date: Date, bypassingCache: Bool) async throws -> [GameDetail] {
        try await base.fetchSchedule(for: date, bypassingCache: bypassingCache)
    }

    // fetchStandings 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        try await base.fetchStandings()
    }

    // refreshBootstrapSnapshotIfNeeded 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    private func refreshBootstrapSnapshotIfNeeded() async {
        let fetchedAt = nowProvider()
        let existingSnapshot = stateStore.load(isEnabled: true)
        var request: URLRequest

        do {
            request = try makeBootstrapRequest(etag: existingSnapshot.etag)
        } catch {
            let failedSnapshot = BootstrapRefreshDebugSnapshot(
                isEnabled: true,
                etag: existingSnapshot.etag,
                lastFetchAt: fetchedAt,
                lastWriteAt: existingSnapshot.lastWriteAt,
                lastResult: .failed
            )
            stateStore.save(failedSnapshot)
            await runtimeState?.recordBootstrapRefresh(failedSnapshot)
            return
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LiveRepositoryError.invalidResponse(endpoint: "v1/bootstrap")
            }

            switch httpResponse.statusCode {
            case 200:
                try await handleUpdatedBootstrapResponse(
                    data: data,
                    response: httpResponse,
                    fetchedAt: fetchedAt
                )
            case 304:
                let snapshot = BootstrapRefreshDebugSnapshot(
                    isEnabled: true,
                    etag: httpResponse.value(forHTTPHeaderField: "ETag") ?? existingSnapshot.etag,
                    lastFetchAt: fetchedAt,
                    lastWriteAt: existingSnapshot.lastWriteAt,
                    lastResult: .notModified
                )
                stateStore.save(snapshot)
                await runtimeState?.recordBootstrapRefresh(snapshot)
            default:
                throw LiveRepositoryError.httpStatus(code: httpResponse.statusCode, endpoint: "v1/bootstrap")
            }
        } catch {
            let failedSnapshot = BootstrapRefreshDebugSnapshot(
                isEnabled: true,
                etag: existingSnapshot.etag,
                lastFetchAt: fetchedAt,
                lastWriteAt: existingSnapshot.lastWriteAt,
                lastResult: .failed
            )
            stateStore.save(failedSnapshot)
            await runtimeState?.recordBootstrapRefresh(failedSnapshot)
#if DEBUG
            print("[BootstrapRefresh] refresh failed errorType=\(String(describing: type(of: error)))")
#endif
        }
    }

    // handleUpdatedBootstrapResponse 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    private func handleUpdatedBootstrapResponse(
        data: Data,
        response: HTTPURLResponse,
        fetchedAt: Date
    ) async throws {
        _ = try BundledJSONKBORepository.decodeBootstrapData(from: data)
        guard let fileURL = localBootstrapRepository.localBootstrapFileURL else {
            throw LiveRepositoryError.invalidBaseURL
        }

        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try RepositoryFileSecurity.applyProtection(
            toDirectory: fileURL.deletingLastPathComponent(),
            fileManager: fileManager
        )
        try data.write(to: fileURL, options: .atomic)
        try RepositoryFileSecurity.applyProtection(to: fileURL, fileManager: fileManager)
        try RepositoryFileSecurity.excludeFromBackup(fileURL)

        let snapshot = BootstrapRefreshDebugSnapshot(
            isEnabled: true,
            etag: response.value(forHTTPHeaderField: "ETag"),
            lastFetchAt: fetchedAt,
            lastWriteAt: fetchedAt,
            lastResult: .updated
        )
        stateStore.save(snapshot)
        await runtimeState?.recordBootstrapRefresh(snapshot)
    }

    // makeBootstrapRequest 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    private func makeBootstrapRequest(etag: String?) throws -> URLRequest {
        guard let url = URL(string: "v1/bootstrap", relativeTo: normalizedBaseURL)?.absoluteURL else {
            throw LiveRepositoryError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag, etag.isEmpty == false {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
#if DEBUG
        print("[LiveAPI] request endpoint=v1/bootstrap method=GET")
#endif
        return request
    }

    private var normalizedBaseURL: URL {
        if bootstrapBaseURL.absoluteString.hasSuffix("/") {
            return bootstrapBaseURL
        }
        return URL(string: bootstrapBaseURL.absoluteString + "/") ?? bootstrapBaseURL
    }
}
