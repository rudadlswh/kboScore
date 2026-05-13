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
        case .live, .rainDelay:
            [.overview, .preview]
        case .final, .cancelled:
            [.overview, .review]
        }
    }
}

@MainActor
@Observable
final class GameDetailScreenModel {
    private static let failedBoxscoreCooldown: TimeInterval = 30
    private static var inFlightBoxscoreTasks: [String: Task<GameBoxscoreResponse?, Never>] = [:]
    private static var recentFailedBoxscoreFetches: [String: Date] = [:]
    private static var cachedBoxscores: [String: GameBoxscoreResponse] = [:]

    private let fetchDetail: @Sendable (GameDetail) async throws -> GameCenterDetailPayload?
    private let boxscoreClient: any GameBoxscoreFetching
    private var lastLoadedGameKey: String?
    private var lastLoadedBoxscoreGameID: String?
    private var activeBoxscoreGameID: String?
    private var boxscoreLoadTask: Task<Void, Never>?

    var selectedSection: GameDetailSection = .overview
    var detail: GameCenterDetailPayload?
    var boxscore: GameBoxscoreResponse?
    var isLoading = false
    var errorMessage: String?
    var boxscoreErrorMessage: String?
    var hasAttemptedLoad = false

    init(
        client: OfficialKBOGameCenterClient? = nil,
        boxscoreClient: (any GameBoxscoreFetching)? = nil,
        fetchDetail: (@Sendable (GameDetail) async throws -> GameCenterDetailPayload?)? = nil
    ) {
        let resolvedClient = client ?? OfficialKBOGameCenterClient()
        self.fetchDetail = fetchDetail ?? { game in
            try await resolvedClient.fetchDetail(for: game)
        }
        self.boxscoreClient = boxscoreClient ?? GameBoxscoreClientFactory.makeAppClient()
    }

    func syncSelection(for status: GameStatus) {
        let availableSections = GameDetailSection.availableSections(for: status)
        guard availableSections.contains(selectedSection) == false else { return }
        selectedSection = availableSections.contains(.preview) ? .preview : .review
    }

    func load(for game: GameDetail, forceRefresh: Bool = false) async {
        let gameKey = [
            game.id.uuidString,
            game.officialGameCenterID ?? "",
            game.publicGameID ?? "",
            game.status.rawValue
        ].joined(separator: "::")
        guard forceRefresh || lastLoadedGameKey != gameKey else { return }

        isLoading = true
        errorMessage = nil
        hasAttemptedLoad = true

        scheduleBoxscoreLoadIfNeeded(for: game, forceRefresh: forceRefresh)

        do {
            detail = try await fetchDetail(game)
            lastLoadedGameKey = gameKey
        } catch {
            detail = nil
            errorMessage = "경기 상태와 스코어는 현재 데이터로 표시하고 있습니다."
        }

        isLoading = false
    }

    private func scheduleBoxscoreLoadIfNeeded(for game: GameDetail, forceRefresh: Bool) {
        guard game.status == .final,
              let publicGameID = game.publicGameID?.nilIfBlank else {
            activeBoxscoreGameID = nil
            return
        }
        activeBoxscoreGameID = publicGameID
        let boxscoreCacheKey = "\(publicGameID)::\(boxscoreClient.cacheIdentity)"
        if forceRefresh == false, lastLoadedBoxscoreGameID == boxscoreCacheKey {
            return
        }
        if forceRefresh == false, let cached = Self.cachedBoxscores[boxscoreCacheKey] {
            boxscore = cached
            lastLoadedBoxscoreGameID = boxscoreCacheKey
            return
        }
        if forceRefresh == false,
           let failedAt = Self.recentFailedBoxscoreFetches[boxscoreCacheKey],
           Date().timeIntervalSince(failedAt) < Self.failedBoxscoreCooldown {
            boxscoreErrorMessage = "박스스코어 기록은 현재 데이터로 표시하고 있습니다."
            return
        }

        boxscoreLoadTask?.cancel()
        boxscoreLoadTask = Task { [weak self] in
            await self?.loadBoxscoreIfNeeded(gameID: publicGameID, cacheKey: boxscoreCacheKey, forceRefresh: forceRefresh)
        }
    }

    private func loadBoxscoreIfNeeded(gameID publicGameID: String, cacheKey: String, forceRefresh: Bool) async {
        boxscoreErrorMessage = nil
        let task: Task<GameBoxscoreResponse?, Never>
        if forceRefresh == false, let inFlight = Self.inFlightBoxscoreTasks[cacheKey] {
            task = inFlight
        } else {
            let client = boxscoreClient
            task = Task.detached(priority: .utility) { () -> GameBoxscoreResponse? in
                do {
                    return try await client.fetchGameBoxscore(gameId: publicGameID)
                } catch {
                    #if DEBUG
                    print("[GameBoxscore] fetch failed gameId=\(publicGameID) error=\(error)")
                    #endif
                    return nil
                }
            }
            Self.inFlightBoxscoreTasks[cacheKey] = task
        }
        let fetchedBoxscore = await task.value
        Self.inFlightBoxscoreTasks[cacheKey] = nil
        lastLoadedBoxscoreGameID = cacheKey
        guard activeBoxscoreGameID == publicGameID else { return }

        if let fetchedBoxscore {
            Self.cachedBoxscores[cacheKey] = fetchedBoxscore
            Self.recentFailedBoxscoreFetches[cacheKey] = nil
            boxscore = fetchedBoxscore
        } else {
            Self.recentFailedBoxscoreFetches[cacheKey] = Date()
            boxscoreErrorMessage = "박스스코어 기록은 현재 데이터로 표시하고 있습니다."
        }
    }

    func waitForBoxscoreLoadForTesting() async {
        await boxscoreLoadTask?.value
    }

    static func resetBoxscoreLoadingCacheForTesting() {
        inFlightBoxscoreTasks.removeAll()
        recentFailedBoxscoreFetches.removeAll()
        cachedBoxscores.removeAll()
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
    private var baseRunnerDisplayResolver = BaseRunnerDisplayResolver()

    let stableIdentity: String
    @Published var game: GameDetail?
    @Published private(set) var baseRunnerDisplay: BaseRunnerDisplayResolution = .empty

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
        if let initialGame {
            baseRunnerDisplay = baseRunnerDisplayResolver.resolve(gameIdentity: stableIdentity, game: initialGame)
        }
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
        baseRunnerDisplay = baseRunnerDisplayResolver.resolve(gameIdentity: stableIdentity, game: initialGame)
        #if DEBUG
        print("GameDetailViewModel init stableIdentity=\(stableIdentity)")
        #endif
    }

    func configureInitialGameIfNeeded(_ initialGame: GameDetail?) {
        guard game == nil, let initialGame else { return }
        game = initialGame
        baseRunnerDisplay = baseRunnerDisplayResolver.resolve(gameIdentity: stableIdentity, game: initialGame)
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
        baseRunnerDisplay = baseRunnerDisplayResolver.resolve(gameIdentity: stableIdentity, game: fetched)
        if changed {
            game = fetched
        }
        #if DEBUG
        print("GameDetailFetch success changed=\(changed)")
        #endif
    }
}

struct BaseRunnerDisplayResolution: Equatable, Sendable {
    static let empty = BaseRunnerDisplayResolution(
        runners: GameBaseRunners(first: nil, second: nil, third: nil),
        source: "empty"
    )

    let runners: GameBaseRunners
    let source: String
}

struct BaseRunnerDisplayResolver: Sendable {
    private static let fallbackRunnerName = "주자"
    private var statesByGameIdentity: [String: CachedBaseRunnerNames] = [:]
    private var activeGameIdentity: String?

    mutating func resolve(gameIdentity: String, game: GameDetail) -> BaseRunnerDisplayResolution {
        if let activeGameIdentity, activeGameIdentity != gameIdentity {
            statesByGameIdentity[activeGameIdentity] = nil
        }
        activeGameIdentity = gameIdentity

        let previous = statesByGameIdentity[gameIdentity]
        let bases = game.bases ?? .empty
        let snapshot = game.baseRunners
        var sources = Set<String>()

        let first = resolveBase(
            base: "first",
            occupied: bases.first,
            snapshotName: snapshot?.first,
            previousName: previous?.runners.first,
            sources: &sources
        )
        let second = resolveBase(
            base: "second",
            occupied: bases.second,
            snapshotName: snapshot?.second,
            previousName: previous?.runners.second,
            sources: &sources
        )
        let third = resolveBase(
            base: "third",
            occupied: bases.third,
            snapshotName: snapshot?.third,
            previousName: previous?.runners.third,
            sources: &sources
        )

        let display = GameBaseRunners(
            first: first.displayName,
            second: second.displayName,
            third: third.displayName
        )
        let cached = CachedBaseRunnerNames(
            runners: GameBaseRunners(
                first: first.realName,
                second: second.realName,
                third: third.realName
            )
        )
        statesByGameIdentity[gameIdentity] = cached
        let source = sourceSummary(sources)

        #if DEBUG
        print("[BaseRunners] resolved display first=\(display.first ?? "<hidden>") second=\(display.second ?? "<hidden>") third=\(display.third ?? "<hidden>") source=\(source)")
        #endif

        return BaseRunnerDisplayResolution(runners: display, source: source)
    }

    private func resolveBase(
        base: String,
        occupied: Bool,
        snapshotName: String?,
        previousName: String?,
        sources: inout Set<String>
    ) -> ResolvedBaseRunnerDisplay {
        guard occupied else {
            if clean(previousName) != nil {
                #if DEBUG
                print("[BaseRunners] cleared name base=\(base) reason=baseEmpty")
                #endif
            }
            return .empty
        }

        if let snapshotName = clean(snapshotName) {
            sources.insert("snapshot")
            return ResolvedBaseRunnerDisplay(displayName: snapshotName, realName: snapshotName)
        }

        if let previousName = clean(previousName) {
            sources.insert("carryForward")
            return ResolvedBaseRunnerDisplay(displayName: previousName, realName: previousName)
        }

        sources.insert("fallback")
        return ResolvedBaseRunnerDisplay(displayName: Self.fallbackRunnerName, realName: nil)
    }

    private func sourceSummary(_ sources: Set<String>) -> String {
        let ordered = ["snapshot", "carryForward", "fallback"].filter { sources.contains($0) }
        return ordered.isEmpty ? "empty" : ordered.joined(separator: "+")
    }

    private func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.isEmpty == false else {
            return nil
        }

        guard trimmed != Self.fallbackRunnerName else {
            return nil
        }

        return trimmed
    }

    private struct CachedBaseRunnerNames: Sendable {
        let runners: GameBaseRunners
    }

    private struct ResolvedBaseRunnerDisplay: Sendable {
        static let empty = ResolvedBaseRunnerDisplay(displayName: nil, realName: nil)

        let displayName: String?
        let realName: String?
    }
}
