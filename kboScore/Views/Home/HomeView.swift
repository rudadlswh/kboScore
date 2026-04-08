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
                VStack(alignment: .leading, spacing: 10) {
                    if let statusMessage = appModel.statusMessage(for: .home) {
                        DataStatusBannerView(message: statusMessage)
                    }

//                    ScrollView(.horizontal, showsIndicators: false) {
//                        HStack(spacing: 6) {
//                            ForEach(HomeGameFilter.allCases) { filter in
//                                FilterChip(
//                                    title: filter.rawValue,
//                                    isSelected: appModel.homeFilter == filter,
//                                    action: { appModel.homeFilter = filter }
//                                )
//                            }
//                        }
//                        .padding(.horizontal, 1)
//                    }

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
                                NavigationLink(value: game.id) {
                                    GameCardView(summary: game, showsHomeTeamBadge: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(KBOLivePalette.background)
            .navigationTitle("KBO LIVE")
            .navigationBarTitleDisplayMode(.inline)
            .notificationsToolbarButton()
            .refreshable {
                await appModel.refreshHome()
            }
            .navigationDestination(for: UUID.self) { gameID in
                GameDetailView(gameID: gameID)
            }
        }
    }
}

private struct HomeFallbackStandingsSection: View {
    let title: String
    let subtitle: String
    let snapshots: [TeamStandingsSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(appModel.currentTheme.accent)
                .frame(width: 28)

            TeamMarkView(team: snapshot.team, size: 42)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(snapshot.team.name)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    Text(snapshot.recordText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    metric(title: "승률", value: snapshot.winPercentageText)
                    metric(title: "최근 6", value: snapshot.recentResultsText)
                }
            }

            Spacer(minLength: 8)
        }
        .cardSurface(padding: 12, cornerRadius: 18, fillColor: Color(.secondarySystemBackground))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(appModel.currentTheme.accent.opacity(0.9))
                .frame(width: 4)
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}

#Preview {
    HomeView()
        .environment(AppModel.previewModel())
}
