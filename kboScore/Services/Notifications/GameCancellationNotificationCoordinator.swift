//
//  GameCancellationNotificationCoordinator.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation
import UserNotifications

struct GameCancellationNotificationCoordinator {
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

    private func notificationBody(favoriteTeam: Team?, isWeatherRelated: Bool) -> String {
        let message = isWeatherRelated
            ? "금일 경기는 우천으로 인해 취소되었습니다."
            : "금일 경기는 취소되었습니다."
        guard let favoriteTeam else { return message }
        return "[\(favoriteTeam.displayName)] \(message)"
    }
}
