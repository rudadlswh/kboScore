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

enum RemoteNotificationRegistrationClientError: Error, Sendable {
    case unexpectedStatusCode(Int)
}

enum NotificationRegistrationClientFactory {
    static func makeAppClient() -> any NotificationRegistrationClient {
        return NoOpNotificationRegistrationClient()
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

    nonisolated init(
        endpointURL: URL,
        session: URLSession = .shared
    ) {
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
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteNotificationRegistrationClientError.unexpectedStatusCode(-1)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RemoteNotificationRegistrationClientError.unexpectedStatusCode(httpResponse.statusCode)
        }
        return .synced
    }
}
