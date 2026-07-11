//
//  KBOScoreLiveActivityWidget.swift
//  kboScoreLiveActivityExtension
//  기능 설명: KBO 경기 Live Activity와 다이내믹 아일랜드 UI를 렌더링합니다.
//  사용자가 경기 상태와 설정을 빠르게 이해하도록 도메인 상태를 화면 구조에 직접 매핑합니다.
//  SwiftUI 상태 갱신, 접근성, 작은 화면 레이아웃에서 정보가 겹치지 않도록 표시 조건을 제한합니다.
//  TODO : 반복되는 화면 조각은 재사용 가능한 컴포넌트로 분리하고 미리보기 케이스를 보강합니다.
//
//  Created by Codex on 3/26/26.
//

import ActivityKit
import SwiftUI
import WidgetKit

// KBOScoreLiveActivityWidget 구조체는 KBOScoreLiveActivityWidget 타입의 역할과 값을 정의합니다.
struct KBOScoreLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FavoriteTeamGameActivityAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            let game = BroadcastScoreboardGame(context: context)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DynamicIslandTeamView(
                        side: game.away,
                        alignment: .leading,
                        isBatting: game.battingSide == .away,
                        showsScore: game.isPreGame == false
                    )
                }

                DynamicIslandExpandedRegion(.trailing) {
                    DynamicIslandTeamView(
                        side: game.home,
                        alignment: .trailing,
                        isBatting: game.battingSide == .home,
                        showsScore: game.isPreGame == false
                    )
                }

                DynamicIslandExpandedRegion(.center) {
                    DynamicIslandStatusView(
                        inningText: game.inningText,
                        statusText: game.statusText,
                        baseState: game.baseState
                    )
                }

                DynamicIslandExpandedRegion(.bottom) {
                    DynamicIslandBroadcastMetadataRow(game: game)
                }
            } compactLeading: {
                Text(game.isPreGame ? game.away.shortName : "\(game.away.shortName) \(game.away.scoreText)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(.white)
            } compactTrailing: {
                Text(game.isPreGame ? game.home.shortName : "\(game.home.scoreText) \(game.home.shortName)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(.white)
            } minimal: {
                Text(game.minimalStatusText)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .keylineTint(game.favoriteAccent)
        }
    }
}

// LockScreenLiveActivityView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
private struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<FavoriteTeamGameActivityAttributes>

    var body: some View {
        BroadcastScoreboardStrip(game: BroadcastScoreboardGame(context: context))
            .padding(.vertical, 6)
            .activityBackgroundTint(Color.black.opacity(0.88))
            .activitySystemActionForegroundColor(.white)
    }
}

// BroadcastScoreboardGame 구조체는 BroadcastScoreboardGame 타입의 역할과 값을 정의합니다.
private struct BroadcastScoreboardGame {
    let away: BroadcastTeamSide
    let home: BroadcastTeamSide
    let inningText: String
    let statusText: String
    let batterText: String?
    let pitcherText: String?
    let metadataText: String?
    let battingSide: KBOLiveActivityOffenseSide?
    let baseState: BroadcastBaseState?
    let isPreGame: Bool
    let awayStartingPitcherName: String?
    let homeStartingPitcherName: String?
    let balls: Int?
    let strikes: Int?
    let outs: Int?
    let favoriteAccent: Color

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(context: ActivityViewContext<FavoriteTeamGameActivityAttributes>) {
        let favorite = BroadcastTeamSide(
            roleLabel: context.attributes.isHomeGame ? "홈" : "원정",
            teamID: context.attributes.favoriteTeamID,
            teamName: context.attributes.favoriteTeamName,
            shortName: context.attributes.favoriteTeamShortName,
            scoreText: context.state.favoriteScoreText
        )
        let opponent = BroadcastTeamSide(
            roleLabel: context.attributes.isHomeGame ? "원정" : "홈",
            teamID: context.attributes.opponentTeamID,
            teamName: context.attributes.opponentTeamName,
            shortName: context.attributes.opponentTeamShortName,
            scoreText: context.state.opponentScoreText
        )

        away = context.attributes.isHomeGame ? opponent : favorite
        home = context.attributes.isHomeGame ? favorite : opponent
        isPreGame = context.state.isPreGame
        inningText = context.state.inningText
        statusText = context.state.summaryText
        batterText = context.state.isPreGame ? nil : context.state.currentBatterName
        pitcherText = context.state.isPreGame ? nil : context.state.currentPitcherName
        awayStartingPitcherName = context.attributes.isHomeGame ? context.state.opponentStartingPitcherName : context.state.favoriteStartingPitcherName
        homeStartingPitcherName = context.attributes.isHomeGame ? context.state.favoriteStartingPitcherName : context.state.opponentStartingPitcherName
        battingSide = KBOLiveActivityOffenseResolver.offenseSide(
            isPreGame: context.state.isPreGame,
            summaryText: context.state.summaryText,
            inningText: context.state.inningText
        )
        metadataText = Self.metadataText(
            inningText: context.state.inningText,
            statusText: context.state.summaryText,
            venue: context.attributes.venue
        )
        baseState = context.state.isPreGame ? nil : Self.baseState(
            first: context.state.runnerOnFirst ?? false,
            second: context.state.runnerOnSecond ?? false,
            third: context.state.runnerOnThird ?? false
        )
        balls = context.state.isPreGame ? nil : context.state.balls
        strikes = context.state.isPreGame ? nil : context.state.strikes
        outs = context.state.isPreGame ? nil : context.state.outs
        favoriteAccent = favorite.accent
    }

    var minimalStatusText: String {
        if statusText == "LIVE" {
            return "LIVE"
        }
        return statusText
    }

    // metadataText 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func metadataText(inningText: String, statusText: String, venue: String) -> String? {
        var parts: [String] = []
        if inningText.isEmpty == false && inningText != statusText {
            parts.append(inningText)
        }
        if venue.isEmpty == false {
            parts.append(venue)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // baseState 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func baseState(first: Bool?, second: Bool?, third: Bool?) -> BroadcastBaseState? {
        guard first != nil || second != nil || third != nil else {
            return nil
        }

        return BroadcastBaseState(
            first: first ?? false,
            second: second ?? false,
            third: third ?? false
        )
    }

    // countText 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func countText(balls: Int?, strikes: Int?, outs: Int?) -> String? {
        let parts = [
            KBOCountDisplay.balls(balls).map { "B \($0)" },
            KBOCountDisplay.strikes(strikes).map { "S \($0)" },
            KBOCountDisplay.outs(outs).map { "O \($0)" }
        ].compactMap { $0 }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var countText: String? {
        Self.countText(balls: balls, strikes: strikes, outs: outs)
    }

    var hasBroadcastMetadata: Bool {
        if isPreGame {
            return true
        }
        return batterText != nil || countText != nil || pitcherText != nil
    }

    var compactMetadataText: String? {
        [
            batterText.map { "B \($0)" },
            countText,
            pitcherText.map { "P \($0)" },
            metadataText
        ]
            .compactMap { $0 }
            .joined(separator: " · ")
            .nilIfEmpty
    }
}

// BroadcastBaseState 구조체는 화면이나 도메인 흐름에서 사용하는 상태 값을 표현합니다.
private struct BroadcastBaseState {
    let first: Bool
    let second: Bool
    let third: Bool
}

// BroadcastTeamSide 구조체는 BroadcastTeamSide 타입의 역할과 값을 정의합니다.
private struct BroadcastTeamSide {
    let roleLabel: String
    let teamID: String
    let teamName: String
    let shortName: String
    let scoreText: String

    var accent: Color {
        TeamIdentity.catalog[teamID]?.theme.accent ?? .white
    }
}

// ScoreboardAlignment 열거형는 ScoreboardAlignment 타입의 역할과 값을 정의합니다.
private enum ScoreboardAlignment {
    case leading
    case trailing

    var horizontal: HorizontalAlignment {
        switch self {
        case .leading:
            .leading
        case .trailing:
            .trailing
        }
    }

    var frame: Alignment {
        switch self {
        case .leading:
            .leading
        case .trailing:
            .trailing
        }
    }
}

// BroadcastScoreboardStrip 구조체는 BroadcastScoreboardStrip 타입의 역할과 값을 정의합니다.
private struct BroadcastScoreboardStrip: View {
    let game: BroadcastScoreboardGame

    var body: some View {
        VStack(spacing: 0) {
            BroadcastScoreboardMainRow(game: game)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 9)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)

            BroadcastScoreboardMetadataRow(game: game)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 9)
        }
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.72))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
    }
}

// BroadcastScoreboardMainRow 구조체는 BroadcastScoreboardMainRow 타입의 역할과 값을 정의합니다.
private struct BroadcastScoreboardMainRow: View {
    let game: BroadcastScoreboardGame

    var body: some View {
        HStack(spacing: 8) {
            BroadcastTeamIdentityView(
                side: game.away,
                alignment: .leading,
                isBatting: game.battingSide == .away
            )

            if game.isPreGame == false {
                BroadcastScoreValue(scoreText: game.away.scoreText)
            }

            BroadcastGameStateHub(
                inningText: game.inningText,
                statusText: game.statusText,
                baseState: game.baseState
            )

            if game.isPreGame == false {
                BroadcastScoreValue(scoreText: game.home.scoreText)
            }

            BroadcastTeamIdentityView(
                side: game.home,
                alignment: .trailing,
                isBatting: game.battingSide == .home
            )
        }
        .frame(minHeight: 56)
    }
}

// BroadcastTeamIdentityView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
private struct BroadcastTeamIdentityView: View {
    let side: BroadcastTeamSide
    let alignment: ScoreboardAlignment
    let isBatting: Bool

    var body: some View {
        HStack(spacing: 7) {
            if alignment == .leading {
                teamMark(isVisible: isBatting)
            }

            VStack(alignment: alignment.horizontal, spacing: 2) {
                Text(side.shortName)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .accessibilityLabel(side.teamName)

                HStack(spacing: 3) {
                    if isBatting {
                        Circle()
                            .fill(.white)
                            .frame(width: 5, height: 5)
                    }

                    Text(isBatting ? "\(side.roleLabel) 공격" : side.roleLabel)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(isBatting ? .white.opacity(0.82) : .white.opacity(0.54))
                }
            }

            if alignment == .trailing {
                teamMark(isVisible: isBatting)
            }
        }
        .padding(.horizontal, isBatting ? 5 : 0)
        .padding(.vertical, isBatting ? 4 : 0)
        .background {
            if isBatting {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment.frame)
    }

    @ViewBuilder
    private func teamMark(isVisible: Bool) -> some View {
        Rectangle()
            .fill(side.accent)
            .frame(width: 4, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .opacity(isVisible ? 1 : 0)
            .accessibilityHidden(isVisible == false)
    }
}

// BroadcastScoreValue 구조체는 BroadcastScoreValue 타입의 역할과 값을 정의합니다.
private struct BroadcastScoreValue: View {
    let scoreText: String

    var body: some View {
        Text(scoreText)
            .font(.system(size: 36, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .shadow(color: Color.black.opacity(0.36), radius: 2, y: 1)
            .frame(minWidth: 34)
    }
}

// BroadcastGameStateHub 구조체는 BroadcastGameStateHub 타입의 역할과 값을 정의합니다.
private struct BroadcastGameStateHub: View {
    let inningText: String
    let statusText: String
    let baseState: BroadcastBaseState?

    var body: some View {
        VStack(spacing: 3) {
            Text(primaryText)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.66)

            if let baseState {
                BroadcastBaseDiamond(baseState: baseState, size: 26)
            }

            if shouldShowStatus {
                Text(statusText)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(statusText == "LIVE" ? Color(red: 1, green: 0.36, blue: 0.36) : .white.opacity(0.74))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(width: 82)
        .frame(minHeight: 54)
        .padding(.horizontal, 4)
        .background(Color.white.opacity(0.08))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 1)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 1)
        }
    }

    private var primaryText: String {
        inningText.isEmpty ? statusText : inningText
    }

    private var shouldShowStatus: Bool {
        statusText.isEmpty == false && statusText != primaryText
    }
}

// BroadcastBaseDiamond 구조체는 BroadcastBaseDiamond 타입의 역할과 값을 정의합니다.
private struct BroadcastBaseDiamond: View {
    let baseState: BroadcastBaseState
    let size: CGFloat

    var body: some View {
        ZStack {
            base(isOccupied: baseState.second)
                .offset(y: -size * 0.26)
            base(isOccupied: baseState.first)
                .offset(x: size * 0.26)
            base(isOccupied: baseState.third)
                .offset(x: -size * 0.26)
            base(isOccupied: false)
                .offset(y: size * 0.26)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityText)
    }

    // base 메서드는 이 타입의 주요 동작을 수행합니다.
    private func base(isOccupied: Bool) -> some View {
        RoundedRectangle(cornerRadius: size * 0.09, style: .continuous)
            .fill(isOccupied ? Color.white : Color.white.opacity(0.18))
            .frame(width: size * 0.24, height: size * 0.24)
            .rotationEffect(.degrees(45))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.09, style: .continuous)
                    .stroke(Color.white.opacity(isOccupied ? 0.90 : 0.26), lineWidth: 0.8)
                    .rotationEffect(.degrees(45))
            }
    }

    private var accessibilityText: String {
        let occupiedBases = [
            baseState.first ? "1루" : nil,
            baseState.second ? "2루" : nil,
            baseState.third ? "3루" : nil
        ].compactMap { $0 }

        if occupiedBases.isEmpty {
            return "주자 없음"
        }
        return "주자 \(occupiedBases.joined(separator: ", "))"
    }
}

// BroadcastScoreboardMetadataRow 구조체는 BroadcastScoreboardMetadataRow 타입의 역할과 값을 정의합니다.
private struct BroadcastScoreboardMetadataRow: View {
    let game: BroadcastScoreboardGame

    var body: some View {
        HStack(spacing: 8) {
            if game.isPreGame {
                BroadcastPlayerSlot(
                    label: "\(game.away.shortName) 선발",
                    text: game.awayStartingPitcherName ?? "선발 미정",
                    alignment: .leading
                )

                Text(game.metadataText ?? game.statusText)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                BroadcastPlayerSlot(
                    label: "\(game.home.shortName) 선발",
                    text: game.homeStartingPitcherName ?? "선발 미정",
                    alignment: .trailing
                )
            } else {
                BroadcastPlayerSlot(
                    label: "타자",
                    text: game.batterText,
                    alignment: .leading
                )

                BroadcastCountCluster(
                    balls: game.balls,
                    strikes: game.strikes,
                    outs: game.outs
                )

                BroadcastPlayerSlot(
                    label: "투수",
                    text: game.pitcherText,
                    alignment: .trailing
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 28)
        .accessibilityElement(children: .combine)
    }
}

// BroadcastPlayerSlot 구조체는 BroadcastPlayerSlot 타입의 역할과 값을 정의합니다.
private struct BroadcastPlayerSlot: View {
    let label: String
    let text: String?
    let alignment: ScoreboardAlignment

    var body: some View {
        Group {
            if let text {
                VStack(alignment: alignment.horizontal, spacing: 2) {
                    Text(label)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.50))

                    Text(text)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                }
            } else {
                Color.clear
                    .frame(height: 26)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment.frame)
    }
}

// BroadcastCountCluster 구조체는 BroadcastCountCluster 타입의 역할과 값을 정의합니다.
private struct BroadcastCountCluster: View {
    let balls: Int?
    let strikes: Int?
    let outs: Int?

    @ViewBuilder
    var body: some View {
        if metrics.isEmpty == false {
            HStack(spacing: 6) {
                ForEach(metrics) { metric in
                    HStack(spacing: 3) {
                        Text(metric.label)
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.56))

                        Text(String(metric.value))
                            .font(.caption2.weight(.black))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.09))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    private var metrics: [BroadcastCountMetric] {
        [
            KBOCountDisplay.balls(balls).map { BroadcastCountMetric(label: "B", value: $0) },
            KBOCountDisplay.strikes(strikes).map { BroadcastCountMetric(label: "S", value: $0) },
            KBOCountDisplay.outs(outs).map { BroadcastCountMetric(label: "O", value: $0) }
        ].compactMap { $0 }
    }
}

// BroadcastCountMetric 구조체는 BroadcastCountMetric 타입의 역할과 값을 정의합니다.
private struct BroadcastCountMetric: Identifiable {
    let label: String
    let value: Int

    var id: String { label }
}

private extension String {
    var nilIfEmpty: String? {
        if isEmpty {
            return nil
        }
        return self
    }
}

// DynamicIslandTeamView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
private struct DynamicIslandTeamView: View {
    let side: BroadcastTeamSide
    let alignment: ScoreboardAlignment
    let isBatting: Bool
    let showsScore: Bool

    var body: some View {
        VStack(alignment: alignment.horizontal, spacing: 3) {
            HStack(spacing: 3) {
                if isBatting {
                    Circle()
                        .fill(.primary)
                        .frame(width: 4, height: 4)
                }

                Text(isBatting ? "\(side.roleLabel) 공격" : side.roleLabel)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(isBatting ? .primary : .secondary)
            }

            HStack(spacing: 5) {
                if alignment == .trailing && showsScore {
                    Text(side.scoreText)
                        .font(scoreFont)
                        .monospacedDigit()
                }

                Text(side.shortName)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(side.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if alignment == .leading && showsScore {
                    Text(side.scoreText)
                        .font(scoreFont)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: alignment.frame)
    }

    private var scoreFont: Font {
        .system(size: 18, weight: .black, design: .rounded)
    }
}

// DynamicIslandStatusView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
private struct DynamicIslandStatusView: View {
    let inningText: String
    let statusText: String
    let baseState: BroadcastBaseState?

    var body: some View {
        VStack(spacing: 2) {
            Text(inningText.isEmpty ? statusText : inningText)
                .font(.caption.weight(.black))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if let baseState {
                BroadcastBaseDiamond(baseState: baseState, size: 18)
            }

            if statusText.isEmpty == false && statusText != inningText {
                Text(statusText)
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(statusText == "LIVE" ? Color(red: 1, green: 0.36, blue: 0.36) : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
    }
}

// DynamicIslandBroadcastMetadataRow 구조체는 DynamicIslandBroadcastMetadataRow 타입의 역할과 값을 정의합니다.
private struct DynamicIslandBroadcastMetadataRow: View {
    let game: BroadcastScoreboardGame

    var body: some View {
        if game.isPreGame {
            HStack(spacing: 8) {
                DynamicIslandMetadataSlot(text: "\(game.away.shortName) \(game.awayStartingPitcherName ?? "선발 미정")", alignment: .leading)
                Text(game.statusText)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                DynamicIslandMetadataSlot(text: "\(game.home.shortName) \(game.homeStartingPitcherName ?? "선발 미정")", alignment: .trailing)
            }
            .frame(maxWidth: .infinity)
        } else if game.hasBroadcastMetadata {
            HStack(spacing: 8) {
                DynamicIslandMetadataSlot(text: game.batterText.map { "B \($0)" }, alignment: .leading)

                if let countText = game.countText {
                    Text(countText)
                        .font(.caption2.weight(.black))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                }

                DynamicIslandMetadataSlot(text: game.pitcherText.map { "P \($0)" }, alignment: .trailing)
            }
            .frame(maxWidth: .infinity)
        } else if let metadataText = game.metadataText {
            Text(metadataText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// DynamicIslandMetadataSlot 구조체는 DynamicIslandMetadataSlot 타입의 역할과 값을 정의합니다.
private struct DynamicIslandMetadataSlot: View {
    let text: String?
    let alignment: ScoreboardAlignment

    var body: some View {
        Group {
            if let text {
                Text(text)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            } else {
                Color.clear
                    .frame(height: 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment.frame)
    }
}
