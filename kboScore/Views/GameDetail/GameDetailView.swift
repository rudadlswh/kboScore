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
                let presentation = GameDetailPresentation(game: game, payload: screenModel.detail)
                let availableSections = GameDetailSection.availableSections(for: presentation.status)

                VStack(alignment: .leading, spacing: 12) {
                    GameStatusSummaryCard(presentation: presentation)
                    actionButtons(for: game)
                    sectionPicker(availableSections: availableSections)
                    selectedSection(presentation: presentation)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .task(id: viewModel.stableIdentity) {
                    await screenModel.load(for: game)
                }
                .task(id: presentation.status) {
                    screenModel.syncSelection(for: presentation.status)
                }
                .task(id: "\(game.id.uuidString)-\(presentation.status.rawValue)-\(appModel.settings.liveActivitiesEnabled)") {
                    await appModel.startOrUpdateLiveActivityIfNeeded(for: game)
                }
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
            let refreshedGame = await viewModel.refreshIfNeeded(
                appModel: appModel,
                bypassAutomaticThrottle: true
            ) ?? viewModel.game
            if let refreshedGame {
                await screenModel.load(for: refreshedGame, forceRefresh: refreshedGame.status.isLiveLike)
                await appModel.startOrUpdateLiveActivityIfNeeded(for: refreshedGame)
            }
        }
        .task(id: viewModel.liveRefreshTaskID) {
            guard viewModel.shouldAutoRefreshLiveGame else { return }
            while Task.isCancelled == false {
                do {
                    try await Task.sleep(nanoseconds: GameDetailViewModel.livePollingIntervalNanoseconds)
                } catch {
                    break
                }
                guard Task.isCancelled == false, viewModel.shouldAutoRefreshLiveGame else { break }
                guard let refreshedGame = await viewModel.refreshIfNeeded(
                    appModel: appModel,
                    bypassAutomaticThrottle: true
                ) else { continue }
                await screenModel.load(for: refreshedGame, forceRefresh: refreshedGame.status.isLiveLike)
                await appModel.startOrUpdateLiveActivityIfNeeded(for: refreshedGame)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, viewModel.shouldAutoRefreshLiveGame else { return }
            Task {
                guard let refreshedGame = await viewModel.refreshIfNeeded(
                    appModel: appModel,
                    bypassAutomaticThrottle: true
                ) else { return }
                await screenModel.load(for: refreshedGame, forceRefresh: refreshedGame.status.isLiveLike)
                await appModel.startOrUpdateLiveActivityIfNeeded(for: refreshedGame)
            }
        }
        .refreshable {
            await viewModel.refreshIfNeeded(appModel: appModel, manual: true)
            guard let refreshedGame = viewModel.game else { return }
            await screenModel.load(for: refreshedGame, forceRefresh: true)
        }
    }

    @ViewBuilder
    private func sectionPicker(availableSections: [GameDetailSection]) -> some View {
        if let palette = appModel.favoriteStadiumPalette {
            DoosanGameDetailSectionPicker(
                selection: $screenModel.selectedSection,
                sections: availableSections,
                palette: palette
            )
        } else {
            Picker("상세 섹션", selection: $screenModel.selectedSection) {
                ForEach(availableSections) { section in
                    Text(section.rawValue)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private func selectedSection(presentation: GameDetailPresentation) -> some View {
        switch screenModel.selectedSection {
        case .overview:
            overviewSection(presentation: presentation)
        case .review:
            reviewSection(for: presentation)
        case .preview:
            previewSection(for: presentation)
        }
    }

    private func overviewSection(
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
            } else {
                DetailMessageCard(
                    icon: "calendar",
                    title: "경기 전 안내",
                    message: "라이브 상황과 라인스코어는 경기 시작 후 자동으로 갱신됩니다."
                )
            }
        }
    }

    private func reviewSection(
        for presentation: GameDetailPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if presentation.status != .final {
                EmptyStateView(
                    systemImage: "doc.text.magnifyingglass",
                    title: "리뷰는 경기 종료 후 제공됩니다",
                    message: "경기 종료 후 박스스코어와 기록 요약이 준비되면 이 섹션에 표시됩니다."
                )
            } else {
                if screenModel.isLoading && screenModel.detail == nil {
                    DetailLoadingCard(message: "리뷰 데이터를 준비하는 중")
                }

                GameLineScoreCard(presentation: presentation)

                if let review = presentation.review {
                    if review.summaryItems.isEmpty == false {
                        SummaryItemsCard(items: review.summaryItems)
                    }

                    BattingSectionCard(title: "\(presentation.game.awayTeam.displayName) 타자 기록", section: review.awayBatting)
                    BattingSectionCard(title: "\(presentation.game.homeTeam.displayName) 타자 기록", section: review.homeBatting)
                    PitchingSectionCard(title: "\(presentation.game.awayTeam.displayName) 투수 기록", section: review.awayPitching)
                    PitchingSectionCard(title: "\(presentation.game.homeTeam.displayName) 투수 기록", section: review.homePitching)
                } else {
                    EmptyStateView(
                        systemImage: "doc.text",
                        title: "리뷰 데이터가 없습니다",
                        message: "현재 데이터 소스에서 리뷰 또는 박스스코어 정보를 아직 제공하지 않습니다."
                    )
                }
            }
        }
    }

    private func previewSection(
        for presentation: GameDetailPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if presentation.status == .final || presentation.status == .cancelled {
                EmptyStateView(
                    systemImage: "sportscourt",
                    title: "프리뷰는 경기 전에 제공됩니다",
                    message: "예정 경기일 때 선발 예상과 매치업 요약을 확인할 수 있습니다."
                )
            } else {
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

private struct DoosanGameDetailSectionPicker: View {
    @Binding var selection: GameDetailSection
    let sections: [GameDetailSection]
    let palette: StadiumPalette

    var body: some View {
        HStack(spacing: 4) {
            ForEach(sections) { section in
                Button {
                    selection = section
                } label: {
                    Text(section.rawValue)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(selection == section ? Color.white : palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selection == section ? palette.primary : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.recessedSurface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.ghostBorder, lineWidth: 0.75)
        }
    }
}

private struct GameDetailPresentation {
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
    let baseRunners: GameCenterBaseRunners?
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

    init(game: GameDetail, payload: GameCenterDetailPayload?) {
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
        baseRunners = summary?.baseRunners
        currentBatterName = game.currentBatterName?.nilIfBlank
        currentPitcherName = game.currentPitcherName?.nilIfBlank
        winningPitcher = summary?.winningPitcher?.nilIfBlank
        losingPitcher = summary?.losingPitcher?.nilIfBlank
        savePitcher = summary?.savePitcher?.nilIfBlank
        endTimeText = summary?.endTime?.nilIfBlank
        durationText = summary?.durationText?.nilIfBlank
        crowdText = summary?.crowdText?.nilIfBlank
        probableStarters = payload?.preview?.probableStarters ?? summary?.probableStarters
        lineScore = payload?.lineScore
        review = payload?.review
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
            ("1B", bases?.first == true, baseRunners?.first?.nilIfBlank),
            ("2B", bases?.second == true, baseRunners?.second?.nilIfBlank),
            ("3B", bases?.third == true, baseRunners?.third?.nilIfBlank)
        ]
        .compactMap { item in
            guard item.1, let name = item.2 else { return nil }
            return BaseRunnerDisplayItem(base: item.0, name: name)
        }
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
        let rendered = visibleBaseRunners.reduce(into: ["1B": "<hidden>", "2B": "<hidden>", "3B": "<hidden>"]) { result, item in
            result[item.base] = item.name
        }
        print("[BaseRunners] rendered first=\(rendered["1B"] ?? "<hidden>") second=\(rendered["2B"] ?? "<hidden>") third=\(rendered["3B"] ?? "<hidden>")")
        #endif
    }
}

private struct BaseRunnerDisplayItem: Identifiable {
    let base: String
    let name: String

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

                    if presentation.visibleBaseRunners.isEmpty == false {
                        BaseRunnerList(runners: presentation.visibleBaseRunners)
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
                    Text(":")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                    Text(runner.name)
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
    @Binding var selectedSection: GameDetailSection

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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if presentation.status == .upcoming {
                        OverviewJumpButton(title: "프리뷰", isSelected: selectedSection == .preview) {
                            selectedSection = .preview
                        }
                    } else {
                        OverviewJumpButton(title: "리뷰", isSelected: selectedSection == .review) {
                            selectedSection = .review
                        }
                    }
                }
                .padding(.horizontal, 1)
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

private struct OverviewJumpButton: View {
    @Environment(AppModel.self) private var appModel
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let palette = appModel.favoriteStadiumPalette
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : (palette?.textPrimary ?? Color.primary))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(isSelected ? (palette?.primary ?? KBOLivePalette.primary) : (palette?.recessedSurface ?? Color(.secondarySystemBackground)))
                )
        }
        .buttonStyle(.plain)
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

            ForEach(["R", "H", "E"], id: \.self) { label in
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

private struct BattingSectionCard: View {
    let title: String
    let section: GameCenterBattingSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline.weight(.bold))
                Spacer()
                if let totals = section.totals {
                    Text(totalsSummary(totals))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(section.lines) { line in
                HStack(alignment: .center, spacing: 10) {
                    Text(line.battingOrder)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text(displayPosition(line.position))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 34, alignment: .center)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(line.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(statSummary(for: line))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.vertical, 6)
            }
        }
        .cardSurface()
    }

    private func statSummary(for line: GameCenterBattingLine) -> String {
        [
            line.atBats.map { "타수 \($0)" },
            line.hits.map { "안타 \($0)" },
            line.runsBattedIn.map { "타점 \($0)" },
            line.runs.map { "득점 \($0)" },
            line.average.map { "타율 \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func totalsSummary(_ totals: GameCenterBattingTotals) -> String {
        [
            totals.atBats.map { "타수 \($0)" },
            totals.hits.map { "안타 \($0)" },
            totals.runsBattedIn.map { "타점 \($0)" },
            totals.runs.map { "득점 \($0)" },
            totals.average.map { "타율 \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
    
    private func displayPosition(_ position: String) -> String {
        let raw = position.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.isEmpty == false else { return "-" }

        let compact = raw
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "ㅡ", with: "-")

        let upper = compact.uppercased()

        let exactMap: [String: String] = [
            "1루수": "1B", "일루수": "1B", "一": "1B", "1": "1B",
            "2루수": "2B", "이루수": "2B", "二": "2B", "2": "2B",
            "3루수": "3B", "삼루수": "3B", "三": "3B", "3": "3B",
            "포수": "C", "포": "C",
            "좌익수": "LF", "좌": "LF",
            "중견수": "CF", "중": "CF",
            "우익수": "RF", "우": "RF",
            "지명타자": "DH", "지": "DH",
            "유격수": "SS", "유": "SS",
            "투수": "P", "투": "P",
            "대타": "PH", "타": "PH", "타-": "PH",
            "대주자": "PR", "주": "PR",
        ]

        if let mapped = exactMap[compact] ?? exactMap[upper] {
            return mapped
        }

        let tokens = compact.split(separator: "/").map(String.init)
        if tokens.count > 1 {
            let mapped = tokens.map { token in
                exactMap[token] ?? exactMap[token.uppercased()] ?? token
            }
            return mapped.joined(separator: "/")
        }

        let mappedParts = compact.compactMap { character -> String? in
            switch character {
            case "一":
                return "1B"
            case "二":
                return "2B"
            case "三":
                return "3B"
            case "포":
                return "c"
            case "좌":
                return "LF"
            case "중":
                return "CF"
            case "우":
                return "RF"
            case "지":
                return "DH"
            case "유":
                return "SS"
            case "투":
                return "P"
            case "타":
                return "PH"
            case "주":
                return "PR"
            case "-":
                return nil
            default:
                return nil
            }
        }

        if mappedParts.isEmpty == false {
            var uniqueParts: [String] = []

            for part in mappedParts {
                if uniqueParts.contains(part) == false {
                    uniqueParts.append(part)
                }
            }

            return uniqueParts.joined(separator: "/")
        }

        return raw
    }
}

private struct PitchingSectionCard: View {
    @Environment(AppModel.self) private var appModel
    let title: String
    let section: GameCenterPitchingSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.bold))

            ForEach(section.lines) { line in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(line.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let result = line.result, result.isEmpty == false {
                            Text(result)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(appModel.favoriteStadiumPalette?.recessedSurface ?? Color(.tertiarySystemBackground), in: Capsule())
                        }
                        Spacer()
                        Text(line.role ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(pitchingSummary(for: line))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            }
        }
        .cardSurface()
    }

    private func pitchingSummary(for line: GameCenterPitchingLine) -> String {
        [
            line.innings.map { "이닝 \($0)" },
            line.pitches.map { "투구수 \($0)" },
            line.hitsAllowed.map { "피안타 \($0)" },
            line.walksAllowed.map { "4사구 \($0)" },
            line.strikeouts.map { "삼진 \($0)" },
            line.runsAllowed.map { "실점 \($0)" },
            line.earnedRuns.map { "자책 \($0)" },
            line.earnedRunAverage.map { "ERA \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
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
}

private extension String {
    var displayCellText: String {
        isEmpty ? "-" : self
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    NavigationStack {
        GameDetailView(gameID: AppModel.previewModel().games.first!.id)
            .environment(AppModel.previewModel())
    }
}
