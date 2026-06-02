//
//  OfficialKBOGameCenterDTOs.swift
//  kboScore
//
//  Created by Codex on 5/13/26.
//

import Foundation

struct OfficialScoreboardResponse: Decodable {
    let stadiumName: String?
    let crowdText: String?
    let startTime: String?
    let endTime: String?
    let durationText: String?
    let inningTable: String?
    let totalsTable: String?

    private enum CodingKeys: String, CodingKey {
        case stadiumName = "S_NM"
        case crowdText = "CROWD_CN"
        case startTime = "START_TM"
        case endTime = "END_TM"
        case durationText = "USE_TM"
        case inningTable = "table2"
        case totalsTable = "table3"
    }
}

struct OfficialBoxScoreResponse: Decodable {
    let summaryTable: String
    let battingTables: [OfficialBattingTableGroup]
    let pitchingTables: [OfficialPitchingTableGroup]

    private enum CodingKeys: String, CodingKey {
        case summaryTable = "tableEtc"
        case battingTables = "arrHitter"
        case pitchingTables = "arrPitcher"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summaryTable = try container.decodeIfPresent(String.self, forKey: .summaryTable) ?? ""
        battingTables = try container.decodeIfPresent([OfficialBattingTableGroup].self, forKey: .battingTables) ?? []
        pitchingTables = try container.decodeIfPresent([OfficialPitchingTableGroup].self, forKey: .pitchingTables) ?? []
    }
}

struct OfficialBattingTableGroup: Decodable {
    let orderTable: String
    let detailTable: String?
    let summaryTable: String?

    private enum CodingKeys: String, CodingKey {
        case orderTable = "table1"
        case detailTable = "table2"
        case summaryTable = "table3"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        orderTable = try container.decodeIfPresent(String.self, forKey: .orderTable) ?? ""
        detailTable = try container.decodeIfPresent(String.self, forKey: .detailTable)
        summaryTable = try container.decodeIfPresent(String.self, forKey: .summaryTable)
    }
}

struct OfficialPitchingTableGroup: Decodable {
    let table: String
}

struct OfficialPreviewRecordResponse: Decodable {
    let rows: [OfficialPreviewRecordRow]
}

struct OfficialPreviewRecordRow: Decodable {
    let row: [OfficialPreviewRecordCell]
}

struct OfficialPreviewRecordCell: Decodable {
    let text: String

    private enum CodingKeys: String, CodingKey {
        case text = "Text"
    }
}

struct OfficialKeyPlayerResponse: Decodable {
    let records: [OfficialKeyPlayerRecord]

    private enum CodingKeys: String, CodingKey {
        case records = "record"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        records = try container.decodeIfPresent([OfficialKeyPlayerRecord].self, forKey: .records) ?? []
    }
}

struct OfficialKeyPlayerRecord: Decodable, Sendable {
    let rank: String
    let playerID: String?
    let playerName: String
    let teamID: String
    let recordInfo: String
    let rawValues: [String: String]

    private enum CodingKeys: String, CodingKey {
        case rank = "RANK_NO"
        case playerID = "P_ID"
        case playerName = "P_NM"
        case teamID = "T_ID"
        case recordInfo = "RECORD_IF"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rank = Self.decodeString(container, forKey: .rank) ?? ""
        playerID = Self.decodeString(container, forKey: .playerID)
        playerName = Self.decodeString(container, forKey: .playerName) ?? ""
        teamID = Self.decodeString(container, forKey: .teamID) ?? ""
        recordInfo = Self.decodeString(container, forKey: .recordInfo) ?? ""
        let rawContainer = try decoder.container(keyedBy: OfficialKeyPlayerDynamicCodingKey.self)
        var values: [String: String] = [:]
        for key in rawContainer.allKeys {
            if let value = Self.decodeString(rawContainer, forKey: key)?.nilIfBlank {
                values[key.stringValue] = value
            }
        }
        rawValues = values
    }

    private static func decodeString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    private static func decodeString(
        _ container: KeyedDecodingContainer<OfficialKeyPlayerDynamicCodingKey>,
        forKey key: OfficialKeyPlayerDynamicCodingKey
    ) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

private struct OfficialKeyPlayerDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
