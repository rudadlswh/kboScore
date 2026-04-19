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
            .background(KBOLivePalette.background)
            .navigationTitle("순위")
            .navigationBarTitleDisplayMode(.inline)
            .notificationsToolbarButton()
            .refreshable {
                await appModel.refreshHome()
            }
        }
    }

//    private var standingsHeader: some View {
//        VStack(alignment: .leading, spacing: 6) {
//            Text("정규시즌 순위")
//                .font(.headline.weight(.bold))
//            Text("현재 앱 데이터에서 시범경기를 제외한 종료 경기 기준")
//                .font(.caption)
//                .foregroundStyle(.secondary)
//        }
//        .cardSurface(
//            padding: 12,
//            cornerRadius: 18,
//            fillColor: appModel.currentTheme.scoreboardBackground
//        )
//    }
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
                        .lineLimit(1)
                    winningStreakIndicator
                    Text(snapshot.recordText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let estimateText = snapshot.postseasonProbabilityEstimateText {
                    Text(estimateText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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

    private var rankBadge: some View {
        Text("\(snapshot.rank)")
            .font(.headline.weight(.heavy))
            .monospacedDigit()
            .foregroundStyle(appModel.currentTheme.accent)
            .frame(width: 28)
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
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}

#Preview {
    StandingsView()
        .environment(AppModel.previewModel())
}
