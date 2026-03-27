//
//  KBOScoreLiveActivityWidget.swift
//  kboScoreLiveActivityExtension
//
//  Created by Codex on 3/26/26.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct KBOScoreLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FavoriteTeamGameActivityAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    teamBadge(
                        shortName: context.attributes.favoriteTeamShortName,
                        teamID: context.attributes.favoriteTeamID
                    )
                }

                DynamicIslandExpandedRegion(.trailing) {
                    teamBadge(
                        shortName: context.attributes.opponentTeamShortName,
                        teamID: context.attributes.opponentTeamID
                    )
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        scoreLine(context: context)
                        Text(context.state.inningText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Label(context.attributes.venue, systemImage: "mappin.and.ellipse")
                            .lineLimit(1)
                        Spacer()
                        Text(homeAwayText(isHomeGame: context.attributes.isHomeGame))
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Text(context.attributes.favoriteTeamShortName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(teamColor(for: context.attributes.favoriteTeamID))
            } compactTrailing: {
                Text("\(context.state.favoriteScoreText):\(context.state.opponentScoreText)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
            } minimal: {
                Text(context.attributes.favoriteTeamShortName)
                    .font(.caption2.weight(.bold))
            }
            .keylineTint(teamColor(for: context.attributes.favoriteTeamID))
        }
    }

    private func homeAwayText(isHomeGame: Bool) -> String {
        isHomeGame ? "홈" : "원정"
    }

    private func teamColor(for teamID: String) -> Color {
        switch teamID {
        case "doosan":
            Color(red: 0.97, green: 0.15, blue: 0.16)
        case "hanwha":
            Color(red: 1.0, green: 0.47, blue: 0.21)
        case "kia":
            Color(red: 0.90, green: 0.10, blue: 0.22)
        case "kiwoom":
            Color(red: 0.89, green: 0.00, blue: 0.49)
        case "kt":
            Color(red: 0.93, green: 0.11, blue: 0.14)
        case "lg":
            Color(red: 0.65, green: 0.00, blue: 0.20)
        case "lotte":
            Color(red: 0.82, green: 0.11, blue: 0.18)
        case "nc":
            Color(red: 0.00, green: 0.15, blue: 0.36)
        case "samsung":
            Color(red: 0.00, green: 0.33, blue: 0.71)
        case "ssg":
            Color(red: 0.78, green: 0.03, blue: 0.12)
        default:
            Color.accentColor
        }
    }

    private func teamBadge(shortName: String, teamID: String) -> some View {
        Text(shortName)
            .font(.headline.weight(.bold))
            .foregroundStyle(teamColor(for: teamID))
            .frame(minWidth: 44)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(teamColor(for: teamID).opacity(0.12), in: Capsule())
    }

    private func scoreLine(context: ActivityViewContext<FavoriteTeamGameActivityAttributes>) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.favoriteTeamShortName)
                    .font(.caption.weight(.bold))
                Text(context.state.favoriteScoreText)
                    .font(.title2.weight(.heavy))
                    .monospacedDigit()
            }

            Text(":")
                .font(.title3.weight(.bold))
                .foregroundStyle(.secondary)

            VStack(alignment: .trailing, spacing: 2) {
                Text(context.attributes.opponentTeamShortName)
                    .font(.caption.weight(.bold))
                Text(context.state.opponentScoreText)
                    .font(.title2.weight(.heavy))
                    .monospacedDigit()
            }
        }
    }
}

private struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<FavoriteTeamGameActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(context.state.summaryText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(homeAwayText)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 12) {
                teamColumn(
                    shortName: context.attributes.favoriteTeamShortName,
                    scoreText: context.state.favoriteScoreText,
                    teamID: context.attributes.favoriteTeamID,
                    alignment: .leading
                )

                Spacer()

                VStack(spacing: 6) {
                    Text(context.state.inningText)
                        .font(.headline.weight(.bold))
                    Label(context.attributes.venue, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                teamColumn(
                    shortName: context.attributes.opponentTeamShortName,
                    scoreText: context.state.opponentScoreText,
                    teamID: context.attributes.opponentTeamID,
                    alignment: .trailing
                )
            }
        }
        .padding(.vertical, 8)
        .activityBackgroundTint(Color.black.opacity(0.88))
        .activitySystemActionForegroundColor(.white)
    }

    private var homeAwayText: String {
        context.attributes.isHomeGame ? "홈 경기" : "원정 경기"
    }

    private func teamColumn(shortName: String, scoreText: String, teamID: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(shortName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(teamColor(for: teamID))
            Text(scoreText)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    private func teamColor(for teamID: String) -> Color {
        switch teamID {
        case "doosan":
            Color(red: 0.97, green: 0.15, blue: 0.16)
        case "hanwha":
            Color(red: 1.0, green: 0.47, blue: 0.21)
        case "kia":
            Color(red: 0.90, green: 0.10, blue: 0.22)
        case "kiwoom":
            Color(red: 0.89, green: 0.00, blue: 0.49)
        case "kt":
            Color(red: 0.93, green: 0.11, blue: 0.14)
        case "lg":
            Color(red: 0.65, green: 0.00, blue: 0.20)
        case "lotte":
            Color(red: 0.82, green: 0.11, blue: 0.18)
        case "nc":
            Color(red: 0.00, green: 0.15, blue: 0.36)
        case "samsung":
            Color(red: 0.00, green: 0.33, blue: 0.71)
        case "ssg":
            Color(red: 0.78, green: 0.03, blue: 0.12)
        default:
            Color.white
        }
    }
}
