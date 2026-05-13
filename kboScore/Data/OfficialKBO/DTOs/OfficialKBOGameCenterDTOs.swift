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
    let inningTable: String
    let totalsTable: String

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
