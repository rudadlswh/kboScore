//
//  GameDetailView.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

struct GameDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var screenModel = GameDetailScreenModel()
    @StateObject private var viewModel: GameDetailViewModel

    let gameIdentity: String

    init(gameID: UUID) {
        let identity = gameID.uuidString
        self.gameIdentity = identity
        self._viewModel = StateObject(wrappedValue: GameDetailViewModel(gameIdentity: identity))
    }

    init(gameIdentity: String) {
        self.gameIdentity = gameIdentity
        self._viewModel = StateObject(wrappedValue: GameDetailViewModel(gameIdentity: gameIdentity))
    }

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
                    actionButtons(for: game)
                    overviewSection(presentation: presentation)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
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
            viewModel.configureInitialGameIfNeeded(appModel.initialGameSnapshot(for: gameIdentity))
            let inputLocalGameID = viewModel.game?.id
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
                    forceRefresh: refreshedGame.status.isLiveLike
                )
                await appModel.startOrUpdateLiveActivityIfNeeded(for: refreshedGame)
            }
        }
        .task(id: viewModel.liveRefreshTaskID) {
            guard viewModel.shouldAutoRefreshLiveGame else {
                #if DEBUG
                print("[GameDetailLive] refresh stop reason=notLive stableIdentity=\(viewModel.stableIdentity)")
                #endif
                return
            }
            #if DEBUG
            print("[GameDetailLive] refresh start stableIdentity=\(viewModel.stableIdentity) intervalSeconds=\(GameDetailViewModel.livePollingIntervalNanoseconds / 1_000_000_000)")
            #endif
            defer {
                #if DEBUG
                print("[GameDetailLive] refresh stop stableIdentity=\(viewModel.stableIdentity)")
                #endif
            }
            while Task.isCancelled == false {
                do {
                    try await Task.sleep(nanoseconds: GameDetailViewModel.livePollingIntervalNanoseconds)
                } catch {
                    break
                }
                guard Task.isCancelled == false, viewModel.shouldAutoRefreshLiveGame else { break }
                let inputLocalGameID = viewModel.game?.id
                guard let refreshedGame = await viewModel.refreshIfNeeded(
                    appModel: appModel,
                    bypassAutomaticThrottle: true
                ) else { continue }
                await loadDetailPresentation(
                    for: refreshedGame,
                    inputLocalGameId: inputLocalGameID ?? refreshedGame.id,
                    rawSupabaseGameID: viewModel.rawSupabaseGameID,
                    rawSupabaseProviderGameID: viewModel.rawSupabaseProviderGameID,
                    rawSupabasePublicGameID: viewModel.rawSupabasePublicGameID,
                    forceRefresh: refreshedGame.status.isLiveLike
                )
                await appModel.startOrUpdateLiveActivityIfNeeded(for: refreshedGame)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, viewModel.shouldAutoRefreshLiveGame else { return }
            Task {
                let inputLocalGameID = viewModel.game?.id
                guard let refreshedGame = await viewModel.refreshIfNeeded(
                    appModel: appModel,
                    bypassAutomaticThrottle: true
                ) else { return }
                await loadDetailPresentation(
                    for: refreshedGame,
                    inputLocalGameId: inputLocalGameID ?? refreshedGame.id,
                    rawSupabaseGameID: viewModel.rawSupabaseGameID,
                    rawSupabaseProviderGameID: viewModel.rawSupabaseProviderGameID,
                    rawSupabasePublicGameID: viewModel.rawSupabasePublicGameID,
                    forceRefresh: refreshedGame.status.isLiveLike
                )
                await appModel.startOrUpdateLiveActivityIfNeeded(for: refreshedGame)
            }
        }
        .refreshable {
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
        }
    }

    private func loadDetailPresentation(
        for game: GameDetail,
        inputLocalGameId: UUID,
        rawSupabaseGameID: UUID?,
        rawSupabaseProviderGameID: String?,
        rawSupabasePublicGameID: String?,
        forceRefresh: Bool
    ) async {
        await screenModel.mergeDatabaseRecordReviewAfterFetchGameSingle(
            inputLocalGameId: inputLocalGameId,
            resolvedGame: game,
            rawSupabaseGameID: rawSupabaseGameID,
            rawSupabaseProviderGameID: rawSupabaseProviderGameID,
            rawSupabasePublicGameID: rawSupabasePublicGameID,
            fetchDatabaseRecordReviewResult: appModel.fetchGameDetailDatabaseReviewResult,
            fetchDatabaseRecordReviewResultByRawSupabaseID: appModel.fetchGameDetailDatabaseReviewResult
        )
        await screenModel.load(
            for: game,
            forceRefresh: forceRefresh,
            fetchDatabaseRecordReview: appModel.fetchGameDetailDatabaseReview
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

    private func previewOverviewContent(
        for presentation: GameDetailPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if screenModel.isLoading && screenModel.detail == nil {
                DetailLoadingCard(message: "프리뷰 데이터를 준비하는 중")
            }

            if let preview = presentation.preview {
                if preview.probableStarters?.away != nil || preview.probableStarters?.home != nil {
                    ProbableStartersCard(
                        awayTeam: presentation.game.awayTeam,
                        homeTeam: presentation.game.homeTeam,
                        starters: preview.probableStarters
                    )
                }

                if let awayMatchup = preview.awayMatchup,
                   let homeMatchup = preview.homeMatchup {
                    MatchupComparisonCard(awayMatchup: awayMatchup, homeMatchup: homeMatchup)
                }

                if preview.probableStarters?.away == nil,
                   preview.probableStarters?.home == nil,
                   preview.awayMatchup == nil,
                   preview.homeMatchup == nil {
                    EmptyStateView(
                        systemImage: "person.crop.circle.badge.questionmark",
                        title: "프리뷰 정보가 아직 없습니다",
                        message: "선발 예고와 팀 비교 데이터가 준비되면 이 섹션에 표시됩니다."
                    )
                }
            } else {
                EmptyStateView(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: "공식 프리뷰 정보 준비 중",
                    message: "현재 데이터 소스에서 프리뷰 정보를 아직 제공하지 않습니다."
                )
            }
        }
    }

    @ViewBuilder
    private func actionButtons(for game: GameDetail) -> some View {
        let palette = appModel.favoriteStadiumPalette
        HStack(spacing: 10) {
            Button {
                appModel.toggleGameAttendance(for: game)
            } label: {
                Label(
                    appModel.isGameAttended(game) ? "직관 해제" : "직관",
                    systemImage: appModel.isGameAttended(game) ? "checkmark.circle.fill" : "checkmark.circle"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    palette?.elevatedCard ?? Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .foregroundStyle(appModel.isGameAttended(game) ? (palette?.primary ?? appModel.currentTheme.accent) : (palette?.textPrimary ?? .primary))
            }
            .buttonStyle(.plain)

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
}

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
        status = summary?.status ?? game.status
        stadium = summary?.stadium?.nilIfBlank ?? game.venue
        startTimeText = summary?.startTime?.nilIfBlank ?? game.scheduledStart.formatted(date: .omitted, time: .shortened)
        if status.isLiveLike || status == .final {
            inningText = KBOInningFormatter.korean(summary?.inningText?.nilIfBlank ?? game.inningText?.nilIfBlank)
        } else {
            inningText = nil
        }
        awayScore = summary?.awayScore ?? game.awayScore
        homeScore = summary?.homeScore ?? game.homeScore
        balls = summary?.balls ?? game.balls
        strikes = summary?.strikes ?? game.strikes
        outs = summary?.outs ?? game.outs
        bases = summary?.bases ?? game.bases
        baseRunners = summary?.baseRunners.map {
            GameBaseRunners(first: $0.first, second: $0.second, third: $0.third)
        } ?? game.baseRunners
        self.baseRunnerDisplay = baseRunnerDisplay
        currentBatterName = game.currentBatterName?.nilIfBlank
        currentPitcherName = game.currentPitcherName?.nilIfBlank
        winningPitcher = summary?.winningPitcher?.nilIfBlank
        losingPitcher = summary?.losingPitcher?.nilIfBlank
        savePitcher = summary?.savePitcher?.nilIfBlank
        endTimeText = summary?.endTime?.nilIfBlank
        durationText = summary?.durationText?.nilIfBlank
        crowdText = summary?.crowdText?.nilIfBlank
        probableStarters = payload?.preview?.probableStarters ?? summary?.probableStarters
        lineScore = payload?.lineScore ?? cachedLineScore
        review = databaseRecordReview?.enrichingBatterPositions(from: payload?.review) ??
            boxscore?.gameCenterReview?.enrichingBatterPositions(from: payload?.review) ??
            officialFallbackReview ??
            payload?.review
        preview = payload?.preview
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
        [
            ("1B", bases?.first == true),
            ("2B", bases?.second == true),
            ("3B", bases?.third == true)
        ]
        .compactMap { item in
            guard item.1 else { return nil }
            return BaseRunnerDisplayItem(base: item.0)
        }
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

    func logRenderedBaseRunnersIfNeeded() {
        #if DEBUG
        print("[BaseRunners] snapshot names first=\(baseRunners?.first ?? "<nil>") second=\(baseRunners?.second ?? "<nil>") third=\(baseRunners?.third ?? "<nil>")")
        let rendered = displayBaseRunners.reduce(into: ["1B": "empty", "2B": "empty", "3B": "empty"]) { result, item in
            result[item.base] = "occupied(no-name)"
        }
        print("[BaseRunners] rendered first=\(rendered["1B"] ?? "unknown") second=\(rendered["2B"] ?? "unknown") third=\(rendered["3B"] ?? "unknown") source=\(baseRunnerDisplay.source)")
        #endif
    }
}

struct BaseRunnerDisplayItem: Identifiable, Equatable {
    let base: String

    var id: String { base }
}

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

private struct ScoreColumn: View {
    let title: String
    let team: Team

    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            TeamMarkView(team: team, size: 54)
            Text(team.displayName)
                .font(.subheadline.weight(.bold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

        }
        .frame(maxWidth: .infinity)
    }
}

private struct LiveSituationRow: View {
    let presentation: GameDetailPresentation

    var body: some View {
        HStack(spacing: 8) {
            StatusTile(title: "카운트") {
                HStack(spacing: 8) {
                    CountMetric(label: "B", value: KBOCountDisplay.balls(presentation.balls))
                    CountMetric(label: "S", value: KBOCountDisplay.strikes(presentation.strikes))
                    CountMetric(label: "O", value: KBOCountDisplay.outs(presentation.outs))
                }
            }

            StatusTile(title: "주자 상황") {
                HStack(alignment: .center, spacing: 12) {
                    BasesDiamondView(bases: presentation.bases ?? .empty)

                    if presentation.displayBaseRunners.isEmpty == false {
                        BaseRunnerList(runners: presentation.displayBaseRunners)
                    }
                }
                .onAppear {
                    presentation.logRenderedBaseRunnersIfNeeded()
                }
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

private struct BaseRunnerList: View {
    @Environment(AppModel.self) private var appModel
    let runners: [BaseRunnerDisplayItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(runners) { runner in
                HStack(spacing: 6) {
                    Text(runner.base)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(appModel.favoriteStadiumPalette?.primary ?? KBOLivePalette.primary)
                        .frame(width: 24, alignment: .leading)
                    Text("점유")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appModel.favoriteStadiumPalette?.textPrimary ?? .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CountMetric: View {
    @Environment(AppModel.self) private var appModel
    let label: String
    let value: Int?

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
            Text(value.map(String.init) ?? "-")
                .font(.headline.weight(.bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

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

private struct StatusTile<Content: View>: View {
    @Environment(AppModel.self) private var appModel
    let title: String
    let content: Content

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

private struct LineScoreValueRow: View {
    @Environment(AppModel.self) private var appModel
    let team: Team
    let inningValues: [String]
    let totals: GameCenterTeamLineTotals
    var isHome: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                TeamMarkView(team: team, size: 24)
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

private struct FallbackLineScoreRow: View {
    @Environment(AppModel.self) private var appModel
    let team: Team
    let runs: Int?
    var isHome: Bool = false

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                TeamMarkView(team: team, size: 26)
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

private enum GameDetailRecordTeam: String, CaseIterable, Identifiable {
    case away = "원정"
    case home = "홈"

    var id: String { rawValue }
}

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

private struct TeamRecordButton: View {
    @Environment(AppModel.self) private var appModel
    let title: String
    let team: Team
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                TeamMarkView(team: team, size: 22)
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
                        if let totals = section.totals {
                            BattingTotalsRow(totals: totals, isLiveLike: isLiveLike)
                        } else if let totals = GameCenterBattingTotals.derived(from: section.lines) {
                            BattingTotalsRow(totals: totals, isLiveLike: isLiveLike)
                        }
                    }
                }
            }
        }
    }
}

enum GameDetailBattingTableColumns {
    static func headers(isLiveLike: Bool) -> [String] {
        if isLiveLike {
            return ["타수", "득점", "안타", "타점", "홈런", "삼진", "볼넷"]
        }
        return ["타수", "득점", "안타", "타점", "홈런", "볼넷", "삼진", "도루", "타율"]
    }

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

private struct KeyRecordMetric: Identifiable {
    let title: String
    let away: Int?
    let home: Int?

    var id: String { title }
}

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

private struct StarterColumn: View {
    @Environment(AppModel.self) private var appModel
    let team: Team
    let role: String
    let pitcherName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TeamMarkView(team: team, size: 32)
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
    func lineScoreTotalStyle(emphasis: Bool = false) -> some View {
        font(.caption.weight(emphasis ? .bold : .semibold))
            .monospacedDigit()
            .frame(width: 34)
    }

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

private extension GameCenterBattingTotals {
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

    private static func combinedWalksOrHitByPitch(walks: Int?, hitBatters: Int?) -> Int? {
        guard walks != nil || hitBatters != nil else { return nil }
        return (walks ?? 0) + (hitBatters ?? 0)
    }

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
    func sum(_ keyPath: KeyPath<GameCenterBattingLine, String?>) -> Int? {
        let values = compactMap { $0[keyPath: keyPath]?.intValue }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}

private extension Array where Element == GameCenterPitchingLine {
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
