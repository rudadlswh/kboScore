//
//  HomeView.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

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
        }
    }

    private var defaultContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let statusMessage = appModel.statusMessage(for: .home) {
                DataStatusBannerView(message: statusMessage)
            }

            SectionTitleView(title: "직관 기록")
            MyTeamAttendanceSummaryView(summary: appModel.myTeamAttendanceSummary)

            if appModel.todayGames.isEmpty {
                if appModel.homeFallbackStandingsSnapshots.isEmpty {
                    EmptyStateView(
                        systemImage: "sportscourt",
                        title: "표시할 경기가 없습니다",
                        message: "오늘 경기가 없고 최근 완료 경기 데이터도 없습니다."
                    )
                } else {
                    HomeFallbackStandingsSection(
                        title: appModel.homeFallbackTitleText,
                        subtitle: appModel.homeFallbackSubtitleText,
                        snapshots: appModel.homeFallbackStandingsSnapshots
                    )
                }
            } else if appModel.filteredHomeGames.isEmpty {
                EmptyStateView(
                    systemImage: "sportscourt",
                    title: "표시할 경기가 없습니다",
                    message: "선택한 필터에 맞는 오늘 경기가 없습니다."
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(appModel.filteredHomeGames) { game in
                        NavigationLink(value: appModel.gameNavigationIdentity(for: game)) {
                            GameCardView(
                                summary: game,
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

    private func stadiumContent(_ palette: StadiumPalette) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let statusMessage = appModel.statusMessage(for: .home) {
                DataStatusBannerView(message: statusMessage)
            }


            if appModel.todayGames.isEmpty {
                if appModel.homeFallbackStandingsSnapshots.isEmpty {
                    EmptyStateView(
                        systemImage: "sportscourt",
                        title: "표시할 경기가 없습니다",
                        message: "오늘 경기가 없고 최근 완료 경기 데이터도 없습니다."
                    )
                } else {
                    HomeFallbackStandingsSection(
                        title: appModel.homeFallbackTitleText,
                        subtitle: appModel.homeFallbackSubtitleText,
                        snapshots: appModel.homeFallbackStandingsSnapshots
                    )
                }
            } else if appModel.filteredHomeGames.isEmpty {
                EmptyStateView(
                    systemImage: "sportscourt",
                    title: "표시할 경기가 없습니다",
                    message: "선택한 필터에 맞는 오늘 경기가 없습니다."
                )
            } else {
                if let featuredHomeGame {
                    Text("오늘의 메인 보드")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.secondary)
                        .padding(.leading, 2)

                    NavigationLink(value: appModel.gameNavigationIdentity(for: featuredHomeGame)) {
                        HomeHeroGameCard(summary: featuredHomeGame, palette: palette)
                    }
                    .buttonStyle(.plain)
                }
                SectionTitleView(title: "직관 기록")
                MyTeamAttendanceSummaryView(summary: appModel.myTeamAttendanceSummary)

            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var featuredHomeGame: GameSummary? {
        appModel.filteredHomeGames.first
    }

}

private struct HomeHeroGameCard: View {
    let summary: GameSummary
    let palette: StadiumPalette

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    palette.sectionBackground,
                    palette.elevatedCardStrong,
                    palette.primary.opacity(0.42)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 8) {
                Text("DIGITAL STADIUM")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(palette.textSecondary)
                GameCardView(
                    summary: summary,
                    showsHomeTeamBadge: true
                )
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(palette.ghostBorder, lineWidth: 0.75)
        )
        .shadow(color: palette.ambientShadow.opacity(0.4), radius: 14, y: 8)
    }
}

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

            TeamMarkView(team: snapshot.team, size: 42)

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
