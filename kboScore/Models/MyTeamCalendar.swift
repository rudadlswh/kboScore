//
//  MyTeamCalendar.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import Foundation

struct MyTeamCalendarDay: Identifiable, Hashable, Sendable {
    let date: Date
    let isInDisplayedMonth: Bool
    let isToday: Bool
    let gameCount: Int
    let dominantStatus: GameStatus?

    var id: Date { date }
    var hasGames: Bool { gameCount > 0 }
}
