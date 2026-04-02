//
//  Repository.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import Foundation

struct KBOMonthScheduleKey: Hashable, Sendable, Codable {
    let year: Int
    let month: Int

    nonisolated init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    nonisolated init(date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) {
        let components = calendar.dateComponents([.year, .month], from: date)
        self.year = components.year ?? 1970
        self.month = components.month ?? 1
    }

    nonisolated var yearMonthText: String {
        String(format: "%04d%02d", year, month)
    }
}

protocol KBOGameDataSource: Sendable {
    nonisolated func fetchGames() async throws -> [GameDetail]
}

protocol KBONotificationDataSource: Sendable {
    nonisolated func fetchNotifications() async throws -> [NotificationItem]
}

protocol KBOMonthScheduleDataSource: Sendable {
    nonisolated func fetchMonthlySchedule(for month: KBOMonthScheduleKey) async throws -> [GameDetail]
}

protocol KBOStandingsDataSource: Sendable {
    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot]
}

extension KBOStandingsDataSource {
    nonisolated func fetchStandings() async throws -> [TeamStandingsSnapshot] {
        []
    }
}

protocol KBORepository: KBOGameDataSource, KBONotificationDataSource, KBOMonthScheduleDataSource, KBOStandingsDataSource, Sendable {
    nonisolated func fetchBootstrapData() async throws -> KBOBootstrapData
}

struct KBOBootstrapData: Sendable {
    let teams: [Team]
    let games: [GameDetail]
    let notifications: [NotificationItem]
    let settings: AppSettings
}
