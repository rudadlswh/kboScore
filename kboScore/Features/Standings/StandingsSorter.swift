//
//  StandingsSorter.swift
//  kboScore
//  기능 설명: KBO 순위표 정렬 규칙과 동률 처리 우선순위를 제공합니다.
//  KBO 순위 산정 규칙과 홈 화면 대체 요약에 필요한 계산을 화면 코드에서 분리합니다.
//  완료되지 않은 경기, 취소 경기, 동률, 원정/홈 득실 계산이 순위에 잘못 반영되지 않도록 제한합니다.
//  TODO : 실제 KBO 동률 규정 변경이나 포스트시즌 확률 로직 개선 시 계산 기준을 갱신합니다.
//
//  Created by Codex on 5/18/26.
//

import Foundation

// StandingsSorter 열거형는 StandingsSorter 타입의 역할과 값을 정의합니다.
enum StandingsSorter {
    // compare 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    nonisolated static func compare(
        _ lhs: TeamStandingsSnapshot,
        _ rhs: TeamStandingsSnapshot,
        previousRankProvider: (Team) -> Int?
    ) -> Bool {
        // Standings are derived locally from the current games payload so the
        // Standings tab stays aligned with the bundled bootstrap file.
        switch (lhs.winPercentage, rhs.winPercentage) {
        case let (left?, right?) where left != right:
            return left > right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            break
        }

        if let leftPreviousRank = previousRankProvider(lhs.team),
           let rightPreviousRank = previousRankProvider(rhs.team),
           leftPreviousRank != rightPreviousRank {
            return leftPreviousRank < rightPreviousRank
        }

        if lhs.wins != rhs.wins {
            return lhs.wins > rhs.wins
        }
        if lhs.losses != rhs.losses {
            return lhs.losses < rhs.losses
        }
        if lhs.ties != rhs.ties {
            return lhs.ties > rhs.ties
        }
        return lhs.team.name.localizedStandardCompare(rhs.team.name) == .orderedAscending
    }
}
