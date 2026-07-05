//
//  ScheduleScreenModel.swift
//  kboScore
//  기능 설명: 일정 화면의 월 이동, 필터, 경기 목록 상태를 관리합니다.
//  월별·일별 일정 상태를 일관되게 계산해 홈, 일정, 위젯이 같은 경기 선택 기준을 공유합니다.
//  우천 취소, 더블헤더, 시간 미정, 오래된 캐시가 섞일 수 있어 날짜 키와 동기화 순서를 엄격히 다룹니다.
//  TODO : 공식 일정 변경 감지와 보정 로직을 더 작은 단위로 검증합니다.
//
//  Created by Codex on 6/5/26.
//

import Combine
import Foundation

// ScheduleSelectedGamesContentState 열거형는 화면이나 도메인 흐름에서 사용하는 상태 값을 표현합니다.
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

    // loadDisplayedMonth 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func loadDisplayedMonth(appModel: AppModel) async {
        await loadMonth(
            displayedMonth,
            forceRefresh: true,
            appModel: appModel
        )
        await normalizeDisplayedMonth(appModel: appModel)
    }

    // refreshDisplayedMonth 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
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

    func refreshLiveScoresIfNeeded(appModel: AppModel) async {
        await refreshCoordinator.refreshTodayLiveIfNeeded(
            selectedDate: selectedDate,
            displayedMonthKey: displayedMonthKey,
            appModel: appModel,
            callSite: "ScheduleViewModel.refreshLiveScoresIfNeeded"
        )
        await rebuildPresentation(
            favoriteTeamID: appModel.settings.favoriteTeamID,
            attendedGameKeys: appModel.attendedGameKeys
        )
    }

    func shouldPollLiveScores(appModel: AppModel) -> Bool {
        let selectedDayKey = ScheduleDateKeyFormatter.dayKey(for: selectedDate)
        let todayKey = ScheduleDateKeyFormatter.dayKey(for: appModel.currentScheduleRefreshDate())
        return selectedDayKey == todayKey
    }

    // changeDisplayedMonth 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // selectDate 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
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

    // rebuildPresentation 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // normalizeDisplayedMonth 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
    private func normalizeDisplayedMonth(appModel: AppModel) async {
        if calendar.isDate(selectedDate, equalTo: displayedMonth, toGranularity: .month) == false {
            selectedDate = preferredSelectedDate(for: displayedMonthKey)
        }
        await rebuildPresentation(
            favoriteTeamID: appModel.settings.favoriteTeamID,
            attendedGameKeys: appModel.attendedGameKeys
        )
    }

    // loadMonth 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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

    // apply 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
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

    // setLoadingDisplayedMonth 메서드는 이 타입의 주요 동작을 수행합니다.
    private func setLoadingDisplayedMonth(_ isLoading: Bool) {
        guard isLoadingDisplayedMonth != isLoading else { return }
        objectWillChange.send()
        isLoadingDisplayedMonth = isLoading
    }

    // applyPendingAutomaticSelectionIfNeeded 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    private func applyPendingAutomaticSelectionIfNeeded(for key: KBOMonthScheduleKey) {
        guard pendingAutomaticSelectionMonthKey == key else { return }
        selectedDate = preferredSelectedDate(for: key)
        pendingAutomaticSelectionMonthKey = nil
    }

    // startOfMonth 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    private func startOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    // shiftedMonth 메서드는 이 타입의 주요 동작을 수행합니다.
    private func shiftedMonth(from date: Date, by offset: Int) -> Date {
        calendar.date(byAdding: .month, value: offset, to: startOfMonth(for: date)) ?? date
    }

    // preferredSelectedDate 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // monthStart 메서드는 이 타입의 주요 동작을 수행합니다.
    private func monthStart(for key: KBOMonthScheduleKey) -> Date {
        calendar.date(from: DateComponents(year: key.year, month: key.month, day: 1)) ?? Date()
    }

    // monthKey 메서드는 이 타입의 주요 동작을 수행합니다.
    private func monthKey(for date: Date) -> KBOMonthScheduleKey {
        KBOMonthScheduleKey(date: date, calendar: calendar)
    }

    // adjacentMonth 메서드는 이 타입의 주요 동작을 수행합니다.
    func adjacentMonth(offset: Int) -> Date {
        shiftedMonth(from: displayedMonth, by: offset)
    }
}
