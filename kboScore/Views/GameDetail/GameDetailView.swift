//
//  GameDetailView.swift
//  kboScore
//  기능 설명: 선택한 경기의 상세 정보, 기록, 알림 액션 화면을 표시합니다.
//  사용자가 경기 상태와 설정을 빠르게 이해하도록 도메인 상태를 화면 구조에 직접 매핑합니다.
//  SwiftUI 상태 갱신, 접근성, 작은 화면 레이아웃에서 정보가 겹치지 않도록 표시 조건을 제한합니다.
//  TODO : 반복되는 화면 조각은 재사용 가능한 컴포넌트로 분리하고 미리보기 케이스를 보강합니다.
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

// GameDetailView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
struct GameDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var screenModel = GameDetailScreenModel()
    @StateObject private var viewModel: GameDetailViewModel

    let gameIdentity: String

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(gameID: UUID) {
        let identity = gameID.uuidString
        self.gameIdentity = identity
        self._viewModel = StateObject(wrappedValue: GameDetailViewModel(gameIdentity: identity))
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(gameIdentity: String) {
        self.gameIdentity = gameIdentity
        self._viewModel = StateObject(wrappedValue: GameDetailViewModel(gameIdentity: gameIdentity))
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(stableIdentity: String, initialGame: GameDetail) {
        self.gameIdentity = stableIdentity
        self._viewModel = StateObject(
            wrappedValue: GameDetailViewModel(
                stableIdentity: stableIdentity,
                requestedIdentity: stableIdentity,
                initialGame: initialGame
            )
        )
    }

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(game: GameDetail) {
        self.gameIdentity = game.stableDetailIdentity
        self._viewModel = StateObject(
            wrappedValue: GameDetailViewModel(
                stableIdentity: game.stableDetailIdentity,
                requestedIdentity: game.stableDetailIdentity,
                initialGame: game
            )
        )
    }

    var body: some View {
        ScrollView {
            if let game = viewModel.game {
                let presentation = GameDetailPresentation(
                    game: game,
                    payload: screenModel.detail,
                    cachedLineScore: screenModel.cachedLineScore,
                    boxscore: screenModel.boxscore,
                    databaseRecordReview: screenModel.databaseRecordReview,
                    officialFallbackReview: screenModel.officialFallbackReview,
                    baseRunnerDisplay: viewModel.baseRunnerDisplay
                )
                VStack(alignment: .leading, spacing: 12) {
                    GameStatusSummaryCard(presentation: presentation)

                    if presentation.status != .cancelled {
                        actionButtons(for: game)
                        overviewSection(presentation: presentation)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .onAppear {
                    logAttendanceDetailAppear(game)
                }
            } else if viewModel.isResolvingInitialGame || viewModel.hasAttemptedInitialResolution == false {
                ProgressView("경기 정보를 불러오는 중")
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .padding(12)
            } else {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "경기를 찾을 수 없습니다",
                    message: "관련 경기 데이터가 준비되지 않았습니다."
                )
                .padding(12)
            }
        }
        .background {
            if let palette = appModel.favoriteStadiumPalette {
                LinearGradient(
                    colors: [palette.background, palette.sectionBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            } else {
                KBOLivePalette.background
            }
        }
        .foregroundStyle(appModel.favoriteStadiumPalette?.textPrimary ?? Color.primary)
        .navigationTitle("경기 상세")
        .navigationBarTitleDisplayMode(.inline)
        .stadiumNavigationChrome(appModel.favoriteStadiumPalette)
        .tint(appModel.favoriteStadiumPalette?.primary ?? appModel.currentTheme.accent)
        .task(id: viewModel.stableIdentity) {
            let initialRenderStartedAt = Date()
            if viewModel.game == nil {
                viewModel.configureInitialGameIfNeeded(appModel.initialGameSnapshot(for: gameIdentity))
            }
            let inputLocalGameID = viewModel.game?.id
            if let initialGame = viewModel.game {
                #if DEBUG
                print("[GameDetail] initialRenderCompleted stableIdentity=\(viewModel.stableIdentity) publicGameID=\(initialGame.publicGameID ?? "<nil>") providerGameID=\(initialGame.providerGameID ?? "<nil>") durationMs=\(Int(Date().timeIntervalSince(initialRenderStartedAt) * 1_000))")
                #endif
                await screenModel.load(
                    for: initialGame,
                    forceRefresh: false,
                    fetchDatabaseRecordReview: { game in
                        await appModel.fetchGameDetailDatabaseReviewResult(
                            for: game,
                            forceRefresh: false
                        )?.review
                    }
                )
            }
            await Task.yield()
            let refreshedGame = await viewModel.refreshIfNeeded(
                appModel: appModel,
                bypassAutomaticThrottle: true
            ) ?? viewModel.game
            if let refreshedGame {
                await loadDetailPresentation(
                    for: refreshedGame,
                    inputLocalGameId: inputLocalGameID ?? refreshedGame.id,
                    rawSupabaseGameID: viewModel.rawSupabaseGameID,
                    rawSupabaseProviderGameID: viewModel.rawSupabaseProviderGameID,
                    rawSupabasePublicGameID: viewModel.rawSupabasePublicGameID,
                    forceRefresh: refreshedGame.shouldPollGameDetail(now: Date())
                )
                await appModel.startOrUpdateLiveActivityIfNeeded(for: refreshedGame)
                await appModel.startLiveGameDetailPolling(gameIdentity: refreshedGame.stableDetailIdentity)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, viewModel.shouldAutoRefreshLiveGame else { return }
            Task {
                await refreshCurrentGame(forceRefresh: true)
            }
        }
        .onDisappear {
            appModel.stopLiveGameDetailPolling()
        }
        .onChange(of: appModel.game(withIdentity: viewModel.stableIdentity)) { _, updatedGame in
            guard let updatedGame else { return }
            Task {
                await applySharedGameDetailUpdate(updatedGame)
            }
        }
        .onChange(of: appModel.gameDetailRecordRefreshSignal(for: viewModel.stableIdentity)) { _, signal in
            guard let signal, let game = viewModel.game else { return }
            Task {
                #if DEBUG
                print("[GameDetailDBRecords] refresh requested source=liveSnapshot rawHash=\(signal.rawHash) sequence=\(signal.sequence)")
                #endif
                await loadDetailPresentation(
                    for: game,
                    inputLocalGameId: game.id,
                    rawSupabaseGameID: viewModel.rawSupabaseGameID,
                    rawSupabaseProviderGameID: viewModel.rawSupabaseProviderGameID,
                    rawSupabasePublicGameID: viewModel.rawSupabasePublicGameID,
                    forceRefresh: true
                )
            }
        }
        .refreshable {
            await refreshCurrentGame(forceRefresh: true)
        }
    }

    // refreshCurrentGame 메서드는 수동 새로고침과 자동 polling/foreground 복귀의 상세 갱신 경로를 맞춥니다.
    private func refreshCurrentGame(forceRefresh: Bool) async {
        if forceRefresh {
            let inputLocalGameID = viewModel.game?.id
            await viewModel.refreshIfNeeded(appModel: appModel, manual: true)
            guard let refreshedGame = viewModel.game else { return }
            await loadDetailPresentation(
                for: refreshedGame,
                inputLocalGameId: inputLocalGameID ?? refreshedGame.id,
                rawSupabaseGameID: viewModel.rawSupabaseGameID,
                rawSupabaseProviderGameID: viewModel.rawSupabaseProviderGameID,
                rawSupabasePublicGameID: viewModel.rawSupabasePublicGameID,
                forceRefresh: true
            )
            await appModel.startLiveGameDetailPolling(gameIdentity: refreshedGame.stableDetailIdentity)
        } else if let refreshedGame = await viewModel.refreshIfNeeded(appModel: appModel) {
            await loadDetailPresentation(
                for: refreshedGame,
                inputLocalGameId: refreshedGame.id,
                rawSupabaseGameID: viewModel.rawSupabaseGameID,
                rawSupabaseProviderGameID: viewModel.rawSupabaseProviderGameID,
                rawSupabasePublicGameID: viewModel.rawSupabasePublicGameID,
                forceRefresh: refreshedGame.shouldPollGameDetail(now: Date())
            )
            await appModel.startLiveGameDetailPolling(gameIdentity: refreshedGame.stableDetailIdentity)
        }
    }

    // applySharedGameDetailUpdate 메서드는 AppModel의 live polling 결과를 현재 표시 중인 상세 화면에 반영합니다.
    private func applySharedGameDetailUpdate(_ updatedGame: GameDetail) async {
        let inputLocalGameID = viewModel.game?.id ?? updatedGame.id
        if let result = appModel.gameDetailRefreshResultSnapshot(for: updatedGame.stableDetailIdentity) ??
            appModel.gameDetailRefreshResultSnapshot(for: viewModel.stableIdentity) {
            viewModel.applyExternalRefreshResult(result)
        }
        await loadDetailPresentation(
            for: updatedGame,
            inputLocalGameId: inputLocalGameID,
            rawSupabaseGameID: viewModel.rawSupabaseGameID,
            rawSupabaseProviderGameID: viewModel.rawSupabaseProviderGameID,
            rawSupabasePublicGameID: viewModel.rawSupabasePublicGameID,
            forceRefresh: false
        )
    }

    // loadDetailPresentation 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    private func loadDetailPresentation(
        for game: GameDetail,
        inputLocalGameId: UUID,
        rawSupabaseGameID: UUID?,
        rawSupabaseProviderGameID: String?,
        rawSupabasePublicGameID: String?,
        forceRefresh: Bool
    ) async {
        await screenModel.load(
            for: game,
            forceRefresh: forceRefresh,
            fetchDatabaseRecordReview: { game in
                await appModel.fetchGameDetailDatabaseReviewResult(
                    for: game,
                    forceRefresh: forceRefresh
                )?.review
            }
        )
        await screenModel.mergeDatabaseRecordReviewAfterFetchGameSingle(
            inputLocalGameId: inputLocalGameId,
            resolvedGame: game,
            rawSupabaseGameID: rawSupabaseGameID,
            rawSupabaseProviderGameID: rawSupabaseProviderGameID,
            rawSupabasePublicGameID: rawSupabasePublicGameID,
            fetchDatabaseRecordReviewResult: appModel.fetchGameDetailDatabaseReviewResult,
            fetchDatabaseRecordReviewResultByRawSupabaseID: appModel.fetchGameDetailDatabaseReviewResult
        )
    }

    // overviewSection 메서드는 이 타입의 주요 동작을 수행합니다.
    @ViewBuilder
    private func overviewSection(
        presentation: GameDetailPresentation
    ) -> some View {
        switch GameDetailOverviewContentKind.contentKind(for: presentation.status) {
        case .preview:
            previewOverviewContent(for: presentation)
        case .overview:
            gameStatusOverviewContent(presentation: presentation)
        }
    }

    // gameStatusOverviewContent 메서드는 이 타입의 주요 동작을 수행합니다.
    private func gameStatusOverviewContent(
        presentation: GameDetailPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage = screenModel.errorMessage {
                DetailMessageCard(
                    icon: "clock.badge.questionmark",
                    title: "공식 프리뷰 정보 준비 중",
                    message: errorMessage
                )
            } else if screenModel.isLoading && screenModel.detail == nil {
                DetailLoadingCard(message: "공식 경기 상세 정보를 불러오는 중")
            }

            GameLineScoreCard(presentation: presentation)

            if presentation.status.isLiveLike {
                DetailMessageCard(
                    icon: "dot.radiowaves.left.and.right",
                    title: "현재 상황",
                    message: presentation.liveSituationSummary
                )
            } else if presentation.status == .final {
                DetailMessageCard(
                    icon: "flag.pattern.checkered",
                    title: "경기 결과",
                    message: presentation.finalSummaryText
                )
            }
//            else {
//                DetailMessageCard(
//                    icon: "calendar",
//                    title: "경기 전 안내",
//                    message: "라이브 상황과 라인스코어는 경기 시작 후 자동으로 갱신됩니다."
//                )
//            }

            GameDetailRecordsPanel(presentation: presentation, isLoading: screenModel.isLoading)
        }
    }

    // previewOverviewContent 메서드는 이 타입의 주요 동작을 수행합니다.
    private func previewOverviewContent(
        for presentation: GameDetailPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if screenModel.isLoading && screenModel.detail == nil {
                DetailLoadingCard(message: "프리뷰 데이터를 준비하는 중")
            }

            if let preview = presentation.preview {
                if presentation.probableStarters?.away != nil || presentation.probableStarters?.home != nil {
                    ProbableStartersCard(
                        awayTeam: presentation.game.awayTeam,
                        homeTeam: presentation.game.homeTeam,
                        starters: presentation.probableStarters
                    )
                }

                if let awayMatchup = preview.awayMatchup,
                   let homeMatchup = preview.homeMatchup {
                    MatchupComparisonCard(awayMatchup: awayMatchup, homeMatchup: homeMatchup)
                }

                if presentation.probableStarters?.away == nil,
                   presentation.probableStarters?.home == nil,
                   preview.awayMatchup == nil,
                   preview.homeMatchup == nil {
                    EmptyStateView(
                        systemImage: "person.crop.circle.badge.questionmark",
                        title: "프리뷰 정보가 아직 없습니다",
                        message: "선발 예고와 팀 비교 데이터가 준비되면 이 섹션에 표시됩니다."
                    )
                }
            } else {
                if presentation.probableStarters?.away != nil || presentation.probableStarters?.home != nil {
                    ProbableStartersCard(
                        awayTeam: presentation.game.awayTeam,
                        homeTeam: presentation.game.homeTeam,
                        starters: presentation.probableStarters
                    )
                } else {
                    EmptyStateView(
                        systemImage: "person.crop.circle.badge.questionmark",
                        title: "공식 프리뷰 정보 준비 중",
                        message: "현재 데이터 소스에서 프리뷰 정보를 아직 제공하지 않습니다."
                    )
                }
            }
        }
    }

    // actionButtons 메서드는 이 타입의 주요 동작을 수행합니다.
    @ViewBuilder
    private func actionButtons(for game: GameDetail) -> some View {
        let palette = appModel.favoriteStadiumPalette
        let attendanceGameID = appModel.attendanceGameID(for: game)
        let isAttended = appModel.isGameDetailAttended(game)
        let isAttendancePending = appModel.isAttendanceSyncPending(for: game)
        let isAttendanceButtonDisabled = attendanceGameID == nil || appModel.isAttendanceSyncAvailable == false || isAttendancePending
        HStack(spacing: 10) {
            Button {
                guard let attendanceGameID else { return }
                let before = appModel.isGameDetailAttended(game)
                #if DEBUG
                print("[AttendanceDetail] toggle rawGameID=\(attendanceGameID.uuidString) canonicalGameID=\(GameIdentifier.attendanceCanonicalKey(attendanceGameID)) publicGameID=\(game.publicGameID ?? "none") from=\(before) to=\(!before)")
                #endif
                appModel.toggleGameDetailAttendance(for: game)
            } label: {
                Label(
                    isAttended ? "직관 해제" : "직관",
                    systemImage: isAttended ? "checkmark.circle.fill" : "checkmark.circle"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    palette?.elevatedCard ?? Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .foregroundStyle(isAttended ? (palette?.primary ?? appModel.currentTheme.accent) : (palette?.textPrimary ?? .primary))
                .opacity(isAttendanceButtonDisabled ? 0.55 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isAttendanceButtonDisabled)

//            ShareLink(item: game.shareText) {
//                Label("경기 공유하기", systemImage: "square.and.arrow.up")
//                    .font(.subheadline.weight(.semibold))
//                    .frame(maxWidth: .infinity)
//                .padding(.vertical, 12)
//                .background(
//                        palette?.elevatedCard ?? Color(.secondarySystemBackground),
//                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
//                    )
//                    .foregroundStyle(palette?.textPrimary ?? .primary)
//            }
        }
    }

    private func logAttendanceDetailAppear(_ game: GameDetail) {
        #if DEBUG
        let attendanceGameID = appModel.attendanceGameID(for: game)
        let reason: String
        if attendanceGameID == nil {
            reason = "missingAttendanceGameID"
        } else if appModel.isAttendanceSyncAvailable == false {
            reason = "missingBackendBaseURL"
        } else if appModel.isAttendanceSyncPending(for: game) {
            reason = "pending"
        } else {
            reason = "ready"
        }
        let enabled = attendanceGameID != nil && appModel.isAttendanceSyncAvailable && appModel.isAttendanceSyncPending(for: game) == false
        print("[AttendanceDetail] button enabled=\(enabled) reason=\(reason) rawGameID=\(attendanceGameID?.uuidString ?? "nil") canonicalGameID=\(attendanceGameID.map(GameIdentifier.attendanceCanonicalKey) ?? "nil")")
        #endif
    }
}

// LiveSituationState 구조체는 live 주자상황/카운트를 단일 snapshot 단위로 교체하기 위한 값입니다.
struct LiveSituationState: Equatable, Sendable {
    let balls: Int?
    let strikes: Int?
    let outs: Int?
    let runnerOnFirst: Bool
    let runnerOnSecond: Bool
    let runnerOnThird: Bool
    let firstRunnerName: String?
    let secondRunnerName: String?
    let thirdRunnerName: String?
    let currentBatterName: String?
    let currentPitcherName: String?

    var bases: RunnerState {
        RunnerState(first: runnerOnFirst, second: runnerOnSecond, third: runnerOnThird)
    }

    var runnerNames: GameBaseRunners {
        GameBaseRunners(
            first: runnerOnFirst ? firstRunnerName?.nilIfBlank : nil,
            second: runnerOnSecond ? secondRunnerName?.nilIfBlank : nil,
            third: runnerOnThird ? thirdRunnerName?.nilIfBlank : nil
        )
    }

    var optionalRunnerNames: GameBaseRunners? {
        let names = runnerNames
        guard names.first != nil || names.second != nil || names.third != nil else {
            return nil
        }
        return names
    }

    var displayBaseRunners: [BaseRunnerDisplayItem] {
        [
            ("1B", runnerOnFirst, firstRunnerName),
            ("2B", runnerOnSecond, secondRunnerName),
            ("3B", runnerOnThird, thirdRunnerName)
        ]
        .compactMap { item in
            guard item.1 else { return nil }
            return BaseRunnerDisplayItem(base: item.0, name: renderedBaseRunnerName(item.2))
        }
    }

    static func fromLatestSnapshot(
        game: GameDetail,
        currentBatterName: String?,
        currentPitcherName: String?
    ) -> LiveSituationState {
        let bases = game.bases ?? .empty
        let firstRunnerName = bases.first ? game.baseRunners?.first?.nilIfBlank : nil
        let secondRunnerName = bases.second ? game.baseRunners?.second?.nilIfBlank : nil
        let thirdRunnerName = bases.third ? game.baseRunners?.third?.nilIfBlank : nil
        return LiveSituationState(
            balls: game.balls,
            strikes: game.strikes,
            outs: game.outs,
            runnerOnFirst: bases.first,
            runnerOnSecond: bases.second,
            runnerOnThird: bases.third,
            firstRunnerName: firstRunnerName,
            secondRunnerName: secondRunnerName,
            thirdRunnerName: thirdRunnerName,
            currentBatterName: currentBatterName?.nilIfBlank,
            currentPitcherName: currentPitcherName?.nilIfBlank
        )
    }

    static func mergedFallback(
        game: GameDetail,
        summary: GameCenterSummary?,
        currentBatterName: String?,
        currentPitcherName: String?
    ) -> LiveSituationState {
        let bases = game.bases ?? summary?.bases ?? .empty
        let officialBaseRunners = summary?.baseRunners
        return LiveSituationState(
            balls: game.balls ?? summary?.balls,
            strikes: game.strikes ?? summary?.strikes,
            outs: game.outs ?? summary?.outs,
            runnerOnFirst: bases.first,
            runnerOnSecond: bases.second,
            runnerOnThird: bases.third,
            firstRunnerName: bases.first ? (game.baseRunners?.first?.nilIfBlank ?? officialBaseRunners?.first?.nilIfBlank) : nil,
            secondRunnerName: bases.second ? (game.baseRunners?.second?.nilIfBlank ?? officialBaseRunners?.second?.nilIfBlank) : nil,
            thirdRunnerName: bases.third ? (game.baseRunners?.third?.nilIfBlank ?? officialBaseRunners?.third?.nilIfBlank) : nil,
            currentBatterName: currentBatterName?.nilIfBlank,
            currentPitcherName: currentPitcherName?.nilIfBlank
        )
    }

    private func renderedBaseRunnerName(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, trimmed.isEmpty == false, trimmed != "주자" else {
            return "점유"
        }
        return trimmed
    }
}

// GameDetailPresentation 구조체는 GameDetailPresentation 타입의 역할과 값을 정의합니다.
struct GameDetailPresentation {
    let game: GameDetail
    let status: GameStatus
    let stadium: String
    let startTimeText: String?
    let inningText: String?
    let awayScore: Int?
    let homeScore: Int?
    let balls: Int?
    let strikes: Int?
    let outs: Int?
    let bases: RunnerState?
    let baseRunners: GameBaseRunners?
    let baseRunnerDisplay: BaseRunnerDisplayResolution
    let liveSituation: LiveSituationState
    let currentBatterName: String?
    let currentPitcherName: String?
    let winningPitcher: String?
    let losingPitcher: String?
    let savePitcher: String?
    let endTimeText: String?
    let durationText: String?
    let crowdText: String?
    let probableStarters: GameCenterProbableStarters?
    let lineScore: GameCenterLineScore?
    let review: GameCenterReview?
    let preview: GameCenterPreview?

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(
        game: GameDetail,
        payload: GameCenterDetailPayload?,
        cachedLineScore: GameCenterLineScore? = nil,
        boxscore: GameBoxscoreResponse?,
        databaseRecordReview: GameCenterReview? = nil,
        officialFallbackReview: GameCenterReview? = nil,
        baseRunnerDisplay: BaseRunnerDisplayResolution = .empty
    ) {
        let summary = payload?.summary
        self.game = game
//        let resolvedStatus = summary?.status ?? game.status
        let resolvedStatus: GameStatus = {
            if game.status == .cancelled {
                return .cancelled
            }

            if game.status == .rainDelay {
                return .rainDelay
            }

            if game.status == .final {
                return .final
            }

            return summary?.status ?? game.status
        }()
        status = resolvedStatus
        stadium = summary?.stadium?.nilIfBlank ?? game.venue
        startTimeText = summary?.startTime?.nilIfBlank ?? game.scheduledStart.formatted(date: .omitted, time: .shortened)
        if resolvedStatus.isLiveLike {
            inningText = KBOInningFormatter.korean(game.inningText?.nilIfBlank)
        } else if resolvedStatus == .final {
            inningText = KBOInningFormatter.korean(summary?.inningText?.nilIfBlank ?? game.inningText?.nilIfBlank)
        } else {
            inningText = nil
        }
        awayScore = resolvedStatus.isLiveLike ? game.awayScore : (summary?.awayScore ?? game.awayScore)
        homeScore = resolvedStatus.isLiveLike ? game.homeScore : (summary?.homeScore ?? game.homeScore)
        let officialBaseRunners = summary?.baseRunners.map {
            GameBaseRunners(first: $0.first, second: $0.second, third: $0.third)
        }
        let resolvedCurrentBatterName = game.currentBatterName?.nilIfBlank
        let resolvedCurrentPitcherName = resolvedStatus.isLiveLike
            ? game.currentPitcherName?.nilIfBlank
            : game.currentPitcherName?.nilIfBlank
        let liveSnapshotAuthoritative = resolvedStatus.isLiveLike
        let rawLiveSituation = liveSnapshotAuthoritative
            ? LiveSituationState.fromLatestSnapshot(
                game: game,
                currentBatterName: resolvedCurrentBatterName,
                currentPitcherName: resolvedCurrentPitcherName
            )
            : LiveSituationState.mergedFallback(
                game: game,
                summary: summary,
                currentBatterName: resolvedCurrentBatterName,
                currentPitcherName: resolvedCurrentPitcherName
            )
        let officialOverride = liveSnapshotAuthoritative
            ? Self.liveSituationApplyingOfficialOverrides(
                rawLiveSituation,
                snapshot: game.baseRunners,
                official: officialBaseRunners
            )
            : nil
        let resolvedLiveSituation = officialOverride?.state ?? rawLiveSituation
        liveSituation = resolvedLiveSituation
        balls = resolvedLiveSituation.balls
        strikes = resolvedLiveSituation.strikes
        outs = resolvedLiveSituation.outs
        bases = resolvedLiveSituation.bases
        baseRunners = resolvedLiveSituation.optionalRunnerNames
        let resolvedBaseRunnerDisplay: BaseRunnerDisplayResolution
        if liveSnapshotAuthoritative {
            Self.logLatestSnapshotRawLiveSituation(game: game)
            Self.logLiveSituationAtomicReplaced(resolvedLiveSituation)
            resolvedBaseRunnerDisplay = officialOverride?.display ?? BaseRunnerDisplayResolution(
                runners: resolvedLiveSituation.runnerNames,
                source: "latestSnapshotOnly"
            )
        } else {
            resolvedBaseRunnerDisplay = Self.resolvedBaseRunnerDisplay(
                snapshot: game.baseRunners,
                official: officialBaseRunners,
                cached: baseRunnerDisplay,
                bases: resolvedLiveSituation.bases
            ).mergingOfficialNames(
                snapshot: game.baseRunners,
                official: officialBaseRunners,
                bases: resolvedLiveSituation.bases
            )
        }
        self.baseRunnerDisplay = resolvedBaseRunnerDisplay
        Self.logCountBaseRunnerApplication(
            game: game,
            summary: summary,
            balls: balls,
            strikes: strikes,
            outs: outs,
            bases: bases,
            baseRunners: baseRunners,
            baseRunnerSource: resolvedBaseRunnerDisplay.source
        )
        currentBatterName = resolvedLiveSituation.currentBatterName
        currentPitcherName = resolvedLiveSituation.currentPitcherName
        winningPitcher = summary?.winningPitcher?.nilIfBlank
        losingPitcher = summary?.losingPitcher?.nilIfBlank
        savePitcher = summary?.savePitcher?.nilIfBlank
        endTimeText = summary?.endTime?.nilIfBlank
        durationText = summary?.durationText?.nilIfBlank
        crowdText = summary?.crowdText?.nilIfBlank
        let gameStarterMetadata: GameCenterProbableStarters? = {
            let away = game.awayStartingPitcherName?.nilIfBlank
            let home = game.homeStartingPitcherName?.nilIfBlank
            guard away != nil || home != nil else { return nil }
            return GameCenterProbableStarters(away: away, home: home)
        }()
        probableStarters = payload?.preview?.probableStarters ?? summary?.probableStarters ?? gameStarterMetadata
        lineScore = payload?.lineScore ?? cachedLineScore
        review = Self.preferredRecordReview(
            status: resolvedStatus,
            payloadReview: payload?.review,
            boxscoreReview: boxscore?.gameCenterReview,
            databaseRecordReview: databaseRecordReview,
            officialFallbackReview: officialFallbackReview
        )
        preview = payload?.preview
    }

    private static func preferredRecordReview(
        status: GameStatus,
        payloadReview: GameCenterReview?,
        boxscoreReview: GameCenterReview?,
        databaseRecordReview: GameCenterReview?,
        officialFallbackReview: GameCenterReview?
    ) -> GameCenterReview? {
        if status == .upcoming {
            return nil
        }
        if status.isLiveLike {
            let fullBoxscoreReview = [
                boxscoreReview,
                officialFallbackReview,
                payloadReview
            ]
                .compactMap { $0 }
                .first { $0.recordSource == .fullBoxscore }
            if let databaseRecordReview,
               databaseRecordReview.recordSource == .dbLiveRecordsFresh {
                if let fullBoxscoreReview,
                   let boxscoreUpdatedAt = fullBoxscoreReview.recordUpdatedAt {
                    guard let databaseUpdatedAt = databaseRecordReview.recordUpdatedAt else {
                        return fullBoxscoreReview
                    }
                    if boxscoreUpdatedAt > databaseUpdatedAt {
                        return fullBoxscoreReview
                    }
                }
                return databaseRecordReview
            }
            return fullBoxscoreReview
        }
        if status == .final, let databaseRecordReview {
            return databaseRecordReview.enrichingBatterPositions(from: payloadReview ?? officialFallbackReview)
        }
        let positionSource = payloadReview ?? officialFallbackReview
        let officialBoxscoreReview = [
            boxscoreReview,
            officialFallbackReview,
            payloadReview
        ]
            .compactMap { $0 }
            .first { $0.recordSource.isOfficialBoxscore }

        return officialBoxscoreReview?.enrichingBatterPositions(from: positionSource) ??
            databaseRecordReview?.enrichingBatterPositions(from: positionSource) ??
            officialFallbackReview?.enrichingBatterPositions(from: payloadReview) ??
            payloadReview
    }

    private static func logCountBaseRunnerApplication(
        game: GameDetail,
        summary: GameCenterSummary?,
        balls: Int?,
        strikes: Int?,
        outs: Int?,
        bases: RunnerState?,
        baseRunners: GameBaseRunners?,
        baseRunnerSource: String
    ) {
        #if DEBUG
        if balls != nil || strikes != nil || outs != nil {
            print("[GameDetailPresentation] GameDetailPresentation count applied source=\(game.balls != nil || game.strikes != nil || game.outs != nil ? "latestSnapshot" : "official") count=\(balls.map(String.init) ?? "-")/\(strikes.map(String.init) ?? "-")/\(outs.map(String.init) ?? "-")")
        } else {
            print("[GameDetailPresentation] count/base update skipped reason=missingCountFields")
        }
        if let bases {
            print("[GameDetailPresentation] GameDetailPresentation bases applied source=\(game.bases == nil ? "official" : "latestSnapshot") first=\(bases.first) second=\(bases.second) third=\(bases.third)")
        } else {
            print("[GameDetailPresentation] count/base update skipped reason=missingBases")
        }
        if let baseRunners {
            print("[GameDetailPresentation] GameDetailPresentation runners applied source=\(baseRunnerSource) first=\(baseRunners.first ?? "<nil>") second=\(baseRunners.second ?? "<nil>") third=\(baseRunners.third ?? "<nil>")")
        } else if bases?.first == true || bases?.second == true || bases?.third == true {
            print("[GameDetailPresentation] runner names skipped reason=missingRunnerNames bases first=\(bases?.first == true) second=\(bases?.second == true) third=\(bases?.third == true)")
        }
        print("[GameDetailPresentation] merged bases first=\(boolDebugText(bases?.first)) second=\(boolDebugText(bases?.second)) third=\(boolDebugText(bases?.third))")
        #endif
    }

    private static func boolDebugText(_ value: Bool?) -> String {
        value.map(String.init) ?? "nil"
    }

    private static func logLatestSnapshotRawLiveSituation(game: GameDetail) {
        #if DEBUG
        print(
            "[GameDetailPresentation] latestSnapshot raw liveSituation " +
                "balls=\(game.balls.map(String.init) ?? "-") " +
                "strikes=\(game.strikes.map(String.init) ?? "-") " +
                "outs=\(game.outs.map(String.init) ?? "-") " +
                "runner_on_first=\(boolDebugText(game.bases?.first)) " +
                "runner_on_second=\(boolDebugText(game.bases?.second)) " +
                "runner_on_third=\(boolDebugText(game.bases?.third)) " +
                "firstRunner=\(game.baseRunners?.first ?? "<nil>") " +
                "secondRunner=\(game.baseRunners?.second ?? "<nil>") " +
                "thirdRunner=\(game.baseRunners?.third ?? "<nil>") " +
                "batter=\(game.currentBatterName ?? "<nil>") " +
                "pitcher=\(game.currentPitcherName ?? "<nil>")"
        )
        #endif
    }

    private static func logLiveSituationAtomicReplaced(_ state: LiveSituationState) {
        #if DEBUG
        print(
            "[GameDetailPresentation] liveSituation atomic replaced " +
                "balls=\(state.balls.map(String.init) ?? "-") " +
                "strikes=\(state.strikes.map(String.init) ?? "-") " +
                "outs=\(state.outs.map(String.init) ?? "-") " +
                "runner_on_first=\(state.runnerOnFirst) " +
                "runner_on_second=\(state.runnerOnSecond) " +
                "runner_on_third=\(state.runnerOnThird) " +
                "firstRunner=\(state.firstRunnerName ?? "<nil>") " +
                "secondRunner=\(state.secondRunnerName ?? "<nil>") " +
                "thirdRunner=\(state.thirdRunnerName ?? "<nil>")"
        )
        #endif
    }

    private static func liveSituationApplyingOfficialOverrides(
        _ state: LiveSituationState,
        snapshot: GameBaseRunners?,
        official: GameBaseRunners?
    ) -> (state: LiveSituationState, display: BaseRunnerDisplayResolution)? {
        guard let official else { return nil }
        let first = resolvedOfficialRunnerName(occupied: state.runnerOnFirst, snapshot: snapshot?.first, official: official.first)
        let second = resolvedOfficialRunnerName(occupied: state.runnerOnSecond, snapshot: snapshot?.second, official: official.second)
        let third = resolvedOfficialRunnerName(occupied: state.runnerOnThird, snapshot: snapshot?.third, official: official.third)
        guard first.usedOfficial || second.usedOfficial || third.usedOfficial else {
            return nil
        }
        if first.conflict || second.conflict || third.conflict {
            #if DEBUG
            print(
                "[BaseRunners] official runner names override snapshot reason=conflict " +
                    "firstSnapshot=\(displayName(snapshot?.first)) firstOfficial=\(displayName(official.first)) " +
                    "secondSnapshot=\(displayName(snapshot?.second)) secondOfficial=\(displayName(official.second)) " +
                    "thirdSnapshot=\(displayName(snapshot?.third)) thirdOfficial=\(displayName(official.third))"
            )
            #endif
        }
        let runners = GameBaseRunners(first: first.name, second: second.name, third: third.name)
        return (
            LiveSituationState(
                balls: state.balls,
                strikes: state.strikes,
                outs: state.outs,
                runnerOnFirst: state.runnerOnFirst,
                runnerOnSecond: state.runnerOnSecond,
                runnerOnThird: state.runnerOnThird,
                firstRunnerName: first.name,
                secondRunnerName: second.name,
                thirdRunnerName: third.name,
                currentBatterName: state.currentBatterName,
                currentPitcherName: state.currentPitcherName
            ),
            BaseRunnerDisplayResolution(
                runners: runners,
                source: first.conflict || second.conflict || third.conflict ? "officialOverride" : "latestSnapshotWithOfficialNames"
            )
        )
    }

    private static func resolvedOfficialRunnerName(
        occupied: Bool,
        snapshot: String?,
        official: String?
    ) -> (name: String?, usedOfficial: Bool, conflict: Bool) {
        guard occupied else { return (nil, false, false) }
        let snapshotName = snapshot?.nilIfBlank
        let officialName = official?.nilIfBlank
        if let snapshotName {
            return (snapshotName, false, false)
        }
        if let officialName {
            return (officialName, true, false)
        }
        return (nil, false, false)
    }

    private static func displayName(_ value: String?) -> String {
        value?.nilIfBlank ?? "<nil>"
    }

    private static func resolvedBaseRunnerDisplay(
        snapshot: GameBaseRunners?,
        official: GameBaseRunners?,
        cached: BaseRunnerDisplayResolution,
        bases: RunnerState?
    ) -> BaseRunnerDisplayResolution {
        guard let bases else {
            return cached
        }
        let runners = GameBaseRunners(
            first: resolvedRunnerName(
                occupied: bases.first,
                snapshot: snapshot?.first,
                official: official?.first,
                cached: cached.runners.first
            ),
            second: resolvedRunnerName(
                occupied: bases.second,
                snapshot: snapshot?.second,
                official: official?.second,
                cached: cached.runners.second
            ),
            third: resolvedRunnerName(
                occupied: bases.third,
                snapshot: snapshot?.third,
                official: official?.third,
                cached: cached.runners.third
            )
        )
        return BaseRunnerDisplayResolution(runners: runners, source: "presentation")
    }

    private static func resolvedRunnerName(
        occupied: Bool,
        snapshot: String?,
        official: String?,
        cached: String?
    ) -> String? {
        guard occupied else { return nil }
        return snapshot?.nilIfBlank ?? official?.nilIfBlank ?? cached?.nilIfBlank ?? "주자"
    }

    var scoreStatusText: String {
        switch status {
        case .upcoming:
            "예정"
        case .live, .rainDelay:
            inningText ?? status.title
        case .final, .cancelled:
            status.title
        }
    }

    var liveSituationSummary: String {
        let countText = [
            KBOCountDisplay.balls(balls).map { "볼 \($0)" },
            KBOCountDisplay.strikes(strikes).map { "스트라이크 \($0)" },
            KBOCountDisplay.outs(outs).map { "아웃 \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        let matchupText = [
            currentBatterName.map { "타자 \($0)" },
            currentPitcherName.map { "투수 \($0)" }
        ]
            .compactMap { $0 }
            .joined(separator: " · ")

        if countText.isEmpty == false, matchupText.isEmpty == false {
            return "\(countText) · \(matchupText)"
        }
        if countText.isEmpty == false {
            return countText
        }
        if matchupText.isEmpty == false {
            return matchupText
        }
        guard countText.isEmpty == false else {
            return inningText ?? "실시간 상황이 들어오는 중입니다."
        }
        return countText
    }

    var finalSummaryText: String {
        var segments: [String] = []
        if let winningPitcher {
            segments.append("승리투수 \(winningPitcher)")
        }
        if let losingPitcher {
            segments.append("패전투수 \(losingPitcher)")
        }
        if let savePitcher {
            segments.append("세이브 \(savePitcher)")
        }
        if let durationText {
            segments.append("경기시간 \(durationText)")
        }
        return segments.isEmpty ? "최종 스코어와 라인스코어를 확인하세요." : segments.joined(separator: " · ")
    }

    var visibleBaseRunners: [BaseRunnerDisplayItem] {
        liveSituation.displayBaseRunners
    }

    var displayBaseRunners: [BaseRunnerDisplayItem] {
        visibleBaseRunners
    }

    var displayAwayScore: String {
        showsLiveOrFinalScore ? (awayScore.map(String.init) ?? "-") : ""
    }

    var displayHomeScore: String {
        showsLiveOrFinalScore ? (homeScore.map(String.init) ?? "-") : ""
    }

    var showsLiveOrFinalScore: Bool {
        status.isLiveLike || status.isFinishedLike
    }

    // logRenderedBaseRunnersIfNeeded 메서드는 이 타입의 주요 동작을 수행합니다.
    func logRenderedBaseRunnersIfNeeded() {
        #if DEBUG
        print("[BaseRunners] snapshot names first=\(liveSituation.firstRunnerName ?? "<nil>") second=\(liveSituation.secondRunnerName ?? "<nil>") third=\(liveSituation.thirdRunnerName ?? "<nil>")")
        let rendered = displayBaseRunners.reduce(into: ["1B": "empty", "2B": "empty", "3B": "empty"]) { result, item in
            result[item.base] = item.name
        }
        print("[BaseRunners] rendered first=\(rendered["1B"] ?? "unknown") second=\(rendered["2B"] ?? "unknown") third=\(rendered["3B"] ?? "unknown") source=\(baseRunnerDisplay.source)")
        #endif
    }

    // logBaseRunnersBeforeRendering 메서드는 SwiftUI 렌더 직전 점유/표시 상태를 남깁니다.
    func logBaseRunnersBeforeRendering() {
        #if DEBUG
        let rendered = displayBaseRunners.reduce(into: ["1B": "empty", "2B": "empty", "3B": "empty"]) { result, item in
            result[item.base] = item.name
        }
        print("[BaseRunners] renderWillUse firstOccupied=\(liveSituation.runnerOnFirst) first=\(rendered["1B"] ?? "empty") secondOccupied=\(liveSituation.runnerOnSecond) second=\(rendered["2B"] ?? "empty") thirdOccupied=\(liveSituation.runnerOnThird) third=\(rendered["3B"] ?? "empty")")
        #endif
    }
}

// BaseRunnerDisplayItem 구조체는 BaseRunnerDisplayItem 타입의 역할과 값을 정의합니다.
struct BaseRunnerDisplayItem: Identifiable, Equatable {
    let base: String
    let name: String

    var id: String { base }
}

// GameStatusSummaryCard 구조체는 GameStatusSummaryCard 타입의 역할과 값을 정의합니다.
private struct GameStatusSummaryCard: View {
    @Environment(AppModel.self) private var appModel
    let presentation: GameDetailPresentation

    var body: some View {
        let palette = appModel.favoriteStadiumPalette
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                ScoreColumn(
                    title: "원정",
                    team: presentation.game.awayTeam,

                    tint: presentation.game.awayTeam.identity.theme.accent
                )

                VStack(spacing: 8) {
                    Text(statusTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(palette.map { presentation.status.stadiumTintColor($0) } ?? presentation.status.tintColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    if presentation.showsLiveOrFinalScore {
                        Text("\(presentation.displayAwayScore) : \(presentation.displayHomeScore)")
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                    } else {
                        Text(presentation.startTimeText ?? "TBD")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                    }

                }
                .frame(maxWidth: .infinity)

                ScoreColumn(
                    title: "홈",
                    team: presentation.game.homeTeam,

                    tint: presentation.game.homeTeam.identity.theme.accent
                )
            }

            switch presentation.status {
            case .live, .rainDelay:
                LiveSituationRow(presentation: presentation)
            case .final:
                FinalDecisionRow(presentation: presentation)
            case .upcoming:
                ScheduledInfoRow(presentation: presentation)
            case .cancelled:
                DetailMessageCard(
                    icon: "xmark.circle",
                    title: "경기 취소",
                    message: "취소된 경기입니다. 추가 라이브 데이터는 제공되지 않습니다."
                )
            }
        }
        .cardSurface(
            padding: 14,
            cornerRadius: 22,
            fillColor: palette.map { presentation.status.stadiumCardBackgroundColor($0) } ?? presentation.status.cardBackgroundColor
        )
    }

    private var statusTitle: String {
        presentation.inningText ?? presentation.status.title
    }

    private var subtitleText: String {
        switch presentation.status {
        case .upcoming:
            presentation.stadium
        case .live, .rainDelay:
            presentation.liveSituationSummary
        case .final:
            presentation.finalSummaryText
        case .cancelled:
            "경기 진행 정보가 없습니다."
        }
    }
}

// ScoreColumn 구조체는 ScoreColumn 타입의 역할과 값을 정의합니다.
private struct ScoreColumn: View {
    let title: String
    let team: Team

    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            Text(team.displayName)
                .font(.title3.weight(.heavy))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

        }
        .frame(maxWidth: .infinity)
    }
}

// LiveSituationRow 구조체는 LiveSituationRow 타입의 역할과 값을 정의합니다.
private struct LiveSituationRow: View {
    let presentation: GameDetailPresentation

    var body: some View {
        VStack(spacing: 8) {
            StatusTile(title: "주자 상황 · 카운트") {
                LiveSituationSummaryContent(presentation: presentation)
                    .onAppear {
                        presentation.logRenderedBaseRunnersIfNeeded()
                    }
            }

            if presentation.status.isLiveLike || presentation.currentBatterName != nil || presentation.currentPitcherName != nil {
                HStack(spacing: 8) {
                    StatusTile(title: "타자") {
                        Text(presentation.currentBatterName ?? "-")
                            .font(.subheadline.weight(.bold))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    StatusTile(title: "투수") {
                        Text(presentation.currentPitcherName ?? "-")
                            .font(.subheadline.weight(.bold))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// LiveSituationSummaryContent 구조체는 주자 상황과 카운트를 하나의 카드 안에 표시합니다.
private struct LiveSituationSummaryContent: View {
    @Environment(AppModel.self) private var appModel
    let presentation: GameDetailPresentation

    var body: some View {
        let _ = presentation.logBaseRunnersBeforeRendering()
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 0) {
                GameDetailBasesDiamondView(
                    bases: presentation.liveSituation.bases,
                    tint: appModel.favoriteStadiumPalette?.primary ?? appModel.currentTheme.accent,
                    borderTint: baseBorderTint
                )

                Spacer(minLength: 36)

                CountDotsStack(
                    balls: KBOCountDisplay.balls(presentation.liveSituation.balls),
                    strikes: KBOCountDisplay.strikes(presentation.liveSituation.strikes),
                    outs: KBOCountDisplay.outs(presentation.liveSituation.outs)
                )
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)

            BaseRunnerGrid(runners: presentation.displayBaseRunners)
        }
    }

    private var baseBorderTint: Color {
        switch appModel.settings.favoriteTeamID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "kt", "lg":
            .white
        default:
            appModel.favoriteStadiumPalette?.primary ?? appModel.currentTheme.accent
        }
    }
}

// GameDetailBasesDiamondView 구조체는 경기상세 통합 카드에서 1루, 2루, 3루만 크게 표시합니다.
private struct GameDetailBasesDiamondView: View {
    let bases: RunnerState
    let tint: Color
    let borderTint: Color

    var body: some View {
        ZStack {
            GameDetailBaseMarker(isFilled: bases.second, tint: tint, borderTint: borderTint)
                .offset(y: -22)
            GameDetailBaseMarker(isFilled: bases.first, tint: tint, borderTint: borderTint)
                .offset(x: 25, y: 4)
            GameDetailBaseMarker(isFilled: bases.third, tint: tint, borderTint: borderTint)
                .offset(x: -25, y: 4)
        }
        .frame(width: 96, height: 74)
    }
}

// GameDetailBaseMarker 구조체는 점유 여부에 따라 베이스 채움과 테두리 강조를 표시합니다.
private struct GameDetailBaseMarker: View {
    let isFilled: Bool
    let tint: Color
    let borderTint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(borderColor, lineWidth: isFilled ? 2.5 : 1.6)
            )
            .frame(width: 22, height: 22)
            .rotationEffect(.degrees(45))
            .shadow(color: borderColor.opacity(isFilled ? 0.25 : 0.12), radius: 2, x: 0, y: 1)
    }

    private var fillColor: Color {
        isFilled ? tint : Color(.systemBackground).opacity(0.82)
    }

    private var borderColor: Color {
        isFilled ? borderTint : borderTint.opacity(0.78)
    }
}

// BaseRunnerGrid 구조체는 1루, 2루, 3루 주자 이름을 같은 폭의 3열로 표시합니다.
private struct BaseRunnerGrid: View {
    let runners: [BaseRunnerDisplayItem]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(baseColumns, id: \.id) { column in
                VStack(spacing: 4) {
                    Text(column.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(runnerName(for: column.id))
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var baseColumns: [(id: String, title: String)] {
        [("1B", "1루"), ("2B", "2루"), ("3B", "3루")]
    }

    private func runnerName(for base: String) -> String {
        runners.first { $0.base == base }?.name ?? "-"
    }
}

// CountDotsStack 구조체는 B/S/O 카운트를 점 형태로 세로 표시합니다.
private struct CountDotsStack: View {
    var balls: Int?
    var strikes: Int?
    var outs: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CountDotsRow(label: "B", tint: .green, value: balls, maxValue: 3)
            CountDotsRow(label: "S", tint: .orange, value: strikes, maxValue: 2)
            CountDotsRow(label: "O", tint: .red, value: outs, maxValue: 2)
        }
    }
}

// CountDotsRow 구조체는 한 종류의 카운트를 채워진 점과 비어 있는 점으로 표시합니다.
private struct CountDotsRow: View {
    @Environment(AppModel.self) private var appModel
    let label: String
    let tint: Color
    let value: Int?
    let maxValue: Int

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption.weight(.heavy))
                .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                .frame(width: 12, alignment: .leading)

            ForEach(0..<maxValue, id: \.self) { index in
                Circle()
                    .fill(index < normalizedValue ? tint : tint.opacity(0.18))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var normalizedValue: Int {
        min(max(value ?? 0, 0), maxValue)
    }
}

// FinalDecisionRow 구조체는 FinalDecisionRow 타입의 역할과 값을 정의합니다.
private struct FinalDecisionRow: View {
    let presentation: GameDetailPresentation

    var body: some View {
        HStack(spacing: 8) {
            if let winningPitcher = presentation.winningPitcher {
                DecisionTag(title: "승", value: winningPitcher, tint: KBOLivePalette.live)
            }
            if let losingPitcher = presentation.losingPitcher {
                DecisionTag(title: "패", value: losingPitcher, tint: KBOLivePalette.final)
            }
            if let savePitcher = presentation.savePitcher {
                DecisionTag(title: "세", value: savePitcher, tint: KBOLivePalette.primary)
            }
        }
    }
}

// DecisionTag 구조체는 DecisionTag 타입의 역할과 값을 정의합니다.
private struct DecisionTag: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

// ScheduledInfoRow 구조체는 ScheduledInfoRow 타입의 역할과 값을 정의합니다.
private struct ScheduledInfoRow: View {
    let presentation: GameDetailPresentation

    var body: some View {
        HStack(spacing: 8) {
            StatusTile(title: "경기 시작") {
                Text(presentation.startTimeText ?? "미정")
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
            }

            StatusTile(title: "구장") {
                Text(presentation.stadium)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
            }
        }
    }
}

// StatusTile 구조체는 StatusTile 타입의 역할과 값을 정의합니다.
private struct StatusTile<Content: View>: View {
    @Environment(AppModel.self) private var appModel
    let title: String
    let content: Content

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            appModel.favoriteStadiumPalette?.recessedSurface ?? Color(.systemBackground).opacity(0.82),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}

// OverviewMetadataCard 구조체는 OverviewMetadataCard 타입의 역할과 값을 정의합니다.
private struct OverviewMetadataCard: View {
    let presentation: GameDetailPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("경기 개요")
                .font(.headline.weight(.bold))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                MetaValueTile(title: "상태", value: presentation.scoreStatusText)
                MetaValueTile(title: "구장", value: presentation.stadium)
                MetaValueTile(title: "시작", value: presentation.startTimeText ?? "미정")
                MetaValueTile(title: "관중", value: presentation.crowdText ?? "미집계")
                MetaValueTile(title: "종료", value: presentation.endTimeText ?? "진행 중")
                MetaValueTile(title: "경기시간", value: presentation.durationText ?? "집계 중")
            }
        }
        .cardSurface()
    }
}

// MetaValueTile 구조체는 MetaValueTile 타입의 역할과 값을 정의합니다.
private struct MetaValueTile: View {
    @Environment(AppModel.self) private var appModel
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(10)
        .background(
            appModel.favoriteStadiumPalette?.recessedSurface ?? Color(.tertiarySystemBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}

// GameLineScoreCard 구조체는 GameLineScoreCard 타입의 역할과 값을 정의합니다.
private struct GameLineScoreCard: View {
    @Environment(AppModel.self) private var appModel
    let presentation: GameDetailPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("라인스코어")
                .font(.headline.weight(.bold))

            if let lineScore = presentation.lineScore {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 8) {
                        LineScoreHeaderRow(inningLabels: lineScore.inningLabels)
                        LineScoreValueRow(team: presentation.game.awayTeam, inningValues: lineScore.awayInnings, totals: lineScore.awayTotals)
                        LineScoreValueRow(team: presentation.game.homeTeam, inningValues: lineScore.homeInnings, totals: lineScore.homeTotals, isHome: true)
                    }
                }
            } else {
                fallbackContent
            }
        }
        .cardSurface()
    }

    @ViewBuilder
    private var fallbackContent: some View {
        switch presentation.status {
        case .upcoming:
            Text("경기 시작 후 이닝별 득점과 팀 합계가 표시됩니다.")
                .font(.subheadline)
                .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
        case .live, .rainDelay:
            Text("이닝별 점수 데이터 준비 중")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
        case .cancelled:
            Text("취소된 경기입니다.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
        default:
            VStack(spacing: 8) {
                FallbackLineScoreRow(team: presentation.game.awayTeam, runs: presentation.awayScore)
                FallbackLineScoreRow(team: presentation.game.homeTeam, runs: presentation.homeScore, isHome: true)
                Text("현재 데이터 소스에서 이닝별 점수는 아직 제공되지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
            }
        }
    }
}

// LineScoreHeaderRow 구조체는 LineScoreHeaderRow 타입의 역할과 값을 정의합니다.
private struct LineScoreHeaderRow: View {
    @Environment(AppModel.self) private var appModel
    let inningLabels: [String]

    var body: some View {
        HStack(spacing: 6) {
            Text("TEAM")
                .font(.caption2.weight(.bold))
                .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                .frame(width: 72, alignment: .leading)

            ForEach(inningLabels.indices, id: \.self) { index in
                Text(inningLabels[index])
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                    .frame(width: 30)
            }

            ForEach(["R", "H", "E", "B"], id: \.self) { label in
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                    .frame(width: 34)
            }
        }
    }
}

// LineScoreValueRow 구조체는 LineScoreValueRow 타입의 역할과 값을 정의합니다.
private struct LineScoreValueRow: View {
    @Environment(AppModel.self) private var appModel
    let team: Team
    let inningValues: [String]
    let totals: GameCenterTeamLineTotals
    var isHome: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(team.displayName)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
            }
            .frame(width: 72, alignment: .leading)

            ForEach(inningValues.indices, id: \.self) { index in
                Text(inningValues[index].displayCellText)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 30)
            }

            Text(totals.runs?.displayCellText ?? "-")
                .lineScoreTotalStyle(emphasis: true)
            Text(totals.hits?.displayCellText ?? "-")
                .lineScoreTotalStyle()
            Text(totals.errors?.displayCellText ?? "-")
                .lineScoreTotalStyle()
            Text(totals.walks?.displayCellText ?? "-")
                .lineScoreTotalStyle()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(appModel.favoriteStadiumPalette.map { isHome ? $0.elevatedCardStrong : $0.recessedSurface } ?? (isHome ? Color(.tertiarySystemBackground) : Color(.secondarySystemBackground)))
        )
    }
}

// FallbackLineScoreRow 구조체는 FallbackLineScoreRow 타입의 역할과 값을 정의합니다.
private struct FallbackLineScoreRow: View {
    @Environment(AppModel.self) private var appModel
    let team: Team
    let runs: Int?
    var isHome: Bool = false

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Text(team.displayName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("R")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                Text(runs.map(String.init) ?? "-")
                    .font(.title3.weight(.heavy))
                    .monospacedDigit()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(appModel.favoriteStadiumPalette.map { isHome ? $0.elevatedCardStrong : $0.recessedSurface } ?? (isHome ? Color(.tertiarySystemBackground) : Color(.secondarySystemBackground)))
        )
    }
}

// SummaryItemsCard 구조체는 SummaryItemsCard 타입의 역할과 값을 정의합니다.
private struct SummaryItemsCard: View {
    let items: [GameCenterSummaryItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("경기 요약")
                .font(.headline.weight(.bold))

            ForEach(items) { item in
                HStack(alignment: .top, spacing: 10) {
                    Text(item.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .leading)
                    Text(item.value)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .cardSurface()
    }
}

// GameDetailRecordTab 열거형는 GameDetailRecordTab 타입의 역할과 값을 정의합니다.
private enum GameDetailRecordTab: String, CaseIterable, Identifiable {
    case batting = "실시간 라인업 / 타자 기록"
    case pitching = "투수 기록"
    case summary = "주요 기록"

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .batting:
            "타자"
        case .pitching:
            "투수"
        case .summary:
            "주요"
        }
    }
}

// GameDetailRecordTeam 열거형는 GameDetailRecordTeam 타입의 역할과 값을 정의합니다.
private enum GameDetailRecordTeam: String, CaseIterable, Identifiable {
    case away = "원정"
    case home = "홈"

    var id: String { rawValue }
}

// GameDetailRecordsPanel 구조체는 GameDetailRecordsPanel 타입의 역할과 값을 정의합니다.
private struct GameDetailRecordsPanel: View {
    @State private var selectedTab: GameDetailRecordTab = .batting
    @State private var selectedTeam: GameDetailRecordTeam = .away

    let presentation: GameDetailPresentation
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("상세 기록")
                    .font(.headline.weight(.bold))
                Spacer()
                if presentation.status.isLiveLike {
                    Text("LIVE")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(KBOLivePalette.live)
                }
            }

            recordTabPicker

            if let review = presentation.review {
                switch selectedTab {
                case .batting:
                    TeamRecordSwitcher(
                        selection: $selectedTeam,
                        awayTeam: presentation.game.awayTeam,
                        homeTeam: presentation.game.homeTeam
                    )
                    if presentation.status.isLiveLike, review.recordSource.isLimited {
                        LimitedRecordSourceNote()
                    }
                    BattingSectionTable(
                        team: selectedTeam == .away ? presentation.game.awayTeam : presentation.game.homeTeam,
                        section: selectedTeam == .away ? review.awayBatting : review.homeBatting,
                        isLiveLike: presentation.status.isLiveLike
                    )
                case .pitching:
                    TeamRecordSwitcher(
                        selection: $selectedTeam,
                        awayTeam: presentation.game.awayTeam,
                        homeTeam: presentation.game.homeTeam
                    )
                    if presentation.status.isLiveLike, review.recordSource.isLimited {
                        LimitedRecordSourceNote()
                    }
                    PitchingSectionTable(
                        team: selectedTeam == .away ? presentation.game.awayTeam : presentation.game.homeTeam,
                        section: selectedTeam == .away ? review.awayPitching : review.homePitching
                    )
                case .summary:
                    KeyRecordsComparisonView(presentation: presentation, review: review)
                }
            } else if isLoading {
                DetailInlineLoadingView(message: "기록 데이터를 불러오는 중")
            } else {
                RecordsEmptyState(status: presentation.status)
            }
        }
        .cardSurface()
    }

    private var recordTabPicker: some View {
        Picker("기록 섹션", selection: $selectedTab) {
            ForEach(GameDetailRecordTab.allCases) { tab in
                Text(tab.shortTitle).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }
}

// TeamRecordSwitcher 구조체는 TeamRecordSwitcher 타입의 역할과 값을 정의합니다.
private struct TeamRecordSwitcher: View {
    @Binding var selection: GameDetailRecordTeam
    let awayTeam: Team
    let homeTeam: Team

    var body: some View {
        HStack(spacing: 8) {
            TeamRecordButton(
                title: awayTeam.displayName,
                team: awayTeam,
                isSelected: selection == .away
            ) {
                selection = .away
            }
            TeamRecordButton(
                title: homeTeam.displayName,
                team: homeTeam,
                isSelected: selection == .home
            ) {
                selection = .home
            }
        }
    }
}

// TeamRecordButton 구조체는 TeamRecordButton 타입의 역할과 값을 정의합니다.
private struct TeamRecordButton: View {
    @Environment(AppModel.self) private var appModel
    let title: String
    let team: Team
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? team.identity.theme.accent.opacity(0.24) : (appModel.favoriteStadiumPalette?.recessedSurface ?? Color(.tertiarySystemBackground)))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? team.identity.theme.accent.opacity(0.75) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// LimitedRecordSourceNote 구조체는 LimitedRecordSourceNote 타입의 역할과 값을 정의합니다.
private struct LimitedRecordSourceNote: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.caption.weight(.semibold))
            Text("공식 전체 박스스코어를 불러오지 못해 제공된 일부 기록만 표시합니다.")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
    }
}

// BattingSectionTable 구조체는 BattingSectionTable 타입의 역할과 값을 정의합니다.
private struct BattingSectionTable: View {
    @Environment(AppModel.self) private var appModel
    let team: Team
    let section: GameCenterBattingSection
    let isLiveLike: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("실시간 라인업 / 타자 기록", systemImage: "figure.baseball")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if section.lines.isEmpty == false {
                    Text(team.shortName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if section.lines.isEmpty {
                RecordsEmptyState(status: .live)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        BattingHeaderRow(isLiveLike: isLiveLike)
                        ForEach(section.lines) { line in
                            BattingValueRow(line: line, isLiveLike: isLiveLike)
                        }
                        if let totals = section.displayedRecordTotals {
                            BattingTotalsRow(totals: totals, isLiveLike: isLiveLike)
                        }
                    }
                }
            }
        }
    }
}

// GameDetailBattingTableColumns 열거형는 GameDetailBattingTableColumns 타입의 역할과 값을 정의합니다.
enum GameDetailBattingTableColumns {
    // headers 메서드는 이 타입의 주요 동작을 수행합니다.
    static func headers(isLiveLike: Bool) -> [String] {
        if isLiveLike {
            return ["타수", "득점", "안타", "타점", "홈런", "삼진", "볼넷"]
        }
        return ["타수", "득점", "안타", "타점", "홈런", "볼넷", "삼진", "도루", "타율"]
    }

    // values 메서드는 이 타입의 주요 동작을 수행합니다.
    static func values(for line: GameCenterBattingLine, isLiveLike: Bool) -> [String] {
        if isLiveLike {
            return [
                line.atBats.displayStat,
                line.runs.displayStat,
                line.hits.displayStat,
                line.runsBattedIn.displayStat,
                (line.homeRuns ?? line.plateAppearanceHomeRuns).displayStat,
                (line.strikeouts ?? line.plateAppearanceStrikeouts).displayStat,
                (line.walks ?? line.plateAppearanceWalks).displayStat
            ]
        }
        return [
            line.atBats.displayStat,
            line.runs.displayStat,
            line.hits.displayStat,
            line.runsBattedIn.displayStat,
            (line.homeRuns ?? line.plateAppearanceHomeRuns).displayStat,
            (line.walks ?? line.plateAppearanceWalks).displayStat,
            (line.strikeouts ?? line.plateAppearanceStrikeouts).displayStat,
            line.stolenBases.displayStolenBaseStat,
            line.average.displayStat
        ]
    }

    // values 메서드는 이 타입의 주요 동작을 수행합니다.
    static func values(for totals: GameCenterBattingTotals, isLiveLike: Bool) -> [String] {
        if isLiveLike {
            return [
                totals.atBats.displayStat,
                totals.runs.displayStat,
                totals.hits.displayStat,
                totals.runsBattedIn.displayStat,
                (totals.homeRuns ?? totals.plateAppearanceHomeRuns).displayStat,
                (totals.strikeouts ?? totals.plateAppearanceStrikeouts).displayStat,
                (totals.walks ?? totals.plateAppearanceWalks).displayStat
            ]
        }
        return [
            totals.atBats.displayStat,
            totals.runs.displayStat,
            totals.hits.displayStat,
            totals.runsBattedIn.displayStat,
            (totals.homeRuns ?? totals.plateAppearanceHomeRuns).displayStat,
            (totals.walks ?? totals.plateAppearanceWalks).displayStat,
            (totals.strikeouts ?? totals.plateAppearanceStrikeouts).displayStat,
            totals.stolenBases.displayStolenBaseStat,
            totals.average.displayStat
        ]
    }
}

// BattingHeaderRow 구조체는 BattingHeaderRow 타입의 역할과 값을 정의합니다.
private struct BattingHeaderRow: View {
    let isLiveLike: Bool

    var body: some View {
        StatsTableRow(
            name: "타자명",
            position: "포지션",
            values: GameDetailBattingTableColumns.headers(isLiveLike: isLiveLike),
            isHeader: true
        )
    }
}

// BattingValueRow 구조체는 BattingValueRow 타입의 역할과 값을 정의합니다.
private struct BattingValueRow: View {
    let line: GameCenterBattingLine
    let isLiveLike: Bool

    var body: some View {
        StatsTableRow(
            order: line.battingOrder,
            name: line.name,
            position: GameRecordPositionFormatter.display(line.position),
            values: GameDetailBattingTableColumns.values(for: line, isLiveLike: isLiveLike)
        )
    }
}

// BattingTotalsRow 구조체는 BattingTotalsRow 타입의 역할과 값을 정의합니다.
private struct BattingTotalsRow: View {
    let totals: GameCenterBattingTotals
    let isLiveLike: Bool

    var body: some View {
        StatsTableRow(
            name: "합계",
            position: "",
            values: GameDetailBattingTableColumns.values(for: totals, isLiveLike: isLiveLike),
            isTotal: true
        )
    }
}

// PitchingSectionTable 구조체는 PitchingSectionTable 타입의 역할과 값을 정의합니다.
private struct PitchingSectionTable: View {
    let team: Team
    let section: GameCenterPitchingSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("투수 기록", systemImage: "baseball.diamond.bases")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if section.lines.isEmpty == false {
                    Text(team.shortName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if section.lines.isEmpty {
                RecordsEmptyState(status: .live)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        PitchingHeaderRow()
                        ForEach(section.lines) { line in
                            PitchingValueRow(line: line)
                        }
                        if let totals = GameCenterPitchingTotals.derived(from: section.lines) {
                            PitchingTotalsRow(totals: totals)
                        }
                    }
                }
            }
        }
        .onAppear {
            #if DEBUG
            print("[GameDetailLive] selectedTeamPitcherRows team=\(team.shortName) count=\(section.lines.count)")
            for line in section.lines {
                print("[GameDetailLive] pitcher row side=selected player=\(line.name) source=view stats=IP:\(line.innings ?? "-") K:\(line.strikeouts ?? "-") R:\(line.runsAllowed ?? "-")")
            }
            #endif
        }
    }
}

// PitchingHeaderRow 구조체는 PitchingHeaderRow 타입의 역할과 값을 정의합니다.
private struct PitchingHeaderRow: View {
    var body: some View {
        StatsTableRow(
            name: "투수명",
            position: "",
            values: ["순서", "등판", "결과", "이닝", "타자", "투구수", "타수", "피안타", "피홈런", "4사구", "삼진", "실점", "자책", "평균자책"],
            isHeader: true,
            nameWidth: 118
        )
    }
}

// PitchingValueRow 구조체는 PitchingValueRow 타입의 역할과 값을 정의합니다.
private struct PitchingValueRow: View {
    let line: GameCenterPitchingLine

    var body: some View {
        StatsTableRow(
            name: line.displayName,
            position: "",
            values: [
                line.pitchingOrder.displayStat,
                line.role.displayStat,
                line.result.displayStat,
                line.innings.displayStat,
                line.battersFaced.displayStat,
                line.pitches.displayStat,
                line.atBats.displayStat,
                line.hitsAllowed.displayStat,
                line.homeRunsAllowed.displayStat,
                (line.walksOrHitByPitch ?? line.walksAllowed).displayStat,
                line.strikeouts.displayStat,
                line.runsAllowed.displayStat,
                line.earnedRuns.displayStat,
                line.earnedRunAverage.displayStat
            ],
            nameWidth: 118
        )
    }
}

// PitchingTotalsRow 구조체는 PitchingTotalsRow 타입의 역할과 값을 정의합니다.
private struct PitchingTotalsRow: View {
    let totals: GameCenterPitchingTotals

    var body: some View {
        StatsTableRow(
            name: "합계",
            position: "",
            values: [
                "-",
                "-",
                "-",
                totals.innings.displayStat,
                totals.battersFaced.displayStat,
                totals.pitches.displayStat,
                totals.atBats.displayStat,
                totals.hitsAllowed.displayStat,
                totals.homeRunsAllowed.displayStat,
                totals.walksOrHitByPitch.displayStat,
                totals.strikeouts.displayStat,
                totals.runsAllowed.displayStat,
                totals.earnedRuns.displayStat,
                "-"
            ],
            isTotal: true,
            nameWidth: 118
        )
    }
}

// StatsTableRow 구조체는 StatsTableRow 타입의 역할과 값을 정의합니다.
private struct StatsTableRow: View {
    @Environment(AppModel.self) private var appModel
    var order: String? = nil
    let name: String
    let position: String
    let values: [String]
    var isHeader = false
    var isTotal = false
    var nameWidth: CGFloat = 132
    private let valueWidth: CGFloat = 46

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                if let order = order?.battingOrderNumber {
                    Text(order)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(isHeader ? secondaryColor : primaryColor)
                        .frame(width: 18, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(isHeader ? .caption.weight(.bold) : .subheadline.weight(isTotal ? .heavy : .semibold))
                        .foregroundStyle(isHeader ? secondaryColor : primaryColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    if position.isEmpty == false {
                        Text(position)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(secondaryColor)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: nameWidth, alignment: .leading)
            .padding(.horizontal, 8)

            ForEach(values.indices, id: \.self) { index in
                Text(values[index])
                    .font(isHeader ? .caption.weight(.bold) : .subheadline.weight(isTotal ? .heavy : .semibold))
                    .foregroundStyle(isHeader ? secondaryColor : primaryColor)
                    .monospacedDigit()
                    .frame(width: valueWidth)
            }
        }
        .frame(minHeight: isHeader ? 38 : 48)
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(appModel.favoriteStadiumPalette?.ghostBorder ?? Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private var primaryColor: Color {
        appModel.favoriteStadiumPalette?.textPrimary ?? .primary
    }

    private var secondaryColor: Color {
        appModel.favoriteStadiumPalette?.textSecondary ?? .secondary
    }

    private var rowBackground: Color {
        if isHeader || isTotal {
            return appModel.favoriteStadiumPalette?.elevatedCardStrong ?? Color(.secondarySystemBackground)
        }
        return Color.clear
    }
}

// KeyRecordsComparisonView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
private struct KeyRecordsComparisonView: View {
    let presentation: GameDetailPresentation
    let review: GameCenterReview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(presentation.game.awayTeam.displayName)
                    .font(.subheadline.weight(.heavy))
                    .frame(maxWidth: .infinity)
                Text("VS")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.secondary)
                Text(presentation.game.homeTeam.displayName)
                    .font(.subheadline.weight(.heavy))
                    .frame(maxWidth: .infinity)
            }

            ForEach(metrics) { metric in
                KeyRecordComparisonRow(
                    title: metric.title,
                    awayValue: metric.away,
                    homeValue: metric.home,
                    awayColor: presentation.game.awayTeam.identity.theme.accent,
                    homeColor: presentation.game.homeTeam.identity.theme.accent
                )
            }
        }
    }

    private var metrics: [KeyRecordMetric] {
        let stats = review.keyStats(
            awayTeam: presentation.game.awayTeam,
            homeTeam: presentation.game.homeTeam,
            lineScore: presentation.lineScore
        )
        return [
            KeyRecordMetric(title: "안타", away: stats.away.hits, home: stats.home.hits),
            KeyRecordMetric(title: "홈런", away: stats.away.homeRuns, home: stats.home.homeRuns),
            KeyRecordMetric(title: "도루", away: stats.away.stolenBases, home: stats.home.stolenBases),
            KeyRecordMetric(title: "삼진", away: stats.away.strikeouts, home: stats.home.strikeouts),
            KeyRecordMetric(title: "병살", away: stats.away.doublePlays, home: stats.home.doublePlays),
            KeyRecordMetric(title: "실책", away: stats.away.errors, home: stats.home.errors)
        ]
    }
}

// KeyRecordMetric 구조체는 KeyRecordMetric 타입의 역할과 값을 정의합니다.
private struct KeyRecordMetric: Identifiable {
    let title: String
    let away: Int?
    let home: Int?

    var id: String { title }
}

// KeyRecordComparisonRow 구조체는 KeyRecordComparisonRow 타입의 역할과 값을 정의합니다.
private struct KeyRecordComparisonRow: View {
    let title: String
    let awayValue: Int?
    let homeValue: Int?
    let awayColor: Color
    let homeColor: Color

    var body: some View {
        HStack(spacing: 10) {
            ComparisonBar(value: awayValue, maxValue: maxValue, color: awayColor, alignment: .trailing)
            Text(awayValue.map(String.init) ?? "-")
                .comparisonValueStyle()
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44)
            Text(homeValue.map(String.init) ?? "-")
                .comparisonValueStyle()
            ComparisonBar(value: homeValue, maxValue: maxValue, color: homeColor, alignment: .leading)
        }
    }

    private var maxValue: Int {
        max(awayValue ?? 0, homeValue ?? 0)
    }
}

// ComparisonBar 구조체는 ComparisonBar 타입의 역할과 값을 정의합니다.
private struct ComparisonBar: View {
    let value: Int?
    let maxValue: Int
    let color: Color
    let alignment: Alignment

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: alignment) {
                Capsule()
                    .fill(Color.white.opacity(0.09))
                if maxValue > 0, let value {
                    Capsule()
                        .fill(color.opacity(0.78))
                        .frame(width: max(4, proxy.size.width * CGFloat(value) / CGFloat(maxValue)))
                }
            }
        }
        .frame(height: 8)
    }
}

// RecordsEmptyState 구조체는 화면이나 도메인 흐름에서 사용하는 상태 값을 표현합니다.
private struct RecordsEmptyState: View {
    let status: GameStatus

    var body: some View {
        DetailMessageCard(
            icon: "chart.bar.doc.horizontal",
            title: emptyTitle,
            message: emptyMessage
        )
    }

    private var emptyTitle: String {
        switch status {
        case .upcoming:
            "기록은 경기 시작 후 제공됩니다"
        default:
            "기록 데이터가 없습니다"
        }
    }

    private var emptyMessage: String {
        switch status {
        case .upcoming:
            "라인업과 박스스코어가 준비되면 타자, 투수, 주요 기록을 표시합니다."
        default:
            "현재 데이터 소스에서 박스스코어 정보를 아직 제공하지 않습니다."
        }
    }
}

// DetailInlineLoadingView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
private struct DetailInlineLoadingView: View {
    @Environment(AppModel.self) private var appModel
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.footnote)
                .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

// ProbableStartersCard 구조체는 ProbableStartersCard 타입의 역할과 값을 정의합니다.
private struct ProbableStartersCard: View {
    let awayTeam: Team
    let homeTeam: Team
    let starters: GameCenterProbableStarters?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("예상 선발")
                .font(.headline.weight(.bold))

            HStack(spacing: 10) {
                StarterColumn(team: awayTeam, role: "원정", pitcherName: starters?.away)
                StarterColumn(team: homeTeam, role: "홈", pitcherName: starters?.home)
            }
        }
        .cardSurface()
    }
}

// StarterColumn 구조체는 StarterColumn 타입의 역할과 값을 정의합니다.
private struct StarterColumn: View {
    @Environment(AppModel.self) private var appModel
    let team: Team
    let role: String
    let pitcherName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(role)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                    Text(team.displayName)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                }
            }

            Text(pitcherName?.nilIfBlank ?? "아직 미정")
                .font(.title3.weight(.heavy))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            appModel.favoriteStadiumPalette?.recessedSurface ?? Color(.tertiarySystemBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

// MatchupComparisonCard 구조체는 MatchupComparisonCard 타입의 역할과 값을 정의합니다.
private struct MatchupComparisonCard: View {
    let awayMatchup: GameCenterMatchupSnapshot
    let homeMatchup: GameCenterMatchupSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("매치업 요약")
                .font(.headline.weight(.bold))

            HStack(spacing: 10) {
                MatchupColumn(snapshot: awayMatchup)
                MatchupColumn(snapshot: homeMatchup)
            }
        }
        .cardSurface()
    }
}

// MatchupColumn 구조체는 MatchupColumn 타입의 역할과 값을 정의합니다.
private struct MatchupColumn: View {
    @Environment(AppModel.self) private var appModel
    let snapshot: GameCenterMatchupSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snapshot.teamName)
                .font(.subheadline.weight(.bold))

            MatchupMetric(title: "시즌", value: snapshot.seasonRecord)
            MatchupMetric(title: "최근5경기", value: snapshot.recentFive)
            MatchupMetric(title: "평균자책점", value: snapshot.teamERA)
            MatchupMetric(title: "타율", value: snapshot.battingAverage)
            MatchupMetric(title: "평균득점", value: snapshot.runsScored)
            MatchupMetric(title: "평균실점", value: snapshot.runsAllowed)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            appModel.favoriteStadiumPalette?.recessedSurface ?? Color(.tertiarySystemBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

// MatchupMetric 구조체는 MatchupMetric 타입의 역할과 값을 정의합니다.
private struct MatchupMetric: View {
    @Environment(AppModel.self) private var appModel
    let title: String
    let value: String?

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
            Spacer(minLength: 8)
            Text(value ?? "-")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }
}

// DetailMessageCard 구조체는 DetailMessageCard 타입의 역할과 값을 정의합니다.
private struct DetailMessageCard: View {
    @Environment(AppModel.self) private var appModel
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(appModel.favoriteStadiumPalette?.primary ?? KBOLivePalette.primary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardSurface()
    }
}

// DetailLoadingCard 구조체는 DetailLoadingCard 타입의 역할과 값을 정의합니다.
private struct DetailLoadingCard: View {
    @Environment(AppModel.self) private var appModel
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.footnote)
                .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
        }
        .cardSurface()
    }
}

private extension Text {
    // lineScoreTotalStyle 메서드는 이 타입의 주요 동작을 수행합니다.
    func lineScoreTotalStyle(emphasis: Bool = false) -> some View {
        font(.caption.weight(emphasis ? .bold : .semibold))
            .monospacedDigit()
            .frame(width: 34)
    }

    // comparisonValueStyle 메서드는 이 타입의 주요 동작을 수행합니다.
    func comparisonValueStyle() -> some View {
        font(.title3.weight(.semibold))
            .monospacedDigit()
            .frame(width: 28)
    }
}

private extension String {
    var displayCellText: String {
        isEmpty ? "-" : self
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var displayStat: String {
        nilIfBlank ?? "-"
    }

    var intValue: Int? {
        Int(trimmingCharacters(in: .whitespacesAndNewlines).filter { $0.isNumber || $0 == "-" })
    }

    var battingOrderNumber: String? {
        let digits = trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }
}

extension Optional where Wrapped == String {
    var displayStolenBaseStat: String {
        self?.displayStat ?? "0"
    }
}

private extension Optional where Wrapped == String {
    var displayStat: String {
        self?.displayStat ?? "-"
    }

    var intValue: Int? {
        self?.intValue
    }

    var outsValue: Int? {
        self?.outsValue
    }
}

private extension GameCenterBattingSection {
    var totalHits: Int? {
        totals?.hits.intValue ?? lines.sum(\.hits)
    }

    var totalHomeRuns: Int? {
        totals?.homeRuns.intValue ?? lines.sum(\.homeRuns)
    }

    var totalStrikeouts: Int? {
        totals?.strikeouts.intValue ?? lines.sum(\.strikeouts)
    }
}

extension GameCenterBattingSection {
    var displayedRecordTotals: GameCenterBattingTotals? {
        GameCenterBattingTotals.derived(from: lines) ?? totals
    }
}

private extension GameCenterBattingTotals {
    // derived 메서드는 이 타입의 주요 동작을 수행합니다.
    static func derived(from lines: [GameCenterBattingLine]) -> GameCenterBattingTotals? {
        let atBats = lines.sum(\.atBats)
        let runs = lines.sum(\.runs)
        let hits = lines.sum(\.hits)
        let runsBattedIn = lines.sum(\.runsBattedIn)
        let homeRuns = lines.sum(\.homeRuns)
        let walks = lines.sum(\.walks)
        let strikeouts = lines.sum(\.strikeouts)
        let stolenBases = lines.sum(\.stolenBases)
        let plateAppearanceHomeRuns = lines.sum(\.plateAppearanceHomeRuns)
        let plateAppearanceWalks = lines.sum(\.plateAppearanceWalks)
        let plateAppearanceStrikeouts = lines.sum(\.plateAppearanceStrikeouts)
        guard [atBats, runs, hits, runsBattedIn, homeRuns, walks, strikeouts, stolenBases, plateAppearanceHomeRuns, plateAppearanceWalks, plateAppearanceStrikeouts].contains(where: { $0 != nil }) else {
            return nil
        }
        return GameCenterBattingTotals(
            atBats: atBats.map(String.init),
            runs: runs.map(String.init),
            hits: hits.map(String.init),
            runsBattedIn: runsBattedIn.map(String.init),
            homeRuns: homeRuns.map(String.init),
            walks: walks.map(String.init),
            strikeouts: strikeouts.map(String.init),
            stolenBases: stolenBases.map(String.init),
            average: nil,
            plateAppearanceHomeRuns: plateAppearanceHomeRuns.map(String.init),
            plateAppearanceWalks: plateAppearanceWalks.map(String.init),
            plateAppearanceStrikeouts: plateAppearanceStrikeouts.map(String.init)
        )
    }
}

// GameCenterPitchingTotals 구조체는 GameCenterPitchingTotals 타입의 역할과 값을 정의합니다.
private struct GameCenterPitchingTotals {
    let innings: String?
    let battersFaced: String?
    let hitsAllowed: String?
    let runsAllowed: String?
    let earnedRuns: String?
    let atBats: String?
    let walksAllowed: String?
    let hitBatters: String?
    let walksOrHitByPitch: String?
    let strikeouts: String?
    let homeRunsAllowed: String?
    let pitches: String?

    // derived 메서드는 이 타입의 주요 동작을 수행합니다.
    static func derived(from lines: [GameCenterPitchingLine]) -> GameCenterPitchingTotals? {
        let outs = lines.compactMap { $0.innings.outsValue }.reduce(0, +)
        let battersFaced = lines.sum(\.battersFaced)
        let hitsAllowed = lines.sum(\.hitsAllowed)
        let runsAllowed = lines.sum(\.runsAllowed)
        let earnedRuns = lines.sum(\.earnedRuns)
        let atBats = lines.sum(\.atBats)
        let walksAllowed = lines.sum(\.walksAllowed)
        let hitBatters = lines.sum(\.hitBatters)
        let walksOrHitByPitch = lines.sum(\.walksOrHitByPitch)
        let strikeouts = lines.sum(\.strikeouts)
        let homeRunsAllowed = lines.sum(\.homeRunsAllowed)
        let pitches = lines.sum(\.pitches)
        guard outs > 0 || [battersFaced, hitsAllowed, runsAllowed, earnedRuns, atBats, walksAllowed, hitBatters, walksOrHitByPitch, strikeouts, homeRunsAllowed, pitches].contains(where: { $0 != nil }) else {
            return nil
        }
        return GameCenterPitchingTotals(
            innings: outs > 0 ? Self.inningsText(fromOuts: outs) : nil,
            battersFaced: battersFaced.map(String.init),
            hitsAllowed: hitsAllowed.map(String.init),
            runsAllowed: runsAllowed.map(String.init),
            earnedRuns: earnedRuns.map(String.init),
            atBats: atBats.map(String.init),
            walksAllowed: walksAllowed.map(String.init),
            hitBatters: hitBatters.map(String.init),
            walksOrHitByPitch: (walksOrHitByPitch ?? combinedWalksOrHitByPitch(walks: walksAllowed, hitBatters: hitBatters)).map(String.init),
            strikeouts: strikeouts.map(String.init),
            homeRunsAllowed: homeRunsAllowed.map(String.init),
            pitches: pitches.map(String.init)
        )
    }

    // combinedWalksOrHitByPitch 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func combinedWalksOrHitByPitch(walks: Int?, hitBatters: Int?) -> Int? {
        guard walks != nil || hitBatters != nil else { return nil }
        return (walks ?? 0) + (hitBatters ?? 0)
    }

    // inningsText 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func inningsText(fromOuts outs: Int) -> String {
        let innings = outs / 3
        let remainder = outs % 3
        return remainder == 0 ? "\(innings)" : "\(innings) \(remainder)/3"
    }
}

private extension GameCenterPitchingLine {
    var displayName: String {
        [name, result?.nilIfBlank.map { "(\($0))" }]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

private extension GameCenterReview {
    // teamSummaryValue 메서드는 이 타입의 주요 동작을 수행합니다.
    func teamSummaryValue(titleContains keyword: String, team: Team) -> Int? {
        summaryItems
            .first { $0.title.contains(keyword) }?
            .value
            .teamValue(for: team)
    }
}

private extension String {
    var outsValue: Int? {
        let cleaned = trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else { return nil }
        let parts = cleaned.split(separator: " ")
        if parts.count == 2,
           let innings = Int(parts[0]),
           let remainder = parts[1].split(separator: "/").first.flatMap({ Int($0) }) {
            return innings * 3 + remainder
        }
        if cleaned.contains("/") {
            let fraction = cleaned.split(separator: "/")
            return fraction.first.flatMap { Int($0) }
        }
        return Int(cleaned).map { $0 * 3 }
    }

    // teamValue 메서드는 이 타입의 주요 동작을 수행합니다.
    func teamValue(for team: Team) -> Int? {
        let names = [team.displayName, team.shortName, team.name]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        for name in names {
            let pattern = "\(NSRegularExpression.escapedPattern(for: name))\\s*[:：]?\\s*(\\d+)"
            if let value = firstRegexCapture(pattern: pattern) {
                return Int(value)
            }
        }
        return nil
    }

    // firstRegexCapture 메서드는 이 타입의 주요 동작을 수행합니다.
    func firstRegexCapture(pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: self) else {
            return nil
        }
        return String(self[captureRange])
    }
}

private extension Array where Element == GameCenterBattingLine {
    // sum 메서드는 이 타입의 주요 동작을 수행합니다.
    func sum(_ keyPath: KeyPath<GameCenterBattingLine, String?>) -> Int? {
        let values = compactMap { $0[keyPath: keyPath]?.intValue }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}

private extension Array where Element == GameCenterPitchingLine {
    // sum 메서드는 이 타입의 주요 동작을 수행합니다.
    func sum(_ keyPath: KeyPath<GameCenterPitchingLine, String?>) -> Int? {
        let values = compactMap { $0[keyPath: keyPath]?.intValue }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}

#Preview {
    NavigationStack {
        GameDetailView(gameID: AppModel.previewModel().games.first!.id)
            .environment(AppModel.previewModel())
    }
}
