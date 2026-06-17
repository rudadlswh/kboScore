//
//  GameCardView.swift
//  kboScore
//  기능 설명: 경기 요약 정보를 카드 형태로 렌더링합니다.
//  사용자가 경기 상태와 설정을 빠르게 이해하도록 도메인 상태를 화면 구조에 직접 매핑합니다.
//  SwiftUI 상태 갱신, 접근성, 작은 화면 레이아웃에서 정보가 겹치지 않도록 표시 조건을 제한합니다.
//  TODO : 반복되는 화면 조각은 재사용 가능한 컴포넌트로 분리하고 미리보기 케이스를 보강합니다.
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

// GameCardLiveColorStyle 열거형는 GameCardLiveColorStyle 타입의 역할과 값을 정의합니다.
enum GameCardLiveColorStyle {
    case standard
    case white
}

// GameCardView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
struct GameCardView: View {
    @Environment(AppModel.self) private var appModel
    let summary: GameSummary
    let showsHomeTeamBadge: Bool
    let liveColorStyle: GameCardLiveColorStyle

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(
        summary: GameSummary,
        showsHomeTeamBadge: Bool = false,
        liveColorStyle: GameCardLiveColorStyle = .standard
    ) {
        self.summary = summary
        self.showsHomeTeamBadge = showsHomeTeamBadge
        self.liveColorStyle = liveColorStyle
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
                        status: summary.status
                    )
                    TeamRowDefault(
                        team: summary.homeTeam,
                        score: summary.homeScore,
                        status: summary.status,
                        showsHomeBadge: showsHomeTeamBadge
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

    // stadiumBody 메서드는 이 타입의 주요 동작을 수행합니다.
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
                        isWinningRow: awayTeamIsWinning
                    )
                    TeamRowDoosan(
                        team: summary.homeTeam,
                        score: summary.homeScore,
                        status: summary.status,
                        palette: palette,
                        isWinningRow: homeTeamIsWinning,
                        showsHomeBadge: showsHomeTeamBadge
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

    // isWinningScore 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private func isWinningScore(away: Int?, home: Int?, checksAway: Bool) -> Bool {
        guard let away, let home, away != home, summary.status != .upcoming else {
            return false
        }
        return checksAway ? away > home : home > away
    }
}

// TeamRowDefault 구조체는 TeamRowDefault 타입의 역할과 값을 정의합니다.
private struct TeamRowDefault: View {
    let team: Team
    let score: Int?
    let status: GameStatus
    var showsHomeBadge: Bool = false

    var body: some View {
        HStack(spacing: 8) {
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

// TeamRowDoosan 구조체는 TeamRowDoosan 타입의 역할과 값을 정의합니다.
private struct TeamRowDoosan: View {
    let team: Team
    let score: Int?
    let status: GameStatus
    let palette: StadiumPalette
    var isWinningRow: Bool = false
    var showsHomeBadge: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(isWinningRow ? palette.secondary : Color.clear)
                .frame(width: 2, height: 24)
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

// HomeTeamBadge 구조체는 HomeTeamBadge 타입의 역할과 값을 정의합니다.
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
