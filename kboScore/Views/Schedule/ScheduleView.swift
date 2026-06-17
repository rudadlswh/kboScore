//
//  ScheduleView.swift
//  kboScore
//  기능 설명: 월별/일별 경기 일정 화면과 경기 선택 흐름을 구성합니다.
//  사용자가 경기 상태와 설정을 빠르게 이해하도록 도메인 상태를 화면 구조에 직접 매핑합니다.
//  SwiftUI 상태 갱신, 접근성, 작은 화면 레이아웃에서 정보가 겹치지 않도록 표시 조건을 제한합니다.
//  TODO : 반복되는 화면 조각은 재사용 가능한 컴포넌트로 분리하고 미리보기 케이스를 보강합니다.
//
//  Created by Codex on 3/26/26.
//

import SwiftUI

// ScheduleDayResultAppearance 열거형는 ScheduleDayResultAppearance 타입의 역할과 값을 정의합니다.
enum ScheduleDayResultAppearance: Equatable, Sendable {
    case win
    case loss
    case draw
    case neutral

    // from 메서드는 이 타입의 주요 동작을 수행합니다.
    static func from(dominantStatus: GameStatus?, favoriteTeamResult: TeamGameResult?) -> ScheduleDayResultAppearance {
        guard dominantStatus == .final, let favoriteTeamResult else {
            return .neutral
        }
        switch favoriteTeamResult {
        case .win:
            return .win
        case .loss:
            return .loss
        case .tie:
            return .draw
        }
    }
}

// ScheduleGameDetailRoute 구조체는 ScheduleGameDetailRoute 타입의 역할과 값을 정의합니다.
struct ScheduleGameDetailRoute: Hashable {
    let stableIdentity: String
    let initialGame: GameDetail

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(game: GameDetail) {
        stableIdentity = game.stableDetailIdentity
        initialGame = game
    }

    // == 메서드는 이 타입의 주요 동작을 수행합니다.
    static func == (lhs: ScheduleGameDetailRoute, rhs: ScheduleGameDetailRoute) -> Bool {
        lhs.stableIdentity == rhs.stableIdentity
    }

    // hash 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    func hash(into hasher: inout Hasher) {
        hasher.combine(stableIdentity)
    }
}

// ScheduleView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
struct ScheduleView: View {
    @Environment(AppModel.self) private var appModel
    @StateObject private var viewModel = ScheduleViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.isDisplayedMonthAvailable,
                       let statusMessage = viewModel.statusMessage {
                        DataStatusBannerView(message: statusMessage)
                    }

                    ScheduleCalendarCardView(
                        viewModel: viewModel
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
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
            .navigationTitle("일정")
            .navigationBarTitleDisplayMode(.inline)
            .stadiumNavigationChrome(appModel.favoriteStadiumPalette)
            .notificationsToolbarButton()
            .refreshable {
                await viewModel.refreshDisplayedMonth(appModel: appModel)
            }
            .task(id: scheduleTaskID) {
                await viewModel.loadDisplayedMonth(appModel: appModel)
            }
            .navigationDestination(for: String.self) { gameIdentity in
                GameDetailView(gameIdentity: gameIdentity)
            }
            .navigationDestination(for: ScheduleGameDetailRoute.self) { route in
                GameDetailView(stableIdentity: route.stableIdentity, initialGame: route.initialGame)
            }
        }
    }

    private var scheduleTaskID: String {
        "\(viewModel.scheduleFilter.rawValue)-\(appModel.settings.favoriteTeamID ?? "none")-\(viewModel.displayedMonthKey.yearMonthText)-\(appModel.schedulePostReconciliationRefreshGeneration)"
    }
}

// ScheduleCalendarCardView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
private struct ScheduleCalendarCardView: View {
    @Environment(AppModel.self) private var appModel
    @ObservedObject var viewModel: ScheduleViewModel

    private let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let palette = appModel.favoriteStadiumPalette {
                DoosanScheduleFilterControl(selection: $viewModel.scheduleFilter, palette: palette)
            } else {
                Picker("일정 필터", selection: $viewModel.scheduleFilter) {
                    ForEach(ScheduleFilter.allCases) { filter in
                        Text(filter.rawValue)
                            .tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .tint(appModel.currentTheme.accent)
            }

            if isDisplayedMonthAvailable {
                HStack {
                    Button {
                        guard let previousMonth = previousAvailableMonth else { return }
                        viewModel.changeDisplayedMonth(
                            to: previousMonth,
                            favoriteTeamID: appModel.settings.favoriteTeamID,
                            attendedGameKeys: appModel.attendedGameKeys
                        )
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(appModel.favoriteStadiumPalette?.secondary ?? appModel.currentTheme.accent)
                            .frame(width: 34, height: 34)
                            .background(
                                appModel.favoriteStadiumPalette?.elevatedCardStrong ?? appModel.currentTheme.chipBackground,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .opacity(previousAvailableMonth == nil ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(previousAvailableMonth == nil)

                    Spacer()

                    VStack(spacing: 2) {
                        Text(appModel.calendarMonthTitle(for: viewModel.displayedMonth))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(appModel.favoriteStadiumPalette?.textPrimary ?? .primary)
                        Text(monthSummaryText)
                            .font(.caption2)
                            .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                    }

                    Spacer()

                    Button {
                        guard let nextMonth = nextAvailableMonth else { return }
                        viewModel.changeDisplayedMonth(
                            to: nextMonth,
                            favoriteTeamID: appModel.settings.favoriteTeamID,
                            attendedGameKeys: appModel.attendedGameKeys
                        )
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(appModel.favoriteStadiumPalette?.secondary ?? appModel.currentTheme.accent)
                            .frame(width: 34, height: 34)
                            .background(
                                appModel.favoriteStadiumPalette?.elevatedCardStrong ?? appModel.currentTheme.chipBackground,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .opacity(nextAvailableMonth == nil ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(nextAvailableMonth == nil)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                            .frame(maxWidth: .infinity)
                    }

                    ForEach(calendarDays) { day in
                        Button {
                            viewModel.selectDate(
                                day.date,
                                favoriteTeamID: appModel.settings.favoriteTeamID,
                                attendedGameKeys: appModel.attendedGameKeys
                            )
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
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(
                                                dayGameCountBadgeColor(for: day),
                                                in: Capsule()
                                            )
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(dayBackground(for: day), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(dayTodayBorderColor(for: day), lineWidth: day.isToday ? (appModel.isStadiumFavoriteSelected ? 0.75 : 1) : 0)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(daySelectionBorderColor(for: day), lineWidth: isSelected(day) ? (appModel.isStadiumFavoriteSelected ? 1.4 : 2) : 0)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if viewModel.isLoadingDisplayedMonth {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("공식 월간 일정 불러오는 중")
                            .font(.caption)
                            .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                    }
                } else if let statusMessage = viewModel.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                }

                #if DEBUG
                if let debugSummary = viewModel.debugSummary {
                    Text(debugSummary)
                        .font(.caption2)
                        .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
                }
                #endif

                switch viewModel.selectedGamesContentState {
                case .initialLoading:
                    ScheduleLoadingPlaceholderView(
                        title: selectedDayTitle,
                        message: "일정을 불러오는 중입니다"
                    )
                case .loadedEmpty:
                    EmptyStateView(
                        systemImage: "calendar",
                        title: selectedDayTitle,
                        message: emptyMessage
                    )
                case .loaded:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(selectedDayTitle)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(appModel.favoriteStadiumPalette?.textPrimary ?? .primary)
                            Spacer()
                            Text("경기 \(selectedGames.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(appModel.favoriteStadiumPalette?.textPrimary ?? appModel.currentTheme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    appModel.favoriteStadiumPalette?.primary ?? appModel.currentTheme.chipBackground,
                                    in: Capsule()
                                )
                        }

                        ForEach(selectedGames) { game in
                            NavigationLink(value: ScheduleGameDetailRoute(game: game)) {
                                ScheduleGameRow(
                                    game: game,
                                    favoriteTeamID: appModel.settings.favoriteTeamID,
                                    filter: viewModel.scheduleFilter
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if viewModel.isLoadingDisplayedMonth {
                ScheduleLoadingPlaceholderView(
                    title: emptyMonthTitle,
                    message: "일정을 불러오는 중입니다"
                )
            } else if viewModel.hasAvailableMonths {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("경기 있는 달로 이동 중")
                        .font(.caption)
                        .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
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
            fillColor: appModel.favoriteStadiumPalette?.sectionBackground ?? appModel.currentTheme.scoreboardBackground
        )
    }

    private var calendarDays: [MyTeamCalendarDay] {
        viewModel.calendarDays
    }

    private var selectedGames: [GameDetail] {
        viewModel.selectedDateGames
    }

    private var selectedDayTitle: String {
        viewModel.selectedDate.formatted(.dateTime.year().month().day().weekday(.wide))
    }

    private var monthSummaryText: String {
        viewModel.monthGameCount == 0 ? "등록 경기 없음" : "이달 경기 \(viewModel.monthGameCount)"
    }

    private var isDisplayedMonthAvailable: Bool {
        viewModel.isDisplayedMonthAvailable
    }

    private var previousAvailableMonth: Date? {
        viewModel.previousAvailableMonth
    }

    private var nextAvailableMonth: Date? {
        viewModel.nextAvailableMonth
    }

    private var emptyMonthTitle: String {
        if viewModel.scheduleFilter == .myTeam, appModel.settings.favoriteTeamID == nil {
            return "응원 팀을 선택해 주세요"
        }
        return "표시할 일정이 없습니다"
    }

    private var emptyMonthMessage: String {
        if viewModel.scheduleFilter == .myTeam, appModel.settings.favoriteTeamID == nil {
            return "응원 팀을 선택하면 경기 있는 달만 일정에 표시됩니다."
        }
        return "현재 일정 데이터에 경기 있는 달이 없습니다."
    }

    private var emptyMessage: String {
        if viewModel.scheduleFilter == .myTeam, appModel.settings.favoriteTeamID == nil {
            return "응원 팀을 선택하면 마이팀 일정이 표시됩니다."
        }
        return "선택한 날짜에는 등록된 경기가 없습니다."
    }

    // isSelected 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private func isSelected(_ day: MyTeamCalendarDay) -> Bool {
        Calendar(identifier: .gregorian).isDate(day.date, inSameDayAs: viewModel.selectedDate)
    }

    // dayNumberColor 메서드는 이 타입의 주요 동작을 수행합니다.
    private func dayNumberColor(for day: MyTeamCalendarDay) -> Color {
        if isSelected(day) {
            return appModel.favoriteStadiumPalette?.secondary ?? appModel.currentTheme.accent
        }
        if let palette = appModel.favoriteStadiumPalette {
            return day.isInDisplayedMonth ? palette.textPrimary : palette.textSecondary.opacity(0.6)
        }
        return day.isInDisplayedMonth ? .primary : .secondary.opacity(0.6)
    }

    // markerColor 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    private func markerColor(for day: MyTeamCalendarDay) -> Color {
        if let palette = appModel.favoriteStadiumPalette {
            return day.dominantStatus?.stadiumTintColor(palette) ?? palette.primary
        }
        return day.dominantStatus?.tintColor ?? appModel.currentTheme.accent
    }

    // dayResultAppearance 메서드는 이 타입의 주요 동작을 수행합니다.
    private func dayResultAppearance(for day: MyTeamCalendarDay) -> ScheduleDayResultAppearance {
        ScheduleDayResultAppearance.from(
            dominantStatus: day.dominantStatus,
            favoriteTeamResult: day.favoriteTeamResult
        )
    }

    // dayGameCountBadgeColor 메서드는 이 타입의 주요 동작을 수행합니다.
    private func dayGameCountBadgeColor(for day: MyTeamCalendarDay) -> Color {
        switch dayResultAppearance(for: day) {
        case .win:
            return KBOLivePalette.upcoming
        case .loss:
            return KBOLivePalette.live
        case .draw:
            return KBOLivePalette.final
        case .neutral:
            if let palette = appModel.favoriteStadiumPalette {
                return palette.recessedSurface
            }
            return appModel.currentTheme.chipBackground
        }
    }

    // dayBackground 메서드는 이 타입의 주요 동작을 수행합니다.
    private func dayBackground(for day: MyTeamCalendarDay) -> Color {
        if let palette = appModel.favoriteStadiumPalette {
            if day.isInDisplayedMonth == false {
                return palette.sectionBackground.opacity(0.65)
            }

            switch day.dominantStatus {
            case .cancelled:
                return stadiumNoGameDayBackground(for: day, palette: palette)
            case .final:
                switch dayResultAppearance(for: day) {
                case .win:
                    return KBOLivePalette.upcoming.opacity(0.30)
                case .loss:
                    return KBOLivePalette.live.opacity(0.26)
                case .draw:
                    return KBOLivePalette.final.opacity(0.28)
                case .neutral:
                    return palette.elevatedCard
                }
            case .live, .rainDelay, .upcoming, nil:
                return day.hasGames ? palette.elevatedCard : stadiumNoGameDayBackground(for: day, palette: palette)
            }
        }

        switch day.dominantStatus {
        case .cancelled:
            return defaultNoGameDayBackground
        case .final:
            switch dayResultAppearance(for: day) {
            case .win:
                return KBOLivePalette.upcoming.opacity(0.18)
            case .loss:
                return KBOLivePalette.live.opacity(0.18)
            case .draw:
                return KBOLivePalette.final.opacity(0.18)
            case .neutral:
                return appModel.currentTheme.chipBackground
            }
        case .live, .rainDelay, .upcoming, nil:
            return defaultNoGameDayBackground
        }
    }

    // stadiumNoGameDayBackground 메서드는 이 타입의 주요 동작을 수행합니다.
    private func stadiumNoGameDayBackground(for day: MyTeamCalendarDay, palette: StadiumPalette) -> Color {
        isSelected(day) ? palette.elevatedCardStrong : palette.recessedSurface
    }

    private var defaultNoGameDayBackground: Color {
        .clear
    }

    // dayTodayBorderColor 메서드는 이 타입의 주요 동작을 수행합니다.
    private func dayTodayBorderColor(for day: MyTeamCalendarDay) -> Color {
        if let palette = appModel.favoriteStadiumPalette {
            return day.isToday ? palette.secondary.opacity(0.85) : .clear
        }
        return day.isToday ? KBOLivePalette.upcoming.opacity(0.9) : .clear
    }

    // daySelectionBorderColor 메서드는 이 타입의 주요 동작을 수행합니다.
    private func daySelectionBorderColor(for day: MyTeamCalendarDay) -> Color {
        if let palette = appModel.favoriteStadiumPalette {
            return isSelected(day) ? palette.primary : .clear
        }
        return isSelected(day) ? appModel.currentTheme.accent : .clear
    }
}

// ScheduleLoadingPlaceholderView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
private struct ScheduleLoadingPlaceholderView: View {
    @Environment(AppModel.self) private var appModel
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.regular)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(appModel.favoriteStadiumPalette?.textPrimary ?? .primary)
            Text(message)
                .font(.caption)
                .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 104)
        .padding(.vertical, 8)
    }
}

// DoosanScheduleFilterControl 구조체는 DoosanScheduleFilterControl 타입의 역할과 값을 정의합니다.
private struct DoosanScheduleFilterControl: View {
    @Binding var selection: ScheduleFilter
    let palette: StadiumPalette

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ScheduleFilter.allCases) { filter in
                Button {
                    selection = filter
                } label: {
                    Text(filter.rawValue)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(selection == filter ? Color.white : palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selection == filter ? palette.primary : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == filter ? .isSelected : [])
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.recessedSurface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.ghostBorder, lineWidth: 0.75)
        }
    }
}

// ScheduleGameRow 구조체는 ScheduleGameRow 타입의 역할과 값을 정의합니다.
private struct ScheduleGameRow: View {
    @Environment(AppModel.self) private var appModel
    let game: GameDetail
    let favoriteTeamID: String?
    let filter: ScheduleFilter

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(titleText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appModel.favoriteStadiumPalette?.textPrimary ?? .primary)
                    Text(homeAwayLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(appModel.favoriteStadiumPalette?.textPrimary ?? appModel.currentTheme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            appModel.favoriteStadiumPalette?.primary ?? appModel.currentTheme.chipBackground,
                            in: Capsule()
                        )
                }

                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .secondary)

                if let finalResultText {
                    Text(finalResultText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appModel.favoriteStadiumPalette?.textPrimary ?? .primary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(game.scheduledStart.formatted(date: .omitted, time: .shortened))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appModel.favoriteStadiumPalette?.textSecondary ?? .primary)
                Text(game.status.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(appModel.favoriteStadiumPalette.map { game.status.stadiumTintColor($0) } ?? game.status.tintColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        (appModel.favoriteStadiumPalette.map { game.status.stadiumTintColor($0) } ?? game.status.tintColor)
                            .opacity(appModel.isStadiumFavoriteSelected ? 0.26 : 0.10),
                        in: Capsule()
                    )
            }
        }
        .padding(10)
        .background(
            appModel.favoriteStadiumPalette?.elevatedCard ?? Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
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
