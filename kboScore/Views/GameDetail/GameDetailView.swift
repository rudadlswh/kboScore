//
//  GameDetailView.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

struct GameDetailView: View {
    @Environment(AppModel.self) private var appModel
    let gameID: UUID

    var body: some View {
        ScrollView {
            if let game = appModel.game(withID: gameID) {
                VStack(alignment: .leading, spacing: 12) {
                    scoreboard(for: game)
                    actionButtons(for: game)

                    Text("경기 타임라인")
                        .font(.headline.weight(.bold))
                        .padding(.top, 4)

                    if game.events.isEmpty {
                        EmptyStateView(
                            systemImage: "list.bullet.rectangle",
                            title: "아직 이벤트가 없습니다",
                            message: "실시간 이벤트가 들어오면 여기에 표시됩니다."
                        )
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(game.events) { event in
                                eventCard(for: event)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "경기를 찾을 수 없습니다",
                    message: "관련 경기 데이터가 준비되지 않았습니다."
                )
                .padding(12)
            }
        }
        .background(KBOLivePalette.background)
        .navigationTitle("경기 상세")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func scoreboard(for game: GameDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                StatusBadge(status: game.status)
                Spacer()
                Label(game.venue, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                ScoreboardTeamColumn(team: game.awayTeam)
                    .frame(maxWidth: .infinity)

                VStack(spacing: 6) {
                    Text(scoreText(for: game))
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    InningStatusLine(text: game.inningText ?? inningFallback(for: game), tint: game.status.tintColor)
                }

                ScoreboardTeamColumn(team: game.homeTeam)
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 8) {
                SituationTile(title: "주자 상황") {
                    BasesDiamondView(bases: game.bases ?? .empty)
                }
                .frame(maxWidth: .infinity)

                SituationTile(title: "아웃") {
                    if let outs = game.outs, game.status.isLiveLike {
                        OutCountView(outs: outs)
                    } else {
                        Text(outsText(for: game))
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)

                SituationTile(title: "메모") {
                    Text(game.note ?? game.highlightText ?? "-")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .cardSurface(padding: 14, cornerRadius: 22, fillColor: game.status.cardBackgroundColor)
    }

    @ViewBuilder
    private func actionButtons(for game: GameDetail) -> some View {
        HStack(spacing: 10) {
            if appModel.shouldShowLiveActivityAction(for: game) {
                LiveActivityActionButton(game: game)
            }

            ShareLink(item: game.shareText) {
                Label("경기 공유하기", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.primary)
            }
        }
    }

    private func eventCard(for event: GameEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol(for: event.type))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color(for: event.type))
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(color(for: event.type).opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(event.inningText)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(event.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }
        .cardSurface(padding: 12, cornerRadius: 16)
    }

    private func symbol(for type: GameEventType) -> String {
        switch type {
        case .score:
            "chart.line.uptrend.xyaxis"
        case .pitching:
            "xmark"
        case .keyPlay:
            "figure.baseball"
        case .weather:
            "cloud.rain.fill"
        case .note:
            "text.bubble"
        }
    }

    private func color(for type: GameEventType) -> Color {
        switch type {
        case .score:
            KBOLivePalette.live
        case .pitching:
            KBOLivePalette.final
        case .keyPlay:
            KBOLivePalette.weather
        case .weather:
            KBOLivePalette.secondary
        case .note:
            KBOLivePalette.primary
        }
    }

    private func scoreText(for game: GameDetail) -> String {
        guard let awayScore = game.awayScore, let homeScore = game.homeScore, game.status != .upcoming else {
            return "VS"
        }
        return "\(awayScore) : \(homeScore)"
    }

    private func inningFallback(for game: GameDetail) -> String {
        switch game.status {
        case .upcoming:
            game.scheduledStart.formatted(date: .omitted, time: .shortened)
        case .live, .rainDelay, .final, .cancelled:
            game.status.title
        }
    }

    private func outsText(for game: GameDetail) -> String {
        guard let outs = game.outs, game.status.isLiveLike else {
            return game.status.isFinishedLike ? "-" : "대기"
        }
        return "\(outs) 아웃"
    }
}

private struct ScoreboardTeamColumn: View {
    let team: Team

    var body: some View {
        VStack(spacing: 8) {
            TeamMarkView(team: team, size: 50)
            Text(team.name)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

private struct InningStatusLine: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.subheadline.weight(.bold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.1), in: Capsule())
    }
}

private struct SituationTile<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.systemBackground).opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        GameDetailView(gameID: AppModel.previewModel().games.first!.id)
            .environment(AppModel.previewModel())
    }
}
