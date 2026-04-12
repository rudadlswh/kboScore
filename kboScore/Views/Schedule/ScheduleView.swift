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
                    if appModel.isScheduleMonthAvailable(displayedMonth, filter: scheduleFilter),
                       let statusMessage = appModel.scheduleStatusMessage(for: displayedMonth) {
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
                await normalizeDisplayedMonth()
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

    private func normalizeDisplayedMonth() async {
        await appModel.loadScheduleIfNeeded(for: displayedMonth)

        guard let resolvedMonth = appModel.nearestScheduleMonth(to: displayedMonth, filter: scheduleFilter) else {
            return
        }

        if Calendar(identifier: .gregorian).isDate(displayedMonth, equalTo: resolvedMonth, toGranularity: .month) == false {
            displayedMonth = resolvedMonth
        }
        if Calendar(identifier: .gregorian).isDate(selectedDate, equalTo: resolvedMonth, toGranularity: .month) == false {
            selectedDate = appModel.startOfMonth(for: resolvedMonth)
        }

        await appModel.loadScheduleIfNeeded(for: resolvedMonth)
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
            Picker("일정 필터", selection: $scheduleFilter) {
                ForEach(ScheduleFilter.allCases) { filter in
                    Text(filter.rawValue)
                        .tag(filter)
                }
            }
            .pickerStyle(.segmented)

            if isDisplayedMonthAvailable {
                HStack {
                    Button {
                        guard let previousMonth = previousAvailableMonth else { return }
                        displayedMonth = previousMonth
                        selectedDate = appModel.startOfMonth(for: previousMonth)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(appModel.currentTheme.accent)
                            .frame(width: 34, height: 34)
                            .background(appModel.currentTheme.chipBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .opacity(previousAvailableMonth == nil ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(previousAvailableMonth == nil)

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
                        guard let nextMonth = nextAvailableMonth else { return }
                        displayedMonth = nextMonth
                        selectedDate = appModel.startOfMonth(for: nextMonth)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(appModel.currentTheme.accent)
                            .frame(width: 34, height: 34)
                            .background(appModel.currentTheme.chipBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .opacity(nextAvailableMonth == nil ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(nextAvailableMonth == nil)
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
                                    if let opponentTeam = day.opponentTeam {
                                        TeamMarkView(team: opponentTeam, size: day.gameCount > 1 ? 18 : 16)
                                            .opacity(day.hasGames ? 1 : 0)
                                    } else {
                                        Circle()
                                            .fill(markerColor(for: day))
                                            .frame(width: day.gameCount > 1 ? 18 : 6, height: day.gameCount > 1 ? 18 : 6)
                                            .opacity(day.hasGames ? 1 : 0.12)
                                    }

                                    if day.gameCount > 1 {
                                        Text("\(day.gameCount)")
                                            .font(.system(size: 9, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(appModel.currentTheme.accent, in: Capsule())
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
            } else if appModel.scheduleHasAvailableMonths(filter: scheduleFilter) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("경기 있는 달로 이동 중")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                EmptyStateView(
                    systemImage: "calendar",
                    title: emptyMonthTitle,
                    message: emptyMonthMessage
                )
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

    private var isDisplayedMonthAvailable: Bool {
        appModel.isScheduleMonthAvailable(displayedMonth, filter: scheduleFilter)
    }

    private var previousAvailableMonth: Date? {
        appModel.shiftedScheduleMonth(from: displayedMonth, by: -1, filter: scheduleFilter)
    }

    private var nextAvailableMonth: Date? {
        appModel.shiftedScheduleMonth(from: displayedMonth, by: 1, filter: scheduleFilter)
    }

    private var emptyMonthTitle: String {
        if scheduleFilter == .myTeam, appModel.settings.favoriteTeamID == nil {
            return "응원 팀을 선택해 주세요"
        }
        return "표시할 일정이 없습니다"
    }

    private var emptyMonthMessage: String {
        if scheduleFilter == .myTeam, appModel.settings.favoriteTeamID == nil {
            return "응원 팀을 선택하면 경기 있는 달만 일정에 표시됩니다."
        }
        return "현재 일정 데이터에 경기 있는 달이 없습니다."
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
            return .clear
        }
        if let favoriteTeamResult = day.favoriteTeamResult {
            switch favoriteTeamResult {
            case .win:
                return KBOLivePalette.upcoming.opacity(0.18)
            case .loss:
                return KBOLivePalette.live.opacity(0.18)
            case .tie:
                return appModel.currentTheme.chipBackground
            }
        }
        return Color.clear
    }

    private func dayBorderColor(for day: MyTeamCalendarDay) -> Color {
        if day.isToday {
            return KBOLivePalette.upcoming.opacity(0.9)
        }
        if isSelected(day) {
            return appModel.currentTheme.accent
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

                if let finalResultText {
                    Text(finalResultText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }
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
            return leadingTeam.displayName
        }
        return "\(game.awayTeam.displayName) vs \(game.homeTeam.displayName)"
    }

    private var subtitleText: String {
        if filter == .myTeam, favoriteTeamID != nil {
            return game.venue
        }
        return "\(game.venue) · \(game.homeTeam.displayName) 홈"
    }

    private var finalResultText: String? {
        guard filter == .all,
              let winningTeam = game.finalWinningTeam,
              let scoreLine = game.finalScoreLine else {
            return nil
        }
        return "\(winningTeam.displayName) 승 · \(scoreLine)"
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
