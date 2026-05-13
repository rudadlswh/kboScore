//
//  LiveActivityAutoStartEligibility.swift
//  kboScore
//
//  Created by Codex on 5/13/26.
//

import Foundation

enum LiveActivityAutoStartEligibility {
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

    nonisolated static func isEligibleForAutomaticLiveActivityStart(
        game: GameDetail,
        now: Date
    ) -> Bool {
        if case .eligible = decision(for: game, now: now) {
            return true
        }
        return false
    }

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

    nonisolated static func decision(for game: GameDetail, now: Date) -> Decision {
        decision(
            status: game.status,
            scheduledAt: scheduledAt(from: game),
            now: now
        )
    }

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

    private nonisolated static func scheduledAt(from game: GameDetail) -> Date? {
        game.scheduledStart == .distantPast ? nil : game.scheduledStart
    }
}
