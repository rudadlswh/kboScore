//
//  OfficialGridModels.swift
//  kboScore
//  기능 설명: KBO 공식 그리드 응답 파싱에 사용하는 중간 모델을 정의합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 5/14/26.
//

import Foundation

// OfficialGridTableDTO 구조체는 외부 응답과 내부 모델 변환에 사용하는 데이터 전송 값을 담습니다.
struct OfficialGridTableDTO: Decodable {
    let headers: [OfficialGridRowDTO]
    let rows: [OfficialGridRowDTO]
    let tfoot: [OfficialGridRowDTO]

    var table: OfficialGridTable {
        OfficialGridTable(
            headers: headers.map(\.row),
            rows: rows.map(\.row),
            tfoot: tfoot.map(\.row)
        )
    }
}

// OfficialGridTable 구조체는 OfficialGridTable 타입의 역할과 값을 정의합니다.
struct OfficialGridTable: Sendable {
    let headers: [OfficialGridRow]
    let rows: [OfficialGridRow]
    let tfoot: [OfficialGridRow]
}

// OfficialGridRowDTO 구조체는 외부 응답과 내부 모델 변환에 사용하는 데이터 전송 값을 담습니다.
struct OfficialGridRowDTO: Decodable {
    let row: OfficialGridRow
}

// OfficialGridRow 구조체는 OfficialGridRow 타입의 역할과 값을 정의합니다.
struct OfficialGridRow: Decodable {
    let cells: [OfficialGridCell]

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawCells = try container.decode([OfficialGridCellDTO].self)
        cells = rawCells.map { OfficialGridCell(text: $0.text.normalizedGridText) }
    }
}

// OfficialGridCell 구조체는 OfficialGridCell 타입의 역할과 값을 정의합니다.
struct OfficialGridCell: Sendable {
    let text: String
}

private extension String {
    var normalizedGridText: String {
        replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\r", with: "")
            .strippingHTML()
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // strippingHTML 메서드는 이 타입의 주요 동작을 수행합니다.
    func strippingHTML() -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) else {
            return self
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: "")
    }
}
