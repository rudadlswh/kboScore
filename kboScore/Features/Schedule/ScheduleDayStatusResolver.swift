//
//  ScheduleDayStatusResolver.swift
//  kboScore
//
//  Created by Codex on 5/18/26.
//

import Foundation

enum ScheduleDayStatusResolver {
    static func dominantStatus(for games: [GameDetail]) -> GameStatus? {
        if games.contains(where: { $0.status == .live }) {
            return .live
        }
        if games.contains(where: { $0.status == .rainDelay }) {
            return .rainDelay
        }
        if games.contains(where: { $0.status == .upcoming }) {
            return .upcoming
        }
        if games.contains(where: { $0.status == .final }) {
            return .final
        }
        if games.contains(where: { $0.status == .cancelled }) {
            return .cancelled
        }
        return nil
    }
}
