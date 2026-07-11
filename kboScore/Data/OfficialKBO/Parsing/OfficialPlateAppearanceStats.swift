//
//  OfficialPlateAppearanceStats.swift
//  kboScore
//  기능 설명: 타석 결과 문자열에서 타수, 안타, 타점 등 세부 기록을 계산합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 5/14/26.
//

import Foundation

// PlateAppearanceDerivedStats 구조체는 PlateAppearanceDerivedStats 타입의 역할과 값을 정의합니다.
struct PlateAppearanceDerivedStats: Sendable, Equatable {
    let homeRuns: Int
    let walks: Int
    let strikeouts: Int

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(homeRuns: Int = 0, walks: Int = 0, strikeouts: Int = 0) {
        self.homeRuns = homeRuns
        self.walks = walks
        self.strikeouts = strikeouts
    }

    // adding 메서드는 이 타입의 주요 동작을 수행합니다.
    func adding(resultText: String) -> PlateAppearanceDerivedStats {
        resultText.plateAppearanceResultTokens.reduce(self) { stats, result in
            PlateAppearanceDerivedStats(
                homeRuns: stats.homeRuns + (result.isHomeRunPlateAppearance ? 1 : 0),
                walks: stats.walks + (result.isWalkPlateAppearance ? 1 : 0),
                strikeouts: stats.strikeouts + (result.isStrikeoutPlateAppearance ? 1 : 0)
            )
        }
    }

    // + 메서드는 이 타입의 주요 동작을 수행합니다.
    static func + (lhs: PlateAppearanceDerivedStats, rhs: PlateAppearanceDerivedStats) -> PlateAppearanceDerivedStats {
        PlateAppearanceDerivedStats(
            homeRuns: lhs.homeRuns + rhs.homeRuns,
            walks: lhs.walks + rhs.walks,
            strikeouts: lhs.strikeouts + rhs.strikeouts
        )
    }
}

extension OfficialKBOGameCenterClient {
    // plateAppearanceDerivedStats 메서드는 이 타입의 주요 동작을 수행합니다.
    func plateAppearanceDerivedStats(
        table: OfficialGridTable?,
        row: OfficialGridRow?
    ) -> PlateAppearanceDerivedStats? {
        guard table?.battingTableInterpretation == .plateAppearanceResults,
              let row else {
            return nil
        }

        return row.cells.reduce(PlateAppearanceDerivedStats()) { stats, cell in
            stats.adding(resultText: cell.text)
        }
    }

    // plateAppearanceTotals 메서드는 이 타입의 주요 동작을 수행합니다.
    func plateAppearanceTotals(table: OfficialGridTable?) -> PlateAppearanceDerivedStats? {
        guard table?.battingTableInterpretation == .plateAppearanceResults,
              let rows = table?.rows,
              rows.isEmpty == false else {
            return nil
        }

        return rows
            .compactMap { plateAppearanceDerivedStats(table: table, row: $0) }
            .reduce(PlateAppearanceDerivedStats()) { $0 + $1 }
    }
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

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedKeyStatLabel: String {
        let scalars = normalizedGridText.unicodeScalars.filter { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar) == false &&
            CharacterSet.punctuationCharacters.contains(scalar) == false &&
            CharacterSet.symbols.contains(scalar) == false
        }
        return String(String.UnicodeScalarView(scalars)).uppercased()
    }

    var isHomeRunPlateAppearance: Bool {
        let normalized = normalizedKeyStatLabel
        return normalized.contains("홈")
    }

    var isWalkPlateAppearance: Bool {
        let normalized = normalizedKeyStatLabel
        return ["4구", "볼넷", "고4", "고의4구", "자동고의4구"].contains(normalized)
    }

    var isStrikeoutPlateAppearance: Bool {
        let normalized = normalizedKeyStatLabel
        return normalized.contains("삼진") || normalized.contains("낫아웃")
    }

    var plateAppearanceResultTokens: [String] {
        normalizedGridText
            .split { character in
                character == "," ||
                    character == "，" ||
                    character == "/" ||
                    character == "\n" ||
                    character == "\r"
            }
            .map(String.init)
            .compactMap(\.nilIfBlank)
    }
}
