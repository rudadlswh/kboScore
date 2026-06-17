//
//  OfficialBoxScoreBattingInterpreter.swift
//  kboScore
//  기능 설명: 공식 박스스코어 타격 행의 위치와 기록 값을 해석합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 5/14/26.
//

import Foundation

// OfficialBattingTableInterpretation 열거형는 OfficialBattingTableInterpretation 타입의 역할과 값을 정의합니다.
enum OfficialBattingTableInterpretation: String {
    case lineup
    case aggregateBattingStats
    case plateAppearanceResults
    case unknown
}

extension OfficialGridTable {
    var battingTableInterpretation: OfficialBattingTableInterpretation {
        let labels = headers.first?.cells.map { $0.text.normalizedKeyStatLabel } ?? []
        let aggregateLabels: Set<String> = ["타수", "AB", "득점", "R", "안타", "H", "타점", "RBI", "홈런", "HR", "HRA", "볼넷", "BB", "4구", "삼진", "SO", "K"]
            .map(\.normalizedKeyStatLabel)
            .reduce(into: Set<String>()) { $0.insert($1) }
        if labels.contains(where: aggregateLabels.contains) {
            return .aggregateBattingStats
        }

        if rows.contains(where: \.isCurrentKBOBattingAggregateRow) || tfoot.contains(where: \.isCurrentKBOBattingAggregateRow) {
            return .aggregateBattingStats
        }

        if let firstRow = rows.first,
           firstRow.cells.count == 3,
           firstRow.cells[0].text.battingOrderNumber != nil,
           firstRow.cells[2].text.nilIfBlank != nil {
            return .lineup
        }

        let sampleValues = rows.prefix(3).flatMap { $0.cells.map(\.text) }
        if sampleValues.contains(where: { $0.nilIfBlank != nil && $0.isIntegerStatValue == false }) {
            return .plateAppearanceResults
        }

        return .unknown
    }
}

private extension OfficialGridRow {
    var isCurrentKBOBattingAggregateRow: Bool {
        guard cells.count >= 5 else { return false }
        return cells[0].text.isIntegerStatValue &&
            cells[1].text.isIntegerStatValue &&
            cells[2].text.isIntegerStatValue &&
            cells[3].text.isIntegerStatValue &&
            cells[4].text.isDecimalStatValue
    }
}

private extension String {
    var battingOrderNumber: String? {
        let digits = trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

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

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isIntegerStatValue: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }
        return trimmed.allSatisfy(\.isNumber)
    }

    var isDecimalStatValue: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 1 {
            return trimmed.isIntegerStatValue
        }
        guard parts.count == 2,
              parts[0].allSatisfy(\.isNumber),
              parts[1].allSatisfy(\.isNumber) else {
            return false
        }
        return true
    }

    var normalizedKeyStatLabel: String {
        let scalars = normalizedGridText.unicodeScalars.filter { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar) == false &&
            CharacterSet.punctuationCharacters.contains(scalar) == false &&
            CharacterSet.symbols.contains(scalar) == false
        }
        return String(String.UnicodeScalarView(scalars)).uppercased()
    }
}
