//
//  HomeContentState.swift
//  kboScore
//  기능 설명: 홈 화면에서 오늘 경기, 빈 상태, 대체 순위 요약 중 표시할 상태를 결정합니다.
//  오늘 경기와 경기 없는 날의 대체 정보를 홈에서 바로 판단할 수 있도록 표시용 요약을 별도로 구성합니다.
//  월요일 직전 주 요약, 마이팀 경기 우선순위, 빈 일정 상태가 겹칠 수 있어 선택 순서를 명확히 유지합니다.
//  TODO : 홈 요약 정책이 바뀌면 날짜별 스냅샷 테스트를 추가합니다.
//
//  Created by Codex on 6/8/26.
//

// HomeContentState 열거형는 화면이나 도메인 흐름에서 사용하는 상태 값을 표현합니다.
enum HomeContentState {
    case noGames
    case noFilteredGames
    case fallbackStandings(title: String, subtitle: String, snapshots: [TeamStandingsSnapshot])
    case games([GameDetail])

    // make 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    static func make(
        todayGames: [GameDetail],
        filteredGames: [GameSummary],
        filteredGameDetails: [GameDetail],
        fallbackTitle: String,
        fallbackSubtitle: String,
        fallbackSnapshots: [TeamStandingsSnapshot]
    ) -> HomeContentState {
        if todayGames.isEmpty {
            if fallbackSnapshots.isEmpty {
                return .noGames
            }
            return .fallbackStandings(
                title: fallbackTitle,
                subtitle: fallbackSubtitle,
                snapshots: fallbackSnapshots
            )
        }

        if filteredGames.isEmpty {
            return .noFilteredGames
        }

        return .games(filteredGameDetails)
    }
}
