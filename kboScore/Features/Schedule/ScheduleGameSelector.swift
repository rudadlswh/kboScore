//
//  ScheduleGameSelector.swift
//  kboScore
//  기능 설명: 일정 화면에서 선택 가능한 경기 목록을 필터링하고 정렬합니다.
//  월별·일별 일정 상태를 일관되게 계산해 홈, 일정, 위젯이 같은 경기 선택 기준을 공유합니다.
//  우천 취소, 더블헤더, 시간 미정, 오래된 캐시가 섞일 수 있어 날짜 키와 동기화 순서를 엄격히 다룹니다.
//  TODO : 공식 일정 변경 감지와 보정 로직을 더 작은 단위로 검증합니다.
//
//  Created by Codex on 5/18/26.
//

import Foundation

// ScheduleGameSelector 열거형는 ScheduleGameSelector 타입의 역할과 값을 정의합니다.
nonisolated enum ScheduleGameSelector {
    // sortSelectedGames 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    static func sortSelectedGames(_ games: [GameDetail], favoriteTeamID: String?) -> [GameDetail] {
        games.sorted { lhs, rhs in
            let lhsIsFavoriteTeam = favoriteTeamID.map { lhs.involves(teamID: $0) } ?? false
            let rhsIsFavoriteTeam = favoriteTeamID.map { rhs.involves(teamID: $0) } ?? false
            if lhsIsFavoriteTeam != rhsIsFavoriteTeam {
                return lhsIsFavoriteTeam && !rhsIsFavoriteTeam
            }
            if lhs.status == rhs.status {
                return lhs.scheduledStart < rhs.scheduledStart
            }
            return priority(for: lhs.status, isFavoriteTeamGame: lhsIsFavoriteTeam) <
                priority(for: rhs.status, isFavoriteTeamGame: rhsIsFavoriteTeam)
        }
    }

    // priority 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func priority(for status: GameStatus, isFavoriteTeamGame: Bool) -> Int {
        switch status {
        case .live, .rainDelay:
            return isFavoriteTeamGame ? 0 : 1
        case .upcoming:
            return 2
        case .final, .cancelled:
            return 3
        }
    }
}
