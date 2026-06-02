//
//  AttendanceView.swift
//  kboScore
//
//  Created by Codex on 5/20/26.
//

import SwiftUI

struct AttendanceView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if appModel.settings.favoriteTeamID == nil {
                        EmptyStateView(
                            systemImage: "person.crop.circle.badge.questionmark",
                            title: "응원팀을 선택해주세요",
                            message: "응원팀 경기의 직관 기록을 모아 보여드립니다."
                        )
                    } else {
                        summarySection
                        attendedGamesSection
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
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
            .navigationTitle("직관 기록")
            .navigationBarTitleDisplayMode(.inline)
            .stadiumNavigationChrome(appModel.favoriteStadiumPalette)
            .notificationsToolbarButton()
            .navigationDestination(for: String.self) { gameIdentity in
                GameDetailView(gameIdentity: gameIdentity)
            }
        }
    }

    private var dashboard: AttendanceDashboard {
        appModel.attendanceDashboard
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitleView(title: "직관 성적")
            VStack(spacing: 8) {
                AttendanceSummaryCard(title: "전체", summary: dashboard.overall, iconName: "checkmark.circle.fill")
                HStack(spacing: 8) {
                    AttendanceSummaryCard(title: "홈", summary: dashboard.home, iconName: "house.fill")
                    AttendanceSummaryCard(title: "원정", summary: dashboard.away, iconName: "airplane")
                }
            }
        }
    }

    @ViewBuilder
    private var attendedGamesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitleView(title: "직관 경기")
            if dashboard.games.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.circle",
                    title: "직관 완료 경기 없음",
                    message: "경기 상세에서 직관한 경기로 표시하면 이곳에 기록됩니다."
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(dashboard.games) { record in
                        NavigationLink(value: record.gameIdentity) {
                            AttendanceGameRecordRow(record: record)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct AttendanceSummaryCard: View {
    @Environment(AppModel.self) private var appModel
    let title: String
    let summary: AttendanceRecordSummary
    let iconName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(appModel.favoriteStadiumPalette?.secondary ?? appModel.currentTheme.accent)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(appModel.favoriteStadiumPalette?.textPrimary ?? .primary)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                AttendanceMetricView(title: "경기", value: summary.gamesText)
                AttendanceMetricView(title: "기록", value: summary.recordText)
                AttendanceMetricView(title: "승률", value: summary.winPercentageText, isHighlighted: true)
            }
        }
        .cardSurface(
            padding: 12,
            cornerRadius: 18,
            fillColor: appModel.favoriteStadiumPalette?.sectionBackground
        )
    }
}

private struct AttendanceMetricView: View {
    @Environment(AppModel.self) private var appModel
    let title: String
    let value: String
    var isHighlighted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
            Text(value)
                .font(.footnote.weight(.heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(
                    isHighlighted
                        ? (appModel.favoriteStadiumPalette?.secondary ?? appModel.currentTheme.accent)
                        : (appModel.favoriteStadiumPalette?.textPrimary ?? .primary)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AttendanceGameRecordRow: View {
    @Environment(AppModel.self) private var appModel
    let record: AttendanceGameRecord

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(record.side.title)
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(resultTint.opacity(0.12), in: Capsule())
                        .foregroundStyle(resultTint)
                    Text("vs \(record.opponentName)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(appModel.favoriteStadiumPalette?.textPrimary ?? .primary)
                        .lineLimit(1)
                }

                Text("\(dateText) · \(record.stadium)")
                    .font(.caption)
                    .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(record.scoreText)
                    .font(.footnote.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(appModel.favoriteStadiumPalette?.textPrimary ?? .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(resultText)
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(resultTint.opacity(0.14), in: Capsule())
                    .foregroundStyle(resultTint)
            }
        }
        .cardSurface(
            padding: 12,
            cornerRadius: 18,
            fillColor: appModel.favoriteStadiumPalette?.sectionBackground
        )
    }

    private var dateText: String {
        record.gameDate.formatted(.dateTime.month(.twoDigits).day(.twoDigits).weekday(.abbreviated))
    }

    private var resultText: String {
        switch record.result {
        case .win:
            "승"
        case .loss:
            "패"
        case .tie:
            "무"
        }
    }

    private var resultTint: Color {
        switch record.result {
        case .win:
            KBOLivePalette.live
        case .loss:
            KBOLivePalette.final
        case .tie:
            .secondary
        }
    }
}

#Preview {
    AttendanceView()
        .environment(AppModel.previewModel())
}
