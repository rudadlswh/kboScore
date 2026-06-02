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

nonisolated private enum GameDetailPayloadLoadResult: Sendable {
    case success(GameCenterDetailPayload?)
    case failure
}

@MainActor
@Observable
final class GameDetailScreenModel {
    private static let failedBoxscoreCooldown: TimeInterval = 30
    private static let officialFallbackCacheTTL: TimeInterval = 60
    private static let officialFallbackFailureCooldown: TimeInterval = 30
    private static var inFlightBoxscoreTasks: [String: Task<GameBoxscoreResponse?, Never>] = [:]
    private static var recentFailedBoxscoreFetches: [String: Date] = [:]
    private static var cachedBoxscores: [String: GameBoxscoreResponse] = [:]
    private static var inFlightOfficialFallbackTasks: [String: Task<GameCenterReview?, Never>] = [:]
    private static var cachedOfficialFallbackReviews: [String: (date: Date, review: GameCenterReview)] = [:]
    private static var recentFailedOfficialFallbacks: [String: Date] = [:]

    private let fetchDetail: @Sendable (GameDetail) async throws -> GameCenterDetailPayload?
    private let fetchOfficialRecordFallback: @Sendable (GameDetail) async throws -> GameCenterReview?
    private let boxscoreClient: any GameBoxscoreFetching
    private var lastLoadedGameKey: String?
    private var activeDetailLoadKey: String?
    private var detailLoadTask: Task<GameDetailPayloadLoadResult, Never>?
    private var lastLoadedBoxscoreGameID: String?
    private var lastLoadedOfficialFallbackGameKey: String?
    private var currentGame: GameDetail?
    private var cachedLineScoreGameKey: String?
    private var activeBoxscoreGameID: String?
    private var activeOfficialFallbackGameKey: String?
    private var boxscoreLoadTask: Task<Void, Never>?
    private var officialFallbackLoadTask: Task<Void, Never>?

    var selectedSection: GameDetailSection = .overview
    var detail: GameCenterDetailPayload?
    var cachedLineScore: GameCenterLineScore?
    var boxscore: GameBoxscoreResponse?
    var officialFallbackReview: GameCenterReview?
    var isLoading = false
    var errorMessage: String?
    var boxscoreErrorMessage: String?
    var hasAttemptedLoad = false

    init(
        client: OfficialKBOGameCenterClient? = nil,
        boxscoreClient: (any GameBoxscoreFetching)? = nil,
        fetchDetail: (@Sendable (GameDetail) async throws -> GameCenterDetailPayload?)? = nil,
        fetchOfficialRecordFallback: (@Sendable (GameDetail) async throws -> GameCenterReview?)? = nil
    ) {
        let resolvedClient = client ?? OfficialKBOGameCenterClient()
        self.fetchDetail = fetchDetail ?? { game in
            try await resolvedClient.fetchDetail(for: game, includeRecordFallback: game.status.isLiveLike)
        }
        self.fetchOfficialRecordFallback = fetchOfficialRecordFallback ?? { game in
            try await resolvedClient.fetchRecordFallbackReview(for: game)
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
        currentGame = game

        #if DEBUG
        print("[GameDetailLive] load start id=\(game.id.uuidString) publicGameID=\(game.publicGameID ?? "<nil>") providerGameID=\(game.providerGameID ?? "<nil>") officialProviderGameID=\(game.officialProviderGameID ?? "<nil>") status=\(game.status.rawValue) forceRefresh=\(forceRefresh)")
        #endif

        isLoading = true
        errorMessage = nil
        hasAttemptedLoad = true

        officialFallbackReview = nil
        if cachedLineScoreGameKey != gameKey {
            cachedLineScore = nil
        }
        scheduleBoxscoreLoadIfNeeded(for: game, forceRefresh: forceRefresh)

        let fetchedDetail = await loadDetailPayload(for: game, gameKey: gameKey)
        detail = fetchedDetail
        if let lineScore = fetchedDetail?.lineScore {
            cachedLineScore = lineScore
            cachedLineScoreGameKey = gameKey
        }
        lastLoadedGameKey = gameKey
        if game.status.isLiveLike {
            if fetchedDetail?.review?.hasDisplayableRecords != true {
                scheduleOfficialRecordFallbackIfNeeded(for: game, forceRefresh: forceRefresh)
            }
            #if DEBUG
            print("[GameDetailLive] load result status=\(game.status.rawValue) lineScorePresent=\((fetchedDetail?.lineScore ?? cachedLineScore) != nil) liveRecordPresent=\((fetchedDetail?.review?.hasDisplayableRecords == true) || (officialFallbackReview?.hasDisplayableRecords == true))")
            #endif
        }

        isLoading = false
    }

    private func loadDetailPayload(for game: GameDetail, gameKey: String) async -> GameCenterDetailPayload? {
        let task: Task<GameDetailPayloadLoadResult, Never>
        if let inFlight = detailLoadTask, activeDetailLoadKey == gameKey {
            #if DEBUG
            print("[GameDetailLive] detail fetch deduped key=\(gameKey)")
            #endif
            task = inFlight
        } else {
            let fetchDetail = fetchDetail
            activeDetailLoadKey = gameKey
            task = Task { () -> GameDetailPayloadLoadResult in
                do {
                    return .success(try await fetchDetail(game))
                } catch {
                    #if DEBUG
                    print("[GameDetailLive] detail fetch failed key=\(gameKey) error=\(error)")
                    #endif
                    return .failure
                }
            }
            detailLoadTask = task
        }

        let result = await task.value
        if activeDetailLoadKey == gameKey {
            detailLoadTask = nil
            activeDetailLoadKey = nil
        }
        switch result {
        case .success(let payload):
            return payload
        case .failure:
            errorMessage = "경기 상태와 스코어는 현재 데이터로 표시하고 있습니다."
            return nil
        }
    }

    private func scheduleBoxscoreLoadIfNeeded(for game: GameDetail, forceRefresh: Bool) {
        guard game.status == .final,
              let publicGameID = game.publicGameID?.nilIfBlank else {
            #if DEBUG
            print("[GameBoxscore] skipped reason=notFinalOrMissingPublicID status=\(game.status.rawValue) publicGameID=\(game.publicGameID ?? "<nil>")")
            #endif
            activeBoxscoreGameID = nil
            boxscore = nil
            boxscoreErrorMessage = nil
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
            if cached.hasRecords {
                cancelOfficialFallbackLoad()
            } else {
                scheduleOfficialRecordFallbackIfNeeded(for: game, forceRefresh: forceRefresh)
            }
            return
        }
        if forceRefresh == false,
           let failedAt = Self.recentFailedBoxscoreFetches[boxscoreCacheKey],
           Date().timeIntervalSince(failedAt) < Self.failedBoxscoreCooldown {
            boxscoreErrorMessage = "박스스코어 기록은 현재 데이터로 표시하고 있습니다."
            scheduleOfficialRecordFallbackIfNeeded(for: game, forceRefresh: forceRefresh)
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
            if fetchedBoxscore.hasRecords {
                cancelOfficialFallbackLoad()
            } else if let currentGame = detailGame(publicGameID: publicGameID) {
                scheduleOfficialRecordFallbackIfNeeded(for: currentGame, forceRefresh: forceRefresh)
            }
        } else {
            Self.recentFailedBoxscoreFetches[cacheKey] = Date()
            boxscoreErrorMessage = "박스스코어 기록은 현재 데이터로 표시하고 있습니다."
            if let currentGame = detailGame(publicGameID: publicGameID) {
                scheduleOfficialRecordFallbackIfNeeded(for: currentGame, forceRefresh: forceRefresh)
            }
        }
    }

    private func scheduleOfficialRecordFallbackIfNeeded(for game: GameDetail, forceRefresh: Bool) {
        guard game.status == .final || game.status.isLiveLike else { return }
        guard boxscore?.hasRecords != true else {
            cancelOfficialFallbackLoad()
            return
        }
        let cacheKey = officialFallbackCacheKey(for: game)
        guard cacheKey.isEmpty == false else { return }
        activeOfficialFallbackGameKey = cacheKey

        if forceRefresh == false, lastLoadedOfficialFallbackGameKey == cacheKey {
            return
        }
        if forceRefresh == false,
           let cached = Self.cachedOfficialFallbackReviews[cacheKey],
           Date().timeIntervalSince(cached.date) < Self.officialFallbackCacheTTL {
            officialFallbackReview = cached.review
            lastLoadedOfficialFallbackGameKey = cacheKey
            return
        }
        if forceRefresh == false,
           let failedAt = Self.recentFailedOfficialFallbacks[cacheKey],
           Date().timeIntervalSince(failedAt) < Self.officialFallbackFailureCooldown {
            return
        }

        officialFallbackLoadTask?.cancel()
        officialFallbackLoadTask = Task { [weak self] in
            await self?.loadOfficialRecordFallbackIfNeeded(for: game, cacheKey: cacheKey, forceRefresh: forceRefresh)
        }
    }

    private func loadOfficialRecordFallbackIfNeeded(for game: GameDetail, cacheKey: String, forceRefresh: Bool) async {
        let task: Task<GameCenterReview?, Never>
        if forceRefresh == false, let inFlight = Self.inFlightOfficialFallbackTasks[cacheKey] {
            task = inFlight
        } else {
            let fetchOfficialRecordFallback = fetchOfficialRecordFallback
            task = Task.detached(priority: .utility) { () -> GameCenterReview? in
                do {
                    return try await fetchOfficialRecordFallback(game)
                } catch {
                    #if DEBUG
                    print("[GameDetailStats] officialFallback failed gameKey=\(cacheKey) error=\(error)")
                    #endif
                    return nil
                }
            }
            Self.inFlightOfficialFallbackTasks[cacheKey] = task
        }

        let fetchedReview = await task.value
        Self.inFlightOfficialFallbackTasks[cacheKey] = nil
        lastLoadedOfficialFallbackGameKey = cacheKey
        guard activeOfficialFallbackGameKey == cacheKey,
              boxscore?.hasRecords != true else { return }

        if let fetchedReview, fetchedReview.hasDisplayableRecords {
            Self.cachedOfficialFallbackReviews[cacheKey] = (Date(), fetchedReview)
            Self.recentFailedOfficialFallbacks[cacheKey] = nil
            officialFallbackReview = fetchedReview
            #if DEBUG
            print("[GameDetailLive] official record fallback success gameKey=\(cacheKey) liveRecordPresent=true")
            #endif
        } else {
            Self.recentFailedOfficialFallbacks[cacheKey] = Date()
            #if DEBUG
            print("[GameDetailLive] official record fallback empty gameKey=\(cacheKey) liveRecordPresent=false")
            #endif
        }
    }

    private func cancelOfficialFallbackLoad() {
        officialFallbackLoadTask?.cancel()
        officialFallbackLoadTask = nil
        activeOfficialFallbackGameKey = nil
        officialFallbackReview = nil
    }

    private func officialFallbackCacheKey(for game: GameDetail) -> String {
        [
            game.publicGameID?.nilIfBlank,
            game.providerGameID?.nilIfBlank,
            game.officialGameCenterID?.nilIfBlank,
            game.id.uuidString
        ]
            .compactMap { $0 }
            .joined(separator: "::")
    }

    private func detailGame(publicGameID: String) -> GameDetail? {
        guard currentGame?.publicGameID == publicGameID else { return nil }
        return currentGame
    }

    func waitForBoxscoreLoadForTesting() async {
        await boxscoreLoadTask?.value
    }

    func waitForDetailLoadForTesting() async {
        _ = await detailLoadTask?.value
    }

    func waitForOfficialFallbackLoadForTesting() async {
        await officialFallbackLoadTask?.value
    }

    static func resetBoxscoreLoadingCacheForTesting() {
        inFlightBoxscoreTasks.removeAll()
        recentFailedBoxscoreFetches.removeAll()
        cachedBoxscores.removeAll()
        inFlightOfficialFallbackTasks.removeAll()
        cachedOfficialFallbackReviews.removeAll()
        recentFailedOfficialFallbacks.removeAll()
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
    @Published private(set) var isResolvingInitialGame: Bool
    @Published private(set) var hasAttemptedInitialResolution: Bool
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
        self.isResolvingInitialGame = initialGame == nil
        self.hasAttemptedInitialResolution = initialGame != nil
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
        self.isResolvingInitialGame = false
        self.hasAttemptedInitialResolution = true
        baseRunnerDisplay = baseRunnerDisplayResolver.resolve(gameIdentity: stableIdentity, game: initialGame)
        #if DEBUG
        print("GameDetailViewModel init stableIdentity=\(stableIdentity)")
        #endif
    }

    func configureInitialGameIfNeeded(_ initialGame: GameDetail?) {
        guard game == nil, let initialGame else { return }
        game = initialGame
        isResolvingInitialGame = false
        hasAttemptedInitialResolution = true
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
        if game == nil {
            isResolvingInitialGame = true
            defer {
                isResolvingInitialGame = false
                hasAttemptedInitialResolution = true
            }
            let fetched = await appModel.refreshGameDetail(for: requestedIdentity, forceRefresh: manual)
            if let fetched {
                apply(fetched)
                return fetched
            }
            return nil
        }
        guard let currentGame = game else { return nil }
        let refreshIdentity = requestedIdentity

        if manual == false, bypassAutomaticThrottle == false {
            if let lastAutomaticRefreshAt,
               Date().timeIntervalSince(lastAutomaticRefreshAt) < Self.automaticRefreshInterval {
                return game
            }

            if let recentRefresh = Self.recentAutomaticRefreshesByStableIdentity[refreshIdentity],
               Date().timeIntervalSince(recentRefresh.date) < Self.automaticRefreshStableIdentityThrottle {
                if recentRefresh.game != game {
                    apply(recentRefresh.game)
                }
                #if DEBUG
                print("GameDetailFetch skipped recent stableIdentity=\(refreshIdentity)")
                #endif
                return game
            }
        }

        if let inFlightRefresh = Self.inFlightRefreshesByStableIdentity[refreshIdentity] {
            #if DEBUG
            print("GameDetailFetch deduped awaitExistingFetch stableIdentity=\(refreshIdentity)")
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
        print("GameDetailFetch start stableIdentity=\(refreshIdentity)")
        #endif
        let task = Task { @MainActor in
            await appModel.refreshGameDetail(for: refreshIdentity, forceRefresh: manual)
        }
        Self.inFlightRefreshesByStableIdentity[refreshIdentity] = task
        let fetched = await task.value
        Self.inFlightRefreshesByStableIdentity[refreshIdentity] = nil
        if manual == false {
            Self.recentAutomaticRefreshesByStableIdentity[refreshIdentity] = (Date(), fetched ?? currentGame)
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
        print("[BaseRunners] resolved occupancy first=\(display.first == nil ? "empty" : "occupied(no-name)") second=\(display.second == nil ? "empty" : "occupied(no-name)") third=\(display.third == nil ? "empty" : "occupied(no-name)") source=\(source)")
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
