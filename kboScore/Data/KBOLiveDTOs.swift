//
//  KBOLiveDTOs.swift
//  kboScore
//  기능 설명: 라이브 KBO API 응답 디코딩에 사용하는 DTO를 정의합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 3/25/26.
//

import Foundation

// KBOTeamDTO 구조체는 외부 응답과 내부 모델 변환에 사용하는 데이터 전송 값을 담습니다.
struct KBOTeamDTO: Codable, Sendable {
    let id: String
    let name: String
    let shortName: String
    let englishName: String
    let markText: String
    let previousRegularSeasonRank: Int?

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(
        id: String,
        name: String,
        shortName: String,
        englishName: String,
        markText: String,
        previousRegularSeasonRank: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.englishName = englishName
        self.markText = markText
        self.previousRegularSeasonRank = previousRegularSeasonRank
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id.uppercased()
        shortName = try container.decodeIfPresent(String.self, forKey: .shortName) ??
            container.decodeIfPresent(String.self, forKey: .short_name) ?? name
        englishName = try container.decodeIfPresent(String.self, forKey: .englishName) ??
            container.decodeIfPresent(String.self, forKey: .english_name) ?? name
        markText = try container.decodeIfPresent(String.self, forKey: .markText) ??
            container.decodeIfPresent(String.self, forKey: .mark_text) ??
            String(shortName.prefix(3)).uppercased()
        previousRegularSeasonRank = try container.decodeIfPresent(Int.self, forKey: .previousRegularSeasonRank) ??
            container.decodeIfPresent(Int.self, forKey: .previous_regular_season_rank)
    }

    // encode 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(shortName, forKey: .shortName)
        try container.encode(englishName, forKey: .englishName)
        try container.encode(markText, forKey: .markText)
        try container.encodeIfPresent(previousRegularSeasonRank, forKey: .previousRegularSeasonRank)
    }

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case shortName
        case short_name
        case englishName
        case english_name
        case markText
        case mark_text
        case previousRegularSeasonRank
        case previous_regular_season_rank
    }
}

// KBORunnerStateDTO 구조체는 외부 응답과 내부 모델 변환에 사용하는 데이터 전송 값을 담습니다.
struct KBORunnerStateDTO: Codable, Sendable {
    let first: Bool
    let second: Bool
    let third: Bool

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(first: Bool, second: Bool, third: Bool) {
        self.first = first
        self.second = second
        self.third = third
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        first = try container.decodeIfPresent(Bool.self, forKey: .first) ?? false
        second = try container.decodeIfPresent(Bool.self, forKey: .second) ?? false
        third = try container.decodeIfPresent(Bool.self, forKey: .third) ?? false
    }
}

// KBOBaseRunnersDTO 구조체는 외부 응답과 내부 모델 변환에 사용하는 데이터 전송 값을 담습니다.
struct KBOBaseRunnersDTO: Codable, Sendable {
    let first: String?
    let second: String?
    let third: String?

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(first: String?, second: String?, third: String?) {
        self.first = first
        self.second = second
        self.third = third
    }
}

// KBOGameEventDTO 구조체는 외부 응답과 내부 모델 변환에 사용하는 데이터 전송 값을 담습니다.
struct KBOGameEventDTO: Codable, Sendable {
    let id: UUID
    let type: String
    let headline: String
    let inningText: String?
    let timestamp: Date

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(
        id: UUID,
        type: String,
        headline: String,
        inningText: String?,
        timestamp: Date
    ) {
        self.id = id
        self.type = type
        self.headline = headline
        self.inningText = inningText
        self.timestamp = timestamp
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "note"
        headline = try container.decodeIfPresent(String.self, forKey: .headline) ?? "상황 업데이트"
        inningText = try container.decodeIfPresent(String.self, forKey: .inningText)
        timestamp = try container.decodeFlexibleDate(forKey: .timestamp) ?? .distantPast
    }
}

// KBOGameDTO 구조체는 외부 응답과 내부 모델 변환에 사용하는 데이터 전송 값을 담습니다.
struct KBOGameDTO: Codable, Sendable {
    let id: UUID
    let providerGameID: String?
    let scheduledStart: Date
    let venue: String?
    let awayTeamID: String
    let homeTeamID: String
    let awayScore: Int?
    let homeScore: Int?
    let statusCode: String?
    let statusText: String?
    let seasonClassification: String?
    let inningText: String?
    let bases: KBORunnerStateDTO?
    let baseRunners: KBOBaseRunnersDTO?
    let balls: Int?
    let strikes: Int?
    let outs: Int?
    let highlightText: String?
    let events: [KBOGameEventDTO]
    let note: String?
    let awayStartingPitcherName: String?
    let homeStartingPitcherName: String?
    let currentPitcherName: String?
    let currentBatterName: String?

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case id
        case providerGameID
        case provider_game_id
        case officialProviderGameID
        case official_provider_game_id
        case scheduledStart
        case venue
        case awayTeamID
        case homeTeamID
        case awayTeamId
        case homeTeamId
        case awayScore
        case homeScore
        case statusCode
        case statusText
        case seasonClassification
        case seasonType
        case inningText
        case bases
        case baseRunners
        case base_runners
        case balls
        case ballCount
        case strikes
        case strikeCount
        case outs
        case outCount
        case highlightText
        case events
        case note
        case awayStartingPitcherName
        case away_starting_pitcher_name
        case homeStartingPitcherName
        case home_starting_pitcher_name
        case currentPitcherName
        case current_pitcher_name
        case currentBatterName
        case current_batter_name
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(
        id: UUID,
        providerGameID: String? = nil,
        scheduledStart: Date,
        venue: String?,
        awayTeamID: String,
        homeTeamID: String,
        awayScore: Int?,
        homeScore: Int?,
        statusCode: String?,
        statusText: String?,
        seasonClassification: String? = nil,
        inningText: String?,
        bases: KBORunnerStateDTO?,
        baseRunners: KBOBaseRunnersDTO? = nil,
        balls: Int? = nil,
        strikes: Int? = nil,
        outs: Int?,
        highlightText: String?,
        events: [KBOGameEventDTO],
        note: String?,
        awayStartingPitcherName: String? = nil,
        homeStartingPitcherName: String? = nil,
        currentPitcherName: String? = nil,
        currentBatterName: String? = nil
    ) {
        let resolvedProviderGameID = providerGameID ?? Self.providerGameID(from: note)
        self.id = GameIdentifier.canonicalUUID(id: id, providerGameID: resolvedProviderGameID)
        self.providerGameID = resolvedProviderGameID
        self.scheduledStart = scheduledStart
        self.venue = venue
        self.awayTeamID = awayTeamID
        self.homeTeamID = homeTeamID
        self.awayScore = awayScore
        self.homeScore = homeScore
        self.statusCode = statusCode
        self.statusText = statusText
        self.seasonClassification = seasonClassification
        self.inningText = inningText
        self.bases = bases
        self.baseRunners = baseRunners
        self.balls = balls
        self.strikes = strikes
        self.outs = outs
        self.highlightText = highlightText
        self.events = events
        self.note = note
        self.awayStartingPitcherName = awayStartingPitcherName
        self.homeStartingPitcherName = homeStartingPitcherName
        self.currentPitcherName = currentPitcherName
        self.currentBatterName = currentBatterName
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedOfficialProviderGameID = try container.decodeIfPresent(String.self, forKey: .officialProviderGameID)
        let decodedOfficialProviderGameIDSnake = try container.decodeIfPresent(String.self, forKey: .official_provider_game_id)
        let decodedProviderGameID = try container.decodeIfPresent(String.self, forKey: .providerGameID)
        let decodedProviderGameIDSnake = try container.decodeIfPresent(String.self, forKey: .provider_game_id)
        let decodedNote = try container.decodeIfPresent(String.self, forKey: .note)
        providerGameID = decodedOfficialProviderGameID?.nilIfBlank ??
            decodedOfficialProviderGameIDSnake?.nilIfBlank ??
            decodedProviderGameID?.nilIfBlank ??
            decodedProviderGameIDSnake?.nilIfBlank ??
            Self.providerGameID(from: decodedNote)
        let decodedRawID = try? container.decodeIfPresent(String.self, forKey: .id)
        let decodedUUID = try? container.decodeIfPresent(UUID.self, forKey: .id)
        id = GameIdentifier.canonicalUUID(id: decodedRawID ?? decodedUUID?.uuidString, providerGameID: providerGameID) ?? UUID()
        scheduledStart = try container.decodeFlexibleDate(forKey: .scheduledStart) ?? .distantPast
        venue = try container.decodeIfPresent(String.self, forKey: .venue)
        note = decodedNote
        let providerTeamIDs = Self.providerTeamIDs(from: note)
        let decodedAwayTeamID = (try container.decodeIfPresent(String.self, forKey: .awayTeamID))?.nilIfBlank
        let decodedAwayTeamId = (try container.decodeIfPresent(String.self, forKey: .awayTeamId))?.nilIfBlank
        let nestedAwayTeamID = Self.nestedTeamIdentifier(from: decoder, keyCandidates: ["awayTeam", "away"])
        awayTeamID = decodedAwayTeamID ?? decodedAwayTeamId ?? nestedAwayTeamID ?? providerTeamIDs?.away ?? ""
        let decodedHomeTeamID = (try container.decodeIfPresent(String.self, forKey: .homeTeamID))?.nilIfBlank
        let decodedHomeTeamId = (try container.decodeIfPresent(String.self, forKey: .homeTeamId))?.nilIfBlank
        let nestedHomeTeamID = Self.nestedTeamIdentifier(from: decoder, keyCandidates: ["homeTeam", "home"])
        homeTeamID = decodedHomeTeamID ?? decodedHomeTeamId ?? nestedHomeTeamID ?? providerTeamIDs?.home ?? ""
        awayScore = try container.decodeIfPresent(Int.self, forKey: .awayScore)
        homeScore = try container.decodeIfPresent(Int.self, forKey: .homeScore)
        statusCode = try container.decodeIfPresent(String.self, forKey: .statusCode)
        statusText = try container.decodeIfPresent(String.self, forKey: .statusText)
        seasonClassification = try container.decodeIfPresent(String.self, forKey: .seasonClassification) ??
            (try container.decodeIfPresent(String.self, forKey: .seasonType))
        inningText = try container.decodeIfPresent(String.self, forKey: .inningText)
        bases = try container.decodeIfPresent(KBORunnerStateDTO.self, forKey: .bases)
        baseRunners = try container.decodeIfPresent(KBOBaseRunnersDTO.self, forKey: .baseRunners) ??
            container.decodeIfPresent(KBOBaseRunnersDTO.self, forKey: .base_runners)
        balls = try container.decodeIfPresent(Int.self, forKey: .balls) ??
            (try container.decodeIfPresent(Int.self, forKey: .ballCount))
        strikes = try container.decodeIfPresent(Int.self, forKey: .strikes) ??
            (try container.decodeIfPresent(Int.self, forKey: .strikeCount))
        outs = try container.decodeIfPresent(Int.self, forKey: .outs) ??
            (try container.decodeIfPresent(Int.self, forKey: .outCount))
        highlightText = try container.decodeIfPresent(String.self, forKey: .highlightText)
        events = try container.decodeIfPresent([KBOGameEventDTO].self, forKey: .events) ?? []
        awayStartingPitcherName = try container.decodeIfPresent(String.self, forKey: .awayStartingPitcherName) ??
            container.decodeIfPresent(String.self, forKey: .away_starting_pitcher_name)
        homeStartingPitcherName = try container.decodeIfPresent(String.self, forKey: .homeStartingPitcherName) ??
            container.decodeIfPresent(String.self, forKey: .home_starting_pitcher_name)
        currentPitcherName = try container.decodeIfPresent(String.self, forKey: .currentPitcherName) ??
            container.decodeIfPresent(String.self, forKey: .current_pitcher_name)
        currentBatterName = try container.decodeIfPresent(String.self, forKey: .currentBatterName) ??
            container.decodeIfPresent(String.self, forKey: .current_batter_name)
    }

    // providerTeamIDs 메서드는 이 타입의 주요 동작을 수행합니다.
    private nonisolated static func providerTeamIDs(from note: String?) -> (away: String, home: String)? {
        guard let note else { return nil }
        guard let range = note.range(of: "provider_game_id=") else { return nil }
        let suffix = note[range.upperBound...]
        let token = suffix.split(whereSeparator: { $0 == " " || $0 == "\n" }).first ?? ""
        let parts = token.split(separator: "_")
        guard parts.count >= 2 else { return nil }
        return (String(parts[parts.count - 2]), String(parts[parts.count - 1]))
    }

    // nestedTeamIdentifier 메서드는 이 타입의 주요 동작을 수행합니다.
    private nonisolated static func nestedTeamIdentifier(
        from decoder: any Decoder,
        keyCandidates: [String]
    ) -> String? {
        guard let container = try? decoder.container(keyedBy: AnyCodingKey.self) else { return nil }
        for keyName in keyCandidates {
            guard let key = AnyCodingKey(stringValue: keyName),
                  let nested = try? container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: key) else {
                continue
            }

            let idKeys = ["id", "teamID", "teamId", "code"]
            for idKeyName in idKeys {
                guard let idKey = AnyCodingKey(stringValue: idKeyName),
                      let value = try? nested.decodeIfPresent(String.self, forKey: idKey),
                      let resolved = value.nilIfBlank else {
                    continue
                }
                return resolved
            }
        }
        return nil
    }

    // encode 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(providerGameID, forKey: .providerGameID)
        try container.encode(scheduledStart, forKey: .scheduledStart)
        try container.encodeIfPresent(venue, forKey: .venue)
        try container.encode(awayTeamID, forKey: .awayTeamID)
        try container.encode(homeTeamID, forKey: .homeTeamID)
        try container.encodeIfPresent(awayScore, forKey: .awayScore)
        try container.encodeIfPresent(homeScore, forKey: .homeScore)
        try container.encodeIfPresent(statusCode, forKey: .statusCode)
        try container.encodeIfPresent(statusText, forKey: .statusText)
        try container.encodeIfPresent(seasonClassification, forKey: .seasonClassification)
        try container.encodeIfPresent(inningText, forKey: .inningText)
        try container.encodeIfPresent(bases, forKey: .bases)
        try container.encodeIfPresent(balls, forKey: .balls)
        try container.encodeIfPresent(strikes, forKey: .strikes)
        try container.encodeIfPresent(outs, forKey: .outs)
        try container.encodeIfPresent(highlightText, forKey: .highlightText)
        try container.encode(events, forKey: .events)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(awayStartingPitcherName, forKey: .awayStartingPitcherName)
        try container.encodeIfPresent(homeStartingPitcherName, forKey: .homeStartingPitcherName)
        try container.encodeIfPresent(currentPitcherName, forKey: .currentPitcherName)
        try container.encodeIfPresent(currentBatterName, forKey: .currentBatterName)
    }

    // providerGameID 메서드는 이 타입의 주요 동작을 수행합니다.
    private nonisolated static func providerGameID(from note: String?) -> String? {
        guard let note,
              let range = note.range(of: "provider_game_id=") else {
            return nil
        }

        let suffix = note[range.upperBound...]
        let token = suffix.split(whereSeparator: { $0 == " " || $0 == "\n" }).first
        guard let token, token.isEmpty == false else {
            return nil
        }
        return String(token)
    }
}

// KBOStandingsTeamDTO 구조체는 외부 응답과 내부 모델 변환에 사용하는 데이터 전송 값을 담습니다.
struct KBOStandingsTeamDTO: Decodable, Sendable {
    let teamID: String
    let nameKo: String

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case teamID
        case teamId
        case nameKo
        case name_ko
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(teamID: String, nameKo: String) {
        self.teamID = teamID
        self.nameKo = nameKo
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teamID = try container.decodeIfPresent(String.self, forKey: .teamID) ??
            container.decode(String.self, forKey: .teamId)
        nameKo = try container.decodeIfPresent(String.self, forKey: .nameKo) ??
            container.decode(String.self, forKey: .name_ko)
    }
}

// KBOStandingsItemDTO 구조체는 외부 응답과 내부 모델 변환에 사용하는 데이터 전송 값을 담습니다.
struct KBOStandingsItemDTO: Decodable, Sendable {
    let team: KBOStandingsTeamDTO
    let rank: Int
    let wins: Int
    let losses: Int
    let ties: Int
    let runsScored: Int?
    let runsAllowed: Int?
    let remainingRegularSeasonGames: Int
    let recentResults: [String]
    let unknownClassificationGames: Int
    let rankingResolution: String
    let rankingResolutionPosition: Int?
    let postseasonQualificationProbability: Double?
    let postseasonProbabilityUnavailableReason: String?

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case team
        case rank
        case wins
        case losses
        case ties
        case runsScored
        case runsAllowed
        case remainingRegularSeasonGames
        case recentResults
        case unknownClassificationGames
        case rankingResolution
        case rankingResolutionPosition
        case postseasonQualificationProbability
        case postseasonProbabilityUnavailableReason
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        team = try container.decode(KBOStandingsTeamDTO.self, forKey: .team)
        rank = try container.decode(Int.self, forKey: .rank)
        wins = try container.decode(Int.self, forKey: .wins)
        losses = try container.decode(Int.self, forKey: .losses)
        ties = try container.decodeIfPresent(Int.self, forKey: .ties) ?? 0
        runsScored = try container.decodeIfPresent(Int.self, forKey: .runsScored)
        runsAllowed = try container.decodeIfPresent(Int.self, forKey: .runsAllowed)
        remainingRegularSeasonGames = try container.decodeIfPresent(Int.self, forKey: .remainingRegularSeasonGames) ?? 0
        recentResults = try container.decodeIfPresent([String].self, forKey: .recentResults) ?? []
        unknownClassificationGames = try container.decodeIfPresent(Int.self, forKey: .unknownClassificationGames) ?? 0
        rankingResolution = try container.decodeIfPresent(String.self, forKey: .rankingResolution) ?? "resolved"
        rankingResolutionPosition = try container.decodeIfPresent(Int.self, forKey: .rankingResolutionPosition)
        postseasonQualificationProbability = try container.decodeIfPresent(Double.self, forKey: .postseasonQualificationProbability)
        postseasonProbabilityUnavailableReason = try container.decodeIfPresent(String.self, forKey: .postseasonProbabilityUnavailableReason)
    }
}

// KBOStandingsResponseDTO 구조체는 외부 응답과 내부 모델 변환에 사용하는 데이터 전송 값을 담습니다.
struct KBOStandingsResponseDTO: Decodable, Sendable {
    let standings: [KBOStandingsItemDTO]

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case standings
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        standings = try container.decodeIfPresent([KBOStandingsItemDTO].self, forKey: .standings) ?? []
    }
}

// KBONotificationDTO 구조체는 외부 응답과 내부 모델 변환에 사용하는 데이터 전송 값을 담습니다.
struct KBONotificationDTO: Codable, Sendable {
    let id: UUID
    let type: String
    let title: String?
    let body: String
    let sentAt: Date
    let isRead: Bool
    let relatedGameID: UUID?
    let gamePublicID: String?
    let gameProviderID: String?
    let gameDatabaseID: String?
    let gameStableIdentity: String?
    let relatedTeamIDs: [String]

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(
        id: UUID,
        type: String,
        title: String?,
        body: String,
        sentAt: Date,
        isRead: Bool,
        relatedGameID: UUID?,
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
        self.isRead = isRead
        self.relatedGameID = relatedGameID
        self.gamePublicID = gamePublicID?.nilIfBlank
        self.gameProviderID = gameProviderID?.nilIfBlank
        self.gameDatabaseID = gameDatabaseID?.nilIfBlank
        self.gameStableIdentity = gameStableIdentity?.nilIfBlank
        self.relatedTeamIDs = relatedTeamIDs
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "scoreChange"
        title = try container.decodeIfPresent(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        sentAt = try container.decodeFlexibleDate(forKey: .sentAt) ?? .distantPast
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        relatedGameID = try container.decodeIfPresent(UUID.self, forKey: .relatedGameID)
        gamePublicID = try container.decodeIfPresent(String.self, forKey: .gamePublicID)?.nilIfBlank
        gameProviderID = try container.decodeIfPresent(String.self, forKey: .gameProviderID)?.nilIfBlank
        gameDatabaseID = try container.decodeIfPresent(String.self, forKey: .gameDatabaseID)?.nilIfBlank
        gameStableIdentity = try container.decodeIfPresent(String.self, forKey: .gameStableIdentity)?.nilIfBlank
        relatedTeamIDs = try container.decodeIfPresent([String].self, forKey: .relatedTeamIDs) ?? []
    }
}

// KBOBootstrapDTO 구조체는 외부 응답과 내부 모델 변환에 사용하는 데이터 전송 값을 담습니다.
struct KBOBootstrapDTO: Codable, Sendable {
    let teams: [KBOTeamDTO]
    let games: [KBOGameDTO]
    let notifications: [KBONotificationDTO]
    let settings: AppSettings?

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(
        teams: [KBOTeamDTO],
        games: [KBOGameDTO],
        notifications: [KBONotificationDTO],
        settings: AppSettings?
    ) {
        self.teams = teams
        self.games = games
        self.notifications = notifications
        self.settings = settings
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teams = try container.decodeIfPresent([KBOTeamDTO].self, forKey: .teams) ?? []
        games = try container.decodeIfPresent([KBOGameDTO].self, forKey: .games) ?? []
        notifications = try container.decodeIfPresent([KBONotificationDTO].self, forKey: .notifications) ?? []
        settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings)
    }
}

// KBODataMapper 열거형는 외부 데이터와 도메인 모델 사이의 변환을 담당합니다.
enum KBODataMapper {
    // mapBootstrap 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated static func mapBootstrap(_ payload: KBOBootstrapDTO) -> KBOBootstrapData {
        let teams = payload.teams.map(mapTeam)
        let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { (normalizedTeamID($0.id), $0) })

        return KBOBootstrapData(
            teams: teams,
            games: payload.games.compactMap { mapGame($0, teamsByID: teamsByID) }
                .sorted { $0.scheduledStart > $1.scheduledStart },
            notifications: payload.notifications.map(mapNotification)
                .sorted { $0.sentAt > $1.sentAt },
            settings: payload.settings ?? .default
        )
    }

    // mapGames 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated static func mapGames(_ payload: [KBOGameDTO], teams: [Team]) -> [GameDetail] {
        let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { (normalizedTeamID($0.id), $0) })
        return payload.compactMap { mapGame($0, teamsByID: teamsByID) }
            .sorted { $0.scheduledStart > $1.scheduledStart }
    }

    // mapNotifications 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated static func mapNotifications(_ payload: [KBONotificationDTO]) -> [NotificationItem] {
        payload.map(mapNotification)
            .sorted { $0.sentAt > $1.sentAt }
    }

    // mapStandings 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated static func mapStandings(_ payload: KBOStandingsResponseDTO, teams: [Team]) -> [TeamStandingsSnapshot] {
        let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { (normalizedTeamID($0.id), $0) })
        return payload.standings.compactMap { item in
            guard let team = resolvedTeam(id: item.team.teamID, teamsByID: teamsByID) else {
                return nil
            }
            return TeamStandingsSnapshot(
                team: team,
                rank: item.rank,
                wins: item.wins,
                losses: item.losses,
                ties: item.ties,
                runsScored: item.runsScored,
                runsAllowed: item.runsAllowed,
                remainingRegularSeasonGames: item.remainingRegularSeasonGames,
                recentResults: item.recentResults.compactMap(mapRecentResult),
                unknownClassificationGames: item.unknownClassificationGames,
                rankingResolution: StandingsRankingResolution(rawValue: item.rankingResolution) ?? .resolved,
                rankingResolutionPosition: item.rankingResolutionPosition,
                postseasonQualificationProbability: item.postseasonQualificationProbability,
                postseasonProbabilityUnavailableReason: item.postseasonProbabilityUnavailableReason.flatMap(PostseasonProbabilityUnavailableReason.init(rawValue:))
            )
        }
    }

    // mapGameStatus 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated static func mapGameStatus(code: String?, text: String?, inningText: String? = nil) -> GameStatus {
        let normalized = [code, text, inningText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " ")

        if normalized.contains("cancel") ||
            normalized.contains("postpon") ||
            normalized.contains("취소") ||
            normalized.contains("연기") {
            return .cancelled
        }

        if normalized.contains("rain") ||
            normalized.contains("우천") ||
            normalized.contains("delay") ||
            normalized.contains("중단") ||
            normalized.contains("suspend") ||
            normalized.contains("interrupted") {
            return .rainDelay
        }

        if normalized.contains("final") || normalized.contains("finished") || normalized.contains("ended") || normalized.contains("completed") || normalized.contains("종료") || normalized.contains("경기종료") {
            return .final
        }

        if normalized.contains("scheduled") ||
            normalized.contains("upcoming") ||
            normalized.contains("예정") ||
            normalized.contains("pre_game") ||
            normalized.contains("pregame") {
            return .upcoming
        }

        if normalized.contains("live") ||
            normalized.contains("inprogress") ||
            normalized.contains("in_progress") ||
            normalized.contains("progress") ||
            normalized.contains("running") ||
            normalized.contains("playing") ||
            normalized.contains("started") ||
            normalized.contains("game_on") ||
            normalized.contains("경기중") ||
            normalized.contains("진행") ||
            normalized.contains("초") ||
            normalized.contains("말") ||
            normalized.contains("회") {
            return .live
        }

        return .upcoming
    }

    // mapTeam 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated static func mapTeam(_ dto: KBOTeamDTO) -> Team {
        let normalizedID = normalizedTeamID(dto.id)
        return Team(
            id: normalizedID,
            name: dto.name,
            shortName: dto.shortName,
            englishName: dto.englishName,
            markText: dto.markText,
            previousRegularSeasonRank: dto.previousRegularSeasonRank
        )
    }

    // mapGame 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func mapGame(_ dto: KBOGameDTO, teamsByID: [String: Team]) -> GameDetail? {
        guard let awayTeam = resolvedTeam(id: dto.awayTeamID, teamsByID: teamsByID),
              let homeTeam = resolvedTeam(id: dto.homeTeamID, teamsByID: teamsByID) else {
            return nil
        }

        let status = mapGameStatus(code: dto.statusCode, text: dto.statusText, inningText: dto.inningText)
        let inningText = dto.inningText?.nilIfBlank
        let note = sanitizedNote(dto.note)
        let highlight = dto.highlightText?.nilIfBlank
        let seasonClassification = mapSeasonClassification(dto.seasonClassification, note: note)

        return GameDetail(
            id: dto.id,
            scheduledStart: dto.scheduledStart,
            venue: dto.venue?.nilIfBlank ?? "장소 미정",
            awayTeam: awayTeam,
            homeTeam: homeTeam,
            awayScore: status == .upcoming ? nil : dto.awayScore,
            homeScore: status == .upcoming ? nil : dto.homeScore,
            status: status,
            seasonClassification: seasonClassification,
            inningText: inningText,
            bases: dto.bases.map { RunnerState(first: $0.first, second: $0.second, third: $0.third) },
            baseRunners: dto.baseRunners.map {
                GameBaseRunners(
                    first: $0.first?.nilIfBlank,
                    second: $0.second?.nilIfBlank,
                    third: $0.third?.nilIfBlank
                )
            },
            balls: dto.balls,
            strikes: dto.strikes,
            outs: dto.outs,
            highlightText: highlight,
            events: dto.events.map(mapEvent).sorted { $0.timestamp > $1.timestamp },
            note: note,
            providerGameID: dto.providerGameID,
            awayStartingPitcherName: dto.awayStartingPitcherName?.nilIfBlank,
            homeStartingPitcherName: dto.homeStartingPitcherName?.nilIfBlank,
            currentPitcherName: dto.currentPitcherName?.nilIfBlank,
            currentBatterName: dto.currentBatterName?.nilIfBlank
        )
    }

    // mapRecentResult 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func mapRecentResult(_ rawValue: String) -> TeamGameResult? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "win":
            .win
        case "loss":
            .loss
        case "tie":
            .tie
        default:
            nil
        }
    }

    // mapEvent 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func mapEvent(_ dto: KBOGameEventDTO) -> GameEvent {
        GameEvent(
            id: dto.id,
            type: mapEventType(dto.type),
            headline: dto.headline,
            inningText: dto.inningText?.nilIfBlank ?? "상황 업데이트",
            timestamp: dto.timestamp
        )
    }

    // mapNotification 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func mapNotification(_ dto: KBONotificationDTO) -> NotificationItem {
        let type = mapNotificationType(dto.type)
        return NotificationItem(
            id: dto.id,
            type: type,
            title: dto.title?.nilIfBlank ?? type.title,
            body: dto.body,
            sentAt: dto.sentAt,
            isRead: dto.isRead,
            relatedGameID: dto.relatedGameID,
            gamePublicID: dto.gamePublicID,
            gameProviderID: dto.gameProviderID,
            gameDatabaseID: dto.gameDatabaseID,
            gameStableIdentity: dto.gameStableIdentity,
            relatedTeamIDs: dto.relatedTeamIDs.map(normalizedTeamID)
        )
    }

    // resolvedTeam 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    nonisolated private static func resolvedTeam(id: String, teamsByID: [String: Team]) -> Team? {
        let normalizedID = normalizedTeamID(id)
        return teamsByID[normalizedID] ?? Team(
            id: normalizedID,
            name: "알 수 없는 팀",
            shortName: normalizedID.uppercased(),
            englishName: normalizedID.uppercased(),
            markText: String(normalizedID.prefix(3)).uppercased()
        )
    }

    // normalizedTeamID 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func normalizedTeamID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // mapSeasonClassification 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func mapSeasonClassification(
        _ rawValue: String?,
        note: String?
    ) -> GameSeasonClassification {
        guard let normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let classification = GameSeasonClassification(rawValue: normalized) else {
            return GameSeasonClassification.inferred(from: note)
        }
        return classification
    }

    // sanitizedNote 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated private static func sanitizedNote(
        _ raw: String?
    ) -> String? {
        guard let raw, let note = raw.nilIfBlank else { return nil }
        // Keep provider identifiers intact so higher layers can recover team IDs when needed.
        return note
    }

    // mapEventType 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func mapEventType(_ rawValue: String) -> GameEventType {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "score", "scorechange", "득점":
            .score
        case "pitching", "strikeout", "투구":
            .pitching
        case "weather", "rain", "우천":
            .weather
        case "keyplay", "play", "주요장면":
            .keyPlay
        default:
            .note
        }
    }

    // mapNotificationType 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated private static func mapNotificationType(_ rawValue: String) -> NotificationType {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "scorechange", "score", "득점":
            .scoreChange
        case "onbase", "on_base", "reachedbase", "reached_base", "출루":
            .onBase
        case "gamestart", "game_start", "start", "시작":
            .gameStart
        case "leadchange", "lead", "역전":
            .leadChange
        case "gameend", "game_end", "final", "종료":
            .gameEnd
        case "inningchange", "inning_changed", "inning", "이닝":
            .inningChange
        case "raindelay", "rain_delay", "game_interrupted", "game_resumed", "game_resume_scheduled", "game_cancelled", "cancelled", "rain", "우천", "취소", "지연", "재개":
            .rainDelay
        default:
            .scoreChange
        }
    }
}

private extension String {
    nonisolated var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension KeyedDecodingContainer {
    // decodeFlexibleDate 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated func decodeFlexibleDate(forKey key: Key) throws -> Date? {
        if let timestamp = try? decodeIfPresent(Date.self, forKey: key) {
            return timestamp
        }

        if let seconds = try? decodeIfPresent(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: seconds)
        }

        if let milliseconds = try? decodeIfPresent(Int64.self, forKey: key) {
            if milliseconds > 2_000_000_000 {
                return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
            }
            return Date(timeIntervalSince1970: TimeInterval(milliseconds))
        }

        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return FlexibleDateParser.parse(text)
        }

        return nil
    }
}

// AnyCodingKey 구조체는 AnyCodingKey 타입의 역할과 값을 정의합니다.
private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// FlexibleDateParser 열거형는 원천 데이터를 앱에서 사용할 수 있는 값으로 해석합니다.
enum FlexibleDateParser {
    // makeFormatter 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    nonisolated private static func makeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }

    // parse 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    nonisolated static func parse(_ value: String) -> Date? {
        let iso8601WithFractional = ISO8601DateFormatter()
        iso8601WithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601WithFractional.date(from: value) {
            return date
        }

        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime]
        if let date = iso8601.date(from: value) {
            return date
        }

        return makeFormatter().date(from: value)
    }
}
