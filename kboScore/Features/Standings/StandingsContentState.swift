//
//  StandingsContentState.swift
//  kboScore
//  기능 설명: 순위 화면의 로딩, 빈 상태, 데이터 표시 상태를 결정합니다.
//  KBO 순위 산정 규칙과 홈 화면 대체 요약에 필요한 계산을 화면 코드에서 분리합니다.
//  완료되지 않은 경기, 취소 경기, 동률, 원정/홈 득실 계산이 순위에 잘못 반영되지 않도록 제한합니다.
//  TODO : 실제 KBO 동률 규정 변경이나 포스트시즌 확률 로직 개선 시 계산 기준을 갱신합니다.
//
//  Created by Codex on 6/8/26.
//

// StandingsContentState 열거형는 화면이나 도메인 흐름에서 사용하는 상태 값을 표현합니다.
enum StandingsContentState {
    case loading
    case empty
    case table(
        rows: [TeamStandingsSnapshot],
        revision: Int,
        favoriteTeamID: String?
    )

    // make 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    static func make(
        rows: [TeamStandingsSnapshot],
        isLoading: Bool,
        revision: Int,
        favoriteTeamID: String?
    ) -> StandingsContentState {
        if isLoading, rows.isEmpty {
            return .loading
        }
        guard rows.isEmpty == false else { return .empty }
        return .table(
            rows: rows,
            revision: revision,
            favoriteTeamID: favoriteTeamID
        )
    }
}
