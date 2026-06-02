//
//  LiveKBOCacheConfiguration.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

struct RepositoryCacheConfiguration: Sendable {
    let bootstrapTTL: TimeInterval
    let gamesTTL: TimeInterval
    let notificationsTTL: TimeInterval
    let monthlyScheduleTTL: TimeInterval
    let diskCacheDirectory: URL?

    init(
        bootstrapTTL: TimeInterval,
        gamesTTL: TimeInterval,
        notificationsTTL: TimeInterval,
        monthlyScheduleTTL: TimeInterval,
        diskCacheDirectory: URL? = nil
    ) {
        self.bootstrapTTL = bootstrapTTL
        self.gamesTTL = gamesTTL
        self.notificationsTTL = notificationsTTL
        self.monthlyScheduleTTL = monthlyScheduleTTL
        self.diskCacheDirectory = diskCacheDirectory
    }

    nonisolated static let `default` = RepositoryCacheConfiguration(
        bootstrapTTL: 15,
        gamesTTL: 12,
        notificationsTTL: 20,
        monthlyScheduleTTL: 60 * 60 * 24,
        diskCacheDirectory: nil
    )

    nonisolated static let supabaseStartup = RepositoryCacheConfiguration(
        bootstrapTTL: 60 * 10,
        gamesTTL: 20,
        notificationsTTL: 20,
        monthlyScheduleTTL: 60 * 60 * 24,
        diskCacheDirectory: nil
    )
}

struct RepositoryCacheEntry<Value: Sendable>: Sendable {
    let value: Value
    let timestamp: Date
}
