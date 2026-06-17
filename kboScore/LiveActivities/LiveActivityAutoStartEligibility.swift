//
//  LiveActivityAutoStartEligibility.swift
//  kboScore
//  기능 설명: 마이팀 경기 Live Activity 자동 시작 가능 여부를 판단합니다.
//  앱 밖에서도 마이팀 경기 흐름을 이어서 볼 수 있도록 Live Activity와 위젯용 스냅샷을 분리합니다.
//  확장 프로세스, App Group 저장소, 푸시 토큰, 시스템 권한 상태에 따라 갱신이 실패할 수 있습니다.
//  TODO : 실기기 권한 상태별 동작과 종료 조건을 더 촘촘히 검증합니다.
//
//  Created by Codex on 5/13/26.
//

import Foundation

// LiveActivityAutoStartEligibility 열거형는 LiveActivityAutoStartEligibility 타입의 역할과 값을 정의합니다.
enum LiveActivityAutoStartEligibility {
// Decision 열거형는 Decision 타입의 역할과 값을 정의합니다.
    enum Decision: Equatable {
        case eligible
        case tooEarly
        case missingScheduledAt
        case terminalStatus

        nonisolated var logReason: String {
            switch self {
            case .eligible:
                "eligible"
            case .tooEarly:
                "tooEarly"
            case .missingScheduledAt:
                "missingScheduledAt"
            case .terminalStatus:
                "terminalStatus"
            }
        }
    }

    private nonisolated static let pregameStartWindow: TimeInterval = 30 * 60

    // isEligibleForAutomaticLiveActivityStart 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    nonisolated static func isEligibleForAutomaticLiveActivityStart(
        game: GameDetail,
        now: Date
    ) -> Bool {
        if case .eligible = decision(for: game, now: now) {
            return true
        }
        return false
    }

    // isEligibleForAutomaticLiveActivityStart 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    nonisolated static func isEligibleForAutomaticLiveActivityStart(
        status: GameStatus,
        scheduledAt: Date?,
        now: Date
    ) -> Bool {
        if case .eligible = decision(status: status, scheduledAt: scheduledAt, now: now) {
            return true
        }
        return false
    }

    // decision 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated static func decision(for game: GameDetail, now: Date) -> Decision {
        decision(
            status: game.status,
            scheduledAt: scheduledAt(from: game),
            now: now
        )
    }

    // decision 메서드는 이 타입의 주요 동작을 수행합니다.
    nonisolated static func decision(
        status: GameStatus,
        scheduledAt: Date?,
        now: Date
    ) -> Decision {
        if status.isLiveLike {
            return .eligible
        }

        if status.isFinishedLike {
            return .terminalStatus
        }

        guard status == .upcoming else {
            return .terminalStatus
        }

        guard let scheduledAt else {
            return .missingScheduledAt
        }

        let earliestStart = scheduledAt.addingTimeInterval(-pregameStartWindow)
        return now >= earliestStart ? .eligible : .tooEarly
    }

    // scheduledAt 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    private nonisolated static func scheduledAt(from game: GameDetail) -> Date? {
        game.scheduledStart == .distantPast ? nil : game.scheduledStart
    }
}
