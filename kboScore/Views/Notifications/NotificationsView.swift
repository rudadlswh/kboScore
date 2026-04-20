//
//  NotificationsView.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

struct NotificationsView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let statusMessage = appModel.statusMessage(for: .notifications) {
                        DataStatusBannerView(message: statusMessage)
                    }

                    if !appModel.filteredNotifications.isEmpty {
                        Text("최근 알림")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(appModel.isDoosanFavoriteSelected ? DoosanPalette.textPrimary : .primary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(NotificationListFilter.allCases) { filter in
                                FilterChip(
                                    title: filter.rawValue,
                                    isSelected: appModel.notificationFilter == filter,
                                    action: { appModel.notificationFilter = filter }
                                )
                            }
                        }
                        .padding(.horizontal, 1)
                    }

                    if appModel.filteredNotifications.isEmpty {
                        EmptyStateView(
                            systemImage: "bell.slash",
                            title: "알림이 없습니다",
                            message: "선택한 조건에 맞는 알림 내역이 없습니다."
                        )
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(appModel.filteredNotifications) { item in
                                if let relatedGameID = item.relatedGameID {
                                    NavigationLink {
                                        GameDetailView(gameID: relatedGameID)
                                            .task {
                                                appModel.markNotificationRead(item.id)
                                            }
                                    } label: {
                                        NotificationCardView(item: item)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Button {
                                        appModel.markNotificationRead(item.id)
                                    } label: {
                                        NotificationCardView(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(
                Group {
                    if appModel.isDoosanFavoriteSelected {
                        LinearGradient(
                            colors: [DoosanPalette.background, DoosanPalette.sectionBackground],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else {
                        KBOLivePalette.background
                    }
                }
            )
            .navigationTitle("알림")
            .modifier(NotificationsNavigationBarModifier(isDoosan: appModel.isDoosanFavoriteSelected))
            .refreshable {
                await appModel.refreshNotifications()
            }
        }
    }
}

private struct NotificationsNavigationBarModifier: ViewModifier {
    let isDoosan: Bool

    func body(content: Content) -> some View {
        if isDoosan {
            content
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(DoosanPalette.glassSurface, for: .navigationBar)
        } else {
            content
        }
    }
}

#Preview {
    NotificationsView()
        .environment(AppModel.previewModel())
}
