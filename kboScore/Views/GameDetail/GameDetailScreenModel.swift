//
//  GameDetailScreenModel.swift
//  kboScore
//  기능 설명: 경기 상세 화면의 데이터 로딩, 갱신, 표시 상태를 관리합니다.
//  사용자가 경기 상태와 설정을 빠르게 이해하도록 도메인 상태를 화면 구조에 직접 매핑합니다.
//  SwiftUI 상태 갱신, 접근성, 작은 화면 레이아웃에서 정보가 겹치지 않도록 표시 조건을 제한합니다.
//  TODO : 반복되는 화면 조각은 재사용 가능한 컴포넌트로 분리하고 미리보기 케이스를 보강합니다.
//
//  Created by Codex on 4/8/26.
//

import Foundation
import Combine
import Observation

// GameDetailSection 열거형는 GameDetailSection 타입의 역할과 값을 정의합니다.
enum GameDetailSection: String, CaseIterable, Identifiable {
    case overview = "개요"

    var id: String { rawValue }

    // availableSections 메서드는 이 타입의 주요 동작을 수행합니다.
    static func availableSections(for _: GameStatus) -> [GameDetailSection] {
        [.overview]
    }
}

// GameDetailOverviewContentKind 열거형는 도메인 값을 종류별로 구분합니다.
nonisolated enum GameDetailOverviewContentKind: Equatable, Sendable {
    case preview
    case overview

    // contentKind 메서드는 이 타입의 주요 동작을 수행합니다.
    static func contentKind(for status: GameStatus) -> GameDetailOverviewContentKind {
        switch status {
        case .upcoming:
            .preview
        case .live, .rainDelay, .final, .cancelled:
            .overview
        }
    }
}

// GameDetailPayloadLoadResult 열거형는 GameDetailPayloadLoadResult 타입의 역할과 값을 정의합니다.
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
    private let fetchDatabaseRecordReview: (@Sendable (GameDetail) async -> GameCenterReview?)?
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
    private var databaseRecordLoadTask: Task<Void, Never>?
    private var activeDatabaseRecordGameKey: String?
    private var databaseRecordMergeInFlightGameIdentity: String?

    var detail: GameCenterDetailPayload?
    var cachedLineScore: GameCenterLineScore?
    var boxscore: GameBoxscoreResponse?
    var databaseRecordReview: GameCenterReview?
    var officialFallbackReview: GameCenterReview?
    var isLoading = false
    var errorMessage: String?
    var boxscoreErrorMessage: String?
    var hasAttemptedLoad = false

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(
        client: OfficialKBOGameCenterClient? = nil,
        boxscoreClient: (any GameBoxscoreFetching)? = nil,
        fetchDetail: (@Sendable (GameDetail) async throws -> GameCenterDetailPayload?)? = nil,
        fetchDatabaseRecordReview: (@Sendable (GameDetail) async -> GameCenterReview?)? = nil,
        fetchOfficialRecordFallback: (@Sendable (GameDetail) async throws -> GameCenterReview?)? = nil
    ) {
        let resolvedClient = client ?? OfficialKBOGameCenterClient()
        self.fetchDetail = fetchDetail ?? { game in
            try await resolvedClient.fetchDetail(for: game, includeRecordFallback: false)
        }
        self.fetchDatabaseRecordReview = fetchDatabaseRecordReview
        self.fetchOfficialRecordFallback = fetchOfficialRecordFallback ?? { game in
            try await resolvedClient.fetchRecordFallbackReview(for: game)
        }
        self.boxscoreClient = boxscoreClient ?? GameBoxscoreClientFactory.makeAppClient()
    }

    // load 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func load(
        for game: GameDetail,
        forceRefresh: Bool = false,
        fetchDatabaseRecordReview: (@Sendable (GameDetail) async -> GameCenterReview?)? = nil
    ) async {
        let stageStartedAt = Date()
        let gameKey = [
            game.id.uuidString,
            game.officialGameCenterID ?? "",
            game.publicGameID ?? "",
            game.status.rawValue
        ].joined(separator: "::")
        guard forceRefresh || lastLoadedGameKey != gameKey else { return }
        let previousGame = currentGame
        let previousDatabaseRecordReview = databaseRecordReview
        let shouldPreserveExistingDatabaseReview =
            previousDatabaseRecordReview?.hasDisplayableRecords == true &&
            previousGame?.stableDetailIdentity == game.stableDetailIdentity
        currentGame = game

        #if DEBUG
        print("[GameDetailLive] load start id=\(game.id.uuidString) publicGameID=\(game.publicGameID ?? "<nil>") providerGameID=\(game.providerGameID ?? "<nil>") officialProviderGameID=\(game.officialProviderGameID ?? "<nil>") status=\(game.status.rawValue) forceRefresh=\(forceRefresh)")
        #endif

        isLoading = true
        errorMessage = nil
        hasAttemptedLoad = true

        officialFallbackReview = nil
        if shouldPreserveExistingDatabaseReview == false {
            databaseRecordReview = nil
        }
        if cachedLineScoreGameKey != gameKey {
            cachedLineScore = nil
        }

        lastLoadedGameKey = gameKey
        if shouldPreserveExistingDatabaseReview {
            databaseRecordReview = previousDatabaseRecordReview
        }

        if game.status == .upcoming {
            #if DEBUG
            print("[GameDetailLive] upcoming official preview skipped reason=automaticDisabled stage=initialRender publicGameID=\(game.publicGameID ?? "<nil>") providerGameID=\(game.providerGameID ?? "<nil>")")
            #endif
        }

        scheduleDatabaseRecordReviewLoadIfNeeded(
            for: game,
            gameKey: gameKey,
            forceRefresh: forceRefresh,
            fetcher: fetchDatabaseRecordReview ?? self.fetchDatabaseRecordReview,
            preserveExistingReview: shouldPreserveExistingDatabaseReview ? previousDatabaseRecordReview : nil
        )
        scheduleBoxscoreLoadIfNeeded(for: game, forceRefresh: forceRefresh)
        guard shouldLoadDetailPayload(for: game, forceRefresh: forceRefresh) else {
            isLoading = false
            #if DEBUG
            print("[GameDetailLive] upcoming official preview skipped reason=automaticDisabled stage=detailPayload publicGameID=\(game.publicGameID ?? "<nil>") providerGameID=\(game.providerGameID ?? "<nil>")")
            print("[GameDetailLive] load scheduled id=\(game.id.uuidString) durationMs=\(Self.durationMilliseconds(since: stageStartedAt))")
            #endif
            return
        }

        scheduleDetailPayloadLoad(for: game, gameKey: gameKey, forceRefresh: forceRefresh)

        #if DEBUG
        print("[GameDetailLive] load scheduled id=\(game.id.uuidString) durationMs=\(Self.durationMilliseconds(since: stageStartedAt))")
        #endif
    }

    // shouldLoadDetailPayload 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private func shouldLoadDetailPayload(for game: GameDetail, forceRefresh: Bool) -> Bool {
        if game.status == .upcoming, forceRefresh == false {
            return false
        }
        return true
    }

    // scheduleDetailPayloadLoad 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    private func scheduleDetailPayloadLoad(for game: GameDetail, gameKey: String, forceRefresh: Bool) {
        let task = detailPayloadTask(for: game, gameKey: gameKey)
        Task { [weak self] in
            guard let self else { return }
            let stageStartedAt = Date()
            let result = await task.value
            if self.activeDetailLoadKey == gameKey {
                self.detailLoadTask = nil
                self.activeDetailLoadKey = nil
            }
            let fetchedDetail = self.detailPayload(from: result)
            guard self.currentGame?.stableDetailIdentity == game.stableDetailIdentity else { return }
            self.detail = fetchedDetail
            if let lineScore = fetchedDetail?.lineScore {
                self.cachedLineScore = lineScore
                self.cachedLineScoreGameKey = gameKey
            }
            if game.status.isLiveLike,
               self.databaseRecordReview?.hasDisplayableRecords != true,
               fetchedDetail?.review?.hasDisplayableRecords != true {
                self.scheduleOfficialRecordFallbackIfNeeded(for: game, forceRefresh: forceRefresh)
            }
            self.isLoading = false
            #if DEBUG
            print("[GameDetailLive] detail payload applied status=\(game.status.rawValue) durationMs=\(Self.durationMilliseconds(since: stageStartedAt)) lineScorePresent=\((fetchedDetail?.lineScore ?? self.cachedLineScore) != nil) selectedRecordSource=\(self.selectedRecordSourceDebugValue)")
            #endif
        }
    }

    // scheduleDatabaseRecordReviewLoadIfNeeded 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    private func scheduleDatabaseRecordReviewLoadIfNeeded(
        for game: GameDetail,
        gameKey: String,
        forceRefresh: Bool,
        fetcher: (@Sendable (GameDetail) async -> GameCenterReview?)?,
        preserveExistingReview: GameCenterReview?
    ) {
        guard game.status == .final || game.status.isLiveLike else {
            #if DEBUG
            print("[GameDetailDBRecords] fetch skipped reason=unsupportedOrNotRecordStatus status=\(game.status.rawValue) gameID=\(game.id.uuidString)")
            #endif
            return
        }
        guard fetcher != nil else {
            if let preserveExistingReview, preserveExistingReview.hasDisplayableRecords {
                databaseRecordReview = preserveExistingReview
            }
            #if DEBUG
            print("[GameDetailDBRecords] fetch skipped reason=noFetcher gameID=\(game.id.uuidString)")
            #endif
            return
        }
        if forceRefresh == false,
           databaseRecordReview?.hasDisplayableRecords == true,
           currentGame?.stableDetailIdentity == game.stableDetailIdentity {
            #if DEBUG
            print("[GameDetailDBRecords] fetch skipped reason=alreadyLoaded gameID=\(game.id.uuidString)")
            #endif
            return
        }
        if let databaseRecordLoadTask, activeDatabaseRecordGameKey == gameKey {
            #if DEBUG
            print("[GameDetailDBRecords] fetch skipped reason=inFlight gameID=\(game.id.uuidString)")
            #endif
            Task {
                await databaseRecordLoadTask.value
            }
            return
        }

        activeDatabaseRecordGameKey = gameKey
        databaseRecordMergeInFlightGameIdentity = game.stableDetailIdentity
        databaseRecordLoadTask = Task { [weak self] in
            guard let self else { return }
            let loadedDatabaseRecordReview = await self.loadDatabaseRecordReviewIfNeeded(
                for: game,
                fetcher: fetcher
            )
            guard self.currentGame?.stableDetailIdentity == game.stableDetailIdentity else {
                if self.databaseRecordMergeInFlightGameIdentity == game.stableDetailIdentity {
                    self.databaseRecordMergeInFlightGameIdentity = nil
                }
                if self.activeDatabaseRecordGameKey == gameKey {
                    self.databaseRecordLoadTask = nil
                    self.activeDatabaseRecordGameKey = nil
                }
                return
            }
            if loadedDatabaseRecordReview?.hasDisplayableRecords == true {
                self.databaseRecordReview = loadedDatabaseRecordReview
                #if DEBUG
                print("[GameDetailLive] Official fetch skipped reason=dbRecordsPresent publicGameID=\(game.publicGameID ?? "<nil>") providerGameID=\(game.providerGameID ?? "<nil>")")
                #endif
                self.cancelOfficialFallbackLoad()
            } else if let preserveExistingReview, preserveExistingReview.hasDisplayableRecords {
                self.databaseRecordReview = preserveExistingReview
            }
            if self.databaseRecordMergeInFlightGameIdentity == game.stableDetailIdentity {
                self.databaseRecordMergeInFlightGameIdentity = nil
            }
            if self.activeDatabaseRecordGameKey == gameKey {
                self.databaseRecordLoadTask = nil
                self.activeDatabaseRecordGameKey = nil
            }
            if self.databaseRecordReview?.hasDisplayableRecords != true,
               self.boxscore?.hasRecords != true {
                self.scheduleOfficialRecordFallbackIfNeeded(for: game, forceRefresh: forceRefresh)
            }
        }
    }

    // loadDatabaseRecordReviewIfNeeded 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    private func loadDatabaseRecordReviewIfNeeded(
        for game: GameDetail,
        fetcher: (@Sendable (GameDetail) async -> GameCenterReview?)?
    ) async -> GameCenterReview? {
        guard game.status == .final || game.status.isLiveLike,
              let fetcher else {
            #if DEBUG
            print("[GameDetailDBRecords] selectedRecordSource=none reason=unsupportedOrNotRecordStatus status=\(game.status.rawValue) gameID=\(game.id.uuidString)")
            #endif
            return nil
        }
        let stageStartedAt = Date()
        let review = await fetcher(game)
        #if DEBUG
        let batterCount = (review?.awayBatting.lines.count ?? 0) + (review?.homeBatting.lines.count ?? 0)
        let pitcherCount = (review?.awayPitching.lines.count ?? 0) + (review?.homePitching.lines.count ?? 0)
        print("[GameDetailDBRecords] selectedRecordSource=\(review?.recordSource.rawValue ?? "none") mappedBatterCount=\(batterCount) mappedPitcherCount=\(pitcherCount) durationMs=\(Self.durationMilliseconds(since: stageStartedAt))")
        #endif
        return review?.hasDisplayableRecords == true ? review : nil
    }

    // mergeDatabaseRecordReviewAfterFetchGameSingle 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func mergeDatabaseRecordReviewAfterFetchGameSingle(
        inputLocalGameId: UUID,
        resolvedGame: GameDetail,
        rawSupabaseGameID: UUID? = nil,
        rawSupabaseProviderGameID: String? = nil,
        rawSupabasePublicGameID: String? = nil,
        fetchDatabaseRecordReviewResult: @Sendable (GameDetail) async -> GameDetailDatabaseReviewFetchResult?,
        fetchDatabaseRecordReviewResultByRawSupabaseID: @Sendable (UUID, String?, String?) async -> GameDetailDatabaseReviewFetchResult?
    ) async {
        guard resolvedGame.status == .final || resolvedGame.status.isLiveLike else { return }
        currentGame = resolvedGame
        let previousRecordSource = selectedRecordSourceDebugValue
        databaseRecordMergeInFlightGameIdentity = resolvedGame.stableDetailIdentity
        let result: GameDetailDatabaseReviewFetchResult?
        if let rawSupabaseGameID {
            result = await fetchDatabaseRecordReviewResultByRawSupabaseID(
                rawSupabaseGameID,
                rawSupabaseProviderGameID ?? resolvedGame.providerGameID,
                rawSupabasePublicGameID ?? resolvedGame.publicGameID
            )
        } else {
            result = await fetchDatabaseRecordReviewResult(resolvedGame)
        }
        let review = result?.review
        let hasMappedRows = (result?.mappedBatterCount ?? 0) > 0 || (result?.mappedPitcherCount ?? 0) > 0
        if let review, review.hasDisplayableRecords, hasMappedRows {
            databaseRecordReview = review
            cancelOfficialFallbackLoad()
        }
        if databaseRecordMergeInFlightGameIdentity == resolvedGame.stableDetailIdentity {
            databaseRecordMergeInFlightGameIdentity = nil
        }
        if databaseRecordReview?.hasDisplayableRecords != true,
           boxscore?.hasRecords != true {
            scheduleOfficialRecordFallbackIfNeeded(for: resolvedGame, forceRefresh: false)
        }
        #if DEBUG
        print("[GameDetailDBRecords] invokedFrom=afterFetchGameSingleProviderResolved localGameId=\(inputLocalGameId.uuidString)")
        print("[GameDetailDBRecords] rawSupabaseGameId=\(result?.rawSupabaseGameID?.uuidString ?? result?.resolvedSupabaseGameID?.uuidString ?? "<nil>") providerGameID=\(result?.providerGameID ?? resolvedGame.providerGameID ?? "<nil>") publicGameID=\(result?.publicGameID ?? resolvedGame.publicGameID ?? "<nil>")")
        print("[GameDetailDBRecords] publicBatterRawRowCount=\(result?.publicBatterRawRowCount ?? 0) publicPitcherRawRowCount=\(result?.publicPitcherRawRowCount ?? 0) eventRawRowCount=\(result?.eventRawRowCount ?? 0)")
        print("[GameDetailDBRecords] mappedBatterCount=\(result?.mappedBatterCount ?? 0) mappedPitcherCount=\(result?.mappedPitcherCount ?? 0) previousRecordSource=\(previousRecordSource) finalRecordSource=\(selectedRecordSourceDebugValue)")
        #endif
    }

    private var selectedRecordSourceDebugValue: String {
        databaseRecordReview?.recordSource.rawValue ??
            detail?.review?.recordSource.rawValue ??
            officialFallbackReview?.recordSource.rawValue ??
            "none"
    }

    // loadDetailPayload 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    private func loadDetailPayload(for game: GameDetail, gameKey: String) async -> GameCenterDetailPayload? {
        let task = detailPayloadTask(for: game, gameKey: gameKey)
        let result = await task.value
        if activeDetailLoadKey == gameKey {
            detailLoadTask = nil
            activeDetailLoadKey = nil
        }
        return detailPayload(from: result)
    }

    // detailPayloadTask 메서드는 이 타입의 주요 동작을 수행합니다.
    private func detailPayloadTask(for game: GameDetail, gameKey: String) -> Task<GameDetailPayloadLoadResult, Never> {
        if let inFlight = detailLoadTask, activeDetailLoadKey == gameKey {
            #if DEBUG
            print("[GameDetailLive] detail fetch deduped key=\(gameKey)")
            #endif
            return inFlight
        }

        let fetchDetail = fetchDetail
        activeDetailLoadKey = gameKey
        let task = Task { () -> GameDetailPayloadLoadResult in
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
        return task
    }

    // detailPayload 메서드는 이 타입의 주요 동작을 수행합니다.
    private func detailPayload(from result: GameDetailPayloadLoadResult) -> GameCenterDetailPayload? {
        switch result {
        case .success(let payload):
            return payload
        case .failure:
            errorMessage = "경기 상태와 스코어는 현재 데이터로 표시하고 있습니다."
            return nil
        }
    }

    // scheduleBoxscoreLoadIfNeeded 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

    // loadBoxscoreIfNeeded 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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

    // scheduleOfficialRecordFallbackIfNeeded 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    private func scheduleOfficialRecordFallbackIfNeeded(for game: GameDetail, forceRefresh: Bool) {
        guard game.status == .final || game.status.isLiveLike else { return }
        guard databaseRecordReview?.hasDisplayableRecords != true else {
            #if DEBUG
            print("[GameDetailLive] Official fetch skipped reason=dbRecordsPresent publicGameID=\(game.publicGameID ?? "<nil>") providerGameID=\(game.providerGameID ?? "<nil>")")
            #endif
            cancelOfficialFallbackLoad()
            return
        }
        guard databaseRecordMergeInFlightGameIdentity != game.stableDetailIdentity else {
            #if DEBUG
            print("[GameDetailLive] Official fetch skipped reason=dbRecordsInFlight publicGameID=\(game.publicGameID ?? "<nil>") providerGameID=\(game.providerGameID ?? "<nil>")")
            #endif
            return
        }
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

    // loadOfficialRecordFallbackIfNeeded 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    private func loadOfficialRecordFallbackIfNeeded(for game: GameDetail, cacheKey: String, forceRefresh: Bool) async {
        let stageStartedAt = Date()
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
        guard databaseRecordReview?.hasDisplayableRecords != true else {
            cancelOfficialFallbackLoad()
            return
        }

        if let fetchedReview, fetchedReview.hasDisplayableRecords {
            Self.cachedOfficialFallbackReviews[cacheKey] = (Date(), fetchedReview)
            Self.recentFailedOfficialFallbacks[cacheKey] = nil
            officialFallbackReview = fetchedReview
            #if DEBUG
            print("[GameDetailLive] official record fallback success gameKey=\(cacheKey) liveRecordPresent=true durationMs=\(Self.durationMilliseconds(since: stageStartedAt))")
            #endif
        } else {
            Self.recentFailedOfficialFallbacks[cacheKey] = Date()
            #if DEBUG
            print("[GameDetailLive] official record fallback empty gameKey=\(cacheKey) liveRecordPresent=false durationMs=\(Self.durationMilliseconds(since: stageStartedAt))")
            #endif
        }
    }

    // cancelOfficialFallbackLoad 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private func cancelOfficialFallbackLoad() {
        officialFallbackLoadTask?.cancel()
        officialFallbackLoadTask = nil
        activeOfficialFallbackGameKey = nil
        officialFallbackReview = nil
    }

    // officialFallbackCacheKey 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // detailGame 메서드는 이 타입의 주요 동작을 수행합니다.
    private func detailGame(publicGameID: String) -> GameDetail? {
        guard currentGame?.publicGameID == publicGameID else { return nil }
        return currentGame
    }

    // waitForBoxscoreLoadForTesting 메서드는 이 타입의 주요 동작을 수행합니다.
    func waitForBoxscoreLoadForTesting() async {
        await boxscoreLoadTask?.value
    }

    // waitForDetailLoadForTesting 메서드는 이 타입의 주요 동작을 수행합니다.
    func waitForDetailLoadForTesting() async {
        _ = await detailLoadTask?.value
    }

    // waitForDatabaseRecordLoadForTesting 메서드는 이 타입의 주요 동작을 수행합니다.
    func waitForDatabaseRecordLoadForTesting() async {
        await databaseRecordLoadTask?.value
    }

    // waitForOfficialFallbackLoadForTesting 메서드는 이 타입의 주요 동작을 수행합니다.
    func waitForOfficialFallbackLoadForTesting() async {
        await officialFallbackLoadTask?.value
    }

    // resetBoxscoreLoadingCacheForTesting 메서드는 저장된 상태나 캐시 값을 정리합니다.
    static func resetBoxscoreLoadingCacheForTesting() {
        inFlightBoxscoreTasks.removeAll()
        recentFailedBoxscoreFetches.removeAll()
        cachedBoxscores.removeAll()
        inFlightOfficialFallbackTasks.removeAll()
        cachedOfficialFallbackReviews.removeAll()
        recentFailedOfficialFallbacks.removeAll()
    }

    // durationMilliseconds 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func durationMilliseconds(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1_000)
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
    private static var inFlightRefreshesByStableIdentity: [String: Task<GameDetailRefreshResult?, Never>] = [:]
    private static var recentAutomaticRefreshesByStableIdentity: [String: (date: Date, result: GameDetailRefreshResult)] = [:]
    static let livePollingIntervalNanoseconds: UInt64 = 12_000_000_000

    private let requestedIdentity: String
    private var lastAutomaticRefreshAt: Date?
    private var baseRunnerDisplayResolver = BaseRunnerDisplayResolver()

    let stableIdentity: String
    @Published var game: GameDetail?
    @Published private(set) var isResolvingInitialGame: Bool
    @Published private(set) var hasAttemptedInitialResolution: Bool
    @Published private(set) var baseRunnerDisplay: BaseRunnerDisplayResolution = .empty
    @Published private(set) var rawSupabaseGameID: UUID?
    @Published private(set) var rawSupabaseProviderGameID: String?
    @Published private(set) var rawSupabasePublicGameID: String?

    var shouldAutoRefreshLiveGame: Bool {
        game?.status.isLiveLike == true
    }

    var liveRefreshTaskID: String {
        shouldAutoRefreshLiveGame ? "live:\(stableIdentity)" : "idle:\(stableIdentity)"
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
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
        print("[GameDetailNavigation] initialSnapshotPresent=\(initialGame != nil) stableIdentity=\(stableIdentity) requestedIdentity=\(requestedIdentity)")
        #endif
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
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
        print("[GameDetailNavigation] initialSnapshotPresent=true stableIdentity=\(stableIdentity) requestedIdentity=\(requestedIdentity)")
        #endif
    }

    // configureInitialGameIfNeeded 메서드는 이 타입의 주요 동작을 수행합니다.
    func configureInitialGameIfNeeded(_ initialGame: GameDetail?) {
        guard game == nil, let initialGame else { return }
        game = initialGame
        isResolvingInitialGame = false
        hasAttemptedInitialResolution = true
        baseRunnerDisplay = baseRunnerDisplayResolver.resolve(gameIdentity: stableIdentity, game: initialGame)
    }

    // refreshIfNeeded 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
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
            let fetched = await appModel.refreshGameDetailResult(for: requestedIdentity, forceRefresh: manual)
            if let fetched {
                apply(fetched)
                return fetched.game
            }
            return nil
        }
        guard let currentGame = game else { return nil }
        let refreshIdentity = requestedIdentity
        if manual == false, currentGame.status == .upcoming {
            hasAttemptedInitialResolution = true
            #if DEBUG
            print("[GameDetailFetch] latestSnapshot skipped reason=scheduledNoSnapshot stableIdentity=\(refreshIdentity) publicGameID=\(currentGame.publicGameID ?? "<nil>") providerGameID=\(currentGame.providerGameID ?? "<nil>")")
            #endif
        }

        if manual == false, bypassAutomaticThrottle == false {
            if let lastAutomaticRefreshAt,
               Date().timeIntervalSince(lastAutomaticRefreshAt) < Self.automaticRefreshInterval {
                return game
            }

            if let recentRefresh = Self.recentAutomaticRefreshesByStableIdentity[refreshIdentity],
               Date().timeIntervalSince(recentRefresh.date) < Self.automaticRefreshStableIdentityThrottle {
                if recentRefresh.result.game != game {
                    apply(recentRefresh.result)
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
                return fetched.game
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
            await appModel.refreshGameDetailResult(
                for: refreshIdentity,
                initialGame: currentGame,
                forceRefresh: manual
            )
        }
        Self.inFlightRefreshesByStableIdentity[refreshIdentity] = task
        let fetched = await task.value
        Self.inFlightRefreshesByStableIdentity[refreshIdentity] = nil
        if manual == false {
            let cachedResult = fetched ?? GameDetailRefreshResult(
                game: currentGame,
                rawSupabaseGameID: rawSupabaseGameID,
                providerGameID: rawSupabaseProviderGameID ?? currentGame.providerGameID,
                publicGameID: rawSupabasePublicGameID ?? currentGame.publicGameID
            )
            Self.recentAutomaticRefreshesByStableIdentity[refreshIdentity] = (Date(), cachedResult)
        }
        if let fetched {
            apply(fetched)
        }
        return fetched?.game ?? game
    }

    // apply 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    private func apply(_ fetched: GameDetailRefreshResult) {
        rawSupabaseGameID = fetched.rawSupabaseGameID
        rawSupabaseProviderGameID = fetched.providerGameID
        rawSupabasePublicGameID = fetched.publicGameID
        apply(fetched.game)
    }

    // apply 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
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

// BaseRunnerDisplayResolution 구조체는 BaseRunnerDisplayResolution 타입의 역할과 값을 정의합니다.
struct BaseRunnerDisplayResolution: Equatable, Sendable {
    static let empty = BaseRunnerDisplayResolution(
        runners: GameBaseRunners(first: nil, second: nil, third: nil),
        source: "empty"
    )

    let runners: GameBaseRunners
    let source: String

    // mergingOfficialNames 메서드는 이 타입의 주요 동작을 수행합니다.
    func mergingOfficialNames(
        snapshot: GameBaseRunners?,
        official: GameBaseRunners?,
        bases: RunnerState?
    ) -> BaseRunnerDisplayResolution {
        guard let official, let bases else {
            return self
        }
        let officialFirst = Self.clean(official.first)
        let officialSecond = Self.clean(official.second)
        let officialThird = Self.clean(official.third)
        guard officialFirst != nil || officialSecond != nil || officialThird != nil else {
            return self
        }

        var first = bases.first
            ? Self.snapshotName(snapshot?.first, base: .first, officialSecond: officialSecond, officialThird: officialThird) ?? officialFirst
            : nil
        var second = bases.second
            ? Self.snapshotName(snapshot?.second, base: .second, officialSecond: officialSecond, officialThird: officialThird) ?? officialSecond
            : nil
        var third = bases.third
            ? Self.snapshotName(snapshot?.third, base: .third, officialSecond: officialSecond, officialThird: officialThird) ?? officialThird
            : nil

        var assignedNames = Set([first, second, third].compactMap(Self.clean))
        if bases.third, third == nil {
            third = Self.cacheName(runners.third, excluding: assignedNames)
            if let thirdName = Self.clean(third) {
                assignedNames.insert(thirdName)
            }
        }
        if bases.second, second == nil {
            second = Self.cacheName(runners.second, excluding: assignedNames)
            if let secondName = Self.clean(second) {
                assignedNames.insert(secondName)
            }
        }
        if bases.first, first == nil {
            first = Self.cacheName(runners.first, excluding: assignedNames)
        }

        let deduplicated = Self.deduplicated(first: first, second: second, third: third)
        first = deduplicated.first
        second = deduplicated.second
        third = deduplicated.third

        let mergedRunners = GameBaseRunners(first: first, second: second, third: third)
        guard mergedRunners != runners || source != "official" else {
            return self
        }

        #if DEBUG
        print("[BaseRunners] applied official names first=\(Self.displayName(first)) second=\(Self.displayName(second)) third=\(Self.displayName(third))")
        print("[BaseRunners] rendered first=\(Self.renderedLogName(occupied: bases.first, name: first)) second=\(Self.renderedLogName(occupied: bases.second, name: second)) third=\(Self.renderedLogName(occupied: bases.third, name: third)) source=official")
        #endif

        return BaseRunnerDisplayResolution(runners: mergedRunners, source: "official")
    }

    // snapshotName 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func snapshotName(
        _ value: String?,
        base: RunnerBase,
        officialSecond: String?,
        officialThird: String?
    ) -> String? {
        guard let name = clean(value) else { return nil }

        switch base {
        case .first:
            if name == officialSecond || name == officialThird {
                return nil
            }
        case .second:
            if name == officialThird {
                return nil
            }
        case .third:
            break
        }

        return name
    }

    // cacheName 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func cacheName(_ value: String?, excluding assignedNames: Set<String>) -> String? {
        guard let name = clean(value), assignedNames.contains(name) == false else {
            return nil
        }
        return name
    }

    // deduplicated 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func deduplicated(first: String?, second: String?, third: String?) -> GameBaseRunners {
        var first = clean(first)
        var second = clean(second)
        let third = clean(third)

        if let secondName = second, secondName == third {
            second = nil
        }
        if let firstName = first, firstName == second || firstName == third {
            first = nil
        }

        return GameBaseRunners(first: first, second: second, third: third)
    }

    // clean 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // displayName 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func displayName(_ value: String?) -> String {
        clean(value) ?? "<nil>"
    }

    // renderedLogName 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func renderedLogName(occupied: Bool, name: String?) -> String {
        guard occupied else {
            return "empty"
        }
        guard let cleaned = clean(name), cleaned != "주자" else {
            return "점유"
        }
        return cleaned
    }

// RunnerBase 열거형는 RunnerBase 타입의 역할과 값을 정의합니다.
    private enum RunnerBase {
        case first
        case second
        case third
    }
}

// BaseRunnerDisplayResolver 구조체는 입력 상태를 해석해 필요한 결과 값을 결정합니다.
struct BaseRunnerDisplayResolver: Sendable {
    private static let fallbackRunnerName = "주자"
    private var statesByGameIdentity: [String: CachedBaseRunnerNames] = [:]
    private var activeGameIdentity: String?

    // resolve 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
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

    // resolveBase 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
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

    // sourceSummary 메서드는 이 타입의 주요 동작을 수행합니다.
    private func sourceSummary(_ sources: Set<String>) -> String {
        let ordered = ["snapshot", "carryForward", "fallback"].filter { sources.contains($0) }
        return ordered.isEmpty ? "empty" : ordered.joined(separator: "+")
    }

    // clean 메서드는 이 타입의 주요 동작을 수행합니다.
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

// CachedBaseRunnerNames 구조체는 CachedBaseRunnerNames 타입의 역할과 값을 정의합니다.
    private struct CachedBaseRunnerNames: Sendable {
        let runners: GameBaseRunners
    }

// ResolvedBaseRunnerDisplay 구조체는 ResolvedBaseRunnerDisplay 타입의 역할과 값을 정의합니다.
    private struct ResolvedBaseRunnerDisplay: Sendable {
        static let empty = ResolvedBaseRunnerDisplay(displayName: nil, realName: nil)

        let displayName: String?
        let realName: String?
    }
}
