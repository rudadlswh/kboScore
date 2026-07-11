//
//  OfficialKBOGameCenterDTOs.swift
//  kboScore
//  기능 설명: KBO 공식 API 응답을 디코딩하기 위한 DTO를 정의합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 5/13/26.
//

import Foundation

// OfficialScoreboardResponse 구조체는 OfficialScoreboardResponse 타입의 역할과 값을 정의합니다.
struct OfficialScoreboardResponse: Decodable {
    let stadiumName: String?
    let crowdText: String?
    let startTime: String?
    let endTime: String?
    let durationText: String?
    let inningTable: String?
    let totalsTable: String?

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
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

// OfficialBoxScoreResponse 구조체는 OfficialBoxScoreResponse 타입의 역할과 값을 정의합니다.
struct OfficialBoxScoreResponse: Decodable {
    let summaryTable: String
    let battingTables: [OfficialBattingTableGroup]
    let pitchingTables: [OfficialPitchingTableGroup]

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case summaryTable = "tableEtc"
        case battingTables = "arrHitter"
        case pitchingTables = "arrPitcher"
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summaryTable = try container.decodeIfPresent(String.self, forKey: .summaryTable) ?? ""
        battingTables = try container.decodeIfPresent([OfficialBattingTableGroup].self, forKey: .battingTables) ?? []
        pitchingTables = try container.decodeIfPresent([OfficialPitchingTableGroup].self, forKey: .pitchingTables) ?? []
    }
}

// OfficialBattingTableGroup 구조체는 OfficialBattingTableGroup 타입의 역할과 값을 정의합니다.
struct OfficialBattingTableGroup: Decodable {
    let orderTable: String
    let detailTable: String?
    let summaryTable: String?

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case orderTable = "table1"
        case detailTable = "table2"
        case summaryTable = "table3"
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        orderTable = try container.decodeIfPresent(String.self, forKey: .orderTable) ?? ""
        detailTable = try container.decodeIfPresent(String.self, forKey: .detailTable)
        summaryTable = try container.decodeIfPresent(String.self, forKey: .summaryTable)
    }
}

// OfficialPitchingTableGroup 구조체는 OfficialPitchingTableGroup 타입의 역할과 값을 정의합니다.
struct OfficialPitchingTableGroup: Decodable {
    let table: String
}

// OfficialPreviewRecordResponse 구조체는 OfficialPreviewRecordResponse 타입의 역할과 값을 정의합니다.
struct OfficialPreviewRecordResponse: Decodable {
    let rows: [OfficialPreviewRecordRow]
}

// OfficialPreviewRecordRow 구조체는 OfficialPreviewRecordRow 타입의 역할과 값을 정의합니다.
struct OfficialPreviewRecordRow: Decodable {
    let row: [OfficialPreviewRecordCell]
}

// OfficialPreviewRecordCell 구조체는 OfficialPreviewRecordCell 타입의 역할과 값을 정의합니다.
struct OfficialPreviewRecordCell: Decodable {
    let text: String

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case text = "Text"
    }
}

// OfficialKeyPlayerResponse 구조체는 OfficialKeyPlayerResponse 타입의 역할과 값을 정의합니다.
struct OfficialKeyPlayerResponse: Decodable {
    let records: [OfficialKeyPlayerRecord]

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case records = "record"
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        records = try container.decodeIfPresent([OfficialKeyPlayerRecord].self, forKey: .records) ?? []
    }
}

// OfficialKeyPlayerRecord 구조체는 OfficialKeyPlayerRecord 타입의 역할과 값을 정의합니다.
struct OfficialKeyPlayerRecord: Decodable, Sendable {
    let rank: String
    let playerID: String?
    let playerName: String
    let teamID: String
    let recordInfo: String
    let rawValues: [String: String]

// CodingKeys 열거형는 Codable 변환에 사용하는 키를 정의합니다.
    private enum CodingKeys: String, CodingKey {
        case rank = "RANK_NO"
        case playerID = "P_ID"
        case playerName = "P_NM"
        case teamID = "T_ID"
        case recordInfo = "RECORD_IF"
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
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

    // decodeString 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
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

    // decodeString 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
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

// OfficialKeyPlayerDynamicCodingKey 구조체는 OfficialKeyPlayerDynamicCodingKey 타입의 역할과 값을 정의합니다.
private struct OfficialKeyPlayerDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
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
