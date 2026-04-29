//
//  GameDetailScreenModel.swift
//  kboScore
//
//  Created by Codex on 4/8/26.
//

import Foundation
import Combine
import Observation

enum GameDetailSection: String, CaseIterable, Identifiable {
    case overview = "개요"
    case review = "리뷰"
    case preview = "프리뷰"

    var id: String { rawValue }

    static func availableSections(for status: GameStatus) -> [GameDetailSection] {
        switch status {
        case .upcoming:
            [.overview, .preview]
        case .live, .final, .rainDelay, .cancelled:
            [.overview, .review]
        }
    }
}

@MainActor
@Observable
final class GameDetailScreenModel {
    private let client: OfficialKBOGameCenterClient
    private var lastLoadedGameKey: String?

    var selectedSection: GameDetailSection = .overview
    var detail: GameCenterDetailPayload?
    var isLoading = false
    var errorMessage: String?
    var hasAttemptedLoad = false

    init(client: OfficialKBOGameCenterClient? = nil) {
        self.client = client ?? OfficialKBOGameCenterClient()
    }

    func syncSelection(for status: GameStatus) {
        let availableSections = GameDetailSection.availableSections(for: status)
        guard availableSections.contains(selectedSection) == false else { return }
        selectedSection = availableSections.contains(.preview) ? .preview : .review
    }

    func load(for game: GameDetail, forceRefresh: Bool = false) async {
        let gameKey = [game.id.uuidString, game.officialGameCenterID ?? ""].joined(separator: "::")
        guard forceRefresh || lastLoadedGameKey != gameKey else { return }

        isLoading = true
        errorMessage = nil
        hasAttemptedLoad = true

        do {
            detail = try await client.fetchDetail(for: game)
            lastLoadedGameKey = gameKey
        } catch {
            detail = nil
            errorMessage = "경기 상태와 스코어는 현재 데이터로 표시하고 있습니다."
        }

        isLoading = false
    }
}

@MainActor
final class GameDetailViewModel: ObservableObject {
    private static let automaticRefreshInterval: TimeInterval = 12
    private static let automaticRefreshStableIdentityThrottle: TimeInterval = 8
    private static var inFlightRefreshesByStableIdentity: [String: Task<GameDetail?, Never>] = [:]
    private static var recentAutomaticRefreshesByStableIdentity: [String: (date: Date, game: GameDetail)] = [:]
    static let livePollingIntervalNanoseconds: UInt64 = 12_000_000_000

    private let requestedIdentity: String
    private var lastAutomaticRefreshAt: Date?

    let stableIdentity: String
    @Published var game: GameDetail?

    var shouldAutoRefreshLiveGame: Bool {
        game?.status.isLiveLike == true
    }

    var liveRefreshTaskID: String {
        shouldAutoRefreshLiveGame ? "live:\(stableIdentity)" : "idle:\(stableIdentity)"
    }

    init(
        gameIdentity: String,
        initialGame: GameDetail? = nil
    ) {
        self.requestedIdentity = gameIdentity
        self.game = initialGame
        self.stableIdentity = initialGame?.stableDetailIdentity ?? gameIdentity
        #if DEBUG
        print("GameDetailViewModel init stableIdentity=\(stableIdentity)")
        #endif
    }

    init(
        stableIdentity: String,
        requestedIdentity: String,
        initialGame: GameDetail
    ) {
        self.requestedIdentity = requestedIdentity
        self.game = initialGame
        self.stableIdentity = stableIdentity
        #if DEBUG
        print("GameDetailViewModel init stableIdentity=\(stableIdentity)")
        #endif
    }

    func configureInitialGameIfNeeded(_ initialGame: GameDetail?) {
        guard game == nil, let initialGame else { return }
        game = initialGame
    }

    @discardableResult
    func refreshIfNeeded(
        appModel: AppModel,
        manual: Bool = false,
        bypassAutomaticThrottle: Bool = false
    ) async -> GameDetail? {
        if game == nil {
            configureInitialGameIfNeeded(appModel.initialGameSnapshot(for: requestedIdentity))
        }
        guard let currentGame = game else { return nil }

        if manual == false, bypassAutomaticThrottle == false {
            if let lastAutomaticRefreshAt,
               Date().timeIntervalSince(lastAutomaticRefreshAt) < Self.automaticRefreshInterval {
                return game
            }

            if let recentRefresh = Self.recentAutomaticRefreshesByStableIdentity[stableIdentity],
               Date().timeIntervalSince(recentRefresh.date) < Self.automaticRefreshStableIdentityThrottle {
                if recentRefresh.game != game {
                    apply(recentRefresh.game)
                }
                #if DEBUG
                print("GameDetailFetch skipped recent stableIdentity=\(stableIdentity)")
                #endif
                return game
            }
        }

        if let inFlightRefresh = Self.inFlightRefreshesByStableIdentity[stableIdentity] {
            #if DEBUG
            print("GameDetailFetch deduped awaitExistingFetch stableIdentity=\(stableIdentity)")
            #endif
            if let fetched = await inFlightRefresh.value {
                apply(fetched)
                return fetched
            }
            return game
        }

        if manual == false {
            lastAutomaticRefreshAt = Date()
        }

        #if DEBUG
        print("GameDetailFetch start stableIdentity=\(stableIdentity)")
        #endif
        let identity = stableIdentity
        let task = Task { @MainActor in
            await appModel.refreshGameDetail(for: identity, forceRefresh: manual)
        }
        Self.inFlightRefreshesByStableIdentity[stableIdentity] = task
        let fetched = await task.value
        Self.inFlightRefreshesByStableIdentity[stableIdentity] = nil
        if manual == false {
            Self.recentAutomaticRefreshesByStableIdentity[stableIdentity] = (Date(), fetched ?? currentGame)
        }
        if let fetched {
            apply(fetched)
        }
        return fetched ?? game
    }

    private func apply(_ fetched: GameDetail) {
        let changed = fetched != game
        if changed {
            game = fetched
        }
        #if DEBUG
        print("GameDetailFetch success changed=\(changed)")
        #endif
    }
}
