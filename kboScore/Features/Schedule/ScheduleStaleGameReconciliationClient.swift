//
//  ScheduleStaleGameReconciliationClient.swift
//  kboScore
//  기능 설명: 오래된 경기 일정 보정을 백엔드에 요청하는 클라이언트를 제공합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 5/22/26.
//

import Foundation

protocol ScheduleStaleGameReconciliationClient: Sendable {
    // reconcileStaleGames 메서드는 이 타입의 주요 동작을 수행합니다.
    func reconcileStaleGames(dates: [String]) async throws
}

// ScheduleStaleGameReconciliationClientFactory 열거형는 실행 환경에 맞는 구현체 생성을 담당합니다.
nonisolated enum ScheduleStaleGameReconciliationClientFactory {
    // makeAppClient 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    static func makeAppClient() -> any ScheduleStaleGameReconciliationClient {
        let backendProcessValue = ProcessInfo.processInfo.environment["KBO_BACKEND_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let backendBundleValue = (Bundle.main.object(forInfoDictionaryKey: "KBOBackendBaseURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let notificationProcessValue = ProcessInfo.processInfo.environment["KBO_NOTIFICATION_REGISTRATION_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let notificationBundleValue = (Bundle.main.object(forInfoDictionaryKey: "NotificationRegistrationURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let resolved = resolveBaseURL(
            backendEnvironmentValue: backendProcessValue,
            backendBundleValue: backendBundleValue,
            notificationEnvironmentValue: notificationProcessValue,
            notificationBundleValue: notificationBundleValue
        ) else {
            #if DEBUG
            print("[ScheduleRefresh] stale reconciliation backendBaseURL source=none resolved=<none> client=noop")
            #endif
            return NoOpScheduleStaleGameReconciliationClient()
        }
        #if DEBUG
        print("[ScheduleRefresh] stale reconciliation backendBaseURL source=\(resolved.source) resolved=\(resolved.url.absoluteString)")
        #endif
        return BackendScheduleStaleGameReconciliationClient(baseURL: resolved.url)
    }

    // resolveBaseURL 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    nonisolated static func resolveBaseURL(
        backendEnvironmentValue: String?,
        backendBundleValue: String?,
        notificationEnvironmentValue: String?,
        notificationBundleValue: String?
    ) -> (source: String, url: URL)? {
        #if DEBUG
        #if targetEnvironment(simulator)
        let developmentFallback = "http://localhost:8088"
        #else
        let developmentFallback: String? = nil
        #endif
        #else
        let developmentFallback: String? = nil
        #endif

        let directCandidates: [(source: String, value: String?)] = [
            ("environment", backendEnvironmentValue),
            ("plist", backendBundleValue)
        ]
        let notificationCandidates: [(source: String, value: String?)] = [
            ("notificationEnvironment", notificationEnvironmentValue),
            ("notificationPlist", notificationBundleValue)
        ]

        if let resolved = resolveDirectCandidate(directCandidates[0]) {
            return resolved
        }
        if let resolved = resolveDirectCandidate(directCandidates[1], requiresNonLocalhost: true) {
            return resolved
        }
        if let resolved = notificationCandidates.compactMap(resolveNotificationCandidate).first {
            return resolved
        }
        if let resolved = resolveDirectCandidate(directCandidates[1]) {
            return resolved
        }
        if let resolved = resolveDirectCandidate((source: "developmentFallback", value: developmentFallback)) {
            return resolved
        }
        return nil
    }

    // resolveDirectCandidate 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    private static func resolveDirectCandidate(
        _ candidate: (source: String, value: String?),
        requiresNonLocalhost: Bool = false
    ) -> (source: String, url: URL)? {
        guard let rawValue = candidate.value,
              rawValue.isEmpty == false,
              rawValue.hasPrefix("$(") == false,
              let url = URL(string: rawValue),
              isAllowed(url),
              (requiresNonLocalhost == false || isLocalhost(url) == false) else {
            #if DEBUG
            if let value = candidate.value, value.isEmpty == false, value.hasPrefix("$(") == false {
                print("[ScheduleRefresh] stale reconciliation backendBaseURL rejected source=\(candidate.source) value=\(value)")
            }
            #endif
            return nil
        }
        return (candidate.source, url)
    }

    // resolveNotificationCandidate 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    private static func resolveNotificationCandidate(_ candidate: (source: String, value: String?)) -> (source: String, url: URL)? {
        guard let rawValue = candidate.value,
              rawValue.isEmpty == false,
              rawValue.hasPrefix("$(") == false,
              let endpointURL = URL(string: rawValue),
              let baseURL = baseURL(fromNotificationEndpoint: endpointURL),
              isAllowed(baseURL) else {
            #if DEBUG
            if let value = candidate.value, value.isEmpty == false, value.hasPrefix("$(") == false {
                print("[ScheduleRefresh] stale reconciliation backendBaseURL rejected source=\(candidate.source) value=\(value)")
            }
            #endif
            return nil
        }
        return (candidate.source, baseURL)
    }

    // baseURL 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func baseURL(fromNotificationEndpoint endpointURL: URL) -> URL? {
        guard let scheme = endpointURL.scheme,
              let host = endpointURL.host else {
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = endpointURL.port
        components.path = "/"
        return components.url
    }

    // isAllowed 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              url.host?.isEmpty == false else {
            return false
        }
        #if DEBUG
        #if os(iOS) && !targetEnvironment(simulator)
        if isLocalhost(url) {
            return false
        }
        #endif
        return scheme == "http" || scheme == "https"
        #else
        return scheme == "https"
        #endif
    }

    // isLocalhost 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private static func isLocalhost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

// NoOpScheduleStaleGameReconciliationClient 구조체는 외부 서비스나 시스템 기능 호출을 캡슐화합니다.
struct NoOpScheduleStaleGameReconciliationClient: ScheduleStaleGameReconciliationClient {
    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init() {}

    // reconcileStaleGames 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated func reconcileStaleGames(dates _: [String]) async throws {}
}

// BackendScheduleStaleGameReconciliationClient 구조체는 외부 서비스나 시스템 기능 호출을 캡슐화합니다.
struct BackendScheduleStaleGameReconciliationClient: ScheduleStaleGameReconciliationClient {
    private let baseURL: URL
    private let session: URLSession

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(
        baseURL: URL,
        session: URLSession = .shared
    ) {
        if baseURL.absoluteString.hasSuffix("/") {
            self.baseURL = baseURL
        } else {
            self.baseURL = URL(string: baseURL.absoluteString + "/") ?? baseURL
        }
        self.session = session
    }

    // reconcileStaleGames 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated func reconcileStaleGames(dates: [String]) async throws {
        guard let url = URL(string: "api/v1/games/reconcile-stale", relativeTo: baseURL)?.absoluteURL else {
            throw ScheduleStaleGameReconciliationClientError.invalidURL
        }
        #if DEBUG
        print("[ScheduleRefresh] stale reconciliation resolvedReconcileURL=\(url.absoluteString) datesCount=\(dates.count)")
        #endif

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ScheduleStaleGameReconciliationRequest(dates: dates))

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ScheduleStaleGameReconciliationClientError.invalidResponse
        }
        #if DEBUG
        print("[ScheduleRefresh] stale reconciliation response status=\(httpResponse.statusCode)")
        #endif
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ScheduleStaleGameReconciliationClientError.httpStatus(httpResponse.statusCode)
        }
    }
}

// ScheduleStaleGameReconciliationClientError 열거형는 실패 상황을 구분하고 호출자에게 전달합니다.
enum ScheduleStaleGameReconciliationClientError: Error, Sendable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
}

// ScheduleStaleGameReconciliationRequest 구조체는 ScheduleStaleGameReconciliationRequest 타입의 역할과 값을 정의합니다.
nonisolated private struct ScheduleStaleGameReconciliationRequest: Encodable {
    let dates: [String]
}
