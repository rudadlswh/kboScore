//
//  ScoreNotificationPayload.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import Foundation
import UserNotifications

enum ScoreNotificationEventType: String, Codable, Sendable {
    case gameStart
    case scoreChange
    case onBase
    case leadChange
    case gameEnd
    case inningChange
    case rainDelay
    case general

    init(remoteValue: String?) {
        switch remoteValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "game_start", "game_started", "gamestart":
            self = .gameStart
        case "score_changed", "scorechange":
            self = .scoreChange
        case "on_base", "onbase":
            self = .onBase
        case "lead_changed", "leadchange":
            self = .leadChange
        case "game_end", "game_final", "gameend":
            self = .gameEnd
        case "inning_changed", "inningchange":
            self = .inningChange
        case "game_cancelled", "rain_delay", "raindelay":
            self = .rainDelay
        default:
            self = .general
        }
    }
}

enum NotificationRouteHint: String, Codable, Sendable {
    case gameDetail
    case notifications
    case home
}

enum AppNotificationAuthorizationStatus: String, Sendable {
    case notDetermined = "미요청"
    case denied = "거부됨"
    case authorized = "허용됨"
    case provisional = "임시 허용"
    case ephemeral = "일시 허용"
    case unsupported = "확인 불가"

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .provisional:
            self = .provisional
        case .ephemeral:
            self = .ephemeral
        @unknown default:
            self = .unsupported
        }
    }

    nonisolated var allowsNotifications: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            true
        case .notDetermined, .denied, .unsupported:
            false
        }
    }
}

struct ScoreNotificationPayload: Codable, Equatable, Sendable {
    let gameID: String?
    let eventType: ScoreNotificationEventType
    let title: String
    let body: String
    let publicGameID: String?
    let teamIDs: [String]
    let routeHint: NotificationRouteHint

    nonisolated init(
        gameID: String?,
        eventType: ScoreNotificationEventType,
        title: String,
        body: String,
        publicGameID: String? = nil,
        teamIDs: [String] = [],
        routeHint: NotificationRouteHint = .gameDetail
    ) {
        self.gameID = gameID
        self.eventType = eventType
        self.title = title
        self.body = body
        self.publicGameID = publicGameID
        self.teamIDs = teamIDs
        self.routeHint = routeHint
    }

    func userInfo() -> [AnyHashable: Any] {
        [
            "kbo_live": [
                "gameId": gameID as Any,
                "eventType": eventType.rawValue,
                "title": title,
                "body": body,
                "publicGameId": publicGameID as Any,
                "teamIds": teamIDs,
                "routeHint": routeHint.rawValue
            ]
        ]
    }
}

enum AppNotificationRoute: Equatable, Sendable {
    case gameDetail(UUID)
    case notifications
    case home
}

enum ScoreNotificationPayloadExtractor {
    nonisolated static func payload(from userInfo: [AnyHashable: Any]) -> ScoreNotificationPayload? {
        let normalizedRoot = userInfo.reduce(into: [String: Any]()) { partialResult, entry in
            if let key = entry.key as? String {
                partialResult[key] = entry.value
            }
        }

        if let nested = normalizedRoot["kbo_live"] as? [String: Any] {
            return payload(from: nested, aps: normalizedRoot["aps"] as? [String: Any])
        }
        if let nested = normalizedRoot["data"] as? [String: Any] {
            return payload(from: nested, aps: normalizedRoot["aps"] as? [String: Any])
        }

        return payload(from: normalizedRoot, aps: normalizedRoot["aps"] as? [String: Any])
    }

    nonisolated static func route(from payload: ScoreNotificationPayload) -> AppNotificationRoute? {
        switch payload.routeHint {
        case .gameDetail:
            guard let gameID = GameIdentifier.uuid(from: payload.gameID) else {
                return .notifications
            }
            return .gameDetail(gameID)
        case .notifications:
            return .notifications
        case .home:
            return .home
        }
    }

    nonisolated private static func payload(from dictionary: [String: Any], aps: [String: Any]?) -> ScoreNotificationPayload? {
        let alert = aps?["alert"] as? [String: Any]
        let title = (dictionary["title"] as? String) ?? (alert?["title"] as? String)
        let body = (dictionary["body"] as? String) ?? (alert?["body"] as? String)

        guard let title, let body else { return nil }

        let eventType = ScoreNotificationEventType(remoteValue: dictionary["eventType"] as? String)
        let routeHint = (dictionary["routeHint"] as? String).flatMap(NotificationRouteHint.init(rawValue:)) ?? .gameDetail
        let teamIDs = notificationTeamIDs(from: dictionary)

        return ScoreNotificationPayload(
            gameID: dictionary["gameId"] as? String,
            eventType: eventType,
            title: title,
            body: body,
            publicGameID: dictionary["publicGameId"] as? String,
            teamIDs: teamIDs,
            routeHint: routeHint
        )
    }

    nonisolated private static func notificationTeamIDs(from dictionary: [String: Any]) -> [String] {
        if let teamIDs = dictionary["teamIds"] as? [String] {
            return teamIDs
        }
        return [dictionary["awayTeamId"], dictionary["homeTeamId"], dictionary["eventTeamId"]]
            .compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.isEmpty == false }
            .reduce(into: []) { result, teamID in
                if !result.contains(teamID) {
                    result.append(teamID)
                }
            }
    }
}
