//
//  ScheduleScreenModel.swift
//  kboScore
//
//  Created by Codex on 6/5/26.
//

import Combine
import Foundation

enum ScheduleSelectedGamesContentState: Equatable, Sendable {
    case initialLoading
    case loadedEmpty
    case loaded
}

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published var displayedMonth = Date()
    @Published var selectedDate = Date()
    @Published var scheduleFilter: ScheduleFilter = .all
    private(set) var calendarDays: [MyTeamCalendarDay] = []
    private(set) var selectedDateGames: [GameDetail] = []
    private(set) var isDisplayedMonthAvailable = false
    private(set) var hasAvailableMonths = false
    private(set) var previousAvailableMonth: Date?
    private(set) var nextAvailableMonth: Date?
    private(set) var isLoadingDisplayedMonth = true
    private(set) var statusMessage: String?
    private(set) var monthGameCount = 0
#if DEBUG
    private(set) var debugSummary: String?
#endif

    private let refreshCoordinator = ScheduleRefreshCoordinator()
    private var pendingAutomaticSelectionMonthKey: KBOMonthScheduleKey?
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }

    var displayedMonthKey: KBOMonthScheduleKey {
        monthKey(for: displayedMonth)
    }

    var selectedGamesContentState: ScheduleSelectedGamesContentState {
        if selectedDateGames.isEmpty == false {
            return .loaded
        }
        if isLoadingDisplayedMonth, monthGameCount == 0 {
            return .initialLoading
        }
        return .loadedEmpty
    }

    func loadDisplayedMonth(appModel: AppModel) async {
        await loadMonth(
            displayedMonth,
            forceRefresh: false,
            appModel: appModel
        )
        await normalizeDisplayedMonth(appModel: appModel)
    }

    func refreshDisplayedMonth(appModel: AppModel) async {
        await loadMonth(
            displayedMonth,
            forceRefresh: true,
            appModel: appModel
        )
        await refreshCoordinator.refreshTodayLiveIfNeeded(
            selectedDate: selectedDate,
            displayedMonthKey: displayedMonthKey,
            appModel: appModel,
            callSite: "ScheduleViewModel.refreshDisplayedMonth"
        )
        await rebuildPresentation(
            favoriteTeamID: appModel.settings.favoriteTeamID,
            attendedGameKeys: appModel.attendedGameKeys
        )
        await refreshCoordinator.reconcileStalePastGamesIfNeeded(
            displayedMonthKey: displayedMonthKey,
            appModel: appModel,
            callSite: "ScheduleViewModel.refreshDisplayedMonth"
        )
        await rebuildPresentation(
            favoriteTeamID: appModel.settings.favoriteTeamID,
            attendedGameKeys: appModel.attendedGameKeys
        )
    }

    func changeDisplayedMonth(
        to month: Date,
        favoriteTeamID: String?,
        attendedGameKeys: Set<String>
    ) {
        let previousKey = displayedMonthKey
        let requestedMonth = startOfMonth(for: month)
        let requestedKey = monthKey(for: requestedMonth)
        guard requestedKey != previousKey else { return }

#if DEBUG
        print("ScheduleMonthChanged from=\(previousKey.yearMonthText) to=\(requestedKey.yearMonthText)")
#endif
        let hasCachedRequestedMonth = refreshCoordinator.hasCachedMonth(requestedKey)
        setLoadingDisplayedMonth(hasCachedRequestedMonth == false)
        displayedMonth = requestedMonth
        selectedDate = preferredSelectedDate(for: requestedKey)
        pendingAutomaticSelectionMonthKey = requestedKey
        Task {
            await rebuildPresentation(
                favoriteTeamID: favoriteTeamID,
                attendedGameKeys: attendedGameKeys
            )
        }
    }

    func selectDate(
        _ date: Date,
        favoriteTeamID: String?,
        attendedGameKeys: Set<String>
    ) {
        let startedAt = Date()
        selectedDate = date
        pendingAutomaticSelectionMonthKey = nil
        Task {
            await rebuildPresentation(
                favoriteTeamID: favoriteTeamID,
                attendedGameKeys: attendedGameKeys
            )
            refreshCoordinator.logDateSelectionLocalOnly(
                date: date,
                selectedGame: selectedDateGames.first,
                callSite: "ScheduleViewModel.selectDate"
            )
            #if DEBUG
            print("[ScheduleRefreshCoordinator] callSite=ScheduleViewModel.selectDate reason=dateSelection durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1_000))")
            #endif
        }
    }

    func rebuildPresentation(
        favoriteTeamID: String?,
        attendedGameKeys: Set<String>
    ) async {
        let presentation = await SchedulePresentation.build(
            displayedMonth: displayedMonth,
            selectedDate: selectedDate,
            filter: scheduleFilter,
            favoriteTeamID: favoriteTeamID,
            attendedGameKeys: attendedGameKeys,
            cachedMonthEntries: refreshCoordinator.cachedMonthEntries,
            failedMonthKeys: refreshCoordinator.failedMonthKeys,
            currentDate: Date()
        )
        apply(presentation)
    }

    private func normalizeDisplayedMonth(appModel: AppModel) async {
        if calendar.isDate(selectedDate, equalTo: displayedMonth, toGranularity: .month) == false {
            selectedDate = preferredSelectedDate(for: displayedMonthKey)
        }
        await rebuildPresentation(
            favoriteTeamID: appModel.settings.favoriteTeamID,
            attendedGameKeys: appModel.attendedGameKeys
        )
    }

    private func loadMonth(
        _ month: Date,
        forceRefresh: Bool,
        appModel: AppModel
    ) async {
        let key = monthKey(for: month)

        setLoadingDisplayedMonth(forceRefresh || refreshCoordinator.hasCachedMonth(key) == false)
        defer {
            setLoadingDisplayedMonth(false)
        }
        await refreshCoordinator.loadMonth(
            key,
            forceRefresh: forceRefresh,
            appModel: appModel,
            callSite: "ScheduleViewModel.loadMonth",
            reason: forceRefresh ? "refreshDisplayedMonth" : "loadDisplayedMonth"
        )

        applyPendingAutomaticSelectionIfNeeded(for: key)
        await rebuildPresentation(
            favoriteTeamID: appModel.settings.favoriteTeamID,
            attendedGameKeys: appModel.attendedGameKeys
        )
    }

    private func apply(_ presentation: SchedulePresentation) {
        objectWillChange.send()
        calendarDays = presentation.calendarDays
        selectedDateGames = presentation.selectedDateGames
        isDisplayedMonthAvailable = presentation.isDisplayedMonthAvailable
        hasAvailableMonths = presentation.hasAvailableMonths
        previousAvailableMonth = presentation.previousAvailableMonth
        nextAvailableMonth = presentation.nextAvailableMonth
        statusMessage = presentation.statusMessage
        monthGameCount = presentation.monthGameCount
#if DEBUG
        debugSummary = presentation.debugSummary
#endif
    }

    private func setLoadingDisplayedMonth(_ isLoading: Bool) {
        guard isLoadingDisplayedMonth != isLoading else { return }
        objectWillChange.send()
        isLoadingDisplayedMonth = isLoading
    }

    private func applyPendingAutomaticSelectionIfNeeded(for key: KBOMonthScheduleKey) {
        guard pendingAutomaticSelectionMonthKey == key else { return }
        selectedDate = preferredSelectedDate(for: key)
        pendingAutomaticSelectionMonthKey = nil
    }

    private func startOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private func shiftedMonth(from date: Date, by offset: Int) -> Date {
        calendar.date(byAdding: .month, value: offset, to: startOfMonth(for: date)) ?? date
    }

    private func preferredSelectedDate(for key: KBOMonthScheduleKey) -> Date {
        let monthStart = monthStart(for: key)
        let today = Date()
        if monthKey(for: today) == key {
            return today
        }
        if let firstGameDate = refreshCoordinator.firstGameDate(in: key) {
            return calendar.startOfDay(for: firstGameDate)
        }
        return monthStart
    }

    private func monthStart(for key: KBOMonthScheduleKey) -> Date {
        calendar.date(from: DateComponents(year: key.year, month: key.month, day: 1)) ?? Date()
    }

    private func monthKey(for date: Date) -> KBOMonthScheduleKey {
        KBOMonthScheduleKey(date: date, calendar: calendar)
    }

    func adjacentMonth(offset: Int) -> Date {
        shiftedMonth(from: displayedMonth, by: offset)
    }
}
