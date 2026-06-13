//
//  ScoreNotificationPayload.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import Foundation
import UserNotifications

nonisolated enum ScoreNotificationEventType: String, Codable, Sendable {
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
    let providerGameID: String?
    let gameDatabaseID: String?
    let stableGameIdentity: String?
    let teamIDs: [String]
    let routeHint: NotificationRouteHint
    let scoringBatterName: String?
    let scoringResultText: String?
    let scoringHitBaseCount: Int?
    let scoringRunsScored: Int?
    let scoringRBI: Int?
    let scoringInning: Int?
    let scoringInningHalf: String?
    let scoringBattingTeamID: String?
    let scoringBattingTeamName: String?
    let scoringAwayScoreAfter: Int?
    let scoringHomeScoreAfter: Int?

    private enum CodingKeys: String, CodingKey {
        case gameID
        case eventType
        case title
        case body
        case publicGameID
        case providerGameID
        case gameDatabaseID
        case stableGameIdentity
        case teamIDs
        case routeHint
        case scoringBatterName
        case scoringResultText
        case scoringHitBaseCount
        case scoringRunsScored
        case scoringRBI = "scoringRbi"
        case scoringInning
        case scoringInningHalf
        case scoringBattingTeamID = "scoringBattingTeamId"
        case scoringBattingTeamName
        case scoringAwayScoreAfter
        case scoringHomeScoreAfter
    }

    nonisolated init(
        gameID: String?,
        eventType: ScoreNotificationEventType,
        title: String,
        body: String,
        publicGameID: String? = nil,
        providerGameID: String? = nil,
        gameDatabaseID: String? = nil,
        stableGameIdentity: String? = nil,
        teamIDs: [String] = [],
        routeHint: NotificationRouteHint = .gameDetail,
        scoringBatterName: String? = nil,
        scoringResultText: String? = nil,
        scoringHitBaseCount: Int? = nil,
        scoringRunsScored: Int? = nil,
        scoringRBI: Int? = nil,
        scoringInning: Int? = nil,
        scoringInningHalf: String? = nil,
        scoringBattingTeamID: String? = nil,
        scoringBattingTeamName: String? = nil,
        scoringAwayScoreAfter: Int? = nil,
        scoringHomeScoreAfter: Int? = nil
    ) {
        self.gameID = gameID
        self.eventType = eventType
        self.title = title
        self.body = body
        self.publicGameID = publicGameID
        self.providerGameID = providerGameID
        self.gameDatabaseID = gameDatabaseID
        self.stableGameIdentity = stableGameIdentity
        self.teamIDs = teamIDs
        self.routeHint = routeHint
        self.scoringBatterName = scoringBatterName
        self.scoringResultText = scoringResultText
        self.scoringHitBaseCount = scoringHitBaseCount
        self.scoringRunsScored = scoringRunsScored
        self.scoringRBI = scoringRBI
        self.scoringInning = scoringInning
        self.scoringInningHalf = scoringInningHalf
        self.scoringBattingTeamID = scoringBattingTeamID
        self.scoringBattingTeamName = scoringBattingTeamName
        self.scoringAwayScoreAfter = scoringAwayScoreAfter
        self.scoringHomeScoreAfter = scoringHomeScoreAfter
    }

    func userInfo() -> [AnyHashable: Any] {
        [
            "kbo_live": [
                "gameId": gameID as Any,
                "eventType": eventType.rawValue,
                "title": title,
                "body": body,
                "publicGameId": publicGameID as Any,
                "providerGameId": providerGameID as Any,
                "gameDatabaseId": gameDatabaseID as Any,
                "stableGameIdentity": stableGameIdentity as Any,
                "teamIds": teamIDs,
                "routeHint": routeHint.rawValue,
                "scoringBatterName": scoringBatterName as Any,
                "scoringResultText": scoringResultText as Any,
                "scoringHitBaseCount": scoringHitBaseCount as Any,
                "scoringRunsScored": scoringRunsScored as Any,
                "scoringRbi": scoringRBI as Any,
                "scoringInning": scoringInning as Any,
                "scoringInningHalf": scoringInningHalf as Any,
                "scoringBattingTeamId": scoringBattingTeamID as Any,
                "scoringBattingTeamName": scoringBattingTeamName as Any,
                "scoringAwayScoreAfter": scoringAwayScoreAfter as Any,
                "scoringHomeScoreAfter": scoringHomeScoreAfter as Any
            ]
        ]
    }
}

enum AppNotificationRoute: Equatable, Sendable {
    case gameDetail(String)
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
            guard let identity = payload.preferredGameNavigationIdentity else {
                return .notifications
            }
            return .gameDetail(identity)
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
            publicGameID: stringValue(for: ["publicGameId", "publicGameID", "gamePublicId", "gamePublicID"], in: dictionary),
            providerGameID: stringValue(for: ["providerGameId", "providerGameID", "gameProviderId", "gameProviderID"], in: dictionary),
            gameDatabaseID: stringValue(for: ["gameDatabaseId", "gameDatabaseID", "databaseGameId", "databaseGameID"], in: dictionary),
            stableGameIdentity: stringValue(for: ["stableGameIdentity", "gameStableIdentity"], in: dictionary),
            teamIDs: teamIDs,
            routeHint: routeHint,
            scoringBatterName: stringValue(for: ["scoringBatterName"], in: dictionary),
            scoringResultText: stringValue(for: ["scoringResultText"], in: dictionary),
            scoringHitBaseCount: intValue(for: ["scoringHitBaseCount"], in: dictionary),
            scoringRunsScored: intValue(for: ["scoringRunsScored"], in: dictionary),
            scoringRBI: intValue(for: ["scoringRbi", "scoringRBI"], in: dictionary),
            scoringInning: intValue(for: ["scoringInning"], in: dictionary),
            scoringInningHalf: stringValue(for: ["scoringInningHalf"], in: dictionary),
            scoringBattingTeamID: stringValue(for: ["scoringBattingTeamId", "scoringBattingTeamID"], in: dictionary),
            scoringBattingTeamName: stringValue(for: ["scoringBattingTeamName"], in: dictionary),
            scoringAwayScoreAfter: intValue(for: ["scoringAwayScoreAfter"], in: dictionary),
            scoringHomeScoreAfter: intValue(for: ["scoringHomeScoreAfter"], in: dictionary)
        )
    }

    nonisolated private static func stringValue(for keys: [String], in dictionary: [String: Any]) -> String? {
        for key in keys {
            guard let value = dictionary[key] as? String else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return trimmed
            }
        }
        return nil
    }

    nonisolated private static func intValue(for keys: [String], in dictionary: [String: Any]) -> Int? {
        for key in keys {
            if let value = dictionary[key] as? Int {
                return value
            }
            if let value = dictionary[key] as? NSNumber {
                return value.intValue
            }
            if let value = dictionary[key] as? String,
               let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return intValue
            }
        }
        return nil
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

extension ScoreNotificationPayload {
    nonisolated var preferredGameNavigationIdentity: String? {
        if let publicGameID = nonBlank(publicGameID) {
            return publicGameID
        }
        if let providerGameID = nonBlank(providerGameID) {
            return GameIdentifier.providerKey(providerGameID)
        }
        if let databaseIdentity = databaseIdentity(from: gameDatabaseID) {
            return databaseIdentity
        }
        if let stableIdentity = realStableIdentity(stableGameIdentity) {
            return stableIdentity
        }
        guard let gameID = nonBlank(gameID) else { return nil }
        if let databaseIdentity = databaseIdentity(from: gameID) {
            return databaseIdentity
        }
        return gameID
    }

    nonisolated private func databaseIdentity(from value: String?) -> String? {
        guard let value = nonBlank(value) else { return nil }
        if value.hasPrefix("id:") {
            let rawID = String(value.dropFirst("id:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return UUID(uuidString: rawID).map { GameIdentifier.idKey($0) }
        }
        return UUID(uuidString: value).map { GameIdentifier.idKey($0) }
    }

    nonisolated private func realStableIdentity(_ value: String?) -> String? {
        guard let value = nonBlank(value) else { return nil }
        if value.hasPrefix("public:") || value.hasPrefix("provider:") {
            return value
        }
        if value.hasPrefix("id:") {
            return databaseIdentity(from: value)
        }
        return nil
    }

    nonisolated private func nonBlank(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else { return nil }
        return value
    }
}
