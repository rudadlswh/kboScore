//
//  NotificationModels.swift
//  kboScore
//  기능 설명: 앱에서 표시하고 저장하는 알림 도메인 모델을 정의합니다.
//  KBO 경기와 팀 규칙을 화면·저장소와 분리된 값 모델로 표현해 계산과 비교 기준을 일관되게 유지합니다.
//  동명이인, 보류 경기, 취소 경기, 누락 점수처럼 원천 데이터가 불완전한 상황을 고려합니다.
//  TODO : 새 시즌 규칙이나 추가 지표가 생기면 모델 확장 지점을 명확히 분리합니다.
//
//  Created by Codex on 3/25/26.
//

import Foundation

// NotificationType 열거형는 도메인 값을 종류별로 구분합니다.
nonisolated enum NotificationType: String, Codable, Hashable, Sendable {
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

// NotificationItem 구조체는 NotificationItem 타입의 역할과 값을 정의합니다.
nonisolated struct NotificationItem: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let type: NotificationType
    let title: String
    let body: String
    let sentAt: Date
    let receivedAt: Date?
    var isRead: Bool
    let relatedGameID: UUID?
    let publicGameID: String?
    let gamePublicID: String?
    let gameProviderID: String?
    let gameDatabaseID: String?
    let gameStableIdentity: String?
    let relatedTeamIDs: [String]

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(
        id: UUID,
        type: NotificationType,
        title: String,
        body: String,
        sentAt: Date,
        receivedAt: Date? = nil,
        isRead: Bool,
        relatedGameID: UUID?,
        publicGameID: String? = nil,
        gamePublicID: String? = nil,
        gameProviderID: String? = nil,
        gameDatabaseID: String? = nil,
        gameStableIdentity: String? = nil,
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
        self.publicGameID = Self.nonBlank(publicGameID) ?? Self.nonBlank(gamePublicID)
        self.gamePublicID = Self.nonBlank(gamePublicID) ?? Self.nonBlank(publicGameID)
        self.gameProviderID = Self.nonBlank(gameProviderID)
        self.gameDatabaseID = Self.nonBlank(gameDatabaseID) ?? relatedGameID.map { GameIdentifier.idKey($0) }
        self.gameStableIdentity = Self.nonBlank(gameStableIdentity)
        self.relatedTeamIDs = relatedTeamIDs
    }

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
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
        case gamePublicID
        case gameProviderID
        case gameDatabaseID
        case gameStableIdentity
        case relatedTeamIDs
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(from decoder: any Decoder) throws {
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
        let decodedPublicGameID = Self.nonBlank(try container.decodeIfPresent(String.self, forKey: .publicGameID))
        let decodedGamePublicID = Self.nonBlank(try container.decodeIfPresent(String.self, forKey: .gamePublicID))
        publicGameID = decodedPublicGameID ?? decodedGamePublicID
        gamePublicID = decodedGamePublicID ?? decodedPublicGameID
        gameProviderID = Self.nonBlank(try container.decodeIfPresent(String.self, forKey: .gameProviderID))
        gameDatabaseID = Self.nonBlank(try container.decodeIfPresent(String.self, forKey: .gameDatabaseID)) ??
            relatedGameID.map { GameIdentifier.idKey($0) }
        gameStableIdentity = Self.nonBlank(try container.decodeIfPresent(String.self, forKey: .gameStableIdentity))
        relatedTeamIDs = try container.decodeIfPresent([String].self, forKey: .relatedTeamIDs) ?? []
    }

    nonisolated var preferredGameNavigationIdentity: String? {
        if let gamePublicID = Self.nonBlank(gamePublicID) ?? Self.nonBlank(publicGameID) {
            return gamePublicID
        }
        if let gameProviderID = Self.nonBlank(gameProviderID) {
            return GameIdentifier.providerKey(gameProviderID)
        }
        if let gameDatabaseID = Self.databaseIdentity(from: gameDatabaseID), gameDatabaseID != GameIdentifier.idKey(id) {
            return gameDatabaseID
        }
        if let relatedGameID, relatedGameID != id {
            return GameIdentifier.idKey(relatedGameID)
        }
        if let gameStableIdentity = Self.realStableIdentity(gameStableIdentity) {
            return gameStableIdentity
        }
        return nil
    }

    // databaseIdentity 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func databaseIdentity(from value: String?) -> String? {
        guard let value = nonBlank(value) else { return nil }
        if value.hasPrefix("id:") {
            let rawID = String(value.dropFirst("id:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return UUID(uuidString: rawID).map { GameIdentifier.idKey($0) }
        }
        return UUID(uuidString: value).map { GameIdentifier.idKey($0) }
    }

    // realStableIdentity 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func realStableIdentity(_ value: String?) -> String? {
        guard let value = nonBlank(value) else { return nil }
        if value.hasPrefix("public:") || value.hasPrefix("provider:") {
            return value
        }
        if value.hasPrefix("id:") {
            return databaseIdentity(from: value)
        }
        return nil
    }

    // nonBlank 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func nonBlank(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else { return nil }
        return value
    }
}
