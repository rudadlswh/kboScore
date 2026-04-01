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

#Preview {
    HomeView()
        .environment(AppModel.previewModel())
}
