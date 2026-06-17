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

// LiveActivityTokenRegistrationClientFactory 열거형는 실행 환경에 맞는 구현체 생성을 담당합니다.
enum LiveActivityTokenRegistrationClientFactory {
    // makeAppClient 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

    // derivedLiveActivityURL 메서드는 이 타입의 주요 동작을 수행합니다.
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
