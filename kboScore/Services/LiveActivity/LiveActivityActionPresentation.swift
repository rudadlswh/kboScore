//
//  LiveActivityActionPresentation.swift
//  kboScore
//  기능 설명: Live Activity 액션 버튼의 표시 상태와 문구를 결정합니다.
//  앱 밖에서도 마이팀 경기 흐름을 이어서 볼 수 있도록 Live Activity와 위젯용 스냅샷을 분리합니다.
//  확장 프로세스, App Group 저장소, 푸시 토큰, 시스템 권한 상태에 따라 갱신이 실패할 수 있습니다.
//  TODO : 실기기 권한 상태별 동작과 종료 조건을 더 촘촘히 검증합니다.
//

import Foundation

// LiveActivityActionPresentation 열거형는 LiveActivityActionPresentation 타입의 역할과 값을 정의합니다.
enum LiveActivityActionPresentation {
    // shouldShow 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    static func shouldShow(game: GameDetail, favoriteTeamID: String?) -> Bool {
        game.status.isLiveLike && game.involves(teamID: favoriteTeamID)
    }

    // isEnabled 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    static func isEnabled(
        game: GameDetail,
        favoriteTeamID: String?,
        liveActivitiesEnabled: Bool,
        liveActivitySupported: Bool
    ) -> Bool {
        shouldShow(game: game, favoriteTeamID: favoriteTeamID) &&
            liveActivitiesEnabled &&
            liveActivitySupported
    }

    // buttonTitle 메서드는 이 타입의 주요 동작을 수행합니다.
    static func buttonTitle(
        game: GameDetail,
        favoriteTeamID: String?,
        liveActivitiesEnabled: Bool,
        liveActivitySupported: Bool,
        isActive: Bool
    ) -> String {
        guard shouldShow(game: game, favoriteTeamID: favoriteTeamID) else {
            return "Live Activity"
        }
        if liveActivitiesEnabled == false {
            return "Live Activity 꺼짐"
        }
        if liveActivitySupported == false {
            return "Live Activity 사용 불가"
        }
        if isActive {
            return "Live Activity 중지"
        }
        return "Live Activity 시작"
    }

    // buttonSystemImage 메서드는 이 타입의 주요 동작을 수행합니다.
    static func buttonSystemImage(isActive _: Bool) -> String {
        "dot.radiowaves.left.and.right"
    }
}
