//
//  OfficialPreviewParser.swift
//  kboScore
//  기능 설명: 공식 프리뷰 페이지에서 경기 전 라인업과 선발 정보를 파싱합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 5/14/26.
//

import Foundation

extension OfficialKBOGameCenterClient {
    // makeMatchupSnapshot 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    func makeMatchupSnapshot(from row: OfficialPreviewRecordRow) -> GameCenterMatchupSnapshot? {
        guard row.row.count >= 7 else { return nil }

        let cells = row.row.map { $0.normalizedText }
        guard let teamName = cells[safe: 0]?.nilIfBlank else {
            return nil
        }

        return GameCenterMatchupSnapshot(
            teamName: teamName,
            seasonRecord: cells[safe: 1]?.nilIfBlank,
            recentFive: cells[safe: 2]?.nilIfBlank,
            teamERA: cells[safe: 3]?.nilIfBlank,
            battingAverage: cells[safe: 4]?.nilIfBlank,
            runsScored: cells[safe: 5]?.nilIfBlank,
            runsAllowed: cells[safe: 6]?.nilIfBlank
        )
    }
}

private extension OfficialPreviewRecordCell {
    var normalizedText: String {
        text.normalizedGridText
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
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
}
