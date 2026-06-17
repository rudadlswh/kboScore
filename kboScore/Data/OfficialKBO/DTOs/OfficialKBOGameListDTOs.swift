//
//  OfficialKBOGameListDTOs.swift
//  kboScore
//  기능 설명: KBO 공식 API 응답을 디코딩하기 위한 DTO를 정의합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 5/13/26.
//

import Foundation

// OfficialGameListResponse 구조체는 OfficialGameListResponse 타입의 역할과 값을 정의합니다.
struct OfficialGameListResponse: Decodable {
    let game: [OfficialGameEntry]
}

// OfficialGameEntry 구조체는 OfficialGameEntry 타입의 역할과 값을 정의합니다.
struct OfficialGameEntry: Decodable, Sendable {
    let leagueID: Int
    let seriesID: Int
    let seasonID: Int
    let gameDate: String
    let displayDateText: String
    let gameID: String
    let startTime: String
    let stadiumName: String?
    let awayTeamCode: String
    let homeTeamCode: String
    let awayTeamName: String
    let homeTeamName: String
    let awayProbablePitcherName: String?
    let homeProbablePitcherName: String?
    let winningPitcherName: String?
    let losingPitcherName: String?
    let savePitcherName: String?
    let gameStateCode: String
    let cancelName: String?
    let inningNumber: Int?
    let inningHalfText: String?
    let awayScoreText: String?
    let homeScoreText: String?
    let strikeCount: Int?
    let ballCount: Int?
    let outCount: Int?
    let firstBaseOccupancy: Int?
    let secondBaseOccupancy: Int?
    let thirdBaseOccupancy: Int?
    private let decodedBaseOrderSourceKeys: [String]

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case leagueID = "LE_ID"
        case seriesID = "SR_ID"
        case seasonID = "SEASON_ID"
        case gameDate = "G_DT"
        case displayDateText = "G_DT_TXT"
        case gameID = "G_ID"
        case startTime = "G_TM"
        case stadiumName = "S_NM"
        case awayTeamCode = "AWAY_ID"
        case homeTeamCode = "HOME_ID"
        case awayTeamName = "AWAY_NM"
        case homeTeamName = "HOME_NM"
        case awayProbablePitcherName = "T_PIT_P_NM"
        case homeProbablePitcherName = "B_PIT_P_NM"
        case winningPitcherName = "W_PIT_P_NM"
        case losingPitcherName = "L_PIT_P_NM"
        case savePitcherName = "SV_PIT_P_NM"
        case gameStateCode = "GAME_STATE_SC"
        case cancelName = "CANCEL_SC_NM"
        case inningNumber = "GAME_INN_NO"
        case inningHalfText = "GAME_TB_SC_NM"
        case awayScoreText = "T_SCORE_CN"
        case homeScoreText = "B_SCORE_CN"
        case strikeCount = "STRIKE_CN"
        case ballCount = "BALL_CN"
        case outCount = "OUT_CN"
        case firstBaseOccupancy = "B1_BAT_ORDER_NO"
        case secondBaseOccupancy = "B2_BAT_ORDER_NO"
        case thirdBaseOccupancy = "B3_BAT_ORDER_NO"
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        leagueID = try container.decode(Int.self, forKey: .leagueID)
        seriesID = try container.decode(Int.self, forKey: .seriesID)
        seasonID = try container.decode(Int.self, forKey: .seasonID)
        gameDate = try container.decode(String.self, forKey: .gameDate)
        displayDateText = try container.decode(String.self, forKey: .displayDateText)
        gameID = try container.decode(String.self, forKey: .gameID)
        startTime = try container.decode(String.self, forKey: .startTime)
        stadiumName = try container.decodeIfPresent(String.self, forKey: .stadiumName)
        awayTeamCode = try container.decode(String.self, forKey: .awayTeamCode)
        homeTeamCode = try container.decode(String.self, forKey: .homeTeamCode)
        awayTeamName = try container.decode(String.self, forKey: .awayTeamName)
        homeTeamName = try container.decode(String.self, forKey: .homeTeamName)
        awayProbablePitcherName = try container.decodeIfPresent(String.self, forKey: .awayProbablePitcherName)
        homeProbablePitcherName = try container.decodeIfPresent(String.self, forKey: .homeProbablePitcherName)
        winningPitcherName = try container.decodeIfPresent(String.self, forKey: .winningPitcherName)
        losingPitcherName = try container.decodeIfPresent(String.self, forKey: .losingPitcherName)
        savePitcherName = try container.decodeIfPresent(String.self, forKey: .savePitcherName)
        gameStateCode = try container.decode(String.self, forKey: .gameStateCode)
        cancelName = try container.decodeIfPresent(String.self, forKey: .cancelName)
        inningNumber = try container.decodeIfPresent(Int.self, forKey: .inningNumber)
        inningHalfText = try container.decodeIfPresent(String.self, forKey: .inningHalfText)
        awayScoreText = try container.decodeIfPresent(String.self, forKey: .awayScoreText)
        homeScoreText = try container.decodeIfPresent(String.self, forKey: .homeScoreText)
        strikeCount = try container.decodeIfPresent(Int.self, forKey: .strikeCount)
        ballCount = try container.decodeIfPresent(Int.self, forKey: .ballCount)
        outCount = try container.decodeIfPresent(Int.self, forKey: .outCount)

        let first = try Self.decodeInt(from: decoder, keys: ["B1_BAT_ORDER_NO", "B1BATORDERNO", "BASE1_BAT_ORDER_NO"])
        let second = try Self.decodeInt(from: decoder, keys: ["B2_BAT_ORDER_NO", "B2BATORDERNO", "BASE2_BAT_ORDER_NO"])
        let third = try Self.decodeInt(from: decoder, keys: ["B3_BAT_ORDER_NO", "B3BATORDERNO", "BASE3_BAT_ORDER_NO"])
        firstBaseOccupancy = first.value
        secondBaseOccupancy = second.value
        thirdBaseOccupancy = third.value
        decodedBaseOrderSourceKeys = [first.key, second.key, third.key].compactMap { $0 }
    }

    var baseOrderSourceKeys: [String] {
        decodedBaseOrderSourceKeys
    }

    // decodeInt 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    private static func decodeInt(
        from decoder: any Decoder,
        keys: [String]
    ) throws -> (value: Int?, key: String?) {
        let container = try decoder.container(keyedBy: OfficialFlexibleCodingKey.self)
        for key in keys {
            let codingKey = OfficialFlexibleCodingKey(key)
            if let value = try? container.decodeIfPresent(Int.self, forKey: codingKey) {
                return (value, key)
            }
            if let value = try? container.decodeIfPresent(String.self, forKey: codingKey),
               let intValue = OfficialBaseRunnerLineupResolver.normalizedBattingOrderNumber(value) {
                return (intValue, key)
            }
        }
        return (nil, nil)
    }
}

// OfficialFlexibleCodingKey 구조체는 OfficialFlexibleCodingKey 타입의 역할과 값을 정의합니다.
private struct OfficialFlexibleCodingKey: CodingKey, Hashable, Sendable {
    let stringValue: String
    let intValue: Int?

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init?(stringValue: String) {
        self.init(stringValue)
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
