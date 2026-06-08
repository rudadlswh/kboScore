//
//  LiveActivityTokenRegistration.swift
//  kboScore
//
//  Created by Codex on 6/5/26.
//

import Foundation

protocol LiveActivityTokenRegistrationClient: Sendable {
    nonisolated var debugEndpointDescription: String? { get }
    nonisolated func register(_ payload: LiveActivityTokenRegistrationPayload) async throws -> LiveActivityTokenRegistrationStatus
}

enum LiveActivityTokenRegistrationStatus: Sendable {
    case synced
    case skipped
}

nonisolated struct LiveActivityTokenRegistrationPayload: Codable, Equatable, Sendable {
    let activityId: String
    let platform: String
    let environment: String
    let activityToken: String
    let installationId: String
    let favoriteTeamID: String
    let publicGameID: String?
    let providerGameID: String?
    let databaseID: String
    let stableDetailIdentity: String

    nonisolated init(
        activityId: String,
        platform: String = "ios",
        environment: String = NotificationRegistrationEnvironment.current,
        activityToken: String,
        installationId: String = NotificationInstallationID.current,
        favoriteTeamID: String,
        publicGameID: String?,
        providerGameID: String?,
        databaseID: String,
        stableDetailIdentity: String
    ) {
        self.activityId = activityId
        self.platform = platform
        self.environment = environment
        self.activityToken = activityToken
        self.installationId = installationId
        self.favoriteTeamID = favoriteTeamID
        self.publicGameID = publicGameID
        self.providerGameID = providerGameID
        self.databaseID = databaseID
        self.stableDetailIdentity = stableDetailIdentity
    }
}

nonisolated struct LiveActivityTokenRegistrationKey: Hashable, Sendable, CustomStringConvertible {
    let activityId: String
    let tokenPrefix: String
    let environment: String
    let publicGameID: String?
    let providerGameID: String?
    let databaseID: String
    let stableDetailIdentity: String
    let endpointDescription: String?

    nonisolated init(payload: LiveActivityTokenRegistrationPayload, endpointDescription: String?) {
        self.activityId = payload.activityId
        self.tokenPrefix = String(payload.activityToken.prefix(16))
        self.environment = payload.environment
        self.publicGameID = payload.publicGameID
        self.providerGameID = payload.providerGameID
        self.databaseID = payload.databaseID
        self.stableDetailIdentity = payload.stableDetailIdentity
        self.endpointDescription = endpointDescription
    }

    nonisolated var description: String {
        [
            "activityId=\(activityId)",
            "tokenPrefix=\(tokenPrefix)",
            "environment=\(environment)",
            "publicGameID=\(publicGameID ?? "none")",
            "providerGameID=\(providerGameID ?? "none")",
            "databaseID=\(databaseID)",
            "stableDetailIdentity=\(stableDetailIdentity)",
            "endpoint=\(endpointDescription ?? "missing")"
        ].joined(separator: " ")
    }
}

enum LiveActivityTokenRegistrationClientFactory {
    static func makeAppClient() -> any LiveActivityTokenRegistrationClient {
        let processValue = ProcessInfo.processInfo.environment["KBO_LIVE_ACTIVITY_REGISTRATION_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitBundleValue = (Bundle.main.object(forInfoDictionaryKey: "LiveActivityRegistrationURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let notificationURL = NotificationRegistrationClientFactory.configuredNotificationRegistrationURL()
        let derivedURL = notificationURL.flatMap { Self.derivedLiveActivityURL(from: $0) }
        let endpointText = [processValue, explicitBundleValue]
            .compactMap { $0 }
            .first(where: { $0.isEmpty == false && $0.hasPrefix("$(") == false })
        let endpointURL = endpointText.flatMap(URL.init(string:)) ?? derivedURL
        guard let endpointURL else {
            #if DEBUG
            print("[LiveActivity] token registration skipped: registration URL missing")
            #endif
            return NoOpLiveActivityTokenRegistrationClient()
        }
        return RemoteLiveActivityTokenRegistrationClient(endpointURL: endpointURL)
    }

    private static func derivedLiveActivityURL(from notificationURL: URL) -> URL? {
        var url = notificationURL
        if url.lastPathComponent == "register" {
            url.deleteLastPathComponent()
        }
        if url.lastPathComponent != "devices" {
            url.deleteLastPathComponent()
            url.appendPathComponent("devices")
        }
        url.appendPathComponent("live-activities")
        url.appendPathComponent("register")
        return url
    }
}

struct NoOpLiveActivityTokenRegistrationClient: LiveActivityTokenRegistrationClient {
    nonisolated var debugEndpointDescription: String? { nil }

    nonisolated func register(_ payload: LiveActivityTokenRegistrationPayload) async throws -> LiveActivityTokenRegistrationStatus {
        #if DEBUG
        print("[LiveActivity] token registration skipped: registration URL missing")
        #endif
        return .skipped
    }
}

struct RemoteLiveActivityTokenRegistrationClient: LiveActivityTokenRegistrationClient {
    let endpointURL: URL
    let session: URLSession

    nonisolated init(endpointURL: URL, session: URLSession = .shared) {
        self.endpointURL = endpointURL
        self.session = session
    }

    nonisolated var debugEndpointDescription: String? {
        endpointURL.absoluteString
    }

    nonisolated func register(_ payload: LiveActivityTokenRegistrationPayload) async throws -> LiveActivityTokenRegistrationStatus {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteNotificationRegistrationClientError.unexpectedStatusCode(-1)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            #if DEBUG
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            print("[LiveActivity] token registration failure status=\(httpResponse.statusCode) body=\(body)")
            #endif
            throw RemoteNotificationRegistrationClientError.unexpectedStatusCode(httpResponse.statusCode)
        }
        return .synced
    }
}
