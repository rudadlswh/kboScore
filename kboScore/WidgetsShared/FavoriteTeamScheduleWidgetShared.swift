//
//  FavoriteTeamScheduleWidgetShared.swift
//  kboScore
//  기능 설명: 앱과 위젯 확장 사이에서 공유하는 마이팀 일정 스냅샷 모델을 정의합니다.
//  앱 밖에서도 마이팀 경기 흐름을 이어서 볼 수 있도록 Live Activity와 위젯용 스냅샷을 분리합니다.
//  확장 프로세스, App Group 저장소, 푸시 토큰, 시스템 권한 상태에 따라 갱신이 실패할 수 있습니다.
//  TODO : 실기기 권한 상태별 동작과 종료 조건을 더 촘촘히 검증합니다.
//
//  Created by Codex on 4/6/26.
//

import Foundation
import os

// WidgetStoreFileSecurity 열거형는 WidgetStoreFileSecurity 타입의 역할과 값을 정의합니다.
private enum WidgetStoreFileSecurity {
    nonisolated static let protectionType = FileProtectionType.completeUntilFirstUserAuthentication

    // applyProtection 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    nonisolated static func applyProtection(
        to fileURL: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.setAttributes(
            [.protectionKey: protectionType],
            ofItemAtPath: fileURL.path
        )
    }
}

// FavoriteTeamScheduleWidgetShared 열거형는 FavoriteTeamScheduleWidgetShared 타입의 역할과 값을 정의합니다.
enum FavoriteTeamScheduleWidgetShared {
    static let appGroupIdentifier = "group.com.chogm.kboScore"
    static let widgetKind = "FavoriteTeamScheduleWidgetV2"

    private static let storeFilename = "favorite-team-schedule-widget-store.json"
    private static let logger = Logger(subsystem: "com.chogm.kboScore", category: "FavoriteTeamScheduleWidgetShared")

    // saveState 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    static func saveState(favoriteTeamID: String?, snapshot: FavoriteTeamScheduleWidgetSnapshot?) {
        if let existingStore = loadStore().store,
           existingStore.favoriteTeamID == favoriteTeamID,
           existingStore.snapshot == snapshot {
            return
        }
        let store = Store(
            favoriteTeamID: favoriteTeamID,
            snapshot: snapshot,
            updatedAt: Date()
        )
        persist(store)
    }

    // saveFavoriteTeamID 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    static func saveFavoriteTeamID(_ value: String?) {
        var store = loadStore().store ?? Store()
        guard store.favoriteTeamID != value else { return }
        store.favoriteTeamID = value
        store.updatedAt = Date()
        persist(store)
    }

    // loadFavoriteTeamID 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    static func loadFavoriteTeamID() -> String? {
        loadState().favoriteTeamID
    }

    // saveSnapshot 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    static func saveSnapshot(_ snapshot: FavoriteTeamScheduleWidgetSnapshot?) {
        var store = loadStore().store ?? Store()
        guard store.snapshot != snapshot else { return }
        store.snapshot = snapshot
        store.updatedAt = Date()
        persist(store)
    }

    // loadSnapshot 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    static func loadSnapshot() -> FavoriteTeamScheduleWidgetSnapshot? {
        loadState().snapshot
    }

    // loadState 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    static func loadState() -> FavoriteTeamScheduleWidgetSharedLoadState {
        let result = loadStore()
        let store = result.store
        return FavoriteTeamScheduleWidgetSharedLoadState(
            favoriteTeamID: store?.favoriteTeamID,
            snapshot: store?.snapshot,
            issue: result.issue
        )
    }

    // persist 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
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
            try WidgetStoreFileSecurity.applyProtection(to: fileURL)
            logger.log(
                "Widget store write success snapshot=\(store.snapshot == nil ? "nil" : "present", privacy: .public)"
            )
        } catch {
            logger.error("Widget store write failed error=\(error.localizedDescription, privacy: .private)")
        }
    }

    // loadStore 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    private static func loadStore() -> StoreLoadResult {
        guard let fileURL = sharedFileURL else {
            logger.error("Widget store read failed: App Group container unavailable")
            return StoreLoadResult(store: nil, issue: .appGroupUnavailable)
        }

        logger.log("Widget store container resolved")

        do {
            let data = try Data(contentsOf: fileURL)
            logger.log("Widget store read success bytes=\(data.count)")
            let store = try JSONDecoder().decode(Store.self, from: data)
            logger.log(
                "Widget store decode success snapshot=\(store.snapshot == nil ? "nil" : "present", privacy: .public)"
            )
            return StoreLoadResult(store: store, issue: nil)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            logger.log("Widget store read result: no shared file")
            return StoreLoadResult(store: nil, issue: .noSharedFile)
        } catch let error as DecodingError {
            logger.error("Widget store decode failed error=\(String(describing: error), privacy: .private)")
            return StoreLoadResult(store: nil, issue: .fileDecodeFailed)
        } catch {
            logger.error("Widget store read failed error=\(error.localizedDescription, privacy: .private)")
            return StoreLoadResult(store: nil, issue: .fileReadFailed)
        }
    }

    private static var sharedFileURL: URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            logger.error("App Group container resolution failed")
            return nil
        }
        logger.log("App Group container resolved")
        return containerURL.appendingPathComponent(storeFilename, isDirectory: false)
    }

    // encode 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    private static func encode(_ store: Store) -> Data? {
        do {
            return try JSONEncoder().encode(store)
        } catch {
            logger.error("Failed encoding widget store error=\(error.localizedDescription, privacy: .private)")
            return nil
        }
    }
}

// FavoriteTeamScheduleWidgetSharedLoadState 구조체는 화면이나 도메인 흐름에서 사용하는 상태 값을 표현합니다.
struct FavoriteTeamScheduleWidgetSharedLoadState: Sendable {
    let favoriteTeamID: String?
    let snapshot: FavoriteTeamScheduleWidgetSnapshot?
    let issue: FavoriteTeamScheduleWidgetSharedLoadIssue?
}

// FavoriteTeamScheduleWidgetSharedLoadIssue 열거형는 FavoriteTeamScheduleWidgetSharedLoadIssue 타입의 역할과 값을 정의합니다.
enum FavoriteTeamScheduleWidgetSharedLoadIssue: String, Sendable {
    case appGroupUnavailable
    case noSharedFile
    case fileReadFailed
    case fileDecodeFailed
}

enum FavoriteTeamScheduleWidgetSnapshotMonthPolicy {
    nonisolated static func monthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = widgetCalendar()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = widgetTimeZone()
        formatter.dateFormat = "yyyyMM"
        return formatter.string(from: date)
    }

    nonisolated static func isCurrentMonth(
        snapshot: FavoriteTeamScheduleWidgetSnapshot,
        now: Date
    ) -> Bool {
        monthKey(for: snapshot.displayedMonth) == monthKey(for: now)
    }

    private nonisolated static func widgetCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = widgetTimeZone()
        return calendar
    }

    private nonisolated static func widgetTimeZone() -> TimeZone {
        TimeZone(identifier: "Asia/Seoul") ?? .current
    }
}

private extension FavoriteTeamScheduleWidgetShared {
    typealias LoadIssue = FavoriteTeamScheduleWidgetSharedLoadIssue

// Store 구조체는 Store 타입의 역할과 값을 정의합니다.
    struct Store: Codable {
        var favoriteTeamID: String?
        var snapshot: FavoriteTeamScheduleWidgetSnapshot?
        var updatedAt: Date?
    }

// StoreLoadResult 구조체는 StoreLoadResult 타입의 역할과 값을 정의합니다.
    struct StoreLoadResult {
        let store: Store?
        let issue: LoadIssue?
    }
}

// FavoriteTeamScheduleWidgetSnapshotState 열거형는 화면이나 도메인 흐름에서 사용하는 상태 값을 표현합니다.
enum FavoriteTeamScheduleWidgetSnapshotState: String, Codable, Sendable {
    case ready
    case emptySchedule
}

// FavoriteTeamScheduleWidgetGameStatus 열거형는 처리 단계나 경기 상태를 구분합니다.
enum FavoriteTeamScheduleWidgetGameStatus: String, Codable, Sendable {
    case upcoming
    case live
    case final
    case rainDelay
    case cancelled
}

// FavoriteTeamScheduleWidgetTeamResult 열거형는 FavoriteTeamScheduleWidgetTeamResult 타입의 역할과 값을 정의합니다.
enum FavoriteTeamScheduleWidgetTeamResult: String, Codable, Sendable {
    case win
    case loss
    case tie
}

// FavoriteTeamScheduleWidgetSnapshot 구조체는 FavoriteTeamScheduleWidgetSnapshot 타입의 역할과 값을 정의합니다.
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

// Day 구조체는 Day 타입의 역할과 값을 정의합니다.
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
