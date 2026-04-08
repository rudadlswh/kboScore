//
//  GameCardView.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

struct GameCardView: View {
    @Environment(AppModel.self) private var appModel
    let summary: GameSummary
    let showsHomeTeamBadge: Bool

    init(summary: GameSummary, showsHomeTeamBadge: Bool = false) {
        self.summary = summary
        self.showsHomeTeamBadge = showsHomeTeamBadge
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StatusBadge(status: summary.status)

                if summary.isMyTeamGame {
                    Text("MY")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(appModel.currentTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(appModel.currentTheme.chipBackground)
                        )
                }

                Spacer(minLength: 8)

                Text(summary.secondaryText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(summary.status.isLiveLike ? summary.status.tintColor : .secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    TeamRow(team: summary.awayTeam, score: summary.awayScore, status: summary.status)
                    TeamRow(team: summary.homeTeam, score: summary.homeScore, status: summary.status, showsHomeBadge: showsHomeTeamBadge)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(summary.displayScore)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(summary.status.isLiveLike ? summary.status.tintColor : .primary)
                    Label(summary.venue, systemImage: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let recentEvent = summary.recentEvent {
                HStack(spacing: 8) {
                    Image(systemName: summary.status.isFinishedLike ? "flag.pattern.checkered" : "waveform.path.ecg")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(summary.status.tintColor)
                    Text(recentEvent)
                        .font(.footnote.weight(summary.status.isLiveLike ? .semibold : .regular))
                        .foregroundStyle(.primary.opacity(summary.status.isLiveLike ? 0.92 : 0.72))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemBackground).opacity(summary.status.isLiveLike ? 0.9 : 0.65))
                )
            }
        }
        .cardSurface(padding: 12, cornerRadius: 18, fillColor: summary.status.cardBackgroundColor)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(summary.status.tintColor.opacity(summary.status.isLiveLike ? 0.95 : 0.3))
                .frame(width: 4)
        }
    }
}

private struct TeamRow: View {
    let team: Team
    let score: Int?
    let status: GameStatus
    var showsHomeBadge: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            TeamMarkView(team: team, size: 28)
            HStack(spacing: 4) {
                Text(team.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .layoutPriority(1)

                if showsHomeBadge {
                    HomeTeamBadge()
                }
            }
            Spacer(minLength: 8)
            if status != .upcoming, let score {
                Text("\(score)")
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
            }
        }
    }
}

private struct HomeTeamBadge: View {
    var body: some View {
        Text("홈")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.14))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.5)
            )
            .accessibilityLabel("홈팀")
    }
}

#Preview {
    let model = AppModel.previewModel()
    return GameCardView(summary: model.filteredHomeGames.first!)
        .padding()
}
