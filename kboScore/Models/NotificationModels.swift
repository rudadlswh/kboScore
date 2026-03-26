//
//  NotificationModels.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import Foundation

enum NotificationType: String, Codable, Hashable, Sendable {
    case scoreChange
    case gameStart
    case leadChange
    case gameEnd
    case rainDelay

    nonisolated var title: String {
        switch self {
        case .scoreChange:
            "점수 변경"
        case .gameStart:
            "경기 시작"
        case .leadChange:
            "리드 변경"
        case .gameEnd:
            "경기 종료"
        case .rainDelay:
            "우천/취소"
        }
    }

    nonisolated var isScoreLike: Bool {
        switch self {
        case .scoreChange, .leadChange:
            true
        case .gameStart, .gameEnd, .rainDelay:
            false
        }
    }
}

struct NotificationItem: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let type: NotificationType
    let title: String
    let body: String
    let sentAt: Date
    var isRead: Bool
    let relatedGameID: UUID?
    let relatedTeamIDs: [String]
}
