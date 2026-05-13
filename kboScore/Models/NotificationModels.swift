//
//  NotificationModels.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import Foundation

enum NotificationType: String, Codable, Hashable, Sendable {
    case scoreChange
    case onBase
    case gameStart
    case leadChange
    case gameEnd
    case inningChange
    case rainDelay

    nonisolated var title: String {
        switch self {
        case .scoreChange:
            "점수 변경"
        case .onBase:
            "출루"
        case .gameStart:
            "경기 시작"
        case .leadChange:
            "리드 변경"
        case .gameEnd:
            "경기 종료"
        case .inningChange:
            "이닝 교체"
        case .rainDelay:
            "우천/취소"
        }
    }

    nonisolated var isScoreLike: Bool {
        switch self {
        case .scoreChange, .leadChange, .onBase:
            true
        case .gameStart, .gameEnd, .inningChange, .rainDelay:
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
    let receivedAt: Date?
    var isRead: Bool
    let relatedGameID: UUID?
    let publicGameID: String?
    let relatedTeamIDs: [String]

    init(
        id: UUID,
        type: NotificationType,
        title: String,
        body: String,
        sentAt: Date,
        receivedAt: Date? = nil,
        isRead: Bool,
        relatedGameID: UUID?,
        publicGameID: String? = nil,
        relatedTeamIDs: [String]
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.sentAt = sentAt
        self.receivedAt = receivedAt
        self.isRead = isRead
        self.relatedGameID = relatedGameID
        self.publicGameID = publicGameID
        self.relatedTeamIDs = relatedTeamIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case body
        case sentAt
        case receivedAt
        case isRead
        case relatedGameID
        case publicGameID
        case relatedTeamIDs
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try container.decodeIfPresent(NotificationType.self, forKey: .type) ?? .scoreChange
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? type.title
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        let decodedReceivedAt = try container.decodeIfPresent(Date.self, forKey: .receivedAt)
        sentAt = try container.decodeIfPresent(Date.self, forKey: .sentAt) ?? decodedReceivedAt ?? .distantPast
        receivedAt = decodedReceivedAt
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        relatedGameID = try container.decodeIfPresent(UUID.self, forKey: .relatedGameID)
        publicGameID = try container.decodeIfPresent(String.self, forKey: .publicGameID)
        relatedTeamIDs = try container.decodeIfPresent([String].self, forKey: .relatedTeamIDs) ?? []
    }
}
