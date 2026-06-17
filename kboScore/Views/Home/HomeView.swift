//
//  HomeView.swift
//  kboScore
//  기능 설명: 홈 화면에서 오늘 경기와 경기 없는 날의 대체 요약을 표시합니다.
//  사용자가 경기 상태와 설정을 빠르게 이해하도록 도메인 상태를 화면 구조에 직접 매핑합니다.
//  SwiftUI 상태 갱신, 접근성, 작은 화면 레이아웃에서 정보가 겹치지 않도록 표시 조건을 제한합니다.
//  TODO : 반복되는 화면 조각은 재사용 가능한 컴포넌트로 분리하고 미리보기 케이스를 보강합니다.
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

// HomeView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
struct HomeView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            ScrollView {
                if let palette = appModel.favoriteStadiumPalette {
                    stadiumContent(palette)
                } else {
                    defaultContent
                }
            }
            .background {
                if let palette = appModel.favoriteStadiumPalette {
                    LinearGradient(
                        colors: [palette.background, palette.sectionBackground],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    KBOLivePalette.background
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle("KBO LIVE")
            .navigationBarTitleDisplayMode(.inline)
            .stadiumNavigationChrome(appModel.favoriteStadiumPalette)
            .notificationsToolbarButton()
            .refreshable {
                await appModel.refreshHome()
            }
            .navigationDestination(for: String.self) { gameIdentity in
                GameDetailView(gameIdentity: gameIdentity)
            }
            .navigationDestination(for: GameDetail.self) { game in
                GameDetailView(game: game)
            }
        }
    }

    private var defaultContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let statusMessage = appModel.statusMessage(for: .home) {
                DataStatusBannerView(message: statusMessage)
            }
#if DEBUG
            if let debugMessage = appModel.debugHomeFallbackDiagnosticMessage {
                DataStatusBannerView(message: debugMessage)
            }
#endif

            SectionTitleView(title: "직관 기록")
            MyTeamAttendanceSummaryView(summary: appModel.myTeamAttendanceSummary)

            switch homeContentState {
            case .noGames:
                EmptyStateView(
                    systemImage: "sportscourt",
                    title: "표시할 경기가 없습니다",
                    message: "오늘 경기가 없고 최근 완료 경기 데이터도 없습니다."
                )
            case let .fallbackStandings(title, subtitle, snapshots):
                HomeFallbackStandingsSection(
                    title: title,
                    subtitle: subtitle,
                    snapshots: snapshots
                )
            case .noFilteredGames:
                EmptyStateView(
                    systemImage: "sportscourt",
                    title: "표시할 경기가 없습니다",
                    message: "선택한 필터에 맞는 오늘 경기가 없습니다."
                )
            case let .games(games):
                LazyVStack(spacing: 8) {
                    ForEach(games) { game in
                        NavigationLink(value: game) {
                            GameCardView(
                                summary: game.summary(isMyTeamGame: game.involves(teamID: appModel.settings.favoriteTeamID)),
                                showsHomeTeamBadge: true,
                                liveColorStyle: .white
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // stadiumContent 메서드는 이 타입의 주요 동작을 수행합니다.
    private func stadiumContent(_ palette: StadiumPalette) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let statusMessage = appModel.statusMessage(for: .home) {
                DataStatusBannerView(message: statusMessage)
            }
#if DEBUG
            if let debugMessage = appModel.debugHomeFallbackDiagnosticMessage {
                DataStatusBannerView(message: debugMessage)
            }
#endif

            switch homeContentState {
            case .noGames:
                EmptyStateView(
                    systemImage: "sportscourt",
                    title: "표시할 경기가 없습니다",
                    message: "오늘 경기가 없고 최근 완료 경기 데이터도 없습니다."
                )
            case let .fallbackStandings(title, subtitle, snapshots):
                HomeFallbackStandingsSection(
                    title: title,
                    subtitle: subtitle,
                    snapshots: snapshots
                )
            case .noFilteredGames:
                EmptyStateView(
                    systemImage: "sportscourt",
                    title: "표시할 경기가 없습니다",
                    message: "선택한 필터에 맞는 오늘 경기가 없습니다."
                )
            case let .games(games):
                if let featuredHomeGame = games.first {
                    Text("오늘의 메인 보드")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.secondary)
                        .padding(.leading, 2)

                    NavigationLink(value: featuredHomeGame) {
                        HomeHeroGameCard(
                            summary: featuredHomeGame.summary(isMyTeamGame: featuredHomeGame.involves(teamID: appModel.settings.favoriteTeamID)),
                            palette: palette
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if appModel.attendedGameKeys.isEmpty == false || appModel.myTeamAttendanceSummary.hasCompletedGames {
                SectionTitleView(title: "직관 기록")
                MyTeamAttendanceSummaryView(summary: appModel.myTeamAttendanceSummary)
            }
            
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var homeContentState: HomeContentState {
        HomeContentState.make(
            todayGames: appModel.todayGames,
            filteredGames: appModel.filteredHomeGames,
            filteredGameDetails: appModel.filteredHomeGameDetails,
            fallbackTitle: appModel.homeFallbackTitleText,
            fallbackSubtitle: appModel.homeFallbackSubtitleText,
            fallbackSnapshots: appModel.homeFallbackStandingsSnapshots
        )
    }

}

// HomeHeroGameCard 구조체는 HomeHeroGameCard 타입의 역할과 값을 정의합니다.
private struct HomeHeroGameCard: View {
    let summary: GameSummary
    let palette: StadiumPalette

    var body: some View {
        ZStack {
            heroBackground

            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    StatusBadge(
                        status: summary.status,
                        tintColor: summary.status.stadiumTintColor(palette),
                        backgroundColor: Color.black.opacity(0.30)
                    )

                    Spacer(minLength: 8)

                    Text(timeText)
                        .font(.caption.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.94))
                        .lineLimit(1)
                }

                HStack(alignment: .center, spacing: 0) {
                    HeroTeamMatchupSide(
                        team: summary.awayTeam,
                        role: "원정",
                        pitcherName: summary.awayStartingPitcherName,
                        alignment: .leading
                    )

                    vsBadge

                    HeroTeamMatchupSide(
                        team: summary.homeTeam,
                        role: "홈",
                        pitcherName: summary.homeStartingPitcherName,
                        alignment: .trailing
                    )
                }

                if summary.status.isLiveLike {
                    liveScorePanel
                }

                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption.weight(.bold))
                    Text(venueText)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundStyle(Color.white.opacity(0.90))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.26))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
                )
            }
            .padding(14)
        }
        .frame(minHeight: 172)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
        )
        .shadow(color: palette.ambientShadow.opacity(0.46), radius: 18, y: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var heroBackground: some View {
        ZStack {
            HStack(spacing: 0) {
                TeamHeroBackground(team: summary.awayTeam, edge: .leading)
                TeamHeroBackground(team: summary.homeTeam, edge: .trailing)
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.20),
                    palette.background.opacity(0.16),
                    Color.black.opacity(0.22)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var vsBadge: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.34))
                .frame(width: 58, height: 58)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.white.opacity(0.10), radius: 12)

            Text("VS")
                .font(.system(size: 23, weight: .black, design: .rounded))
                .foregroundStyle(Color.white)
        }
        .frame(width: 62)
    }

    private var liveScorePanel: some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(summary.awayScore.map(String.init) ?? "-")
                Text(":")
                    .foregroundStyle(Color.white.opacity(0.62))
                Text(summary.homeScore.map(String.init) ?? "-")
            }
            .font(.system(size: 34, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.white)

            HStack(spacing: 8) {
                Text(KBOInningFormatter.korean(summary.inningText) ?? summary.status.title)
                if let countText {
                    Text(countText)
                }
                if let basesText {
                    Text(basesText)
                }
            }
            .font(.caption.weight(.heavy))
            .foregroundStyle(Color.white.opacity(0.88))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.75)
        )
    }

    private var timeText: String {
        HomeHeroGamePresentation.timeText(for: summary)
    }

    private var venueText: String {
        HomeHeroGamePresentation.venueText(for: summary)
    }

    private var accessibilityLabel: String {
        HomeHeroGamePresentation.accessibilityLabel(for: summary)
    }

    private var countText: String? {
        HomeHeroGamePresentation.countText(for: summary)
    }

    private var basesText: String? {
        HomeHeroGamePresentation.basesText(for: summary)
    }
}

// TeamHeroBackground 구조체는 TeamHeroBackground 타입의 역할과 값을 정의합니다.
private struct TeamHeroBackground: View {
    let team: Team
    let edge: HorizontalAlignment

    var body: some View {
        let identity = team.identity

        ZStack(alignment: edge == .leading ? .leading : .trailing) {
            LinearGradient(
                colors: [
                    identity.theme.heroEnd,
                    identity.theme.accent.opacity(0.82),
                    identity.theme.heroStart.opacity(0.70)
                ],
                startPoint: edge == .leading ? .topLeading : .topTrailing,
                endPoint: edge == .leading ? .bottomTrailing : .bottomLeading
            )
            Color.black.opacity(0.18)

            Text(identity.homeHeroWatermarkLabel)
                .font(.system(size: 58, weight: .black, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.10))
                .offset(x: edge == .leading ? -10 : 10, y: 12)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

// HeroTeamMatchupSide 구조체는 HeroTeamMatchupSide 타입의 역할과 값을 정의합니다.
private struct HeroTeamMatchupSide: View {
    let team: Team
    let role: String
    let pitcherName: String?
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 10) {
            VStack(alignment: alignment, spacing: 5) {
                Text(team.identity.displayName)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)

                VStack(alignment: alignment, spacing: 2) {
                    Text(role)
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Color.white.opacity(0.68))
                    Text(pitcherText)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private var pitcherText: String {
        HomeHeroGamePresentation.pitcherText(pitcherName)
    }
}

// HomeFallbackStandingsSection 구조체는 HomeFallbackStandingsSection 타입의 역할과 값을 정의합니다.
private struct HomeFallbackStandingsSection: View {
    @Environment(AppModel.self) private var appModel
    let title: String
    let subtitle: String
    let snapshots: [TeamStandingsSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(appModel.favoriteStadiumPalette?.textPrimary ?? .primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
            }

            LazyVStack(spacing: 8) {
                ForEach(snapshots) { snapshot in
                    HomeFallbackStandingsRow(snapshot: snapshot)
                }
            }
        }
    }
}

// HomeFallbackStandingsRow 구조체는 HomeFallbackStandingsRow 타입의 역할과 값을 정의합니다.
private struct HomeFallbackStandingsRow: View {
    @Environment(AppModel.self) private var appModel

    let snapshot: TeamStandingsSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(snapshot.rank)")
                .font(.headline.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(appModel.favoriteStadiumPalette?.secondary ?? appModel.currentTheme.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(snapshot.team.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(appModel.favoriteStadiumPalette?.textPrimary ?? .primary)
                        .lineLimit(1)
                    Text(snapshot.recordText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                }

                HStack(spacing: 10) {
                    metric(title: "승률", value: snapshot.winPercentageText)
                    metric(title: snapshot.recentResultsMetricTitle, value: snapshot.recentResultsText)
                }
            }

            Spacer(minLength: 8)
        }
        .cardSurface(
            padding: 12,
            cornerRadius: 18,
            fillColor: appModel.favoriteStadiumPalette?.elevatedCard ?? Color(.secondarySystemBackground)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill((appModel.favoriteStadiumPalette?.primary ?? appModel.currentTheme.accent).opacity(0.9))
                .frame(width: 4)
        }
    }

    // metric 메서드는 이 타입의 주요 동작을 수행합니다.
    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(appModel.favoriteStadiumPalette?.textPrimary ?? .primary)
                .lineLimit(1)
        }
    }
}

#Preview {
    HomeView()
        .environment(AppModel.previewModel())
}
