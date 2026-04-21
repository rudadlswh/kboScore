//
//  StandingsView.swift
//  kboScore
//
//  Created by Codex on 4/2/26.
//

import SwiftUI

struct StandingsView: View {
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
                } else {
                    KBOLivePalette.background
                }
            }
            .navigationTitle("순위")
            .navigationBarTitleDisplayMode(.inline)
            .stadiumNavigationChrome(appModel.favoriteStadiumPalette)
            .notificationsToolbarButton()
            .refreshable {
                await appModel.refreshHome()
            }
        }
    }

    private var defaultContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appModel.standingsSnapshots.isEmpty {
                EmptyStateView(
                    systemImage: "list.number",
                    title: "정규시즌 순위 데이터 없음",
                    message: "현재 데이터에서 시범경기를 제외한 정규시즌 종료 경기를 찾지 못했습니다."
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(appModel.standingsSnapshots) { snapshot in
                        StandingsRow(snapshot: snapshot)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func stadiumContent(_ palette: StadiumPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            //standingsHeader(palette)

            if appModel.standingsSnapshots.isEmpty {
                EmptyStateView(
                    systemImage: "list.number",
                    title: "정규시즌 순위 데이터 없음",
                    message: "현재 데이터에서 시범경기를 제외한 정규시즌 종료 경기를 찾지 못했습니다."
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(appModel.standingsSnapshots) { snapshot in
                        StandingsRow(snapshot: snapshot)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func standingsHeader(_ palette: StadiumPalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("리그 스코어보드")
                .font(.headline.weight(.heavy))
                .foregroundStyle(palette.textPrimary)
            Text("정규시즌 종료 경기 기준 순위 · 승률 중심 정렬")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .cardSurface(
            padding: 12,
            cornerRadius: 18,
            fillColor: palette.sectionBackground
        )
    }
}

private struct StandingsRow: View {
    @Environment(AppModel.self) private var appModel

    let snapshot: TeamStandingsSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            rankBadge

            TeamMarkView(team: snapshot.team, size: 42)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(snapshot.team.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(appModel.favoriteStadiumPalette?.textPrimary ?? .primary)
                        .lineLimit(1)
                    winningStreakIndicator
                    Text(snapshot.recordText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                }

                HStack(spacing: 10) {
                    standingsMetric(title: "승률", value: snapshot.winPercentageText)
                    standingsMetric(title: "최근", value: snapshot.recentResultsText)
                    if let postseasonValue = snapshot.postseasonQualificationText {
                        standingsMetric(title: "포스트시즌 확률", value: postseasonValue)
                    }
                }

                if let unavailableReason = snapshot.visiblePostseasonProbabilityUnavailableReason {
                    Text(unavailableReason.displayText)
                        .font(.caption2)
                        .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                        .lineLimit(1)
                } else if let estimateText = snapshot.postseasonProbabilityEstimateText {
                    Text(estimateText)
                        .font(.caption2)
                        .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
        }
        .cardSurface(
            padding: 12,
            cornerRadius: 18,
            fillColor: appModel.favoriteStadiumPalette?.elevatedCardStrong ?? Color(.secondarySystemBackground)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill((appModel.favoriteStadiumPalette?.primary ?? appModel.currentTheme.accent).opacity(0.9))
                .frame(width: 4)
        }
    }

    private var rankBadge: some View {
        Group {
            if let palette = appModel.favoriteStadiumPalette {
                Text("\(snapshot.rank)")
                    .font(.title3.weight(.black))
                    .monospacedDigit()
                    .foregroundStyle(palette.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(palette.recessedSurface)
                    )
            } else {
                Text("\(snapshot.rank)")
                    .font(.headline.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(appModel.currentTheme.accent)
                    .frame(width: 28)
            }
        }
    }

    private var winningStreakIndicator: some View {
        Text("🔥")
            .font(.caption)
            .opacity(snapshot.showsWinningStreakFire ? 1 : 0)
            .frame(width: 16)
            .accessibilityLabel("3연승 이상")
            .accessibilityHidden(snapshot.showsWinningStreakFire == false)
    }

    private func standingsMetric(title: String, value: String) -> some View {
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
    StandingsView()
        .environment(AppModel.previewModel())
}
