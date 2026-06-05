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

    private var cachedMonths: [KBOMonthScheduleKey: ScheduleMonthCacheEntry] = [:]
    private var failedMonths: Set<KBOMonthScheduleKey> = []
    private var inFlightMonthTasks: [KBOMonthScheduleKey: Task<ScheduleMonthCacheEntry, Error>] = [:]
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
        if SchedulePresentation.dayKey(for: selectedDate) == SchedulePresentation.dayKey(for: Date()) {
            await appModel.refreshScheduleDay(for: selectedDate)
            let key = displayedMonthKey
            let refreshedSnapshot = appModel.currentScheduleMonthSnapshot(for: key)
            let mergedGames = mergeSelectedDayRefresh(
                refreshedSnapshot,
                into: cachedMonths[key]?.games ?? [],
                selectedDayKey: SchedulePresentation.dayKey(for: selectedDate)
            )
            cachedMonths[key] = await ScheduleMonthCacheEntry.build(
                key: key,
                games: mergedGames
            )
            await rebuildPresentation(
                favoriteTeamID: appModel.settings.favoriteTeamID,
                attendedGameKeys: appModel.attendedGameKeys
            )
        }

        await reconcileStalePastGamesIfNeeded(appModel: appModel)
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
        let hasCachedRequestedMonth = cachedMonths[requestedKey] != nil
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
        selectedDate = date
        pendingAutomaticSelectionMonthKey = nil
        Task {
            await rebuildPresentation(
                favoriteTeamID: favoriteTeamID,
                attendedGameKeys: attendedGameKeys
            )
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
            cachedMonthEntries: Dictionary(
                uniqueKeysWithValues: cachedMonths.map { ($0.key.yearMonthText, $0.value) }
            ),
            failedMonthKeys: Set(failedMonths.map(\.yearMonthText)),
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

        if forceRefresh == false, cachedMonths[key] != nil {
            logLocalMonthIfNeeded(key)
            await syncCachedMonthFromAppModelIfNeeded(key, appModel: appModel)
            setLoadingDisplayedMonth(false)
            applyPendingAutomaticSelectionIfNeeded(for: key)
            await rebuildPresentation(
                favoriteTeamID: appModel.settings.favoriteTeamID,
                attendedGameKeys: appModel.attendedGameKeys
            )
            return
        }

        if let task = inFlightMonthTasks[key] {
#if DEBUG
            print("[ScheduleCache] month=\(key.yearMonthText) source=inFlight")
#endif
            setLoadingDisplayedMonth(cachedMonths[key] == nil)
            defer {
                setLoadingDisplayedMonth(false)
            }
            do {
                cachedMonths[key] = try await task.value
                failedMonths.remove(key)
            } catch {
                failedMonths.insert(key)
            }
            applyPendingAutomaticSelectionIfNeeded(for: key)
            await rebuildPresentation(
                favoriteTeamID: appModel.settings.favoriteTeamID,
                attendedGameKeys: appModel.attendedGameKeys
            )
            return
        }

        setLoadingDisplayedMonth(cachedMonths[key] == nil)
        let task = Task<ScheduleMonthCacheEntry, Error> { @MainActor in
            let fetched = try await appModel.fetchIsolatedScheduleMonth(
                for: key,
                bypassingCache: forceRefresh
            )
            return await ScheduleMonthCacheEntry.build(key: key, games: fetched)
        }
        inFlightMonthTasks[key] = task
        defer {
            inFlightMonthTasks[key] = nil
            setLoadingDisplayedMonth(false)
        }

        do {
            let entry = try await task.value
            cachedMonths[key] = entry
            failedMonths.remove(key)
#if DEBUG
            print("[ScheduleCache] month=\(key.yearMonthText) source=repository gameCount=\(entry.games.count)")
#endif
        } catch {
            failedMonths.insert(key)
#if DEBUG
            print("[ScheduleCache] month=\(key.yearMonthText) source=repository failed error=\(error)")
#endif
        }

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

    private func logLocalMonthIfNeeded(_ key: KBOMonthScheduleKey) {
#if DEBUG
        print("[ScheduleCache] month=\(key.yearMonthText) source=local")
#endif
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
        if let firstGameDate = cachedMonths[key]?.games.first?.scheduledStart {
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

    private func mergeSelectedDayRefresh(
        _ refreshedSnapshot: [GameDetail],
        into existingMonthGames: [GameDetail],
        selectedDayKey: String
    ) -> [GameDetail] {
        guard existingMonthGames.isEmpty == false else {
            return refreshedSnapshot.sorted { $0.scheduledStart < $1.scheduledStart }
        }

        var mergedGames = existingMonthGames
        let refreshedDayGames = refreshedSnapshot.filter {
            SchedulePresentation.dayKey(for: $0.scheduledStart) == selectedDayKey
        }

        for refreshedGame in refreshedDayGames {
            let refreshedAliases = refreshedGame.gameIdentityAliases
            if let index = mergedGames.firstIndex(where: { $0.gameIdentityAliases.isDisjoint(with: refreshedAliases) == false }) {
                mergedGames[index] = refreshedGame
            } else {
                mergedGames.append(refreshedGame)
            }
        }

        return mergedGames.sorted { $0.scheduledStart < $1.scheduledStart }
    }

    private func mergeAppModelMonthSnapshot(
        _ snapshot: [GameDetail],
        into existingMonthGames: [GameDetail],
        for key: KBOMonthScheduleKey
    ) -> [GameDetail] {
        ScheduleMonthOverlayResolver.merge(
            existingMonthGames: existingMonthGames,
            incomingGames: snapshot,
            monthKey: key,
            calendar: calendar
        )
    }

    private func mergePostReconciliationDateRefresh(
        _ refreshedSnapshot: [GameDetail],
        into existingMonthGames: [GameDetail],
        refreshedDayKeys: Set<String>
    ) -> [GameDetail] {
        guard refreshedDayKeys.isEmpty == false else {
            return existingMonthGames.sorted { $0.scheduledStart < $1.scheduledStart }
        }

        let preservedGames = existingMonthGames.filter {
            refreshedDayKeys.contains(SchedulePresentation.dayKey(for: $0.scheduledStart)) == false
        }
        let refreshedGames = refreshedSnapshot.filter {
            refreshedDayKeys.contains(SchedulePresentation.dayKey(for: $0.scheduledStart))
        }
        return (preservedGames + refreshedGames).sorted { $0.scheduledStart < $1.scheduledStart }
    }

    private func reconcileStalePastGamesIfNeeded(appModel: AppModel) async {
        guard appModel.isScheduleStaleReconciliationInFlight() == false else {
#if DEBUG
            print("[ScheduleRefresh] stale reconciliation skipped reason=inFlight")
#endif
            return
        }

        let key = displayedMonthKey
        let visibleGames = cachedMonths[key]?.games ?? []
        let dates = ScheduleStaleGameReconciliationResolver.staleGameDates(
            in: visibleGames,
            today: appModel.currentScheduleRefreshDate(),
            calendar: calendar
        )

        guard dates.isEmpty == false else {
#if DEBUG
            print("[ScheduleRefresh] stale reconciliation skipped reason=noCandidates")
#endif
            return
        }

        let selectedDates = Array(dates.prefix(3))
        let droppedOlderDateCount = dates.count - selectedDates.count
#if DEBUG
        print("[ScheduleRefresh] stale reconciliation totalStaleDateCount=\(dates.count) selectedDateCount=\(selectedDates.count) droppedOlderDateCount=\(droppedOlderDateCount) selectedDates=\(selectedDates.joined(separator: ","))")
#endif
        let preflightResult = await appModel.preflightRefreshStaleScheduleDates(selectedDates)
        if displayedMonthKey == key {
            await syncCachedMonthFromAppModelIfNeeded(key, appModel: appModel)
#if DEBUG
            print("[ScheduleRefresh] stale preflight visibleMonth updated month=\(key.yearMonthText)")
#endif
        } else {
#if DEBUG
            print("[ScheduleRefresh] stale preflight visibleMonth skipped reason=differentMonth month=\(key.yearMonthText) current=\(displayedMonthKey.yearMonthText)")
#endif
        }
        await rebuildPresentation(
            favoriteTeamID: appModel.settings.favoriteTeamID,
            attendedGameKeys: appModel.attendedGameKeys
        )

        let reconciliationDates = preflightResult.remainingStaleDateKeys
        guard reconciliationDates.isEmpty == false else {
#if DEBUG
            print("[ScheduleRefresh] stale reconciliation skipped reason=freshDataResolvedStaleDates")
#endif
            return
        }

        do {
            let reconciledDates = try await appModel.reconcileStaleScheduleGameDates(reconciliationDates)
            guard reconciledDates.isEmpty == false else {
                return
            }
#if DEBUG
            print("[ScheduleRefresh] stale reconciliation success dates=\(reconciledDates.joined(separator: ","))")
#endif
            appModel.startPostReconciliationForceRefresh(reconciledDates)
        } catch {
#if DEBUG
            print("[ScheduleRefresh] stale reconciliation failure dates=\(reconciliationDates.joined(separator: ",")) error=\(error)")
#endif
        }
    }

    private func syncCachedMonthFromAppModelIfNeeded(_ key: KBOMonthScheduleKey, appModel: AppModel) async {
        let snapshot = appModel.currentScheduleMonthSnapshot(for: key)
        guard snapshot.isEmpty == false else { return }
        let currentGames = cachedMonths[key]?.games ?? []
        let mergedGames = mergeAppModelMonthSnapshot(snapshot, into: currentGames, for: key)
        guard currentGames != mergedGames else { return }
        cachedMonths[key] = await ScheduleMonthCacheEntry.build(key: key, games: mergedGames)
#if DEBUG
        print("[ScheduleCache] month=\(key.yearMonthText) source=appModelSync incoming=\(snapshot.count) before=\(currentGames.count) after=\(mergedGames.count)")
#endif
    }

    func adjacentMonth(offset: Int) -> Date {
        shiftedMonth(from: displayedMonth, by: offset)
    }
}

private struct ScheduleMonthCacheEntry: Sendable {
    let key: KBOMonthScheduleKey
    let games: [GameDetail]
    let gamesByDate: [String: [GameDetail]]

    nonisolated static func build(key: KBOMonthScheduleKey, games: [GameDetail]) async -> ScheduleMonthCacheEntry {
        await Task.detached(priority: .userInitiated) {
            let sortedGames = games.sorted { $0.scheduledStart < $1.scheduledStart }
            let gamesByDate = Dictionary(grouping: sortedGames) { game in
                SchedulePresentation.dayKey(for: game.scheduledStart)
            }
            return ScheduleMonthCacheEntry(key: key, games: sortedGames, gamesByDate: gamesByDate)
        }.value
    }
}

enum ScheduleMonthOverlayResolver {
    static func merge(
        existingMonthGames: [GameDetail],
        incomingGames: [GameDetail],
        monthKey: KBOMonthScheduleKey,
        calendar: Calendar
    ) -> [GameDetail] {
        let monthIncomingGames = incomingGames.filter {
            isGame($0, in: monthKey, calendar: calendar)
        }
        guard existingMonthGames.isEmpty == false else {
            return monthIncomingGames.sorted { $0.scheduledStart < $1.scheduledStart }
        }

        var mergedGames = existingMonthGames.filter {
            isGame($0, in: monthKey, calendar: calendar)
        }

        for incomingGame in monthIncomingGames {
            let incomingAliases = incomingGame.gameIdentityAliases
            if let index = mergedGames.firstIndex(where: { existingGame in
                existingGame.gameIdentityAliases.isDisjoint(with: incomingAliases) == false
            }) {
                mergedGames[index] = incomingGame
            } else {
                mergedGames.append(incomingGame)
            }
        }

        return mergedGames.sorted { $0.scheduledStart < $1.scheduledStart }
    }

    private static func isGame(
        _ game: GameDetail,
        in monthKey: KBOMonthScheduleKey,
        calendar: Calendar
    ) -> Bool {
        let components = calendar.dateComponents([.year, .month], from: game.scheduledStart)
        return components.year == monthKey.year && components.month == monthKey.month
    }
}

private struct SchedulePresentation: Sendable {
    let calendarDays: [MyTeamCalendarDay]
    let selectedDateGames: [GameDetail]
    let isDisplayedMonthAvailable: Bool
    let hasAvailableMonths: Bool
    let previousAvailableMonth: Date?
    let nextAvailableMonth: Date?
    let statusMessage: String?
    let monthGameCount: Int
#if DEBUG
    let debugSummary: String?
#endif

    nonisolated static func build(
        displayedMonth: Date,
        selectedDate: Date,
        filter: ScheduleFilter,
        favoriteTeamID: String?,
        attendedGameKeys: Set<String>,
        cachedMonthEntries: [String: ScheduleMonthCacheEntry],
        failedMonthKeys: Set<String>,
        currentDate: Date
    ) async -> SchedulePresentation {
        await Task.detached(priority: .userInitiated) {
            buildSynchronously(
                displayedMonth: displayedMonth,
                selectedDate: selectedDate,
                filter: filter,
                favoriteTeamID: favoriteTeamID,
                attendedGameKeys: attendedGameKeys,
                cachedMonthEntries: cachedMonthEntries,
                failedMonthKeys: failedMonthKeys,
                currentDate: currentDate
            )
        }.value
    }

    nonisolated static func dayKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }

    nonisolated private static func buildSynchronously(
        displayedMonth: Date,
        selectedDate: Date,
        filter: ScheduleFilter,
        favoriteTeamID: String?,
        attendedGameKeys: Set<String>,
        cachedMonthEntries: [String: ScheduleMonthCacheEntry],
        failedMonthKeys: Set<String>,
        currentDate: Date
    ) -> SchedulePresentation {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let displayedKey = KBOMonthScheduleKey(date: displayedMonth, calendar: calendar)
        let displayedKeyText = displayedKey.yearMonthText
        let monthEntry = cachedMonthEntries[displayedKeyText]
        let filteredGamesByDate = filteredGamesByDate(
            from: monthEntry,
            filter: filter,
            favoriteTeamID: favoriteTeamID
        )
        let monthStart = startOfMonth(for: displayedMonth, calendar: calendar)
        let selectedDayKey = dayKey(for: selectedDate)
        let selectedGames = sortSelectedGames(
            filteredGamesByDate[selectedDayKey] ?? [],
            favoriteTeamID: favoriteTeamID
        )
        let todayKey = dayKey(for: currentDate)
        let days = ScheduleCalendarDayBuilder.makeDays(
            monthStart: monthStart,
            gamesByDate: filteredGamesByDate,
            filter: filter,
            favoriteTeamID: favoriteTeamID,
            calendar: calendar,
            dayKey: dayKey(for:),
            isToday: { _, cursorKey in cursorKey == todayKey },
            hasAttendedGame: { games in
                games.contains {
                    attendedGameKeys.isDisjoint(with: $0.attendanceStorageAliases) == false
                }
            },
            favoriteTeamResult: calendarFavoriteTeamResult(for:favoriteTeamID:)
        )
        let displayedMonthStart = startOfMonth(for: displayedMonth, calendar: calendar)
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonthStart)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonthStart)
        let isDisplayedMonthAvailable = true
        let statusMessage = failedMonthKeys.contains(displayedKeyText) && monthEntry == nil
            ? "월간 일정을 불러오지 못했습니다."
            : nil
        let monthGameCount = days.reduce(0) { count, day in
            count + (day.isInDisplayedMonth ? day.gameCount : 0)
        }

#if DEBUG
        return SchedulePresentation(
            calendarDays: days,
            selectedDateGames: selectedGames,
            isDisplayedMonthAvailable: isDisplayedMonthAvailable,
            hasAvailableMonths: true,
            previousAvailableMonth: previousMonth,
            nextAvailableMonth: nextMonth,
            statusMessage: statusMessage,
            monthGameCount: monthGameCount,
            debugSummary: monthEntry.map { "월간 캐시 \($0.games.count)경기" }
        )
#else
        return SchedulePresentation(
            calendarDays: days,
            selectedDateGames: selectedGames,
            isDisplayedMonthAvailable: isDisplayedMonthAvailable,
            hasAvailableMonths: true,
            previousAvailableMonth: previousMonth,
            nextAvailableMonth: nextMonth,
            statusMessage: statusMessage,
            monthGameCount: monthGameCount
        )
#endif
    }

    nonisolated private static func filteredGamesByDate(
        from entry: ScheduleMonthCacheEntry?,
        filter: ScheduleFilter,
        favoriteTeamID: String?
    ) -> [String: [GameDetail]] {
        guard let entry else { return [:] }
        switch filter {
        case .all:
            return entry.gamesByDate
        case .myTeam:
            guard let favoriteTeamID else { return [:] }
            return entry.gamesByDate.mapValues { games in
                games.filter { $0.involves(teamID: favoriteTeamID) }
            }
        }
    }

    nonisolated private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    nonisolated private static func sortSelectedGames(_ games: [GameDetail], favoriteTeamID: String?) -> [GameDetail] {
        ScheduleGameSelector.sortSelectedGames(games, favoriteTeamID: favoriteTeamID)
    }

    nonisolated private static func calendarFavoriteTeamResult(
        for games: [GameDetail],
        favoriteTeamID: String?
    ) -> TeamGameResult? {
        for game in games {
            guard let favoriteTeamID,
                  game.involves(teamID: favoriteTeamID),
                  game.status == .final,
                  let awayScore = game.awayScore,
                  let homeScore = game.homeScore else { continue }
            if awayScore == homeScore { return .tie }
            let favoriteTeamWon = (game.awayTeam.id == favoriteTeamID && awayScore > homeScore) ||
                (game.homeTeam.id == favoriteTeamID && homeScore > awayScore)
            return favoriteTeamWon ? .win : .loss
        }
        return nil
    }
}
