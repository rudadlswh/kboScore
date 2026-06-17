//
//  NotificationsView.swift
//  kboScore
//  기능 설명: 알림 목록과 필터링 UI를 표시합니다.
//  사용자가 경기 상태와 설정을 빠르게 이해하도록 도메인 상태를 화면 구조에 직접 매핑합니다.
//  SwiftUI 상태 갱신, 접근성, 작은 화면 레이아웃에서 정보가 겹치지 않도록 표시 조건을 제한합니다.
//  TODO : 반복되는 화면 조각은 재사용 가능한 컴포넌트로 분리하고 미리보기 케이스를 보강합니다.
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

// NotificationsView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
struct NotificationsView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let palette = notificationPalette

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let statusMessage = appModel.statusMessage(for: .notifications) {
                        NotificationsStatusBannerView(message: statusMessage, palette: palette)
                    }

                    if !appModel.filteredNotifications.isEmpty {
                        Text("최근 알림")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(palette.textPrimary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(NotificationListFilter.allCases) { filter in
                                NotificationsFilterChip(
                                    title: filter.rawValue,
                                    isSelected: appModel.notificationFilter == filter,
                                    palette: palette,
                                    action: { appModel.notificationFilter = filter }
                                )
                            }
                        }
                        .padding(.horizontal, 1)
                    }

                    if appModel.filteredNotifications.isEmpty {
                        NotificationsEmptyStateView(
                            systemImage: "bell.slash",
                            title: "알림이 없습니다",
                            message: "선택한 조건에 맞는 알림 내역이 없습니다.",
                            palette: palette
                        )
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(appModel.filteredNotifications) { item in
                                if let gameIdentity = item.preferredGameNavigationIdentity {
                                    NavigationLink {
                                        GameDetailView(gameIdentity: gameIdentity)
                                            .task {
                                                appModel.markNotificationRead(item.id)
                                            }
                                    } label: {
                                        NotificationCardView(item: item)
                                    }
                                    .buttonStyle(.plain)
                                    .simultaneousGesture(TapGesture().onEnded {
                                        _ = appModel.notificationGameDetailNavigationIdentity(for: item)
                                    })
                                } else {
                                    Button {
                                        _ = appModel.notificationGameDetailNavigationIdentity(for: item)
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
            .background {
                LinearGradient(
                    colors: [palette.background, palette.sectionBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .navigationTitle("알림")
            .modifier(NotificationsNavigationBarModifier(palette: palette))
            .refreshable {
                await appModel.refreshNotifications()
            }
        }
        .preferredColorScheme(.dark)
        .presentationBackground(palette.background)
    }

    private var notificationPalette: StadiumPalette {
        appModel.favoriteStadiumPalette ?? .doosan
    }
}

// NotificationsNavigationBarModifier 구조체는 SwiftUI 뷰 스타일과 동작을 재사용 가능한 형태로 적용합니다.
private struct NotificationsNavigationBarModifier: ViewModifier {
    let palette: StadiumPalette

    // body 메서드는 SwiftUI 화면의 본문 구성을 반환합니다.
    func body(content: Content) -> some View {
        content
            .toolbarColorScheme(palette.usesLightForegroundStyle ? .light : .dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(palette.navigationSurface, for: .navigationBar)
    }
}

// NotificationsFilterChip 구조체는 NotificationsFilterChip 타입의 역할과 값을 정의합니다.
private struct NotificationsFilterChip: View {
    let title: String
    let isSelected: Bool
    let palette: StadiumPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : palette.textSecondary)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(
                    Capsule()
                        .fill(isSelected ? DoosanPalette.primary : palette.elevatedCardStrong)
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? DoosanPalette.primary.opacity(0.65) : palette.ghostBorder, lineWidth: 0.75)
                )
        }
        .buttonStyle(.plain)
    }
}

// NotificationsEmptyStateView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
private struct NotificationsEmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    let palette: StadiumPalette

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(palette.textSecondary)
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .cardSurface(fillColor: palette.sectionBackground, showsGhostBorder: true)
    }
}

// NotificationsStatusBannerView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
private struct NotificationsStatusBannerView: View {
    let message: String
    let palette: StadiumPalette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondary)

            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.textSecondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.sectionBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.ghostBorder, lineWidth: 0.75)
        )
    }
}

#Preview {
    NotificationsView()
        .environment(AppModel.previewModel())
}
