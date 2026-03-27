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

extension View {
    func notificationsToolbarButton() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NotificationsToolbarButton()
            }
        }
    }
}
