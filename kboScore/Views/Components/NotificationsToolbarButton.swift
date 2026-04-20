//
//  NotificationsToolbarButton.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import SwiftUI

struct NotificationsToolbarButton: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        notificationButton
    }

    private var notificationButton: some View {
        Button {
            appModel.presentNotifications()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(appModel.currentTheme.accent)

                if appModel.unreadNotificationsCount > 0 {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                        .offset(x: 10, y: -8)
                }
            }
            .frame(width: 28, height: 28)
        }
        .accessibilityLabel("알림")
        .accessibilityValue(appModel.unreadNotificationsCount > 0 ? "읽지 않은 알림 \(appModel.unreadNotificationsCount)개" : "새 알림 없음")
    }

    private var badgeText: String {
        let count = appModel.unreadNotificationsCount
        return count > 99 ? "99+" : "\(count)"
    }
}

struct StadiumNotificationChromeButton: View {
    @Environment(AppModel.self) private var appModel
    let palette: StadiumPalette

    var body: some View {
        Button {
            appModel.presentNotifications()
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.tabBarSurface,
                                palette.recessedSurface,
                                palette.elevatedCard.opacity(0.82)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(palette.primary)
                            .frame(width: 3)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(palette.textPrimary.opacity(0.14), lineWidth: 0.75)
                    }
                    .shadow(color: palette.ambientShadow.opacity(0.62), radius: 12, y: 6)

                Image(systemName: "bell.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if appModel.unreadNotificationsCount > 0 {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(palette.primary, in: Capsule())
                        .offset(x: 7, y: -6)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("알림")
        .accessibilityValue(appModel.unreadNotificationsCount > 0 ? "읽지 않은 알림 \(appModel.unreadNotificationsCount)개" : "새 알림 없음")
    }

    private var badgeText: String {
        let count = appModel.unreadNotificationsCount
        return count > 99 ? "99+" : "\(count)"
    }
}

struct DoosanNotificationChromeButton: View {
    var body: some View {
        StadiumNotificationChromeButton(palette: .doosan)
    }
}

extension View {
    func notificationsToolbarButton() -> some View {
        modifier(NotificationsToolbarButtonModifier())
    }
}

private struct NotificationsToolbarButtonModifier: ViewModifier {
    @Environment(AppModel.self) private var appModel

    func body(content: Content) -> some View {
        if appModel.isStadiumFavoriteSelected {
            content
        } else {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NotificationsToolbarButton()
                    }
                }
        }
    }
}
