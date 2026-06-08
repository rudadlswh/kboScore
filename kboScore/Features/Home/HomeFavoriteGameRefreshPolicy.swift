//
//  HomeFavoriteGameRefreshPolicy.swift
//  kboScore
//
//  Created by Codex on 6/9/26.
//

import Foundation

enum HomeFavoriteGameRefreshPolicy {
    private static let recentRefreshInterval: TimeInterval = 15
    private static let unthrottledReasons: Set<String> = [
        "homeRefresh",
        "favoriteTeamSelected",
        "sceneBackground",
        "backgroundTask"
    ]

    static func shouldThrottleRecentRefresh(reason: String) -> Bool {
        unthrottledReasons.contains(reason) == false
    }

    static func shouldSkipRecentRefresh(
        reason: String,
        lastRefreshedAt: Date?,
        now: Date
    ) -> Bool {
        guard shouldThrottleRecentRefresh(reason: reason),
              let lastRefreshedAt else {
            return false
        }
        return now.timeIntervalSince(lastRefreshedAt) < recentRefreshInterval
    }
}
