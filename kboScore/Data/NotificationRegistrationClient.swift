//
//  NotificationRegistrationClient.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import Foundation

protocol NotificationRegistrationClient: Sendable {
    nonisolated func syncRegistration(_ payload: NotificationRegistrationPayload) async throws -> NotificationRegistrationSyncStatus
    nonisolated var debugEndpointDescription: String? { get }
}

struct NotificationRegistrationConfiguration: Sendable {
    let endpointURL: URL?
    let timeout: TimeInterval

    static func current(
        processInfo: ProcessInfo = .processInfo,
        bundle: Bundle = .main
    ) -> NotificationRegistrationConfiguration {
        let environmentURL = processInfo.environment["KBO_NOTIFICATION_REGISTRATION_URL"]
        let bundleURL = bundle.object(forInfoDictionaryKey: "KBONotificationRegistrationURL") as? String
        let timeoutText = processInfo.environment["KBO_NOTIFICATION_REGISTRATION_TIMEOUT"] ??
            (bundle.object(forInfoDictionaryKey: "KBONotificationRegistrationTimeout") as? String)

        return NotificationRegistrationConfiguration(
            endpointURL: URL(string: environmentURL ?? bundleURL ?? ""),
            timeout: TimeInterval(timeoutText ?? "") ?? 8
        )
    }
}

enum NotificationRegistrationClientFactory {
    static func makeAppClient(
        configuration: NotificationRegistrationConfiguration = .current()
    ) -> any NotificationRegistrationClient {
        // Backend notification registration is intentionally disabled in JSON-only mode.
        let _ = configuration
        return NoOpNotificationRegistrationClient()
    }

    static func makeSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }
}

struct NoOpNotificationRegistrationClient: NotificationRegistrationClient {
    nonisolated init() {}

    nonisolated var debugEndpointDescription: String? { nil }

    nonisolated func syncRegistration(_ payload: NotificationRegistrationPayload) async throws -> NotificationRegistrationSyncStatus {
        .skipped
    }
}

struct RemoteNotificationRegistrationClient: NotificationRegistrationClient {
    let endpointURL: URL
    let session: URLSession

    nonisolated init(endpointURL: URL, session: URLSession) {
        self.endpointURL = endpointURL
        self.session = session
    }

    nonisolated var debugEndpointDescription: String? {
        endpointURL.absoluteString
    }

    nonisolated func syncRegistration(_ payload: NotificationRegistrationPayload) async throws -> NotificationRegistrationSyncStatus {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return .synced
    }
}
