//
//  ScheduleDateKeyFormatter.swift
//  kboScore
//
//  Created by Codex on 6/8/26.
//

import Foundation

nonisolated enum ScheduleDateKeyFormatter {
    static func dayKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }
}
