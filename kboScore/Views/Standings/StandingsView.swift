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
            if appModel.standingsSnapshots.isEmpty {
                EmptyStateView(
                    systemImage: "list.number",
                    title: "정규시즌 순위 데이터 없음",
                    message: "현재 데이터에서 시범경기를 제외한 정규시즌 종료 경기를 찾지 못했습니다."
                )
            } else {
                standingsTable
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var standingsTable: some View {
        GeometryReader { proxy in
            let metrics = StandingsTableMetrics(width: proxy.size.width)
            let leaderSnapshot = appModel.standingsSnapshots.first

            VStack(spacing: 5) {
                StandingsTableHeader(metrics: metrics)

                LazyVStack(spacing: 5) {
                    ForEach(appModel.standingsSnapshots) { snapshot in
                        StandingsRowView(
                            snapshot: snapshot,
                            leaderSnapshot: leaderSnapshot,
                            favoriteTeamID: appModel.settings.favoriteTeamID,
                            metrics: metrics
                        )
                    }
                }
            }
        }
        .frame(height: CGFloat(appModel.standingsSnapshots.count) * 57 + 18)
    }
}

private struct StandingsTableMetrics {
    let isCompact: Bool

    init(width: CGFloat) {
        isCompact = width < 370
    }

    var rowHeight: CGFloat { isCompact ? 48 : 52 }
    var horizontalPadding: CGFloat { isCompact ? 6 : 7 }
    var spacing: CGFloat { 4 }
    var teamColumnWidth: CGFloat { isCompact ? 76 : 128 }
    var rankWidth: CGFloat { isCompact ? 30 : 36 }
    var logoSize: CGFloat { isCompact ? 22 : 30 }
    var gamesWidth: CGFloat { isCompact ? 24 : 26 }
    var countWidth: CGFloat { isCompact ? 19 : 20 }
    var percentageWidth: CGFloat { isCompact ? 38 : 42 }
    var gamesBehindWidth: CGFloat { isCompact ? 32 : 36 }
    var streakWidth: CGFloat { isCompact ? 30 : 32 }
    var accentWidth: CGFloat { isCompact ? 78 : 120 }
}

private struct StandingsTableHeader: View {
    @Environment(AppModel.self) private var appModel

    let metrics: StandingsTableMetrics

    var body: some View {
        HStack(spacing: metrics.spacing) {
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
        ZStack(alignment: .leading) {
            rowBackground

            TeamLogoAccentView(
                identity: identity,
                isFavorite: isFavorite,
                width: metrics.accentWidth
            )

            HStack(spacing: metrics.spacing) {
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

    private var teamCell: some View {
        HStack(spacing: metrics.isCompact ? 4 : 6) {
            HStack(spacing: 2) {
                Text("\(snapshot.rank)")
                    .font((isFavorite ? Font.subheadline.weight(.black) : Font.subheadline.weight(.heavy)))
                    .monospacedDigit()

                if let indicator = rankMovement.indicator {
                    Text(indicator)
                        .font(.caption2.weight(.black))
                }
            }
            .foregroundStyle(Color.white.opacity(isFavorite ? 1 : 0.94))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(width: metrics.rankWidth, alignment: .trailing)

            if metrics.isCompact == false {
                TeamMarkView(team: snapshot.team, size: metrics.logoSize)
                    .shadow(color: Color.black.opacity(0.16), radius: 4, y: 2)
            }

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
        StandingsRankMovementResolver.movement(currentRank: snapshot.rank, preGameRank: snapshot.preGameRank)
    }

    private var accessibilityLabel: String {
        let movementText = rankMovement.accessibilityText.map { ", \($0)" } ?? ""
        return "\(snapshot.rank)위 \(identity.standingsDisplayName)\(movementText), \(snapshot.wins)승 \(snapshot.losses)패 \(snapshot.ties)무, 승률 \(snapshot.winPercentageText), 게임차 \(snapshot.gamesBehindText(leader: leaderSnapshot)), 연속 \(snapshot.currentStreakText)"
    }
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
            .minimumScaleFactor(0.74)
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

private extension TeamIdentity {
    var standingsDisplayName: String {
        switch id {
        case "lg":
            "LG"
        case "kt":
            "KT"
        case "ssg":
            "SSG"
        case "samsung":
            "삼성"
        case "kia":
            "KIA"
        case "hanwha":
            "한화"
        case "nc":
            "NC"
        case "doosan":
            "두산"
        case "lotte":
            "롯데"
        case "kiwoom":
            "키움"
        default:
            shortLabel
        }
    }
}

private extension TeamStandingsSnapshot {
    var broadcastWinPercentageText: String {
        if winPercentageText.hasPrefix("0.") {
            return String(winPercentageText.dropFirst())
        }
        return winPercentageText
    }

    var currentStreakText: String {
        if let precomputedStreakText,
           precomputedStreakText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return precomputedStreakText
        }
        guard let firstResult = recentResults.first else { return "-" }

        var count = 0
        for result in recentResults {
            guard result == firstResult else { break }
            count += 1
        }

        return "\(count)\(firstResult.shortLabel)"
    }

    func gamesBehindText(leader: TeamStandingsSnapshot?) -> String {
        if let precomputedGamesBehind {
            guard precomputedGamesBehind > 0 else { return "-" }
            if precomputedGamesBehind.rounded(.towardZero) == precomputedGamesBehind {
                return String(format: "%.0f", precomputedGamesBehind)
            }
            return String(format: "%.1f", precomputedGamesBehind)
        }
        guard let leader else { return "-" }
        guard rank != leader.rank else { return "-" }

        let gamesBehind = Double((leader.wins - wins) + (losses - leader.losses)) / 2
        guard gamesBehind > 0 else { return "-" }

        if gamesBehind.rounded(.towardZero) == gamesBehind {
            return String(format: "%.0f", gamesBehind)
        }
        return String(format: "%.1f", gamesBehind)
    }
}

#Preview {
    StandingsView()
        .environment(AppModel.previewModel())
}
