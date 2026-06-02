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
            relatedGameID: relatedGameID(from: payload),
            publicGameID: payload.publicGameID,
            gamePublicID: payload.publicGameID,
            gameProviderID: payload.providerGameID,
            gameDatabaseID: payload.gameDatabaseID,
            gameStableIdentity: payload.stableGameIdentity,
            relatedTeamIDs: payload.teamIDs
        )
    }

    private static func relatedGameID(from payload: ScoreNotificationPayload) -> UUID? {
        if let databaseID = databaseUUID(from: payload.gameDatabaseID) {
            return databaseID
        }
        return databaseUUID(from: payload.gameID)
    }

    private static func databaseUUID(from value: String?) -> UUID? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else { return nil }
        if value.hasPrefix("id:") {
            let rawID = String(value.dropFirst("id:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return UUID(uuidString: rawID)
        }
        return UUID(uuidString: value)
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
