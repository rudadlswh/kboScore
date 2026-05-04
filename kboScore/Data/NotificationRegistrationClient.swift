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
    case localhostUnavailableOnDevice(String)
}

enum NotificationRegistrationClientFactory {
    static func makeAppClient() -> any NotificationRegistrationClient {
        let processValue = ProcessInfo.processInfo.environment["KBO_NOTIFICATION_REGISTRATION_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleValue = (Bundle.main.object(forInfoDictionaryKey: "NotificationRegistrationURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpointText = [processValue, bundleValue]
                .compactMap({ $0 })
                .first(where: { $0.isEmpty == false && $0.hasPrefix("$(") == false }),
              let endpointURL = URL(string: endpointText) else {
            #if DEBUG
            print("[NotificationPipeline] notification registration skipped: registration URL missing")
            #endif
            return NoOpNotificationRegistrationClient()
        }
        #if DEBUG
        print("[NotificationPipeline] registration URL=\(endpointURL.absoluteString)")
        #endif
        return RemoteNotificationRegistrationClient(endpointURL: endpointURL)
    }

    nonisolated static func makeAppClient(endpointURL: URL?) -> any NotificationRegistrationClient {
        guard let endpointURL else {
            return NoOpNotificationRegistrationClient()
        }
        return RemoteNotificationRegistrationClient(endpointURL: endpointURL)
    }
}

struct NoOpNotificationRegistrationClient: NotificationRegistrationClient {
    nonisolated init() {}

    nonisolated var debugEndpointDescription: String? { nil }

    nonisolated func syncRegistration(_ payload: NotificationRegistrationPayload) async throws -> NotificationRegistrationSyncStatus {
        #if DEBUG
        print("[NotificationPipeline] notification registration skipped: registration URL missing")
        #endif
        return .skipped
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
        guard shouldSendRequest(to: endpointURL) else {
            let urlText = endpointURL.absoluteString
            #if DEBUG
            print("[NotificationPipeline] notification registration warning: localhost URL is not reachable from a real device url=\(urlText)")
            #endif
            throw RemoteNotificationRegistrationClientError.localhostUnavailableOnDevice(urlText)
        }

        #if DEBUG
        print("[NotificationPipeline] registration URL=\(endpointURL.absoluteString)")
        print("[NotificationPipeline] registration request start tokenPrefix=\(payload.deviceToken.prefix(12)) environment=\(payload.environment) favoriteTeamID=\(payload.favoriteTeamID ?? "none") notificationsEnabled=\(payload.notificationsAuthorized)")
        #endif

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                #if DEBUG
                print("[NotificationPipeline] registration failure error=non-http response")
                #endif
                throw RemoteNotificationRegistrationClientError.unexpectedStatusCode(-1)
            }
            #if DEBUG
            print("[NotificationPipeline] registration response status=\(httpResponse.statusCode)")
            #endif
            guard (200..<300).contains(httpResponse.statusCode) else {
                #if DEBUG
                let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
                print("[NotificationPipeline] registration failure body=\(body)")
                #endif
                throw RemoteNotificationRegistrationClientError.unexpectedStatusCode(httpResponse.statusCode)
            }
            return .synced
        } catch {
            #if DEBUG
            print("[NotificationPipeline] registration failure error=\(error)")
            #endif
            throw error
        }
    }

    private nonisolated func shouldSendRequest(to url: URL) -> Bool {
        guard Self.isLocalhost(url) else { return true }
        #if os(iOS) && !targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    private nonisolated static func isLocalhost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
