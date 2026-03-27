//
//  ScheduleView.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import SwiftUI

struct ScheduleView: View {
    @Environment(AppModel.self) private var appModel
    @State private var displayedMonth = Date()
    @State private var selectedDate = Date()
    @State private var scheduleFilter: ScheduleFilter = .all

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let statusMessage = appModel.scheduleStatusMessage(for: displayedMonth) {
                        DataStatusBannerView(message: statusMessage)
                    }

                    ScheduleCalendarCardView(
                        displayedMonth: $displayedMonth,
                        selectedDate: $selectedDate,
                        scheduleFilter: $scheduleFilter
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(KBOLivePalette.background)
            .navigationTitle("일정")
            .navigationBarTitleDisplayMode(.inline)
            .notificationsToolbarButton()
            .refreshable {
                await appModel.refreshSchedule(for: displayedMonth)
            }
            .task(id: scheduleTaskID) {
                if Calendar(identifier: .gregorian).isDate(selectedDate, equalTo: displayedMonth, toGranularity: .month) == false {
                    selectedDate = displayedMonth
                }
                await appModel.loadScheduleIfNeeded(for: displayedMonth)
            }
            .navigationDestination(for: UUID.self) { gameID in
                GameDetailView(gameID: gameID)
            }
        }
    }

    private var scheduleTaskID: String {
        let key = KBOMonthScheduleKey(date: displayedMonth)
        return "\(scheduleFilter.rawValue)-\(appModel.settings.favoriteTeamID ?? "none")-\(key.yearMonthText)"
    }
}

private struct ScheduleCalendarCardView: View {
    @Environment(AppModel.self) private var appModel
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date
    @Binding var scheduleFilter: ScheduleFilter

    private let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    let previousMonth = appModel.shiftedMonth(from: displayedMonth, by: -1)
                    displayedMonth = previousMonth
                    selectedDate = appModel.startOfMonth(for: previousMonth)
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

            Picker("일정 필터", selection: $scheduleFilter) {
                ForEach(ScheduleFilter.allCases) { filter in
                    Text(filter.rawValue)
                        .tag(filter)
                }
            }
            .pickerStyle(.segmented)

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

            if appModel.isLoadingSchedule(for: displayedMonth) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("공식 월간 일정 불러오는 중")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let statusMessage = appModel.scheduleStatusMessage(for: displayedMonth) {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            #if DEBUG
            if let debugSummary = appModel.scheduleDebugSummary(for: displayedMonth) {
                Text(debugSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            #endif

            if selectedGames.isEmpty {
                EmptyStateView(
                    systemImage: "calendar",
                    title: selectedDayTitle,
                    message: emptyMessage
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
                        NavigationLink(value: game.id) {
                            ScheduleGameRow(
                                game: game,
                                favoriteTeamID: appModel.settings.favoriteTeamID,
                                filter: scheduleFilter
                            )
                        }
                        .buttonStyle(.plain)
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
        appModel.scheduleCalendarDays(for: displayedMonth, filter: scheduleFilter)
    }

    private var selectedGames: [GameDetail] {
        appModel.scheduleGames(on: selectedDate, filter: scheduleFilter)
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

    private var emptyMessage: String {
        if scheduleFilter == .myTeam, appModel.settings.favoriteTeamID == nil {
            return "응원 팀을 선택하면 마이팀 일정이 표시됩니다."
        }
        return "선택한 날짜에는 등록된 경기가 없습니다."
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

private struct ScheduleGameRow: View {
    @Environment(AppModel.self) private var appModel
    let game: GameDetail
    let favoriteTeamID: String?
    let filter: ScheduleFilter

    var body: some View {
        HStack(spacing: 10) {
            TeamMarkView(team: leadingTeam, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(titleText)
                        .font(.subheadline.weight(.semibold))
                    Text(homeAwayLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(appModel.currentTheme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(appModel.currentTheme.chipBackground, in: Capsule())
                }

                Text(subtitleText)
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

    private var leadingTeam: Team {
        if filter == .myTeam, let favoriteTeamID {
            if game.awayTeam.id == favoriteTeamID {
                return game.homeTeam
            }
            if game.homeTeam.id == favoriteTeamID {
                return game.awayTeam
            }
        }
        return game.awayTeam
    }

    private var titleText: String {
        if filter == .myTeam, favoriteTeamID != nil {
            return leadingTeam.name
        }
        return "\(game.awayTeam.shortName) vs \(game.homeTeam.shortName)"
    }

    private var subtitleText: String {
        if filter == .myTeam, favoriteTeamID != nil {
            return game.venue
        }
        return "\(game.venue) · \(game.homeTeam.shortName) 홈"
    }

    private var homeAwayLabel: String {
        if filter == .myTeam, let favoriteTeamID {
            if game.awayTeam.id == favoriteTeamID {
                return "원정"
            }
            if game.homeTeam.id == favoriteTeamID {
                return "홈"
            }
        }
        return "리그"
    }
}

#Preview {
    ScheduleView()
        .environment(AppModel.previewModel())
}
