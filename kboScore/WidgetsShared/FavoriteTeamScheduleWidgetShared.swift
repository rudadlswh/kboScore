//
//  FavoriteTeamScheduleWidgetShared.swift
//  kboScore
//
//  Created by Codex on 4/6/26.
//

import Foundation
import os

enum FavoriteTeamScheduleWidgetShared {
    static let appGroupIdentifier = "group.com.chogm.kboScore"
    static let widgetKind = "FavoriteTeamScheduleWidgetV2"

    private static let storeFilename = "favorite-team-schedule-widget-store.json"
    private static let logger = Logger(subsystem: "com.chogm.kboScore", category: "FavoriteTeamScheduleWidgetShared")

    static func saveState(favoriteTeamID: String?, snapshot: FavoriteTeamScheduleWidgetSnapshot?) {
        let store = Store(
            favoriteTeamID: favoriteTeamID,
            snapshot: snapshot,
            updatedAt: Date()
        )
        persist(store)
    }

    static func saveFavoriteTeamID(_ value: String?) {
        var store = loadStore().store ?? Store()
        store.favoriteTeamID = value
        store.updatedAt = Date()
        persist(store)
    }

    static func loadFavoriteTeamID() -> String? {
        loadState().favoriteTeamID
    }

    static func saveSnapshot(_ snapshot: FavoriteTeamScheduleWidgetSnapshot?) {
        var store = loadStore().store ?? Store()
        store.snapshot = snapshot
        store.updatedAt = Date()
        persist(store)
    }

    static func loadSnapshot() -> FavoriteTeamScheduleWidgetSnapshot? {
        loadState().snapshot
    }

    static func loadState() -> FavoriteTeamScheduleWidgetSharedLoadState {
        let result = loadStore()
        let store = result.store
        return FavoriteTeamScheduleWidgetSharedLoadState(
            favoriteTeamID: store?.favoriteTeamID,
            snapshot: store?.snapshot,
            issue: result.issue
        )
    }

    private static func persist(_ store: Store) {
        guard let fileURL = sharedFileURL else {
            logger.error("Widget store write skipped: App Group container unavailable")
            return
        }

        guard let encoded = encode(store) else {
            return
        }

        do {
            try encoded.write(to: fileURL, options: .atomic)
            logger.log(
                "Widget store write success path=\(fileURL.path, privacy: .public) favoriteTeamID=\(store.favoriteTeamID ?? "nil", privacy: .public) snapshot=\(store.snapshot == nil ? "nil" : "present", privacy: .public)"
            )
        } catch {
            logger.error("Widget store write failed path=\(fileURL.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private static func loadStore() -> StoreLoadResult {
        guard let fileURL = sharedFileURL else {
            logger.error("Widget store read failed: App Group container unavailable")
            return StoreLoadResult(store: nil, issue: .appGroupUnavailable)
        }

        logger.log("Widget store container resolved path=\(fileURL.path, privacy: .public)")

        do {
            let data = try Data(contentsOf: fileURL)
            logger.log("Widget store read success path=\(fileURL.path, privacy: .public) bytes=\(data.count)")
            let store = try JSONDecoder().decode(Store.self, from: data)
            logger.log(
                "Widget store decode success favoriteTeamID=\(store.favoriteTeamID ?? "nil", privacy: .public) snapshot=\(store.snapshot == nil ? "nil" : "present", privacy: .public)"
            )
            return StoreLoadResult(store: store, issue: nil)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            logger.log("Widget store read result: no shared file path=\(fileURL.path, privacy: .public)")
            return StoreLoadResult(store: nil, issue: .noSharedFile)
        } catch let error as DecodingError {
            logger.error("Widget store decode failed path=\(fileURL.path, privacy: .public) error=\(String(describing: error), privacy: .public)")
            return StoreLoadResult(store: nil, issue: .fileDecodeFailed)
        } catch {
            logger.error("Widget store read failed path=\(fileURL.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return StoreLoadResult(store: nil, issue: .fileReadFailed)
        }
    }

    private static var sharedFileURL: URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            logger.error("App Group container resolution failed identifier=\(appGroupIdentifier, privacy: .public)")
            return nil
        }
        logger.log("App Group container resolved identifier=\(appGroupIdentifier, privacy: .public) path=\(containerURL.path, privacy: .public)")
        return containerURL.appendingPathComponent(storeFilename, isDirectory: false)
    }

    private static func encode(_ store: Store) -> Data? {
        do {
            return try JSONEncoder().encode(store)
        } catch {
            logger.error("Failed encoding widget store: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

struct FavoriteTeamScheduleWidgetSharedLoadState: Sendable {
    let favoriteTeamID: String?
    let snapshot: FavoriteTeamScheduleWidgetSnapshot?
    let issue: FavoriteTeamScheduleWidgetSharedLoadIssue?
}

enum FavoriteTeamScheduleWidgetSharedLoadIssue: String, Sendable {
    case appGroupUnavailable
    case noSharedFile
    case fileReadFailed
    case fileDecodeFailed
}

private extension FavoriteTeamScheduleWidgetShared {
    typealias LoadIssue = FavoriteTeamScheduleWidgetSharedLoadIssue

    struct Store: Codable {
        var favoriteTeamID: String?
        var snapshot: FavoriteTeamScheduleWidgetSnapshot?
        var updatedAt: Date?
    }

    struct StoreLoadResult {
        let store: Store?
        let issue: LoadIssue?
    }
}

enum FavoriteTeamScheduleWidgetSnapshotState: String, Codable, Sendable {
    case ready
    case emptySchedule
}

enum FavoriteTeamScheduleWidgetGameStatus: String, Codable, Sendable {
    case upcoming
    case live
    case final
    case rainDelay
    case cancelled
}

enum FavoriteTeamScheduleWidgetTeamResult: String, Codable, Sendable {
    case win
    case loss
    case tie
}

struct FavoriteTeamScheduleWidgetSnapshot: Codable, Hashable, Sendable {
    let generatedAt: Date
    let refreshAfter: Date
    let teamID: String
    let teamName: String
    let teamShortName: String
    let displayedMonth: Date
    let monthTitle: String
    let monthSummaryText: String
    let state: FavoriteTeamScheduleWidgetSnapshotState
    let days: [Day]

    struct Day: Codable, Hashable, Sendable, Identifiable {
        let date: Date
        let isInDisplayedMonth: Bool
        let isToday: Bool
        let gameCount: Int
        let dominantStatus: FavoriteTeamScheduleWidgetGameStatus?
        let opponentTeamID: String?
        let favoriteTeamIsHome: Bool?
        let favoriteTeamResult: FavoriteTeamScheduleWidgetTeamResult?

        var id: Date { date }
    }
}
