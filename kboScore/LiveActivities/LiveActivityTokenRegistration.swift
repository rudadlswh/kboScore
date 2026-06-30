//
//  LiveActivityTokenRegistration.swift
//  kboScore
//  기능 설명: Live Activity 푸시 토큰 등록 요청과 전송 모델을 정의합니다.
//  앱 밖에서도 마이팀 경기 흐름을 이어서 볼 수 있도록 Live Activity와 위젯용 스냅샷을 분리합니다.
//  확장 프로세스, App Group 저장소, 푸시 토큰, 시스템 권한 상태에 따라 갱신이 실패할 수 있습니다.
//  TODO : 실기기 권한 상태별 동작과 종료 조건을 더 촘촘히 검증합니다.
//
//  Created by Codex on 6/5/26.
//

import Foundation

protocol LiveActivityTokenRegistrationClient: Sendable {
    nonisolated var debugEndpointDescription: String? { get }
    // register 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    nonisolated func register(_ payload: LiveActivityTokenRegistrationPayload) async throws -> LiveActivityTokenRegistrationStatus
}

protocol LiveActivityPushToStartTokenRegistrationClient: Sendable {
    nonisolated var debugEndpointDescription: String? { get }
    nonisolated func register(_ payload: LiveActivityPushToStartTokenRegistrationPayload) async throws -> LiveActivityTokenRegistrationStatus
}

// LiveActivityTokenRegistrationStatus 열거형는 처리 단계나 경기 상태를 구분합니다.
enum LiveActivityTokenRegistrationStatus: Sendable {
    case synced
    case skipped
}

// LiveActivityTokenRegistrationPayload 구조체는 LiveActivityTokenRegistrationPayload 타입의 역할과 값을 정의합니다.
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

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
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

nonisolated struct LiveActivityPushToStartTokenRegistrationPayload: Codable, Equatable, Sendable {
    let platform: String
    let environment: String
    let pushToStartToken: String
    let installationId: String
    let favoriteTeamID: String?
    let notificationsAuthorized: Bool
    let liveActivitiesEnabled: Bool
    let liveActivityAutoStartEnabled: Bool
    let gameStartEnabled: Bool
    let favoriteTeamOnlyEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case platform
        case environment
        case pushToStartToken
        case installationId
        case favoriteTeamID
        case notificationsAuthorized
        case liveActivitiesEnabled
        case liveActivityAutoStartEnabled
        case gameStartEnabled
        case favoriteTeamOnlyEnabled
    }

    nonisolated init(
        platform: String = "ios",
        environment: String = NotificationRegistrationEnvironment.current,
        pushToStartToken: String,
        installationId: String = NotificationInstallationID.current,
        favoriteTeamID: String?,
        notificationsAuthorized: Bool,
        liveActivitiesEnabled: Bool,
        liveActivityAutoStartEnabled: Bool,
        gameStartEnabled: Bool,
        favoriteTeamOnlyEnabled: Bool
    ) {
        self.platform = platform
        self.environment = environment
        self.pushToStartToken = pushToStartToken
        self.installationId = installationId
        self.favoriteTeamID = favoriteTeamID
        self.notificationsAuthorized = notificationsAuthorized
        self.liveActivitiesEnabled = liveActivitiesEnabled
        self.liveActivityAutoStartEnabled = liveActivityAutoStartEnabled
        self.gameStartEnabled = gameStartEnabled
        self.favoriteTeamOnlyEnabled = favoriteTeamOnlyEnabled
    }

    nonisolated init(
        pushToStartToken: String,
        settings: AppSettings,
        authorizationStatus: AppNotificationAuthorizationStatus
    ) {
        self.init(
            pushToStartToken: pushToStartToken,
            favoriteTeamID: settings.favoriteTeamID,
            notificationsAuthorized: authorizationStatus.allowsNotifications,
            liveActivitiesEnabled: settings.liveActivitiesEnabled,
            liveActivityAutoStartEnabled: settings.liveActivityAutoStartEnabled,
            gameStartEnabled: settings.notificationPreferences.gameStartEnabled,
            favoriteTeamOnlyEnabled: settings.notificationPreferences.favoriteTeamOnlyEnabled
        )
    }
}

nonisolated struct LiveActivityPushToStartTokenRegistrationKey: Hashable, Sendable, CustomStringConvertible {
    let tokenPrefix: String
    let environment: String
    let installationId: String
    let favoriteTeamID: String?
    let notificationsAuthorized: Bool
    let liveActivitiesEnabled: Bool
    let liveActivityAutoStartEnabled: Bool
    let gameStartEnabled: Bool
    let favoriteTeamOnlyEnabled: Bool
    let endpointDescription: String?

    nonisolated init(payload: LiveActivityPushToStartTokenRegistrationPayload, endpointDescription: String?) {
        self.tokenPrefix = String(payload.pushToStartToken.prefix(8))
        self.environment = payload.environment
        self.installationId = payload.installationId
        self.favoriteTeamID = payload.favoriteTeamID
        self.notificationsAuthorized = payload.notificationsAuthorized
        self.liveActivitiesEnabled = payload.liveActivitiesEnabled
        self.liveActivityAutoStartEnabled = payload.liveActivityAutoStartEnabled
        self.gameStartEnabled = payload.gameStartEnabled
        self.favoriteTeamOnlyEnabled = payload.favoriteTeamOnlyEnabled
        self.endpointDescription = endpointDescription
    }

    nonisolated var description: String {
        [
            "environment=\(environment)",
            "hasFavoriteTeamID=\(favoriteTeamID?.isEmpty == false)",
            "notificationsAuthorized=\(notificationsAuthorized)",
            "liveActivitiesEnabled=\(liveActivitiesEnabled)",
            "liveActivityAutoStartEnabled=\(liveActivityAutoStartEnabled)",
            "gameStartEnabled=\(gameStartEnabled)",
            "favoriteTeamOnlyEnabled=\(favoriteTeamOnlyEnabled)",
            "endpoint=\(endpointDescription ?? "missing")"
        ].joined(separator: " ")
    }
}

// LiveActivityTokenRegistrationKey 구조체는 LiveActivityTokenRegistrationKey 타입의 역할과 값을 정의합니다.
nonisolated struct LiveActivityTokenRegistrationKey: Hashable, Sendable, CustomStringConvertible {
    let activityId: String
    let tokenPrefix: String
    let environment: String
    let publicGameID: String?
    let providerGameID: String?
    let databaseID: String
    let stableDetailIdentity: String
    let endpointDescription: String?

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(payload: LiveActivityTokenRegistrationPayload, endpointDescription: String?) {
        self.activityId = payload.activityId
        self.tokenPrefix = String(payload.activityToken.prefix(8))
        self.environment = payload.environment
        self.publicGameID = payload.publicGameID
        self.providerGameID = payload.providerGameID
        self.databaseID = payload.databaseID
        self.stableDetailIdentity = payload.stableDetailIdentity
        self.endpointDescription = endpointDescription
    }

    nonisolated var description: String {
        [
            "hasActivityId=\(activityId.isEmpty == false)",
            "environment=\(environment)",
            "hasPublicGameID=\(publicGameID?.isEmpty == false)",
            "hasProviderGameID=\(providerGameID?.isEmpty == false)",
            "hasDatabaseID=\(databaseID.isEmpty == false)",
            "hasStableDetailIdentity=\(stableDetailIdentity.isEmpty == false)",
            "endpoint=\(endpointDescription ?? "missing")"
        ].joined(separator: " ")
    }
}

// LiveActivityTokenRegistrationClientFactory 열거형는 실행 환경에 맞는 구현체 생성을 담당합니다.
enum LiveActivityTokenRegistrationClientFactory {
    // makeAppClient 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    static func makeAppClient() -> any LiveActivityTokenRegistrationClient {
        let processValue = ProcessInfo.processInfo.environment["KBO_LIVE_ACTIVITY_REGISTRATION_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitBundleValue = (Bundle.main.object(forInfoDictionaryKey: "LiveActivityRegistrationURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let notificationURL = NotificationRegistrationClientFactory.configuredNotificationRegistrationURL()
        let endpointURL = configuredLiveActivityRegistrationURL(
            processValue: processValue,
            explicitBundleValue: explicitBundleValue,
            notificationURL: notificationURL
        )
        guard let endpointURL else {
            #if DEBUG
            print("[LiveActivity] token registration skipped: registration URL missing")
            #endif
            return NoOpLiveActivityTokenRegistrationClient()
        }
        return RemoteLiveActivityTokenRegistrationClient(endpointURL: endpointURL)
    }

    // configuredLiveActivityRegistrationURL 메서드는 명시 URL을 우선하고 없으면 알림 등록 URL에서 파생합니다.
    static func configuredLiveActivityRegistrationURL(
        processValue: String?,
        explicitBundleValue: String?,
        notificationURL: URL?
    ) -> URL? {
        let endpointText = [processValue, explicitBundleValue]
            .compactMap { $0 }
            .first(where: { $0.isEmpty == false && $0.hasPrefix("$(") == false })
        return endpointText.flatMap(URL.init(string:)) ?? notificationURL.flatMap { derivedLiveActivityURL(from: $0) }
    }

    // derivedLiveActivityURL 메서드는 이 타입의 주요 동작을 수행합니다.
    static func derivedLiveActivityURL(from notificationURL: URL) -> URL? {
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

enum LiveActivityPushToStartTokenRegistrationClientFactory {
    static func makeAppClient() -> any LiveActivityPushToStartTokenRegistrationClient {
        let processValue = ProcessInfo.processInfo.environment["KBO_LIVE_ACTIVITY_PUSH_TO_START_REGISTRATION_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitBundleValue = (Bundle.main.object(forInfoDictionaryKey: "LiveActivityPushToStartRegistrationURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let notificationURL = NotificationRegistrationClientFactory.configuredNotificationRegistrationURL()
        let endpointURL = configuredPushToStartRegistrationURL(
            processValue: processValue,
            explicitBundleValue: explicitBundleValue,
            notificationURL: notificationURL
        )
        guard let endpointURL else {
            #if DEBUG
            print("[LiveActivity] push-to-start registration skipped: registration URL missing")
            #endif
            return NoOpLiveActivityPushToStartTokenRegistrationClient()
        }
        return RemoteLiveActivityPushToStartTokenRegistrationClient(endpointURL: endpointURL)
    }

    static func configuredPushToStartRegistrationURL(
        processValue: String?,
        explicitBundleValue: String?,
        notificationURL: URL?
    ) -> URL? {
        let endpointText = [processValue, explicitBundleValue]
            .compactMap { $0 }
            .first(where: { $0.isEmpty == false && $0.hasPrefix("$(") == false })
        return endpointText.flatMap(URL.init(string:)) ?? notificationURL.flatMap { derivedPushToStartRegistrationURL(from: $0) }
    }

    static func derivedPushToStartRegistrationURL(from notificationURL: URL) -> URL? {
        var url = notificationURL
        if url.lastPathComponent == "register" {
            url.deleteLastPathComponent()
        }
        if url.lastPathComponent != "devices" {
            url.deleteLastPathComponent()
            url.appendPathComponent("devices")
        }
        url.appendPathComponent("live-activities")
        url.appendPathComponent("push-to-start")
        url.appendPathComponent("register")
        return url
    }
}

// NoOpLiveActivityTokenRegistrationClient 구조체는 외부 서비스나 시스템 기능 호출을 캡슐화합니다.
struct NoOpLiveActivityTokenRegistrationClient: LiveActivityTokenRegistrationClient {
    nonisolated var debugEndpointDescription: String? { nil }

    // register 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    nonisolated func register(_ payload: LiveActivityTokenRegistrationPayload) async throws -> LiveActivityTokenRegistrationStatus {
        #if DEBUG
        print("[LiveActivity] token registration skipped: registration URL missing")
        #endif
        return .skipped
    }
}

struct NoOpLiveActivityPushToStartTokenRegistrationClient: LiveActivityPushToStartTokenRegistrationClient {
    nonisolated var debugEndpointDescription: String? { nil }

    nonisolated func register(_ payload: LiveActivityPushToStartTokenRegistrationPayload) async throws -> LiveActivityTokenRegistrationStatus {
        #if DEBUG
        print("[LiveActivity] push-to-start registration skipped: registration URL missing")
        #endif
        return .skipped
    }
}

// RemoteLiveActivityTokenRegistrationClient 구조체는 외부 서비스나 시스템 기능 호출을 캡슐화합니다.
struct RemoteLiveActivityTokenRegistrationClient: LiveActivityTokenRegistrationClient {
    let endpointURL: URL
    let session: URLSession

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(endpointURL: URL, session: URLSession = .shared) {
        self.endpointURL = endpointURL
        self.session = session
    }

    nonisolated var debugEndpointDescription: String? {
        endpointURL.absoluteString
    }

    // register 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    nonisolated func register(_ payload: LiveActivityTokenRegistrationPayload) async throws -> LiveActivityTokenRegistrationStatus {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            #if DEBUG
            print("[LiveActivity] token registration failure endpoint=\(endpointURL.absoluteString) environment=\(payload.environment) hasActivityId=\(payload.activityId.isEmpty == false) hasPublicGameID=\(payload.publicGameID?.isEmpty == false) hasProviderGameID=\(payload.providerGameID?.isEmpty == false) status=-1 responseKind=nonHttp retry=false")
            #else
            print("[LiveActivity] token registration failure reason=nonHttpResponse status=-1 retry=false")
            #endif
            throw RemoteNotificationRegistrationClientError.unexpectedStatusCode(-1)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            #if DEBUG
            print("[LiveActivity] token registration failure endpoint=\(endpointURL.absoluteString) environment=\(payload.environment) hasActivityId=\(payload.activityId.isEmpty == false) hasPublicGameID=\(payload.publicGameID?.isEmpty == false) hasProviderGameID=\(payload.providerGameID?.isEmpty == false) status=\(httpResponse.statusCode) responseBytes=\(data.count) retry=false")
            #else
            print("[LiveActivity] token registration failure reason=unexpectedStatusCode status=\(httpResponse.statusCode) retry=false")
            #endif
            throw RemoteNotificationRegistrationClientError.unexpectedStatusCode(httpResponse.statusCode)
        }
        #if DEBUG
        print("[LiveActivity] token registration response success endpoint=\(endpointURL.absoluteString) environment=\(payload.environment) hasActivityId=\(payload.activityId.isEmpty == false) hasPublicGameID=\(payload.publicGameID?.isEmpty == false) hasProviderGameID=\(payload.providerGameID?.isEmpty == false) status=\(httpResponse.statusCode) retry=false")
        #endif
        return .synced
    }
}

struct RemoteLiveActivityPushToStartTokenRegistrationClient: LiveActivityPushToStartTokenRegistrationClient {
    let endpointURL: URL
    let session: URLSession

    nonisolated init(endpointURL: URL, session: URLSession = .shared) {
        self.endpointURL = endpointURL
        self.session = session
    }

    nonisolated var debugEndpointDescription: String? {
        endpointURL.absoluteString
    }

    nonisolated func register(_ payload: LiveActivityPushToStartTokenRegistrationPayload) async throws -> LiveActivityTokenRegistrationStatus {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            #if DEBUG
            print("[LiveActivity] push-to-start registration failure endpoint=\(endpointURL.absoluteString) environment=\(payload.environment) hasFavoriteTeamID=\(payload.favoriteTeamID?.isEmpty == false) status=-1 responseKind=nonHttp retry=false")
            #else
            print("[LiveActivity] push-to-start registration failure reason=nonHttpResponse status=-1 retry=false")
            #endif
            throw RemoteNotificationRegistrationClientError.unexpectedStatusCode(-1)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            #if DEBUG
            print("[LiveActivity] push-to-start registration failure endpoint=\(endpointURL.absoluteString) environment=\(payload.environment) hasFavoriteTeamID=\(payload.favoriteTeamID?.isEmpty == false) status=\(httpResponse.statusCode) responseBytes=\(data.count) retry=false")
            #else
            print("[LiveActivity] push-to-start registration failure reason=unexpectedStatusCode status=\(httpResponse.statusCode) retry=false")
            #endif
            throw RemoteNotificationRegistrationClientError.unexpectedStatusCode(httpResponse.statusCode)
        }
        #if DEBUG
        print("[LiveActivity] push-to-start registration response success endpoint=\(endpointURL.absoluteString) environment=\(payload.environment) hasFavoriteTeamID=\(payload.favoriteTeamID?.isEmpty == false) status=\(httpResponse.statusCode) retry=false")
        #endif
        return .synced
    }
}
