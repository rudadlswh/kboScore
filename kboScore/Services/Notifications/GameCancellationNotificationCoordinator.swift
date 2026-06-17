//
//  GameCancellationNotificationCoordinator.swift
//  kboScore
//  기능 설명: 경기 취소 알림 중복 방지와 예약 로직을 조정합니다.
//  경기 상태 변화와 사용자 설정을 연결해 필요한 알림만 중복 없이 전달합니다.
//  APNs 토큰 누락, 권한 거부, 취소 경기, 같은 이벤트 반복 수신을 방어해야 합니다.
//  TODO : 알림 실패 사유를 사용자에게 보여줄 수 있도록 진단 정보를 확장합니다.
//
//  Created by Codex on 5/14/26.
//

import Foundation
import UserNotifications

// GameCancellationNotificationCoordinator 구조체는 GameCancellationNotificationCoordinator 타입의 역할과 값을 정의합니다.
struct GameCancellationNotificationCoordinator {
    // makeRequest 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    func makeRequest(
        for game: GameDetail,
        favoriteTeam: Team?,
        fingerprint: String,
        isWeatherRelated: Bool
    ) -> UNNotificationRequest {
        let title = "우천/취소 알림"
        let body = notificationBody(favoriteTeam: favoriteTeam, isWeatherRelated: isWeatherRelated)
        let payload = ScoreNotificationPayload(
            gameID: game.canonicalGameIdentityValue,
            eventType: .rainDelay,
            title: title,
            body: body,
            publicGameID: game.publicGameID,
            providerGameID: game.officialGameCenterID ?? game.providerGameID,
            gameDatabaseID: game.id.uuidString,
            stableGameIdentity: game.stableDetailIdentity,
            teamIDs: [game.awayTeam.id, game.homeTeam.id],
            routeHint: .gameDetail
        )

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = payload.userInfo()

        let requestID = GameIdentifier.uuid(from: fingerprint)?.uuidString ?? UUID().uuidString
        return UNNotificationRequest(
            identifier: "game-cancellation-\(requestID)",
            content: content,
            trigger: nil
        )
    }

    // notificationBody 메서드는 이 타입의 주요 동작을 수행합니다.
    private func notificationBody(favoriteTeam: Team?, isWeatherRelated: Bool) -> String {
        let message = isWeatherRelated
            ? "금일 경기는 우천으로 인해 취소되었습니다."
            : "금일 경기는 취소되었습니다."
        guard let favoriteTeam else { return message }
        return "[\(favoriteTeam.displayName)] \(message)"
    }
}
