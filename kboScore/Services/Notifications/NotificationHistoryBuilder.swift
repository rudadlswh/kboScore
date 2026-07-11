//
//  NotificationHistoryBuilder.swift
//  kboScore
//  기능 설명: 수신 알림 내역에 저장할 화면 표시용 알림 항목을 생성합니다.
//  경기 상태 변화와 사용자 설정을 연결해 필요한 알림만 중복 없이 전달합니다.
//  APNs 토큰 누락, 권한 거부, 취소 경기, 같은 이벤트 반복 수신을 방어해야 합니다.
//  TODO : 알림 실패 사유를 사용자에게 보여줄 수 있도록 진단 정보를 확장합니다.
//
//  Created by Codex on 5/14/26.
//

import Foundation

// NotificationHistoryBuilder 열거형는 화면이나 도메인 모델에 필요한 값을 조립합니다.
enum NotificationHistoryBuilder {
    // makeItem 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

    // relatedGameID 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func relatedGameID(from payload: ScoreNotificationPayload) -> UUID? {
        if let databaseID = databaseUUID(from: payload.gameDatabaseID) {
            return databaseID
        }
        return databaseUUID(from: payload.gameID)
    }

    // databaseUUID 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // notificationType 메서드는 이 타입의 주요 동작을 수행합니다.
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
