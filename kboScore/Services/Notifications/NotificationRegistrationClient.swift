//
//  NotificationRegistrationClient.swift
//  kboScore
//  기능 설명: 기기 알림 설정과 APNs 토큰을 백엔드에 등록하는 클라이언트를 제공합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 3/26/26.
//

import Foundation

protocol NotificationRegistrationClient: Sendable {
    // syncRegistration 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    nonisolated func syncRegistration(_ payload: NotificationRegistrationPayload) async throws -> NotificationRegistrationSyncStatus
    nonisolated var debugEndpointDescription: String? { get }
}

// RemoteNotificationRegistrationClientError 열거형는 실패 상황을 구분하고 호출자에게 전달합니다.
enum RemoteNotificationRegistrationClientError: Error, Sendable {
    case unexpectedStatusCode(Int)
    case localhostUnavailableOnDevice(String)
}

// NotificationRegistrationClientFactory 열거형는 실행 환경에 맞는 구현체 생성을 담당합니다.
enum NotificationRegistrationClientFactory {
    // configuredNotificationRegistrationURL 메서드는 이 타입의 주요 동작을 수행합니다.
    static func configuredNotificationRegistrationURL() -> URL? {
        let processValue = ProcessInfo.processInfo.environment["KBO_NOTIFICATION_REGISTRATION_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleValue = (Bundle.main.object(forInfoDictionaryKey: "NotificationRegistrationURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpointText = [processValue, bundleValue]
                .compactMap({ $0 })
                .first(where: { $0.isEmpty == false && $0.hasPrefix("$(") == false }),
              let endpointURL = URL(string: endpointText) else {
            return nil
        }
        return endpointURL
    }

    // makeAppClient 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    static func makeAppClient() -> any NotificationRegistrationClient {
        guard let endpointURL = configuredNotificationRegistrationURL() else {
            #if DEBUG
            print("[NotificationPipeline] notification registration skipped: registration URL missing")
            #endif
            return NoOpNotificationRegistrationClient()
        }
        return RemoteNotificationRegistrationClient(endpointURL: endpointURL)
    }

    // makeAppClient 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    nonisolated static func makeAppClient(endpointURL: URL?) -> any NotificationRegistrationClient {
        guard let endpointURL else {
            return NoOpNotificationRegistrationClient()
        }
        return RemoteNotificationRegistrationClient(endpointURL: endpointURL)
    }
}

// NoOpNotificationRegistrationClient 구조체는 외부 서비스나 시스템 기능 호출을 캡슐화합니다.
struct NoOpNotificationRegistrationClient: NotificationRegistrationClient {
    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init() {}

    nonisolated var debugEndpointDescription: String? { nil }

    // syncRegistration 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    nonisolated func syncRegistration(_ payload: NotificationRegistrationPayload) async throws -> NotificationRegistrationSyncStatus {
        #if DEBUG
        print("[NotificationPipeline] notification registration skipped: registration URL missing")
        #endif
        return .skipped
    }
}

// RemoteNotificationRegistrationClient 구조체는 외부 서비스나 시스템 기능 호출을 캡슐화합니다.
struct RemoteNotificationRegistrationClient: NotificationRegistrationClient {
    let endpointURL: URL
    let session: URLSession

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
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

    // syncRegistration 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    nonisolated func syncRegistration(_ payload: NotificationRegistrationPayload) async throws -> NotificationRegistrationSyncStatus {
        guard shouldSendRequest(to: endpointURL) else {
            let urlText = endpointURL.absoluteString
            #if DEBUG
            print("[NotificationPipeline] notification registration warning: localhost URL is not reachable from a real device url=\(urlText)")
            #endif
            throw RemoteNotificationRegistrationClientError.localhostUnavailableOnDevice(urlText)
        }

        #if DEBUG
        print("[NotificationPipeline] registration request start buildConfiguration=\(AppBuildConfiguration.current) \(payload.debugRegistrationDescription)")
        #endif
        AppLog.info(.notification, "[NotificationPipeline] registration request start buildConfiguration=\(AppBuildConfiguration.current) \(payload.debugRegistrationDescription)")

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                #if DEBUG
                print("[NotificationPipeline] registration failure error=non-http response")
                #endif
                AppLog.error(.notification, "[NotificationPipeline] registration failure error=non-http response")
                throw RemoteNotificationRegistrationClientError.unexpectedStatusCode(-1)
            }
            #if DEBUG
            print("[NotificationPipeline] registration response status=\(httpResponse.statusCode)")
            #endif
            AppLog.info(.notification, "[NotificationPipeline] registration response status=\(httpResponse.statusCode)")
            guard (200..<300).contains(httpResponse.statusCode) else {
                #if DEBUG
                let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
                print("[NotificationPipeline] registration failure body=\(body)")
                #endif
                AppLog.warning(.notification, "[NotificationPipeline] registration failure status=\(httpResponse.statusCode)")
                throw RemoteNotificationRegistrationClientError.unexpectedStatusCode(httpResponse.statusCode)
            }
            return .synced
        } catch {
            #if DEBUG
            print("[NotificationPipeline] registration failure error=\(error)")
            #endif
            AppLog.error(.notification, "[NotificationPipeline] registration failure error=\(error)")
            throw error
        }
    }

    // shouldSendRequest 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private nonisolated func shouldSendRequest(to url: URL) -> Bool {
        guard Self.isLocalhost(url) else { return true }
        #if os(iOS) && !targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    // isLocalhost 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private nonisolated static func isLocalhost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
