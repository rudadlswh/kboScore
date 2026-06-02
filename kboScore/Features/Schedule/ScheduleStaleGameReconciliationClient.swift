//
//  ScheduleStaleGameReconciliationClient.swift
//  kboScore
//
//  Created by Codex on 5/22/26.
//

import Foundation

protocol ScheduleStaleGameReconciliationClient: Sendable {
    func reconcileStaleGames(dates: [String]) async throws
}

nonisolated enum ScheduleStaleGameReconciliationClientFactory {
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

    private static func isLocalhost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

struct NoOpScheduleStaleGameReconciliationClient: ScheduleStaleGameReconciliationClient {
    nonisolated init() {}

    nonisolated func reconcileStaleGames(dates _: [String]) async throws {}
}

struct BackendScheduleStaleGameReconciliationClient: ScheduleStaleGameReconciliationClient {
    private let baseURL: URL
    private let session: URLSession

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

enum ScheduleStaleGameReconciliationClientError: Error, Sendable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
}

nonisolated private struct ScheduleStaleGameReconciliationRequest: Encodable {
    let dates: [String]
}
