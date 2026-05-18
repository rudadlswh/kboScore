//
//  LiveActivityActionPresentation.swift
//  kboScore
//

import Foundation

enum LiveActivityActionPresentation {
    static func shouldShow(game: GameDetail, favoriteTeamID: String?) -> Bool {
        game.status.isLiveLike && game.involves(teamID: favoriteTeamID)
    }

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

    static func buttonSystemImage(isActive _: Bool) -> String {
        "dot.radiowaves.left.and.right"
    }
}
