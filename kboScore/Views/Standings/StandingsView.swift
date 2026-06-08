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
                standingsContent
            }
            .background {
                if let palette = appModel.favoriteStadiumPalette {
                    LinearGradient(
                        colors: [palette.background, palette.sectionBackground],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    KBOLivePalette.background
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle("순위")
            .navigationBarTitleDisplayMode(.inline)
            .stadiumNavigationChrome(appModel.favoriteStadiumPalette)
            .notificationsToolbarButton()
            .task(id: appModel.selectedTab) {
                guard appModel.selectedTab == .standings else { return }
                await appModel.loadStandingsIfNeeded()
            }
            .refreshable {
                await appModel.refreshStandings()
            }
        }
    }

    private var standingsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
#if DEBUG
            if let debugMessage = appModel.debugStandingsDiagnosticMessage {
                DataStatusBannerView(message: debugMessage)
            }
#endif
            switch standingsContentState {
            case .loading:
                ProgressView("순위 데이터를 불러오는 중")
                    .frame(maxWidth: .infinity, minHeight: 220)
            case .empty:
                EmptyStateView(
                    systemImage: "list.number",
                    title: "정규시즌 순위 데이터 없음",
                    message: "현재 데이터에서 시범경기를 제외한 정규시즌 종료 경기를 찾지 못했습니다."
                )
            case let .table(rows, revision, favoriteTeamID):
                standingsTable(
                    rows: rows,
                    revision: revision,
                    favoriteTeamID: favoriteTeamID
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var standingsContentState: StandingsContentState {
        StandingsContentState.make(
            rows: appModel.standingsSnapshots,
            isLoading: appModel.isLoading && appModel.games.isEmpty,
            revision: appModel.standingsRowsRevision,
            favoriteTeamID: appModel.settings.favoriteTeamID
        )
    }

    private func standingsTable(
        rows: [TeamStandingsSnapshot],
        revision: Int,
        favoriteTeamID: String?
    ) -> some View {
#if DEBUG
        let _ = Self.logVisibleRows(rows, revision: revision)
#endif

        return GeometryReader { proxy in
            let metrics = StandingsTableMetrics(width: proxy.size.width)
            let leaderSnapshot = rows.first

            VStack(spacing: 5) {
                StandingsTableHeader(metrics: metrics)

                LazyVStack(spacing: 5) {
                    ForEach(rows) { snapshot in
                        StandingsRowView(
                            snapshot: snapshot,
                            leaderSnapshot: leaderSnapshot,
                            favoriteTeamID: favoriteTeamID,
                            metrics: metrics
                        )
                        .id(StandingsRowRenderIdentity(snapshot: snapshot))
                    }
                }
            }
            .id(revision)
        }
        .frame(height: CGFloat(rows.count) * 57 + 18)
    }

#if DEBUG
    private static func logVisibleRows(_ rows: [TeamStandingsSnapshot], revision: Int) {
        let movementCount = rows.filter { $0.rankMovement != .unchanged }.count
        print("[StandingsRankMovement] visible rows source count=\(rows.count) movementCount=\(movementCount) revision=\(revision)")
    }
#endif
}

private struct StandingsTableHeader: View {
    @Environment(AppModel.self) private var appModel

    let metrics: StandingsTableMetrics

    var body: some View {
        HStack(spacing: metrics.spacing) {
            Color.clear
                .frame(width: metrics.rankMovementWidth)
            Text("팀")
                .frame(width: metrics.teamColumnWidth, alignment: .leading)
            headerLabel("경기", width: metrics.gamesWidth)
            headerLabel("승", width: metrics.countWidth)
            headerLabel("패", width: metrics.countWidth)
            headerLabel("무", width: metrics.countWidth)
            headerLabel("승률", width: metrics.percentageWidth)
            headerLabel("게임차", width: metrics.gamesBehindWidth)
            headerLabel("연속", width: metrics.streakWidth)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
        .padding(.horizontal, metrics.horizontalPadding)
        .frame(height: 18)
    }

    private func headerLabel(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: width, alignment: .trailing)
    }
}

private struct StandingsRowView: View {
    let snapshot: TeamStandingsSnapshot
    let leaderSnapshot: TeamStandingsSnapshot?
    let favoriteTeamID: String?
    let metrics: StandingsTableMetrics

    var body: some View {
#if DEBUG
        let _ = logRender()
#endif
        ZStack(alignment: .leading) {
            rowBackground

            TeamLogoAccentView(
                identity: identity,
                isFavorite: isFavorite,
                width: metrics.accentWidth
            )

            HStack(spacing: metrics.spacing) {
                rankCell
                teamCell
                StandingsColumnValue(value: "\(snapshot.gamesPlayed)", width: metrics.gamesWidth, isFavorite: isFavorite)
                StandingsColumnValue(value: "\(snapshot.wins)", width: metrics.countWidth, isFavorite: isFavorite)
                StandingsColumnValue(value: "\(snapshot.losses)", width: metrics.countWidth, isFavorite: isFavorite)
                StandingsColumnValue(value: "\(snapshot.ties)", width: metrics.countWidth, isFavorite: isFavorite)
                StandingsColumnValue(value: snapshot.broadcastWinPercentageText, width: metrics.percentageWidth, isFavorite: isFavorite)
                StandingsColumnValue(value: snapshot.gamesBehindText(leader: leaderSnapshot), width: metrics.gamesBehindWidth, isFavorite: isFavorite)
                StandingsColumnValue(value: snapshot.currentStreakText, width: metrics.streakWidth, isFavorite: isFavorite)
            }
            .padding(.horizontal, metrics.horizontalPadding)
        }
        .frame(height: metrics.rowHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(borderColor, lineWidth: isFavorite ? 1 : 0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var rankCell: some View {
        HStack(spacing: 2) {
            Text("\(snapshot.rank)")
                .font(isFavorite ? Font.subheadline.weight(.black) : Font.subheadline.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(isFavorite ? 1 : 0.94))
                .frame(width: metrics.rankWidth, alignment: .trailing)

            Text(rankMovement.displayText)
                .font(.caption2.weight(.black))
                .monospacedDigit()
                .foregroundStyle(rankMovementColor)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(width: metrics.movementWidth, alignment: .trailing)
        }
        .frame(width: metrics.rankMovementWidth, alignment: .trailing)
    }

    private var teamCell: some View {
        HStack(spacing: metrics.isCompact ? 4 : 6) {
            TeamMarkView(team: snapshot.team, size: metrics.logoSize)
                .shadow(color: Color.black.opacity(0.16), radius: 4, y: 2)

            Text(teamName)
                .font(.system(size: 15, weight: isFavorite ? .black : .bold, design: .default))
                .foregroundStyle(Color.white.opacity(isFavorite ? 1 : 0.96))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: metrics.teamColumnWidth, alignment: .leading)
    }

    private var rowBackground: some View {
        Group {
            if isFavorite {
                LinearGradient(
                    colors: [
                        identity.theme.heroEnd,
                        identity.theme.accent,
                        identity.theme.accentSecondary.opacity(0.82)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.34, green: 0.34, blue: 0.34),
                        Color(red: 0.25, green: 0.25, blue: 0.25)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
    }

    private var identity: TeamIdentity {
        snapshot.team.identity
    }

    private var teamName: String {
        identity.standingsDisplayName
    }

    private var isFavorite: Bool {
        snapshot.team.id == favoriteTeamID
    }

    private var borderColor: Color {
        isFavorite ? Color.white.opacity(0.28) : Color.white.opacity(0.08)
    }

    private var rankMovement: RankingMovement {
        snapshot.rankMovement
    }

    private var rankMovementColor: Color {
        switch rankMovement {
        case .up:
            Color(red: 0.42, green: 1.0, blue: 0.62)
        case .down:
            Color(red: 1.0, green: 0.58, blue: 0.58)
        case .unchanged:
            Color.white.opacity(0.48)
        }
    }

    private var accessibilityLabel: String {
        let movementText = rankMovement.accessibilityText.map { ", \($0)" } ?? ""
        return "\(snapshot.rank)위 \(identity.standingsDisplayName)\(movementText), \(snapshot.wins)승 \(snapshot.losses)패 \(snapshot.ties)무, 승률 \(snapshot.winPercentageText), 게임차 \(snapshot.gamesBehindText(leader: leaderSnapshot)), 연속 \(snapshot.currentStreakText)"
    }

#if DEBUG
    private func logRender() {
        let preGameRankText = snapshot.preGameRank.map(String.init) ?? "<nil>"
        print("[StandingsRankMovement] row render teamId=\(snapshot.team.id) rank=\(snapshot.rank) preGameRank=\(preGameRankText) movement displayText=\(rankMovement.displayText)")
    }
#endif
}

private struct StandingsColumnValue: View {
    let value: String
    let width: CGFloat
    let isFavorite: Bool

    var body: some View {
        Text(value)
            .font(.callout.weight(isFavorite ? .bold : .semibold))
            .monospacedDigit()
            .foregroundStyle(Color.white.opacity(isFavorite ? 1 : 0.92))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .allowsTightening(true)
            .frame(width: width, alignment: .trailing)
    }
}

private struct TeamLogoAccentView: View {
    let identity: TeamIdentity
    let isFavorite: Bool
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [
                    identity.theme.accent.opacity(isFavorite ? 0.12 : 0.86),
                    identity.theme.accent.opacity(isFavorite ? 0.08 : 0.36),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            if identity.hasLogoAsset {
                Image(identity.logoAssetName)
                    .resizable()
                    .scaledToFit()
                    .opacity(isFavorite ? 0.18 : 0.14)
                    .frame(width: width * 0.78, height: 58)
                    .offset(x: -14)
            } else {
                Text(identity.monogram)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white.opacity(isFavorite ? 0.14 : 0.10))
                    .offset(x: 8)
            }
        }
        .frame(width: width)
        .clipped()
    }
}

#Preview {
    StandingsView()
        .environment(AppModel.previewModel())
}
