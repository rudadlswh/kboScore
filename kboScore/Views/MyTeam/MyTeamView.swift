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
                            SectionTitleView(title: "오늘 경기")

                            if let todayGame = appModel.myTeamTodayGame {
                                NavigationLink(value: todayGame.id) {
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
                                        Text("득점, 리드 변경, 종료 알림을 이 경기 기준으로 받습니다.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(.switch)
                                .cardSurface(padding: 12, cornerRadius: 18)

                                if appModel.shouldShowLiveActivityAction(for: todayGame) {
                                    LiveActivityActionButton(game: todayGame)
                                }
                            } else {
                                EmptyStateView(
                                    systemImage: "calendar.badge.exclamationmark",
                                    title: "오늘 \(favoriteTeam.shortName) 경기 없음",
                                    message: "오늘은 쉬는 날입니다. 아래에서 다음 경기와 최근 결과를 확인하세요."
                                )
                            }
                        }

                        Group {
                            SectionTitleView(title: "다음 경기")

                            if let nextGame = appModel.myTeamNextGame {
                                NavigationLink(value: nextGame.id) {
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
                                NavigationLink(value: recentResult.id) {
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
            .background(KBOLivePalette.background)
            .navigationTitle("마이팀")
            .notificationsToolbarButton()
            .refreshable {
                await appModel.refreshMyTeam()
            }
            .navigationDestination(for: UUID.self) { gameID in
                GameDetailView(gameID: gameID)
            }
        }
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
                Text(team.name)
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
                    Button(candidate.name) {
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
                    appModel.currentTheme.heroStart.opacity(0.96),
                    appModel.currentTheme.heroEnd.opacity(0.84)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: appModel.currentTheme.shadowTint, radius: 12, y: 6)
    }
}

private struct SectionTitleView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .padding(.top, 2)
    }
}

#Preview {
    MyTeamView()
        .environment(AppModel.previewModel())
}
