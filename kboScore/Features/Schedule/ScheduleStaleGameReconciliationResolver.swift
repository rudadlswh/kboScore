//
//  ScheduleStaleGameReconciliationResolver.swift
//  kboScore
//
//  Created by Codex on 5/22/26.
//

import Foundation

struct ScheduleStaleGameReconciliationResolver: Sendable {
    nonisolated static func staleGameDates(
        in games: [GameDetail],
        today: Date,
        calendar: Calendar
    ) -> [String] {
        let dates = Set(
            games.compactMap { game -> String? in
                guard isStalePastGame(game, today: today, calendar: calendar) else {
                    return nil
                }
                return dayKey(for: game.scheduledStart, calendar: calendar)
            }
        )
        return dates.sorted(by: >)
    }

    nonisolated static func isStalePastGame(
        _ game: GameDetail,
        today: Date,
        calendar: Calendar
    ) -> Bool {
        let gameDate = calendar.startOfDay(for: game.scheduledStart)
        let todayDate = calendar.startOfDay(for: today)
        guard gameDate < todayDate else {
            return false
        }

        switch game.status {
        case .upcoming:
            return true
        case .live, .rainDelay:
            return true
        case .final, .cancelled:
            return false
        }
    }

    nonisolated private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }
}
