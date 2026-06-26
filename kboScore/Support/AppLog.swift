//
//  AppLog.swift
//  kboScore
//  기능 설명: 운영 이슈 추적에 필요한 앱 로그 카테고리를 한 곳에서 제공합니다.
//

import Foundation
import OSLog

enum AppLog {
    enum Category: String {
        case schedule
        case gameDetail
        case supabase
        case liveActivity
        case notification
        case statusMapping
    }

    nonisolated private static var subsystem: String {
        Bundle.main.bundleIdentifier ?? "com.chogm.kboScore"
    }

    nonisolated private static func logger(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    nonisolated static func info(_ category: Category, _ message: String) {
        logger(category).info("\(message, privacy: .private)")
    }

    nonisolated static func warning(_ category: Category, _ message: String) {
        logger(category).warning("\(message, privacy: .private)")
    }

    nonisolated static func error(_ category: Category, _ message: String) {
        logger(category).error("\(message, privacy: .private)")
    }

    nonisolated static func debug(_ category: Category, _ message: String) {
        #if DEBUG
        logger(category).debug("\(message, privacy: .private)")
        #endif
    }
}
