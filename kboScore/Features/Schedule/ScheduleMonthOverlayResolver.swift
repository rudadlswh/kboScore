//
//  ScheduleMonthOverlayResolver.swift
//  kboScore
//
//  Created by Codex on 6/8/26.
//

import Foundation

enum ScheduleMonthOverlayResolver {
    static func merge(
        existingMonthGames: [GameDetail],
        incomingGames: [GameDetail],
        monthKey: KBOMonthScheduleKey,
        calendar: Calendar
    ) -> [GameDetail] {
        let monthIncomingGames = incomingGames.filter {
            isGame($0, in: monthKey, calendar: calendar)
        }
        guard existingMonthGames.isEmpty == false else {
            return monthIncomingGames.sorted { $0.scheduledStart < $1.scheduledStart }
        }

        var mergedGames = existingMonthGames.filter {
            isGame($0, in: monthKey, calendar: calendar)
        }

        for incomingGame in monthIncomingGames {
            let incomingAliases = incomingGame.gameIdentityAliases
            if let index = mergedGames.firstIndex(where: { existingGame in
                existingGame.gameIdentityAliases.isDisjoint(with: incomingAliases) == false
            }) {
                mergedGames[index] = incomingGame
            } else {
                mergedGames.append(incomingGame)
            }
        }

        return mergedGames.sorted { $0.scheduledStart < $1.scheduledStart }
    }

    private static func isGame(
        _ game: GameDetail,
        in monthKey: KBOMonthScheduleKey,
        calendar: Calendar
    ) -> Bool {
        let components = calendar.dateComponents([.year, .month], from: game.scheduledStart)
        return components.year == monthKey.year && components.month == monthKey.month
    }
}
