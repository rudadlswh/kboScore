//
//  LiveKBOResponseAdapter.swift
//  kboScore
//  기능 설명: 라이브 KBO API DTO를 앱 도메인 모델로 변환합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 3/26/26.
//

import Foundation

// KBOExternalNormalizedPayload 구조체는 KBOExternalNormalizedPayload 타입의 역할과 값을 정의합니다.
struct KBOExternalNormalizedPayload: Sendable {
    let teams: [KBOTeamDTO]
    let games: [KBOGameDTO]
    let notifications: [KBONotificationDTO]
    let settings: AppSettings?

    nonisolated static let empty = KBOExternalNormalizedPayload(teams: [], games: [], notifications: [], settings: nil)

    // asBootstrapDTO 메서드는 이 타입의 주요 동작을 수행합니다.
    func asBootstrapDTO() -> KBOBootstrapDTO {
        KBOBootstrapDTO(
            teams: teams,
            games: games,
            notifications: notifications,
            settings: settings
        )
    }
}

// KBOExternalResponseAdapter 열거형는 KBOExternalResponseAdapter 타입의 역할과 값을 정의합니다.
enum KBOExternalResponseAdapter {
    // normalize 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated static func normalize(data: Data) throws -> KBOExternalNormalizedPayload {
        let rawObject = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return normalize(object: rawObject)
    }

    // normalize 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func normalize(object: Any) -> KBOExternalNormalizedPayload {
        if let dictionary = object as? [String: Any] {
            let root = unwrapContainer(dictionary)
            if let officialGameList = normalizeOfficialGameList(root) {
                return officialGameList
            }
            if let officialScheduleList = normalizeOfficialScheduleList(root) {
                return officialScheduleList
            }
            let explicitTeams = parseTeams(in: root)
            let games = parseGames(in: root)
            let embeddedTeams = extractTeams(from: games, root: root)
            let notifications = parseNotifications(in: root)

            return KBOExternalNormalizedPayload(
                teams: mergeTeams(explicitTeams + embeddedTeams),
                games: games,
                notifications: notifications,
                settings: nil
            )
        }

        if let array = object as? [Any] {
            return normalizeCollection(array)
        }

        return .empty
    }

    // normalizeCollection 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func normalizeCollection(_ array: [Any]) -> KBOExternalNormalizedPayload {
        guard let first = array.first as? [String: Any] else { return .empty }

        if looksLikeNotification(first) {
            return KBOExternalNormalizedPayload(
                teams: [],
                games: [],
                notifications: array.compactMap { ($0 as? [String: Any]).flatMap(parseNotification) },
                settings: nil
            )
        }

        if looksLikeTeam(first) {
            return KBOExternalNormalizedPayload(
                teams: mergeTeams(array.compactMap { ($0 as? [String: Any]).flatMap(parseTeam) }),
                games: [],
                notifications: [],
                settings: nil
            )
        }

        let games = array.compactMap { ($0 as? [String: Any]).flatMap(parseGame) }
        return KBOExternalNormalizedPayload(
            teams: mergeTeams(extractTeams(from: games, root: [:])),
            games: games,
            notifications: [],
            settings: nil
        )
    }

    // unwrapContainer 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func unwrapContainer(_ dictionary: [String: Any]) -> [String: Any] {
        for key in ["payload", "data", "response", "result", "body"] {
            if let nested = dictionaryValue(for: [key], in: dictionary) {
                if let nestedDictionary = nested as? [String: Any] {
                    return unwrapContainer(nestedDictionary)
                }

                if let nestedArray = nested as? [Any] {
                    return ["items": nestedArray]
                }
            }
        }

        return dictionary
    }

    // parseTeams 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func parseTeams(in root: [String: Any]) -> [KBOTeamDTO] {
        let aliases = ["teams", "teamList", "clubs", "clubList", "items"]
        for alias in aliases {
            if let array = arrayValue(for: [alias], in: root) {
                return mergeTeams(array.compactMap { ($0 as? [String: Any]).flatMap(parseTeam) })
            }

            if let nested = nestedDictionary(for: [alias], in: root),
               let array = arrayValue(for: ["items", "list"], in: nested) {
                return mergeTeams(array.compactMap { ($0 as? [String: Any]).flatMap(parseTeam) })
            }
        }

        return []
    }

    // parseGames 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func parseGames(in root: [String: Any]) -> [KBOGameDTO] {
        let arrays = [
            arrayValue(for: ["game"], in: root),
            arrayValue(for: ["games"], in: root),
            arrayValue(for: ["gameList"], in: root),
            arrayValue(for: ["schedule"], in: root),
            arrayValue(for: ["matches"], in: root),
            arrayValue(for: ["items"], in: root)
        ].compactMap { $0 }

        for array in arrays where array.first is [String: Any] {
            let games = array.compactMap { ($0 as? [String: Any]).flatMap(parseGame) }
            if !games.isEmpty {
                return games
            }
        }

        for alias in ["schedule", "games", "matches", "result"] {
            if let nested = nestedDictionary(for: [alias], in: root),
               let array = arrayValue(for: ["items", "list", "games"], in: nested) {
                let games = array.compactMap { ($0 as? [String: Any]).flatMap(parseGame) }
                if !games.isEmpty {
                    return games
                }
            }
        }

        return []
    }

    // parseNotifications 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func parseNotifications(in root: [String: Any]) -> [KBONotificationDTO] {
        let arrays = [
            arrayValue(for: ["notifications"], in: root),
            arrayValue(for: ["alerts"], in: root),
            arrayValue(for: ["pushes"], in: root),
            arrayValue(for: ["feed"], in: root),
            arrayValue(for: ["items"], in: root)
        ].compactMap { $0 }

        for array in arrays where array.first is [String: Any] {
            let notifications = array.compactMap { ($0 as? [String: Any]).flatMap(parseNotification) }
            if !notifications.isEmpty {
                return notifications
            }
        }

        for alias in ["notifications", "alerts", "feed", "result"] {
            if let nested = nestedDictionary(for: [alias], in: root),
               let array = arrayValue(for: ["items", "list"], in: nested) {
                let notifications = array.compactMap { ($0 as? [String: Any]).flatMap(parseNotification) }
                if !notifications.isEmpty {
                    return notifications
                }
            }
        }

        return []
    }

    // parseGame 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func parseGame(_ dictionary: [String: Any]) -> KBOGameDTO? {
        if let officialGame = parseOfficialGame(dictionary) {
            return officialGame
        }

        let awayTeam = nestedDictionary(for: ["away", "awayTeam", "visitor", "visitorTeam"], in: dictionary)
        let homeTeam = nestedDictionary(for: ["home", "homeTeam", "host", "hostTeam"], in: dictionary)

        let awayTeamID = stringValue(for: ["awayTeamID", "awayTeamId", "visitorTeamId"], in: dictionary) ??
            stringValue(for: ["id", "teamId", "code"], in: awayTeam)
        let homeTeamID = stringValue(for: ["homeTeamID", "homeTeamId", "hostTeamId"], in: dictionary) ??
            stringValue(for: ["id", "teamId", "code"], in: homeTeam)

        guard let awayTeamID, let homeTeamID else { return nil }

        let scheduledStart = parseDate(in: dictionary)
        let statusText = stringValue(for: ["statusText", "gameStatus", "statusName", "state"], in: dictionary) ??
            stringValue(for: ["name", "description", "text"], in: nestedDictionary(for: ["status"], in: dictionary))
        let statusCode = stringValue(for: ["statusCode", "status", "statusCd", "stateCode"], in: dictionary) ??
            stringValue(for: ["code", "value"], in: nestedDictionary(for: ["status"], in: dictionary))
        let seasonClassification = stringValue(
            for: ["seasonClassification", "seasonType", "gameClassification", "gameType", "GAME_SC_NM"],
            in: dictionary
        )
        let bases = parseBases(in: dictionary)

        return KBOGameDTO(
            id: GameIdentifier.uuid(from: stringValue(for: ["id", "gameId", "gameID", "matchId"], in: dictionary)) ?? UUID(),
            providerGameID: stringValue(
                for: ["officialProviderGameID", "official_provider_game_id", "providerGameID", "provider_game_id", "gameId", "gameID", "matchId"],
                in: dictionary
            ),
            scheduledStart: scheduledStart,
            venue: stringValue(for: ["venue", "stadium", "stadiumName", "ballpark"], in: dictionary) ??
                stringValue(for: ["name"], in: nestedDictionary(for: ["venue"], in: dictionary)),
            awayTeamID: awayTeamID,
            homeTeamID: homeTeamID,
            awayScore: intValue(for: ["awayScore", "visitorScore"], in: dictionary) ??
                intValue(for: ["score", "runs"], in: awayTeam),
            homeScore: intValue(for: ["homeScore", "hostScore"], in: dictionary) ??
                intValue(for: ["score", "runs"], in: homeTeam),
            statusCode: statusCode,
            statusText: statusText,
            seasonClassification: seasonClassification,
            inningText: stringValue(for: ["inningText", "inning", "displayInning"], in: dictionary),
            bases: bases,
            balls: intValue(for: ["balls", "ballCount"], in: dictionary),
            strikes: intValue(for: ["strikes", "strikeCount"], in: dictionary),
            outs: intValue(for: ["outs", "outCount"], in: dictionary),
            highlightText: stringValue(for: ["highlightText", "highlight", "summary", "headline"], in: dictionary),
            events: parseEvents(in: dictionary),
            note: stringValue(for: ["note", "memo", "remark"], in: dictionary),
            awayStartingPitcherName: stringValue(for: ["awayStartingPitcherName", "away_starting_pitcher_name"], in: dictionary),
            homeStartingPitcherName: stringValue(for: ["homeStartingPitcherName", "home_starting_pitcher_name"], in: dictionary),
            currentPitcherName: stringValue(for: ["currentPitcherName", "current_pitcher_name", "pitcherName", "pitcher_name"], in: dictionary),
            currentBatterName: stringValue(for: ["currentBatterName", "current_batter_name", "batterName", "batter_name"], in: dictionary)
        )
    }

    // parseBases 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func parseBases(in dictionary: [String: Any]) -> KBORunnerStateDTO? {
        if let bases = nestedDictionary(for: ["bases", "baseState"], in: dictionary) {
            return KBORunnerStateDTO(
                first: boolValue(for: ["first", "onFirst"], in: bases) ?? false,
                second: boolValue(for: ["second", "onSecond"], in: bases) ?? false,
                third: boolValue(for: ["third", "onThird"], in: bases) ?? false
            )
        }

        let first = boolValue(for: ["runnerOnFirst", "onFirst"], in: dictionary)
        let second = boolValue(for: ["runnerOnSecond", "onSecond"], in: dictionary)
        let third = boolValue(for: ["runnerOnThird", "onThird"], in: dictionary)

        guard first != nil || second != nil || third != nil else { return nil }
        return KBORunnerStateDTO(first: first ?? false, second: second ?? false, third: third ?? false)
    }

    // parseEvents 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func parseEvents(in dictionary: [String: Any]) -> [KBOGameEventDTO] {
        let aliases = ["events", "timeline", "plays", "highlights"]
        for alias in aliases {
            if let array = arrayValue(for: [alias], in: dictionary) {
                let events = array.compactMap { ($0 as? [String: Any]).flatMap(parseEvent) }
                if !events.isEmpty {
                    return events
                }
            }
        }

        return []
    }

    // parseEvent 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func parseEvent(_ dictionary: [String: Any]) -> KBOGameEventDTO? {
        let headline = stringValue(for: ["headline", "title", "description", "text"], in: dictionary) ?? "상황 업데이트"
        return KBOGameEventDTO(
            id: parseUUID(stringValue(for: ["id", "eventId"], in: dictionary)) ?? UUID(),
            type: stringValue(for: ["type", "kind", "category"], in: dictionary) ?? "note",
            headline: headline,
            inningText: stringValue(for: ["inningText", "inning", "label"], in: dictionary),
            timestamp: parseDate(in: dictionary, defaultDate: .distantPast)
        )
    }

    // parseNotification 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func parseNotification(_ dictionary: [String: Any]) -> KBONotificationDTO? {
        let relatedTeamIDs = stringArrayValue(for: ["relatedTeamIDs", "teamIds", "teams"], in: dictionary)
        let rawGameID = stringValue(for: ["gameId", "matchId"], in: dictionary)
        let parsedPublicGameID = stringValue(for: ["gamePublicID", "gamePublicId", "publicGameID", "publicGameId"], in: dictionary) ??
            publicGameIDCandidate(from: rawGameID)
        let parsedProviderGameID = stringValue(for: ["gameProviderID", "gameProviderId", "providerGameID", "providerGameId"], in: dictionary) ??
            providerGameIDCandidate(from: rawGameID, publicGameID: parsedPublicGameID)
        return KBONotificationDTO(
            id: parseUUID(stringValue(for: ["id", "notificationId", "alertId"], in: dictionary)) ?? UUID(),
            type: stringValue(for: ["type", "category", "eventType"], in: dictionary) ?? "scoreChange",
            title: stringValue(for: ["title", "headline"], in: dictionary),
            body: stringValue(for: ["body", "message", "description", "text"], in: dictionary) ?? "",
            sentAt: parseDate(in: dictionary, defaultDate: .distantPast),
            isRead: boolValue(for: ["isRead", "read"], in: dictionary) ?? false,
            relatedGameID: parseUUID(stringValue(for: ["relatedGameID", "databaseGameId", "databaseGameID"], in: dictionary)),
            gamePublicID: parsedPublicGameID,
            gameProviderID: parsedProviderGameID,
            gameDatabaseID: stringValue(for: ["gameDatabaseID", "gameDatabaseId", "databaseGameID", "databaseGameId", "relatedGameID"], in: dictionary),
            gameStableIdentity: stringValue(for: ["gameStableIdentity", "stableGameIdentity"], in: dictionary),
            relatedTeamIDs: relatedTeamIDs
        )
    }

    // publicGameIDCandidate 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func publicGameIDCandidate(from value: String?) -> String? {
        guard let value, value.contains("-"), parseUUID(value) == nil else { return nil }
        return value
    }

    // providerGameIDCandidate 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func providerGameIDCandidate(from value: String?, publicGameID: String?) -> String? {
        guard publicGameID == nil,
              let value,
              parseUUID(value) == nil else { return nil }
        return value
    }

    // parseTeam 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func parseTeam(_ dictionary: [String: Any]) -> KBOTeamDTO? {
        let id = stringValue(for: ["id", "teamId", "code", "teamCode"], in: dictionary)
        guard let id else { return nil }

        let shortName = stringValue(for: ["shortName", "abbr", "abbreviation", "displayName"], in: dictionary)
        let name = stringValue(for: ["name", "fullName", "koreanName", "teamName"], in: dictionary) ??
            shortName ?? id.uppercased()

        return KBOTeamDTO(
            id: id,
            name: name,
            shortName: shortName ?? name,
            englishName: stringValue(for: ["englishName", "enName"], in: dictionary) ?? name,
            markText: stringValue(for: ["markText", "symbol", "emblemText"], in: dictionary) ?? String((shortName ?? id).prefix(3)).uppercased(),
            previousRegularSeasonRank: intValue(
                for: ["previousRegularSeasonRank", "previous_regular_season_rank"],
                in: dictionary
            )
        )
    }

    // extractTeams 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func extractTeams(from games: [KBOGameDTO], root: [String: Any]) -> [KBOTeamDTO] {
        var teams: [KBOTeamDTO] = []

        let rootArrays = [
            arrayValue(for: ["game"], in: root),
            arrayValue(for: ["games"], in: root),
            arrayValue(for: ["items"], in: root),
            nestedDictionary(for: ["schedule", "games"], in: root).flatMap { arrayValue(for: ["items", "list"], in: $0) }
        ].compactMap { $0 }

        for array in rootArrays {
            for item in array {
                guard let dictionary = item as? [String: Any] else { continue }
                for alias in ["away", "awayTeam", "visitor", "visitorTeam", "home", "homeTeam", "host", "hostTeam"] {
                    if let teamDictionary = nestedDictionary(for: [alias], in: dictionary),
                       let team = parseTeam(teamDictionary) {
                        teams.append(team)
                    }
                }

                if let awayTeam = officialTeamDTO(
                    codeOrIdentifier: stringValue(for: ["AWAY_ID", "awayId", "awayTeamCode"], in: dictionary),
                    name: stringValue(for: ["AWAY_NM", "awayName"], in: dictionary)
                ) {
                    teams.append(awayTeam)
                }

                if let homeTeam = officialTeamDTO(
                    codeOrIdentifier: stringValue(for: ["HOME_ID", "homeId", "homeTeamCode"], in: dictionary),
                    name: stringValue(for: ["HOME_NM", "homeName"], in: dictionary)
                ) {
                    teams.append(homeTeam)
                }
            }
        }

        let inferredTeams = games.flatMap { game in
            [
                KBOTeamDTO(id: game.awayTeamID, name: game.awayTeamID.uppercased(), shortName: game.awayTeamID.uppercased(), englishName: game.awayTeamID.uppercased(), markText: String(game.awayTeamID.prefix(3)).uppercased()),
                KBOTeamDTO(id: game.homeTeamID, name: game.homeTeamID.uppercased(), shortName: game.homeTeamID.uppercased(), englishName: game.homeTeamID.uppercased(), markText: String(game.homeTeamID.prefix(3)).uppercased())
            ]
        }

        return mergeTeams(teams + inferredTeams)
    }

    // normalizeOfficialGameList 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func normalizeOfficialGameList(_ root: [String: Any]) -> KBOExternalNormalizedPayload? {
        guard let rawGames = arrayValue(for: ["game"], in: root),
              rawGames.first is [String: Any] else {
            return nil
        }

        let games = rawGames.compactMap { ($0 as? [String: Any]).flatMap(parseOfficialGame) }
        guard games.isEmpty == false else { return nil }

        let teams = mergeTeams(rawGames.flatMap { item -> [KBOTeamDTO] in
            guard let dictionary = item as? [String: Any] else { return [] }
            return [
                officialTeamDTO(
                    codeOrIdentifier: stringValue(for: ["AWAY_ID"], in: dictionary),
                    name: stringValue(for: ["AWAY_NM"], in: dictionary)
                ),
                officialTeamDTO(
                    codeOrIdentifier: stringValue(for: ["HOME_ID"], in: dictionary),
                    name: stringValue(for: ["HOME_NM"], in: dictionary)
                )
            ].compactMap { $0 }
        })

        return KBOExternalNormalizedPayload(
            teams: teams,
            games: games,
            notifications: [],
            settings: nil
        )
    }

    // normalizeOfficialScheduleList 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func normalizeOfficialScheduleList(_ root: [String: Any]) -> KBOExternalNormalizedPayload? {
        guard let rawRows = arrayValue(for: ["rows"], in: root),
              rawRows.first is [String: Any] else {
            return nil
        }

        var currentDayText: String?
        var games: [KBOGameDTO] = []
        var teams: [KBOTeamDTO] = []

        for rawRow in rawRows {
            guard let row = rawRow as? [String: Any],
                  let parsedRow = parseOfficialScheduleRow(row, currentDayText: &currentDayText) else {
                continue
            }
            games.append(parsedRow.game)
            teams.append(contentsOf: parsedRow.teams)
        }

        guard games.isEmpty == false else { return nil }

        return KBOExternalNormalizedPayload(
            teams: mergeTeams(teams),
            games: games,
            notifications: [],
            settings: nil
        )
    }

    // parseOfficialGame 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func parseOfficialGame(_ dictionary: [String: Any]) -> KBOGameDTO? {
        guard value(for: ["G_ID"], in: dictionary) != nil else { return nil }
        guard let awayTeam = officialTeamDTO(
            codeOrIdentifier: stringValue(for: ["AWAY_ID"], in: dictionary),
            name: stringValue(for: ["AWAY_NM"], in: dictionary)
        ), let homeTeam = officialTeamDTO(
            codeOrIdentifier: stringValue(for: ["HOME_ID"], in: dictionary),
            name: stringValue(for: ["HOME_NM"], in: dictionary)
        ) else {
            return nil
        }

        let gameState = stringValue(for: ["GAME_STATE_SC"], in: dictionary)
        let cancelName = stringValue(for: ["CANCEL_SC_NM"], in: dictionary)
        let inningNumber = intValue(for: ["GAME_INN_NO"], in: dictionary)
        let halfText = stringValue(for: ["GAME_TB_SC_NM"], in: dictionary)

        return KBOGameDTO(
            id: GameIdentifier.uuid(from: stringValue(for: ["G_ID"], in: dictionary)) ?? UUID(),
            providerGameID: stringValue(for: ["G_ID"], in: dictionary),
            scheduledStart: parseDate(in: dictionary),
            venue: stringValue(for: ["S_NM"], in: dictionary),
            awayTeamID: awayTeam.id,
            homeTeamID: homeTeam.id,
            awayScore: intValue(for: ["T_SCORE_CN"], in: dictionary),
            homeScore: intValue(for: ["B_SCORE_CN"], in: dictionary),
            statusCode: normalizedOfficialStatusCode(gameState: gameState, cancelName: cancelName),
            statusText: normalizedOfficialStatusText(gameState: gameState, cancelName: cancelName),
            seasonClassification: stringValue(for: ["GAME_SC_NM"], in: dictionary),
            inningText: officialInningText(number: inningNumber, halfText: halfText, stateCode: gameState),
            bases: officialBases(in: dictionary),
            balls: intValue(for: ["BALL_CN"], in: dictionary),
            strikes: intValue(for: ["STRIKE_CN"], in: dictionary),
            outs: intValue(for: ["OUT_CN"], in: dictionary),
            highlightText: nil,
            events: [],
            note: nil,
            awayStartingPitcherName: stringValue(for: ["T_PIT_P_NM"], in: dictionary),
            homeStartingPitcherName: stringValue(for: ["B_PIT_P_NM"], in: dictionary)
        )
    }

    // parseOfficialScheduleRow 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func parseOfficialScheduleRow(
        _ dictionary: [String: Any],
        currentDayText: inout String?
    ) -> (game: KBOGameDTO, teams: [KBOTeamDTO])? {
        guard let cells = arrayValue(for: ["row"], in: dictionary) else { return nil }

        var startIndex = 0
        if let firstCell = cells.first as? [String: Any],
           stringValue(for: ["Class"], in: firstCell) == "day" {
            currentDayText = stringValue(for: ["Text"], in: firstCell)
            startIndex = 1
        }

        guard currentDayText != nil else { return nil }
        guard let timeCell = element(at: startIndex, in: cells) as? [String: Any],
              let playCell = element(at: startIndex + 1, in: cells) as? [String: Any],
              let relayCell = element(at: startIndex + 2, in: cells) as? [String: Any] else {
            return nil
        }

        let timeText = strippedHTML(from: stringValue(for: ["Text"], in: timeCell))
        let playHTML = stringValue(for: ["Text"], in: playCell) ?? ""
        let relayHTML = stringValue(for: ["Text"], in: relayCell)
        guard let gameLink = extractOfficialGameLink(from: relayHTML),
              let teamsAndScores = extractOfficialScheduleTeamsAndScores(from: playHTML),
              let identifiers = parseOfficialGameIdentifier(gameLink.gameID),
              let awayTeam = officialTeamDTO(codeOrIdentifier: identifiers.awayCode, name: teamsAndScores.awayName),
              let homeTeam = officialTeamDTO(codeOrIdentifier: identifiers.homeCode, name: teamsAndScores.homeName) else {
            return nil
        }

        let scheduledStart = combineDate(dateText: gameLink.gameDate, timeText: timeText) ?? .distantPast
        let venueIndex = max(cells.count - 2, 0)
        let venueText = (element(at: venueIndex, in: cells) as? [String: Any]).flatMap { strippedHTML(from: stringValue(for: ["Text"], in: $0)) }
        let isFinal = teamsAndScores.awayScore != nil && teamsAndScores.homeScore != nil

        let game = KBOGameDTO(
            id: GameIdentifier.uuid(from: gameLink.gameID) ?? UUID(),
            providerGameID: gameLink.gameID,
            scheduledStart: scheduledStart,
            venue: venueText,
            awayTeamID: awayTeam.id,
            homeTeamID: homeTeam.id,
            awayScore: teamsAndScores.awayScore,
            homeScore: teamsAndScores.homeScore,
            statusCode: isFinal ? "FINAL" : "UPCOMING",
            statusText: isFinal ? "경기 종료" : "경기 예정",
            inningText: nil,
            bases: nil,
            outs: nil,
            highlightText: nil,
            events: [],
            note: nil
        )

        return (game, [awayTeam, homeTeam])
    }

    // mergeTeams 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    nonisolated private static func mergeTeams(_ teams: [KBOTeamDTO]) -> [KBOTeamDTO] {
        var merged: [String: KBOTeamDTO] = [:]
        for team in teams {
            let existing = merged[team.id]
            merged[team.id] = chooseTeam(preferred: existing, candidate: team)
        }
        return Array(merged.values)
    }

    // chooseTeam 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func chooseTeam(preferred existing: KBOTeamDTO?, candidate: KBOTeamDTO) -> KBOTeamDTO {
        guard let existing else { return candidate }

        let existingScore = [existing.name, existing.shortName, existing.englishName]
            .filter { $0.isEmpty == false && $0 != existing.id.uppercased() }
            .count
        let candidateScore = [candidate.name, candidate.shortName, candidate.englishName]
            .filter { $0.isEmpty == false && $0 != candidate.id.uppercased() }
            .count

        return candidateScore >= existingScore ? candidate : existing
    }

    // parseDate 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func parseDate(in dictionary: [String: Any], defaultDate: Date = .distantPast) -> Date {
        if let primary = value(for: ["scheduledStart", "scheduledAt", "startAt", "startDateTime", "gameDateTime", "firstPitch"], in: dictionary),
           let date = parseDateValue(primary) {
            return date
        }

        let dateText = stringValue(for: ["gameDate", "date", "G_DT"], in: dictionary)
        let timeText = stringValue(for: ["gameTime", "time", "startTime", "G_TM"], in: dictionary)
        if let date = combineDate(dateText: dateText, timeText: timeText) {
            return date
        }

        return defaultDate
    }

    // parseDateValue 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func parseDateValue(_ value: Any) -> Date? {
        if let text = string(from: value) {
            return FlexibleDateParser.parse(text)
        }

        if let integer = int(from: value) {
            if integer > 2_000_000_000 {
                return Date(timeIntervalSince1970: TimeInterval(integer) / 1_000)
            }
            return Date(timeIntervalSince1970: TimeInterval(integer))
        }

        return nil
    }

    // combineDate 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func combineDate(dateText: String?, timeText: String?) -> Date? {
        guard let dateText else { return nil }
        let trimmedDate = dateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTime = timeText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = [trimmedDate, trimmedTime].compactMap { $0 }.joined(separator: " ")

        if let date = FlexibleDateParser.parse(combined) {
            return date
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")

        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyyMMdd HH:mm:ss", "yyyyMMdd HH:mm", "yyyy-MM-dd", "yyyyMMdd", "MM.dd HH:mm", "MM.dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: combined) {
                if format.hasPrefix("MM.") {
                    let yearFormatter = DateFormatter()
                    yearFormatter.calendar = formatter.calendar
                    yearFormatter.locale = formatter.locale
                    yearFormatter.timeZone = formatter.timeZone
                    yearFormatter.dateFormat = "yyyy"
                    let currentYear = yearFormatter.string(from: .now)
                    let normalized = "\(currentYear).\(combined)"
                    formatter.dateFormat = format == "MM.dd" ? "yyyy.MM.dd" : "yyyy.MM.dd HH:mm"
                    if let yearDate = formatter.date(from: normalized) {
                        return yearDate
                    }
                    formatter.dateFormat = format
                }
                return date
            }
        }

        return nil
    }

    // looksLikeNotification 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func looksLikeNotification(_ dictionary: [String: Any]) -> Bool {
        value(for: ["body", "message", "description"], in: dictionary) != nil
    }

    // looksLikeTeam 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func looksLikeTeam(_ dictionary: [String: Any]) -> Bool {
        value(for: ["teamId", "teamCode", "abbr", "id", "code"], in: dictionary) != nil
    }

    // nestedDictionary 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func nestedDictionary(for aliases: [String], in dictionary: [String: Any]?) -> [String: Any]? {
        guard let value = value(for: aliases, in: dictionary),
              let nested = value as? [String: Any] else {
            return nil
        }
        return nested
    }

    // arrayValue 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func arrayValue(for aliases: [String], in dictionary: [String: Any]?) -> [Any]? {
        guard let value = value(for: aliases, in: dictionary) else { return nil }
        return value as? [Any]
    }

    // dictionaryValue 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func dictionaryValue(for aliases: [String], in dictionary: [String: Any]?) -> Any? {
        value(for: aliases, in: dictionary)
    }

    // stringValue 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func stringValue(for aliases: [String], in dictionary: [String: Any]?) -> String? {
        guard let value = value(for: aliases, in: dictionary) else { return nil }
        return string(from: value)
    }

    // intValue 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func intValue(for aliases: [String], in dictionary: [String: Any]?) -> Int? {
        guard let value = value(for: aliases, in: dictionary) else { return nil }
        return int(from: value)
    }

    // boolValue 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func boolValue(for aliases: [String], in dictionary: [String: Any]?) -> Bool? {
        guard let value = value(for: aliases, in: dictionary) else { return nil }
        return bool(from: value)
    }

    // stringArrayValue 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func stringArrayValue(for aliases: [String], in dictionary: [String: Any]?) -> [String] {
        guard let value = value(for: aliases, in: dictionary) else { return [] }
        if let strings = value as? [String] {
            return strings
        }
        if let array = value as? [Any] {
            return array.compactMap(string(from:))
        }
        if let text = string(from: value) {
            return text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return []
    }

    // value 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func value(for aliases: [String], in dictionary: [String: Any]?) -> Any? {
        guard let dictionary else { return nil }
        for alias in aliases {
            if let exact = dictionary[alias] {
                return exact
            }

            if let fuzzy = dictionary.first(where: { normalizeKey($0.key) == normalizeKey(alias) })?.value {
                return fuzzy
            }
        }
        return nil
    }

    // normalizeKey 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func normalizeKey(_ key: String) -> String {
        key.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
    }

    // string 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func string(from value: Any) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    // int 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func int(from value: Any) -> Int? {
        switch value {
        case let int as Int:
            int
        case let double as Double:
            Int(double)
        case let number as NSNumber:
            number.intValue
        case let string as String:
            Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            nil
        }
    }

    // bool 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func bool(from value: Any) -> Bool? {
        switch value {
        case let bool as Bool:
            bool
        case let number as NSNumber:
            number.boolValue
        case let string as String:
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on", "y":
                true
            case "0", "false", "no", "off", "n":
                false
            default:
                nil
            }
        default:
            nil
        }
    }

    // parseUUID 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func parseUUID(_ value: String?) -> UUID? {
        guard let value else { return nil }
        return UUID(uuidString: value)
    }

    // normalizedOfficialStatusCode 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func normalizedOfficialStatusCode(gameState: String?, cancelName: String?) -> String {
        if let cancelName, cancelName.contains("취소") {
            return "CANCELLED"
        }
        if let cancelName, cancelName.contains("우천") || cancelName.contains("지연") || cancelName.contains("중단") {
            return "RAIN_DELAY"
        }

        switch gameState {
        case "3":
            return "FINAL"
        case "2":
            return "LIVE"
        default:
            return "UPCOMING"
        }
    }

    // normalizedOfficialStatusText 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func normalizedOfficialStatusText(gameState: String?, cancelName: String?) -> String {
        if let cancelName, cancelName.contains("취소") {
            return cancelName
        }
        if let cancelName, cancelName.contains("우천") || cancelName.contains("지연") || cancelName.contains("중단") {
            return cancelName
        }

        switch gameState {
        case "3":
            return "경기 종료"
        case "2":
            return "경기 중"
        default:
            return "경기 예정"
        }
    }

    // officialInningText 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func officialInningText(number: Int?, halfText: String?, stateCode: String?) -> String? {
        guard stateCode == "2", let number else { return nil }
        if let halfText, halfText.isEmpty == false {
            return "\(number)회 \(halfText)"
        }
        return "\(number)회"
    }

    // officialBases 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func officialBases(in dictionary: [String: Any]) -> KBORunnerStateDTO? {
        let first = (intValue(for: ["B1_BAT_ORDER_NO"], in: dictionary) ?? 0) > 0
        let second = (intValue(for: ["B2_BAT_ORDER_NO"], in: dictionary) ?? 0) > 0
        let third = (intValue(for: ["B3_BAT_ORDER_NO"], in: dictionary) ?? 0) > 0

        guard first || second || third else { return nil }
        return KBORunnerStateDTO(first: first, second: second, third: third)
    }

    // officialTeamDTO 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func officialTeamDTO(codeOrIdentifier: String?, name: String?) -> KBOTeamDTO? {
        guard let identifier = officialTeamIdentifier(codeOrIdentifier: codeOrIdentifier, name: name) else {
            return nil
        }

        if let canonical = officialTeamsByIdentifier[identifier] {
            return canonical
        }

        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (trimmedName?.isEmpty == false ? trimmedName : nil) ?? identifier.uppercased()
        return KBOTeamDTO(
            id: identifier,
            name: displayName,
            shortName: displayName,
            englishName: displayName,
            markText: String(displayName.prefix(3)).uppercased()
        )
    }

    // officialTeamIdentifier 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func officialTeamIdentifier(codeOrIdentifier: String?, name: String?) -> String? {
        if let codeOrIdentifier {
            let normalized = codeOrIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if let mapped = officialTeamCodeMap[normalized] {
                return mapped
            }
            if let mapped = officialTeamNameMap[normalized] {
                return mapped
            }
        }

        if let name {
            let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return officialTeamNameMap[normalized]
        }

        return nil
    }

    // extractOfficialGameLink 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func extractOfficialGameLink(from html: String?) -> (gameDate: String, gameID: String)? {
        guard let html else { return nil }
        guard let gameDate = firstMatch(in: html, pattern: "gameDate=(\\d{8})", group: 1),
              let gameID = firstMatch(in: html, pattern: "gameId=([A-Z0-9]+)", group: 1) else {
            return nil
        }
        return (gameDate, gameID)
    }

    // parseOfficialGameIdentifier 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func parseOfficialGameIdentifier(_ value: String) -> (awayCode: String, homeCode: String)? {
        guard let awayCode = firstMatch(in: value, pattern: "^\\d{8}([A-Z]{2})([A-Z]{2})\\d$", group: 1),
              let homeCode = firstMatch(in: value, pattern: "^\\d{8}([A-Z]{2})([A-Z]{2})\\d$", group: 2) else {
            return nil
        }
        return (awayCode, homeCode)
    }

    // extractOfficialScheduleTeamsAndScores 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func extractOfficialScheduleTeamsAndScores(
        from html: String
    ) -> (awayName: String, awayScore: Int?, homeName: String, homeScore: Int?)? {
        let spanMatches = matches(in: html, pattern: "<span(?: [^>]+)?>([^<]+)</span>")
            .map(\.1)
            .filter { $0.caseInsensitiveCompare("vs") != .orderedSame }
        guard let awayName = spanMatches.first, let homeName = spanMatches.last else {
            return nil
        }

        let scores = matches(in: html, pattern: "<span class=\\\"(?:win|lose)\\\">(\\d+)</span>")
            .compactMap { Int($0.1) }

        return (
            awayName,
            element(at: 0, in: scores),
            homeName,
            element(at: 1, in: scores)
        )
    }

    // strippedHTML 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func strippedHTML(from value: String?) -> String? {
        guard let value else { return nil }
        let stripped = value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // firstMatch 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func firstMatch(in text: String, pattern: String, group: Int) -> String? {
        matches(in: text, pattern: pattern, group: group).first?.1
    }

    // matches 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    nonisolated private static func matches(in text: String, pattern: String, group: Int = 1) -> [(String, String)] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { result in
            guard result.numberOfRanges > group,
                  let fullRange = Range(result.range(at: 0), in: text),
                  let captureRange = Range(result.range(at: group), in: text) else {
                return nil
            }
            return (String(text[fullRange]), String(text[captureRange]))
        }
    }

    // element 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func element<T>(at index: Int, in array: [T]) -> T? {
        guard array.indices.contains(index) else { return nil }
        return array[index]
    }

    nonisolated private static let officialTeamCodeMap: [String: String] = [
        "WO": "kiwoom",
        "LG": "lg",
        "OB": "doosan",
        "KT": "kt",
        "HT": "kia",
        "LT": "lotte",
        "NC": "nc",
        "SS": "samsung",
        "HH": "hanwha",
        "SK": "ssg",
        "SSG": "ssg",
        "KIA": "kia"
    ]

    nonisolated private static let officialTeamNameMap: [String: String] = [
        "키움": "kiwoom",
        "KIWOOM": "kiwoom",
        "LG": "lg",
        "두산": "doosan",
        "DOOSAN": "doosan",
        "KT": "kt",
        "KIA": "kia",
        "롯데": "lotte",
        "LOTTE": "lotte",
        "NC": "nc",
        "삼성": "samsung",
        "SAMSUNG": "samsung",
        "한화": "hanwha",
        "HANWHA": "hanwha",
        "SSG": "ssg"
    ]

    nonisolated private static let officialTeamsByIdentifier: [String: KBOTeamDTO] = [
        "lg": KBOTeamDTO(id: "lg", name: "LG 트윈스", shortName: "LG", englishName: "LG Twins", markText: "LG"),
        "kiwoom": KBOTeamDTO(id: "kiwoom", name: "키움 히어로즈", shortName: "키움", englishName: "Kiwoom Heroes", markText: "KIW"),
        "doosan": KBOTeamDTO(id: "doosan", name: "두산 베어스", shortName: "두산", englishName: "Doosan Bears", markText: "DOO"),
        "kt": KBOTeamDTO(id: "kt", name: "KT 위즈", shortName: "KT", englishName: "KT Wiz", markText: "KT"),
        "kia": KBOTeamDTO(id: "kia", name: "KIA 타이거즈", shortName: "KIA", englishName: "KIA Tigers", markText: "KIA"),
        "lotte": KBOTeamDTO(id: "lotte", name: "롯데 자이언츠", shortName: "롯데", englishName: "Lotte Giants", markText: "LOT"),
        "nc": KBOTeamDTO(id: "nc", name: "NC 다이노스", shortName: "NC", englishName: "NC Dinos", markText: "NC"),
        "samsung": KBOTeamDTO(id: "samsung", name: "삼성 라이온즈", shortName: "삼성", englishName: "Samsung Lions", markText: "SAM"),
        "hanwha": KBOTeamDTO(id: "hanwha", name: "한화 이글스", shortName: "한화", englishName: "Hanwha Eagles", markText: "HAN"),
        "ssg": KBOTeamDTO(id: "ssg", name: "SSG 랜더스", shortName: "SSG", englishName: "SSG Landers", markText: "SSG")
    ]
}
