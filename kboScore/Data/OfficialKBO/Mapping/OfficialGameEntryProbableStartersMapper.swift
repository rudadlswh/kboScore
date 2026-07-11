//
//  OfficialGameEntryProbableStartersMapper.swift
//  kboScore
//  기능 설명: KBO 공식 경기 항목에서 선발 투수 정보를 추출합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 5/14/26.
//

import Foundation

extension OfficialGameEntry {
    var probableStarters: GameCenterProbableStarters {
        GameCenterProbableStarters(
            away: awayProbablePitcherName?.nilIfBlank,
            home: homeProbablePitcherName?.nilIfBlank
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
