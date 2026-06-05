//
//  NotificationCardView.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

struct NotificationCardView: View {
    @Environment(AppModel.self) private var appModel
    let item: NotificationItem

    var body: some View {
        let palette = appModel.favoriteStadiumPalette ?? StadiumPalette.doosan
        let typeTint = item.type.stadiumTintColor(palette)

        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(typeTint.opacity(item.isRead ? 0.20 : 0.28))
                Image(systemName: item.type.systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(typeTint)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.type.title)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(typeTint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(typeTint.opacity(0.12), in: Capsule())

                    Spacer(minLength: 6)

                    if !item.isRead {
                        Circle()
                            .fill(DoosanPalette.primary)
                            .frame(width: 7, height: 7)
                    }

                    Text(item.sentAt.relativeKoreanText)
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                }

                Text(item.body)
                    .font(.subheadline.weight(item.isRead ? .semibold : .bold))
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.leading)

                if !relatedTeams.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(relatedTeams) { team in
                            TeamMarkView(team: team, size: 22)
                            Text(team.displayName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                }

                Text(item.title)
                    .font(.caption)
                    .foregroundStyle(item.isRead ? palette.textSecondary : palette.textPrimary.opacity(0.84))
            }
        }
        .cardSurface(
            padding: 12,
            cornerRadius: 18,
            fillColor: item.isRead ? palette.sectionBackground : palette.elevatedCardStrong,
            showsGhostBorder: true
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(typeTint.opacity(item.isRead ? 0.35 : 0.9))
                .frame(width: 4)
        }
    }

    private var relatedTeams: [Team] {
        appModel.teams.filter { item.relatedTeamIDs.contains($0.id) }
    }
}

private extension Date {
    var relativeKoreanText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: .now)
    }
}

#Preview {
    let model = AppModel.previewModel()
    return NotificationCardView(item: model.filteredNotifications.first!)
        .padding()
}
