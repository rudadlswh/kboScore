//
//  OfficialKBOGameListDTOs.swift
//  kboScore
//
//  Created by Codex on 5/13/26.
//

import Foundation

struct OfficialGameListResponse: Decodable {
    let game: [OfficialGameEntry]
}

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
               let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return (intValue, key)
            }
        }
        return (nil, nil)
    }
}

private struct OfficialFlexibleCodingKey: CodingKey, Hashable, Sendable {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
