//
//  MyTeamView.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

struct MyTeamView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let favoriteTeam = appModel.favoriteTeam {
                        MyTeamHeaderView(team: favoriteTeam)

                        if let statusMessage = appModel.statusMessage(for: .myTeam) {
                            DataStatusBannerView(message: statusMessage)
                        }

                        Group {
                            SectionTitleView(title: "직관 기록")
                            MyTeamAttendanceSummaryView(summary: appModel.myTeamAttendanceSummary)
                        }

                        Group {
                            SectionTitleView(title: "오늘 경기")

                            if let todayGame = appModel.myTeamTodayGame {
                                NavigationLink(value: appModel.gameNavigationIdentity(for: todayGame)) {
                                    GameCardView(summary: todayGame.summary(isMyTeamGame: true))
                                }
                                .buttonStyle(.plain)

                                Toggle(isOn: Binding(
                                    get: { appModel.isGameAlertEnabled(for: todayGame.id) },
                                    set: { appModel.setGameAlert($0, for: todayGame.id) }
                                )) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("현재 경기 알림")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(appModel.favoriteStadiumPalette?.textPrimary ?? .primary)
                                        Text("득점, 리드 변경, 종료 알림을 이 경기 기준으로 받습니다.")
                                            .font(.caption)
                                            .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                                    }
                                }
                                .toggleStyle(.switch)
                                .cardSurface(
                                    padding: 12,
                                    cornerRadius: 18,
                                    fillColor: appModel.favoriteStadiumPalette?.sectionBackground
                                )

                                if appModel.shouldShowLiveActivityAction(for: todayGame) {
                                    LiveActivityActionButton(game: todayGame)
                                }
                            } else {
                                EmptyStateView(
                                    systemImage: "calendar.badge.exclamationmark",
                                    title: "오늘 \(favoriteTeam.displayName) 경기 없음",
                                    message: "오늘은 쉬는 날입니다. 아래에서 다음 경기와 최근 결과를 확인하세요."
                                )
                            }
                        }

                        Group {
                            SectionTitleView(title: "다음 경기")

                            if let nextGame = appModel.myTeamNextGame {
                                NavigationLink(value: appModel.gameNavigationIdentity(for: nextGame)) {
                                    GameCardView(summary: nextGame.summary(isMyTeamGame: true))
                                }
                                .buttonStyle(.plain)
                            } else {
                                EmptyStateView(
                                    systemImage: "calendar",
                                    title: "다음 경기가 없습니다",
                                    message: "편성 데이터가 준비되면 표시됩니다."
                                )
                            }
                        }

                        Group {
                            SectionTitleView(title: "최근 결과")

                            if let recentResult = appModel.myTeamRecentResult {
                                NavigationLink(value: appModel.gameNavigationIdentity(for: recentResult)) {
                                    GameCardView(summary: recentResult.summary(isMyTeamGame: true))
                                }
                                .buttonStyle(.plain)
                            } else {
                                EmptyStateView(
                                    systemImage: "flag.pattern.checkered",
                                    title: "최근 결과가 없습니다",
                                    message: "최근 종료 경기 데이터가 준비되면 표시됩니다."
                                )
                            }
                        }
                    } else {
                        EmptyStateView(
                            systemImage: "star.slash",
                            title: "응원 팀을 선택해 주세요",
                            message: "설정 탭에서 응원 팀을 고르면 오늘 경기와 최근 결과를 바로 확인할 수 있습니다."
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background {
                if let palette = appModel.favoriteStadiumPalette {
                    LinearGradient(
                        colors: [palette.background, palette.sectionBackground],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    KBOLivePalette.background
                }
            }
            .navigationTitle("마이팀")
            .doosanInlineNavigationTitle(isEnabled: appModel.isStadiumFavoriteSelected)
            .stadiumNavigationChrome(appModel.favoriteStadiumPalette)
            .notificationsToolbarButton()
            .refreshable {
                await appModel.refreshMyTeam()
            }
            .navigationDestination(for: String.self) { gameIdentity in
                GameDetailView(gameIdentity: gameIdentity)
            }
        }
    }
}

private struct MyTeamAttendanceSummaryView: View {
    @Environment(AppModel.self) private var appModel
    let summary: AttendedGameSummary

    var body: some View {
        if summary.hasCompletedGames {
            HStack(spacing: 8) {
                attendanceMetric(title: "직관", value: summary.gamesText)
                attendanceMetric(title: "기록", value: summary.recordText)
                attendanceMetric(title: "승률", value: summary.winPercentageText)
            }
            .cardSurface(
                padding: 12,
                cornerRadius: 18,
                fillColor: appModel.favoriteStadiumPalette?.sectionBackground
            )
        } else {
            EmptyStateView(
                systemImage: "checkmark.circle",
                title: "직관 완료 경기 없음",
                message: "경기 상세에서 직관한 경기로 표시하면 이곳에 승률을 모아 보여드립니다."
            )
        }
    }

    private func attendanceMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
            Text(value)
                .font(.subheadline.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(
                    title == "승률"
                        ? (appModel.favoriteStadiumPalette?.secondary ?? appModel.currentTheme.accent)
                        : (appModel.favoriteStadiumPalette?.textPrimary ?? .primary)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MyTeamHeaderView: View {
    @Environment(AppModel.self) private var appModel
    let team: Team

    var body: some View {
        HStack(spacing: 12) {
            TeamMarkView(team: team, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("마이팀")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.82))
                Text(team.displayName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text("오늘 경기 우선, 다음 일정과 최근 결과를 함께 봅니다.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.76))
            }

            Spacer()

            Menu {
                Button("선택 해제", role: .destructive) {
                    appModel.settings.favoriteTeamID = nil
                }

                ForEach(appModel.teams) { candidate in
                    Button(candidate.displayName) {
                        appModel.settings.favoriteTeamID = candidate.id
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [
                    appModel.favoriteStadiumPalette?.background.opacity(0.96) ?? appModel.currentTheme.heroStart.opacity(0.96),
                    appModel.favoriteStadiumPalette?.primary.opacity(0.80) ?? appModel.currentTheme.heroEnd.opacity(0.84)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    appModel.favoriteStadiumPalette?.ghostBorder ?? Color.white.opacity(0.08),
                    lineWidth: appModel.isStadiumFavoriteSelected ? 0.75 : 1
                )
        )
        .shadow(
            color: appModel.favoriteStadiumPalette?.ambientShadow.opacity(0.40) ?? appModel.currentTheme.shadowTint,
            radius: appModel.isStadiumFavoriteSelected ? 14 : 12,
            y: appModel.isStadiumFavoriteSelected ? 8 : 6
        )
    }
}

private struct SectionTitleView: View {
    @Environment(AppModel.self) private var appModel
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .primary)
            .padding(.top, 2)
    }
}

#Preview {
    MyTeamView()
        .environment(AppModel.previewModel())
}
