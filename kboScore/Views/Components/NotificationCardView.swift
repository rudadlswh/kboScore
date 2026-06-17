//
//  NotificationCardView.swift
//  kboScore
//  기능 설명: 알림 내역의 개별 항목 카드를 표시합니다.
//  사용자가 경기 상태와 설정을 빠르게 이해하도록 도메인 상태를 화면 구조에 직접 매핑합니다.
//  SwiftUI 상태 갱신, 접근성, 작은 화면 레이아웃에서 정보가 겹치지 않도록 표시 조건을 제한합니다.
//  TODO : 반복되는 화면 조각은 재사용 가능한 컴포넌트로 분리하고 미리보기 케이스를 보강합니다.
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

// NotificationCardView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
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
