//
//  NotificationHistoryBuilder.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

enum NotificationHistoryBuilder {
    static func makeItem(
        from payload: ScoreNotificationPayload,
        receivedAt: Date
    ) -> NotificationItem {
        NotificationItem(
            id: UUID(),
            type: notificationType(from: payload.eventType),
            title: payload.title,
            body: payload.body,
            sentAt: receivedAt,
            receivedAt: receivedAt,
            isRead: false,
            relatedGameID: GameIdentifier.uuid(from: payload.gameID ?? payload.publicGameID),
            publicGameID: payload.publicGameID,
            relatedTeamIDs: payload.teamIDs
        )
    }

    private static func notificationType(from eventType: ScoreNotificationEventType) -> NotificationType {
        switch eventType {
        case .gameStart:
            .gameStart
        case .scoreChange:
            .scoreChange
        case .onBase:
            .onBase
        case .leadChange:
            .leadChange
        case .gameEnd:
            .gameEnd
        case .inningChange:
            .inningChange
        case .rainDelay:
            .rainDelay
        case .general:
            .scoreChange
        }
    }
}
