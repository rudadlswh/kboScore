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
                    HomeSummaryHeaderView(
                        totalGames: appModel.todayGamesCount,
                        liveGames: appModel.liveGamesCount,
                        myGames: appModel.myGamesCount
                    )

                    if let statusMessage = appModel.statusMessage(for: .home) {
                        DataStatusBannerView(message: statusMessage)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(HomeGameFilter.allCases) { filter in
                                FilterChip(
                                    title: filter.rawValue,
                                    isSelected: appModel.homeFilter == filter,
                                    action: { appModel.homeFilter = filter }
                                )
                            }
                        }
                        .padding(.horizontal, 1)
                    }

                    if appModel.filteredHomeGames.isEmpty {
                        EmptyStateView(
                            systemImage: "sportscourt",
                            title: "표시할 경기가 없습니다",
                            message: "선택한 필터에 맞는 오늘 경기가 없습니다."
                        )
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(appModel.filteredHomeGames) { game in
                                NavigationLink(value: game.id) {
                                    GameCardView(summary: game)
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
            .refreshable {
                await appModel.refreshHome()
            }
            .navigationDestination(for: UUID.self) { gameID in
                GameDetailView(gameID: gameID)
            }
        }
    }
}

private struct HomeSummaryHeaderView: View {
    @Environment(AppModel.self) private var appModel
    let totalGames: Int
    let liveGames: Int
    let myGames: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("오늘 경기 현황")
                        .font(.headline.weight(.bold))
                    Text("실시간 상황을 빠르게 확인하세요")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.76))
                }

                Spacer()

                Text("\(liveGames) LIVE")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.16), in: Capsule())
            }

            HStack(spacing: 10) {
                SummaryMetric(title: "오늘", value: "\(totalGames)")
                SummaryMetric(title: "라이브", value: "\(liveGames)")
                SummaryMetric(title: "내 경기", value: "\(myGames)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [appModel.currentTheme.heroStart, appModel.currentTheme.heroEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .shadow(color: appModel.currentTheme.shadowTint, radius: 18, y: 8)
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    HomeView()
        .environment(AppModel.previewModel())
}
