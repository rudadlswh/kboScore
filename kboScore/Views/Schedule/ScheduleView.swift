//
//  ScheduleView.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import Combine
import SwiftUI

enum ScheduleDayResultAppearance: Equatable, Sendable {
    case win
    case loss
    case draw
    case neutral

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

private struct ScheduleGameDetailRoute: Hashable {
    let stableIdentity: String
    let initialGame: GameDetail

    init(game: GameDetail) {
        stableIdentity = game.stableDetailIdentity
        initialGame = game
    }

    static func == (lhs: ScheduleGameDetailRoute, rhs: ScheduleGameDetailRoute) -> Bool {
        lhs.stableIdentity == rhs.stableIdentity
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(stableIdentity)
    }
}

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
                            .overlay(alignment: .topTrailing) {
                                if day.hasAttendedGame {
                                    FavoriteTeamAttendanceMarker(
                                        favoriteTeamID: appModel.settings.favoriteTeamID,
                                        size: 15
                                    )
                                        .padding(3)
                                }
                            }
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

    private func isSelected(_ day: MyTeamCalendarDay) -> Bool {
        Calendar(identifier: .gregorian).isDate(day.date, inSameDayAs: viewModel.selectedDate)
    }

    private func dayNumberColor(for day: MyTeamCalendarDay) -> Color {
        if isSelected(day) {
            return appModel.favoriteStadiumPalette?.secondary ?? appModel.currentTheme.accent
        }
        if let palette = appModel.favoriteStadiumPalette {
            return day.isInDisplayedMonth ? palette.textPrimary : palette.textSecondary.opacity(0.6)
        }
        return day.isInDisplayedMonth ? .primary : .secondary.opacity(0.6)
    }

    private func markerColor(for day: MyTeamCalendarDay) -> Color {
        if let palette = appModel.favoriteStadiumPalette {
            return day.dominantStatus?.stadiumTintColor(palette) ?? palette.primary
        }
        return day.dominantStatus?.tintColor ?? appModel.currentTheme.accent
    }

    private func dayResultAppearance(for day: MyTeamCalendarDay) -> ScheduleDayResultAppearance {
        ScheduleDayResultAppearance.from(
            dominantStatus: day.dominantStatus,
            favoriteTeamResult: day.favoriteTeamResult
        )
    }

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

    private func stadiumNoGameDayBackground(for day: MyTeamCalendarDay, palette: StadiumPalette) -> Color {
        isSelected(day) ? palette.elevatedCardStrong : palette.recessedSurface
    }

    private var defaultNoGameDayBackground: Color {
        .clear
    }

    private func dayTodayBorderColor(for day: MyTeamCalendarDay) -> Color {
        if let palette = appModel.favoriteStadiumPalette {
            return day.isToday ? palette.secondary.opacity(0.85) : .clear
        }
        return day.isToday ? KBOLivePalette.upcoming.opacity(0.9) : .clear
    }

    private func daySelectionBorderColor(for day: MyTeamCalendarDay) -> Color {
        if let palette = appModel.favoriteStadiumPalette {
            return isSelected(day) ? palette.primary : .clear
        }
        return isSelected(day) ? appModel.currentTheme.accent : .clear
    }
}

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
                    if appModel.isGameAttended(game) {
                        FavoriteTeamAttendanceMarker(
                            favoriteTeamID: favoriteTeamID,
                            size: 18
                        )
                    }
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

private struct FavoriteTeamAttendanceMarker: View {
    let favoriteTeamID: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let imageAssetName {
                Image(imageAssetName)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
            } else {
                Text("⭐")
                    .font(.system(size: size * 0.82))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("직관 경기")
    }

    private var imageAssetName: String? {
        switch favoriteTeamID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "doosan":
            return "attendance-cheering-doosan"
        case "hanwha":
            return "attendance-cheering-hanwha"
        case "kia":
            return "attendance-cheering-kia"
        case "kiwoom":
            return "attendance-cheering-kiwoom"
        case "lg":
            return "attendance-cheering-lg"
        case "lotte":
            return "attendance-cheering-lotte"
        case "nc":
            return "attendance-cheering-nc"
        case "samsung":
            return "attendance-cheering-samsung"
        case "ssg":
            return "attendance-cheering-ssg"
        default:
            return nil
        }
    }
}

#Preview {
    ScheduleView()
        .environment(AppModel.previewModel())
}
