//
//  HomeFavoriteGameRefreshPolicy.swift
//  kboScore
//  기능 설명: 홈 화면 마이팀 경기 새로고침의 중복 실행과 스로틀 정책을 결정합니다.
//  오늘 경기와 경기 없는 날의 대체 정보를 홈에서 바로 판단할 수 있도록 표시용 요약을 별도로 구성합니다.
//  월요일 직전 주 요약, 마이팀 경기 우선순위, 빈 일정 상태가 겹칠 수 있어 선택 순서를 명확히 유지합니다.
//  TODO : 홈 요약 정책이 바뀌면 날짜별 스냅샷 테스트를 추가합니다.
//
//  Created by Codex on 6/9/26.
//

import Foundation

// HomeFavoriteGameRefreshPolicy 열거형는 HomeFavoriteGameRefreshPolicy 타입의 역할과 값을 정의합니다.
enum HomeFavoriteGameRefreshPolicy {
    private static let recentRefreshInterval: TimeInterval = 15
    private static let unthrottledReasons: Set<String> = [
        "homeRefresh",
        "favoriteTeamSelected",
        "sceneBackground",
        "backgroundTask"
    ]

    // shouldThrottleRecentRefresh 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    static func shouldThrottleRecentRefresh(reason: String) -> Bool {
        unthrottledReasons.contains(reason) == false
    }

    // shouldSkipRecentRefresh 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
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
