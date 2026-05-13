//
//  GameCardView.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

enum GameCardLiveColorStyle {
    case standard
    case white
}

struct GameCardView: View {
    @Environment(AppModel.self) private var appModel
    let summary: GameSummary
    let showsHomeTeamBadge: Bool
    let liveColorStyle: GameCardLiveColorStyle
    let teamMarkAssetStyle: TeamImageAssetStyle

    init(
        summary: GameSummary,
        showsHomeTeamBadge: Bool = false,
        liveColorStyle: GameCardLiveColorStyle = .standard,
        teamMarkAssetStyle: TeamImageAssetStyle = .officialLogoPreferred
    ) {
        self.summary = summary
        self.showsHomeTeamBadge = showsHomeTeamBadge
        self.liveColorStyle = liveColorStyle
        self.teamMarkAssetStyle = teamMarkAssetStyle
    }

    var body: some View {
        if let palette = appModel.favoriteStadiumPalette {
            stadiumBody(palette)
        } else {
            defaultBody
        }
    }

    private var defaultBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StatusBadge(
                    status: summary.status,
                    tintColor: statusTintColor,
                    backgroundColor: statusBadgeBackgroundColor
                )

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
                    .foregroundStyle(summary.status.isLiveLike ? statusTintColor : .secondary)
                    .shadow(color: liveTextShadowColor, radius: 1, y: 1)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    TeamRowDefault(
                        team: summary.awayTeam,
                        score: summary.awayScore,
                        status: summary.status,
                        assetStyle: teamMarkAssetStyle
                    )
                    TeamRowDefault(
                        team: summary.homeTeam,
                        score: summary.homeScore,
                        status: summary.status,
                        showsHomeBadge: showsHomeTeamBadge,
                        assetStyle: teamMarkAssetStyle
                    )
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 6) {
                    if summary.showsLiveOrFinalScore {
                        Text(summary.displayScore)
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(summary.status.isLiveLike ? statusTintColor : .primary)
                            .shadow(color: liveTextShadowColor, radius: 1, y: 1)
                    }
                    Label(summary.venue, systemImage: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let currentPitcher = summary.currentPitcherName?.nilIfBlank, summary.status.isLiveLike {
                        Label(currentPitcher, systemImage: "figure.baseball")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if let recentEvent = summary.recentEvent {
                HStack(spacing: 8) {
                    Image(systemName: summary.status.isFinishedLike ? "flag.pattern.checkered" : "waveform.path.ecg")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(statusTintColor)
                        .shadow(color: liveTextShadowColor, radius: 1, y: 1)
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
        .cardSurface(padding: 12, cornerRadius: 18, fillColor: cardBackgroundColor)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(statusTintColor.opacity(summary.status.isLiveLike ? 0.95 : 0.3))
                .frame(width: 4)
        }
    }

    private func stadiumBody(_ palette: StadiumPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                StatusBadge(
                    status: summary.status,
                    tintColor: statusTintColor,
                    backgroundColor: statusBadgeBackgroundColor
                )

                if summary.isMyTeamGame {
                    Text("MY")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(palette.elevatedCardStrong)
                        )
                }

                Spacer(minLength: 8)

                Text(summary.secondaryText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(summary.status.isLiveLike ? statusTintColor : palette.textSecondary)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    TeamRowDoosan(
                        team: summary.awayTeam,
                        score: summary.awayScore,
                        status: summary.status,
                        palette: palette,
                        isWinningRow: awayTeamIsWinning,
                        assetStyle: teamMarkAssetStyle
                    )
                    TeamRowDoosan(
                        team: summary.homeTeam,
                        score: summary.homeScore,
                        status: summary.status,
                        palette: palette,
                        isWinningRow: homeTeamIsWinning,
                        showsHomeBadge: showsHomeTeamBadge,
                        assetStyle: teamMarkAssetStyle
                    )
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 6) {
                    if summary.showsLiveOrFinalScore {
                        Text(summary.displayScore)
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(summary.status.isLiveLike ? statusTintColor : palette.textPrimary)
                    }
                    Label(summary.venue, systemImage: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    if let currentPitcher = summary.currentPitcherName?.nilIfBlank, summary.status.isLiveLike {
                        Label(currentPitcher, systemImage: "figure.baseball")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                }
            }

            if let recentEvent = summary.recentEvent {
                HStack(spacing: 8) {
                    Image(systemName: summary.status.isFinishedLike ? "flag.pattern.checkered" : "waveform.path.ecg")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(statusTintColor)
                    Text(recentEvent)
                        .font(.footnote.weight(summary.status.isLiveLike ? .semibold : .regular))
                        .foregroundStyle(palette.textPrimary.opacity(summary.status.isLiveLike ? 0.92 : 0.72))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.recessedSurface.opacity(summary.status.isLiveLike ? 0.96 : 0.75))
                )
            }
        }
        .cardSurface(padding: 14, cornerRadius: 18, fillColor: cardBackgroundColor)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(statusTintColor.opacity(summary.status.isLiveLike ? 0.95 : 0.3))
                .frame(width: 5)
        }
    }

    private var usesWhiteLiveStyle: Bool {
        liveColorStyle == .white && summary.status == .live
    }

    private var statusTintColor: Color {
        usesWhiteLiveStyle ? Color.white : baseStatusTintColor
    }

    private var baseStatusTintColor: Color {
        if let palette = appModel.favoriteStadiumPalette {
            return summary.status.stadiumTintColor(palette)
        }
        return summary.status.tintColor
    }

    private var statusBadgeBackgroundColor: Color? {
        usesWhiteLiveStyle ? Color.black.opacity(0.42) : nil
    }

    private var cardBackgroundColor: Color {
        if usesWhiteLiveStyle {
            return appModel.favoriteStadiumPalette?.elevatedCardStrong ?? Color.white.opacity(0.18)
        }
        if let palette = appModel.favoriteStadiumPalette {
            return summary.status.stadiumCardBackgroundColor(palette)
        }
        return summary.status.cardBackgroundColor
    }

    private var liveTextShadowColor: Color {
        usesWhiteLiveStyle ? Color.black.opacity(0.42) : .clear
    }

    private var awayTeamIsWinning: Bool {
        isWinningScore(away: summary.awayScore, home: summary.homeScore, checksAway: true)
    }

    private var homeTeamIsWinning: Bool {
        isWinningScore(away: summary.awayScore, home: summary.homeScore, checksAway: false)
    }

    private func isWinningScore(away: Int?, home: Int?, checksAway: Bool) -> Bool {
        guard let away, let home, away != home, summary.status != .upcoming else {
            return false
        }
        return checksAway ? away > home : home > away
    }
}

private struct TeamRowDefault: View {
    let team: Team
    let score: Int?
    let status: GameStatus
    var showsHomeBadge: Bool = false
    var assetStyle: TeamImageAssetStyle = .officialLogoPreferred

    var body: some View {
        HStack(spacing: 8) {
            TeamMarkView(team: team, size: 28, assetStyle: assetStyle)
            HStack(spacing: 4) {
                Text(team.displayName)
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

private struct TeamRowDoosan: View {
    let team: Team
    let score: Int?
    let status: GameStatus
    let palette: StadiumPalette
    var isWinningRow: Bool = false
    var showsHomeBadge: Bool = false
    var assetStyle: TeamImageAssetStyle = .officialLogoPreferred

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(isWinningRow ? palette.secondary : Color.clear)
                .frame(width: 2, height: 24)
            TeamMarkView(team: team, size: 28, assetStyle: assetStyle)
            HStack(spacing: 4) {
                Text(team.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isWinningRow ? palette.textPrimary : palette.textSecondary)
                    .lineLimit(1)
                    .layoutPriority(1)

                if showsHomeBadge {
                    HomeTeamBadge()
                }
            }
            Spacer(minLength: 8)
            if status != .upcoming, let score {
                Text("\(score)")
                    .font(.headline.weight(isWinningRow ? .heavy : .bold))
                    .foregroundStyle(isWinningRow ? palette.textPrimary : palette.textSecondary)
                    .monospacedDigit()
            }
        }
    }
}

private struct HomeTeamBadge: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let palette = appModel.favoriteStadiumPalette

        Text("홈")
            .font(.caption2.weight(.bold))
            .foregroundStyle(palette?.textSecondary ?? .secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(palette?.sectionBackground ?? Color.secondary.opacity(0.14))
            )
            .overlay {
                if palette == nil {
                    Capsule()
                        .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.5)
                }
            }
            .accessibilityLabel("홈팀")
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    let model = AppModel.previewModel()
    return GameCardView(summary: model.filteredHomeGames.first!)
        .padding()
}
