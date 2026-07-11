//
//  HomeGameSelector.swift
//  kboScore
//  기능 설명: 홈 화면에서 우선 노출할 경기와 필터 결과를 선택합니다.
//  오늘 경기와 경기 없는 날의 대체 정보를 홈에서 바로 판단할 수 있도록 표시용 요약을 별도로 구성합니다.
//  월요일 직전 주 요약, 마이팀 경기 우선순위, 빈 일정 상태가 겹칠 수 있어 선택 순서를 명확히 유지합니다.
//  TODO : 홈 요약 정책이 바뀌면 날짜별 스냅샷 테스트를 추가합니다.
//
//  Created by Codex on 5/18/26.
//

import Foundation

// HomeGameSelector 열거형는 HomeGameSelector 타입의 역할과 값을 정의합니다.
enum HomeGameSelector {
    // matches 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    static func matches(_ summary: GameSummary, filter: HomeGameFilter) -> Bool {
        switch filter {
        case .all:
            true
        case .live:
            summary.status.isLiveLike
        case .upcoming:
            summary.status == .upcoming
        case .final:
            summary.status.isFinishedLike
        case .myTeam:
            summary.isMyTeamGame
        }
    }

    // compare 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    static func compare(_ lhs: GameSummary, _ rhs: GameSummary) -> Bool {
        if lhs.isMyTeamGame != rhs.isMyTeamGame {
            return lhs.isMyTeamGame && !rhs.isMyTeamGame
        }

        let lhsPriority = priority(for: lhs)
        let rhsPriority = priority(for: rhs)

        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        if lhs.status.isLiveLike && rhs.status.isLiveLike, lhs.isMyTeamGame == rhs.isMyTeamGame {
            return lhs.scheduledStart > rhs.scheduledStart
        }

        return lhs.scheduledStart < rhs.scheduledStart
    }

    // compareTodayGames 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    static func compareTodayGames(_ lhs: GameDetail, _ rhs: GameDetail, favoriteTeamID: String?) -> Bool {
        compare(
            lhs.summary(isMyTeamGame: lhs.involves(teamID: favoriteTeamID)),
            rhs.summary(isMyTeamGame: rhs.involves(teamID: favoriteTeamID))
        )
    }

    // priority 메서드는 이 타입의 주요 동작을 수행합니다.
    static func priority(for summary: GameSummary) -> Int {
        switch summary.status {
        case .live, .rainDelay:
            return summary.isMyTeamGame ? 0 : 1
        case .upcoming:
            return 2
        case .final, .cancelled:
            return 3
        }
    }
}
