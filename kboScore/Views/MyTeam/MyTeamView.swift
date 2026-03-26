//
//  MyTeamView.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import SwiftUI

struct MyTeamView: View {
    @Environment(AppModel.self) private var appModel
    @State private var displayedMonth = Date()
    @State private var selectedDate = Date()

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

                        Group {
                            SectionTitleView(title: "월간 일정")
                            MyTeamScheduleCalendarView(
                                displayedMonth: $displayedMonth,
                                selectedDate: $selectedDate
                            )
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
            .refreshable {
                await appModel.refreshMyTeam()
                await appModel.refreshMyTeamSchedule(for: displayedMonth)
            }
            .task(id: scheduleTaskID) {
                await appModel.loadMyTeamScheduleIfNeeded(for: displayedMonth)
            }
            .navigationDestination(for: UUID.self) { gameID in
                GameDetailView(gameID: gameID)
            }
        }
    }

    private var scheduleTaskID: String {
        let key = KBOMonthScheduleKey(date: displayedMonth)
        return "\(appModel.settings.favoriteTeamID ?? "none")-\(key.yearMonthText)"
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

private struct MyTeamScheduleCalendarView: View {
    @Environment(AppModel.self) private var appModel
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date

    private let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    let nextMonth = appModel.shiftedMonth(from: displayedMonth, by: -1)
                    displayedMonth = nextMonth
                    selectedDate = appModel.startOfMonth(for: nextMonth)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(appModel.currentTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(appModel.currentTheme.chipBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 2) {
                    Text(appModel.calendarMonthTitle(for: displayedMonth))
                        .font(.headline.weight(.bold))
                    Text(monthSummaryText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    let nextMonth = appModel.shiftedMonth(from: displayedMonth, by: 1)
                    displayedMonth = nextMonth
                    selectedDate = appModel.startOfMonth(for: nextMonth)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(appModel.currentTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(appModel.currentTheme.chipBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(calendarDays) { day in
                    Button {
                        selectedDate = day.date
                    } label: {
                        VStack(spacing: 4) {
                            Text(day.date.formatted(.dateTime.day()))
                                .font(.caption.weight(isSelected(day) ? .bold : .medium))
                                .foregroundStyle(dayNumberColor(for: day))

                            ZStack {
                                Circle()
                                    .fill(markerColor(for: day))
                                    .frame(width: day.gameCount > 1 ? 18 : 6, height: day.gameCount > 1 ? 18 : 6)
                                    .opacity(day.hasGames ? 1 : 0.12)

                                if day.gameCount > 1 {
                                    Text("\(day.gameCount)")
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(dayBackground(for: day), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(dayBorderColor(for: day), lineWidth: day.isToday || isSelected(day) ? 1 : 0)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if appModel.isLoadingMyTeamSchedule(for: displayedMonth) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("공식 월간 일정 불러오는 중")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let statusMessage = appModel.myTeamScheduleStatusMessage(for: displayedMonth) {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if selectedGames.isEmpty {
                EmptyStateView(
                    systemImage: "calendar",
                    title: selectedDayTitle,
                    message: appModel.settings.favoriteTeamID == nil
                        ? "응원 팀을 선택하면 일정이 표시됩니다."
                        : "선택한 날짜에는 등록된 경기가 없습니다."
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(selectedDayTitle)
                            .font(.subheadline.weight(.bold))
                        Spacer()
                        Text("경기 \(selectedGames.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appModel.currentTheme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(appModel.currentTheme.chipBackground, in: Capsule())
                    }

                    ForEach(selectedGames) { game in
                        MyTeamScheduleRow(
                            game: game,
                            selectedTeamID: appModel.settings.favoriteTeamID
                        )
                    }
                }
            }
        }
        .cardSurface(
            padding: 12,
            cornerRadius: 18,
            fillColor: appModel.currentTheme.scoreboardBackground
        )
    }

    private var calendarDays: [MyTeamCalendarDay] {
        appModel.myTeamCalendarDays(for: displayedMonth)
    }

    private var selectedGames: [GameDetail] {
        appModel.myTeamGames(on: selectedDate)
    }

    private var selectedDayTitle: String {
        selectedDate.formatted(.dateTime.year().month().day().weekday(.wide))
    }

    private var monthSummaryText: String {
        let count = calendarDays.reduce(0) { partialResult, day in
            partialResult + (day.isInDisplayedMonth ? day.gameCount : 0)
        }
        return count == 0 ? "등록 경기 없음" : "이달 경기 \(count)"
    }

    private func isSelected(_ day: MyTeamCalendarDay) -> Bool {
        Calendar(identifier: .gregorian).isDate(day.date, inSameDayAs: selectedDate)
    }

    private func dayNumberColor(for day: MyTeamCalendarDay) -> Color {
        if isSelected(day) {
            return .white
        }
        return day.isInDisplayedMonth ? .primary : .secondary.opacity(0.6)
    }

    private func markerColor(for day: MyTeamCalendarDay) -> Color {
        day.dominantStatus?.tintColor ?? appModel.currentTheme.accent
    }

    private func dayBackground(for day: MyTeamCalendarDay) -> Color {
        if isSelected(day) {
            return appModel.currentTheme.accent
        }
        if day.isToday {
            return appModel.currentTheme.chipBackground
        }
        return Color.clear
    }

    private func dayBorderColor(for day: MyTeamCalendarDay) -> Color {
        if isSelected(day) {
            return appModel.currentTheme.accent
        }
        if day.isToday {
            return appModel.currentTheme.accent.opacity(0.28)
        }
        return .clear
    }
}

private struct MyTeamScheduleRow: View {
    @Environment(AppModel.self) private var appModel
    let game: GameDetail
    let selectedTeamID: String?

    var body: some View {
        HStack(spacing: 10) {
            TeamMarkView(team: opponentTeam, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(opponentTeam.name)
                        .font(.subheadline.weight(.semibold))
                    Text(homeAwayLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(appModel.currentTheme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(appModel.currentTheme.chipBackground, in: Capsule())
                }

                Text(game.venue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(game.scheduledStart.formatted(date: .omitted, time: .shortened))
                    .font(.caption.weight(.semibold))
                Text(game.status.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(game.status.tintColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(game.status.tintColor.opacity(0.10), in: Capsule())
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var opponentTeam: Team {
        if game.awayTeam.id == selectedTeamID {
            return game.homeTeam
        }
        return game.awayTeam
    }

    private var homeAwayLabel: String {
        game.awayTeam.id == selectedTeamID ? "원정" : "홈"
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
