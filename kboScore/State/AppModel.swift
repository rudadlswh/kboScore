//
//  AppModel.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import Foundation
import Observation

enum RefreshScope: Hashable, Sendable {
    case home
    case myTeam
    case notifications
}

private enum RefreshDataSet: Hashable {
    case games
    case notifications
}

enum HomeGameFilter: String, CaseIterable, Identifiable {
    case all = "전체"
    case live = "라이브"
    case upcoming = "예정"
    case final = "종료"
    case myTeam = "마이팀"

    var id: String { rawValue }
}

enum NotificationListFilter: String, CaseIterable, Identifiable {
    case all = "전체"
    case myTeam = "마이팀"
    case score = "스코어"
    case final = "종료"
    case today = "오늘"

    var id: String { rawValue }
}

@MainActor
@Observable
final class AppModel {
    private static let settingsStorageKey = "kbo_live_app_settings"
    private static let staleThreshold: TimeInterval = 90

    private let repository: any KBORepository
    private let repositoryRuntimeState: RepositoryRuntimeState?
    private let calendar = Calendar(identifier: .gregorian)
    private(set) var hasLoaded = false
    private(set) var activeRefreshScopes: Set<RefreshScope> = []
    private let usesPersistedSettings: Bool
    private let hasPersistedSettingsAtLaunch: Bool

    var isLoading = false
    var loadErrorMessage: String?
    var lastUpdatedAt: Date?
    var debugActiveDataSource: String
    var debugDeliverySource: String
    var debugBaseURL: String?
    var isShowingStaleData = false
    var teams: [Team] = []
    var games: [GameDetail] = []
    var notifications: [NotificationItem] = []
    var settings: AppSettings {
        didSet {
            persistSettings()
        }
    }
    var homeFilter: HomeGameFilter = .all
    var notificationFilter: NotificationListFilter = .all
    var trackedLiveActivities: Set<UUID> = []
    var gameAlertOverrides: [UUID: Bool] = [:]
    private var lastSuccessfulRefresh: [RefreshDataSet: Date] = [:]
    private var refreshFailures: Set<RefreshDataSet> = []
    private(set) var monthlyScheduleGames: [KBOMonthScheduleKey: [GameDetail]] = [:]
    private(set) var loadingScheduleMonths: Set<KBOMonthScheduleKey> = []
    private(set) var failedScheduleMonths: Set<KBOMonthScheduleKey> = []

    init(
        repository: any KBORepository = MockKBORepository(),
        repositoryRuntimeState: RepositoryRuntimeState? = nil,
        bootstrap: KBOBootstrapData? = nil,
        usePersistedSettings: Bool = true
    ) {
        self.repository = repository
        self.repositoryRuntimeState = repositoryRuntimeState
        self.usesPersistedSettings = usePersistedSettings
        let persistedSettings = usePersistedSettings ? Self.loadPersistedSettings() : nil
        self.hasPersistedSettingsAtLaunch = persistedSettings != nil
        self.settings = persistedSettings ?? .default
        self.debugActiveDataSource = "목 데이터"
        self.debugDeliverySource = "목 데이터"
        self.debugBaseURL = nil
        if let bootstrap {
            apply(bootstrap)
            hasLoaded = true
            let now = Date()
            lastSuccessfulRefresh[.games] = now
            lastSuccessfulRefresh[.notifications] = now
            lastUpdatedAt = now
        }
    }

    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }

        isLoading = true
        loadErrorMessage = nil

        do {
            let bootstrap = try await repository.fetchBootstrapData()
            apply(bootstrap)
            hasLoaded = true
            let refreshedAt = Date()
            markRefreshSuccess(for: .games, at: refreshedAt, isStale: false)
            markRefreshSuccess(for: .notifications, at: refreshedAt, isStale: false)
            await refreshRepositoryDebugInfo(dataSets: [.games, .notifications])
        } catch {
            loadErrorMessage = "데이터를 불러오지 못했습니다."
        }

        isLoading = false
    }

    private func apply(_ bootstrap: KBOBootstrapData) {
        teams = bootstrap.teams
        games = bootstrap.games.sorted { $0.scheduledStart > $1.scheduledStart }
        notifications = bootstrap.notifications.sorted { $0.sentAt > $1.sentAt }
        if !hasPersistedSettingsAtLaunch {
            settings = bootstrap.settings
        }
    }

    func refreshHome() async {
        await refreshGames(for: [.home, .myTeam])
    }

    func refreshMyTeam() async {
        await refreshGames(for: [.myTeam, .home])
        await refreshMyTeamSchedule(for: Date())
    }

    func refreshNotifications() async {
        await refreshNotifications(for: [.notifications])
    }

    func isRefreshing(_ scope: RefreshScope) -> Bool {
        activeRefreshScopes.contains(scope)
    }

    func statusMessage(for scope: RefreshScope) -> String? {
        switch scope {
        case .home, .myTeam:
            guard !games.isEmpty, isGamesStale else { return nil }
            return staleStatusMessage(lastRefreshAt: lastSuccessfulRefresh[.games])
        case .notifications:
            guard !notifications.isEmpty, isNotificationsStale else { return nil }
            return staleStatusMessage(lastRefreshAt: lastSuccessfulRefresh[.notifications])
        }
    }

    var debugLastRefreshText: String {
        guard let lastUpdatedAt else { return "없음" }
        return lastUpdatedAt.formatted(date: .omitted, time: .shortened)
    }

    var currentTheme: TeamTheme {
        switch settings.teamThemeMode {
        case .systemDefault:
            .neutral
        case .favoriteTeam:
            TeamTheme.resolve(for: settings.favoriteTeamID)
        }
    }

    var favoriteTeam: Team? {
        teams.first { $0.id == settings.favoriteTeamID }
    }

    var todayGames: [GameDetail] {
        games.filter { calendar.isDateInToday($0.scheduledStart) }
            .sorted(by: todayGameComparator)
    }

    var filteredHomeGames: [GameSummary] {
        todayGames
            .map { $0.summary(isMyTeamGame: $0.involves(teamID: settings.favoriteTeamID)) }
            .filter(matchesHomeFilter)
            .sorted(by: homeSummaryComparator)
    }

    var todayGamesCount: Int {
        todayGames.count
    }

    var liveGamesCount: Int {
        todayGames.filter { $0.status.isLiveLike }.count
    }

    var myGamesCount: Int {
        todayGames.filter { $0.involves(teamID: settings.favoriteTeamID) }.count
    }

    var myTeamTodayGame: GameDetail? {
        todayGames.first { $0.involves(teamID: settings.favoriteTeamID) }
    }

    var myTeamNextGame: GameDetail? {
        guard let favoriteTeamID = settings.favoriteTeamID else { return nil }
        return games
            .filter { $0.involves(teamID: favoriteTeamID) && $0.status == .upcoming && $0.id != myTeamTodayGame?.id }
            .sorted { $0.scheduledStart < $1.scheduledStart }
            .first
    }

    var myTeamRecentResult: GameDetail? {
        guard let favoriteTeamID = settings.favoriteTeamID else { return nil }
        return games
            .filter { $0.involves(teamID: favoriteTeamID) && $0.status.isFinishedLike && !calendar.isDateInToday($0.scheduledStart) }
            .sorted { $0.scheduledStart > $1.scheduledStart }
            .first
    }

    func myTeamGames(on date: Date) -> [GameDetail] {
        guard let favoriteTeamID = settings.favoriteTeamID else { return [] }
        return myTeamMonthScheduleSource(for: date)
            .filter { $0.involves(teamID: favoriteTeamID) && calendar.isDate($0.scheduledStart, inSameDayAs: date) }
            .sorted { lhs, rhs in
                if lhs.status == rhs.status {
                    return lhs.scheduledStart < rhs.scheduledStart
                }
                return homePriority(for: lhs.summary(isMyTeamGame: true)) < homePriority(for: rhs.summary(isMyTeamGame: true))
            }
    }

    func myTeamCalendarDays(for month: Date) -> [MyTeamCalendarDay] {
        guard settings.favoriteTeamID != nil else { return [] }
        let monthGames = myTeamMonthScheduleSource(for: month)
        let monthStart = startOfMonth(for: month)
        guard let monthRange = calendar.dateInterval(of: .month, for: monthStart),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthRange.start),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthRange.start),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthEnd) else {
            return []
        }

        var days: [MyTeamCalendarDay] = []
        var cursor = firstWeek.start
        while cursor < lastWeek.end {
            let dayGames = monthGames.filter {
                $0.involves(teamID: settings.favoriteTeamID) && calendar.isDate($0.scheduledStart, inSameDayAs: cursor)
            }
            days.append(
                MyTeamCalendarDay(
                    date: cursor,
                    isInDisplayedMonth: calendar.isDate(cursor, equalTo: monthStart, toGranularity: .month),
                    isToday: calendar.isDateInToday(cursor),
                    gameCount: dayGames.count,
                    dominantStatus: dominantStatus(for: dayGames)
                )
            )
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = nextDay
        }
        return days
    }

    func startOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    func shiftedMonth(from date: Date, by offset: Int) -> Date {
        calendar.date(byAdding: .month, value: offset, to: startOfMonth(for: date)) ?? date
    }

    func calendarMonthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: startOfMonth(for: date))
    }

    func loadMyTeamScheduleIfNeeded(for month: Date) async {
        await loadMyTeamSchedule(for: month, forceRefresh: false)
    }

    func refreshMyTeamSchedule(for month: Date) async {
        await loadMyTeamSchedule(for: month, forceRefresh: true)
    }

    func isLoadingMyTeamSchedule(for month: Date) -> Bool {
        loadingScheduleMonths.contains(KBOMonthScheduleKey(date: month, calendar: calendar))
    }

    func myTeamScheduleStatusMessage(for month: Date) -> String? {
        let key = KBOMonthScheduleKey(date: month, calendar: calendar)
        guard failedScheduleMonths.contains(key), monthlyScheduleGames[key] == nil else { return nil }
        return "공식 월간 일정이 지연되어 현재 보유한 일정으로 표시 중입니다."
    }

    var filteredNotifications: [NotificationItem] {
        notifications.filter { item in
            switch notificationFilter {
            case .all:
                return true
            case .myTeam:
                guard let favoriteTeamID = settings.favoriteTeamID else { return false }
                return item.relatedTeamIDs.contains(favoriteTeamID)
            case .score:
                return item.type.isScoreLike
            case .final:
                return item.type == .gameEnd
            case .today:
                return calendar.isDateInToday(item.sentAt)
            }
        }
    }

    func game(withID gameID: UUID) -> GameDetail? {
        games.first { $0.id == gameID }
    }

    func toggleLiveActivity(for gameID: UUID) {
        if trackedLiveActivities.contains(gameID) {
            trackedLiveActivities.remove(gameID)
        } else {
            trackedLiveActivities.insert(gameID)
        }
    }

    func isLiveActivityOn(for gameID: UUID) -> Bool {
        trackedLiveActivities.contains(gameID)
    }

    func isGameAlertEnabled(for gameID: UUID) -> Bool {
        gameAlertOverrides[gameID, default: true]
    }

    func setGameAlert(_ isEnabled: Bool, for gameID: UUID) {
        gameAlertOverrides[gameID] = isEnabled
    }

    func markNotificationRead(_ notificationID: UUID) {
        guard let index = notifications.firstIndex(where: { $0.id == notificationID }) else { return }
        notifications[index].isRead = true
    }

    static func previewModel() -> AppModel {
        AppModel(bootstrap: MockKBOData.makeBootstrap(), usePersistedSettings: false)
    }

    private func loadMyTeamSchedule(for month: Date, forceRefresh: Bool) async {
        guard settings.favoriteTeamID != nil else { return }
        let key = KBOMonthScheduleKey(date: month, calendar: calendar)
        guard forceRefresh || monthlyScheduleGames[key] == nil else { return }
        guard !loadingScheduleMonths.contains(key) else { return }

        loadingScheduleMonths.insert(key)
        defer { loadingScheduleMonths.remove(key) }

        do {
            let schedule = try await repository.fetchMonthlySchedule(for: key)
            monthlyScheduleGames[key] = schedule.sorted { $0.scheduledStart < $1.scheduledStart }
            failedScheduleMonths.remove(key)
        } catch {
            failedScheduleMonths.insert(key)
            if monthlyScheduleGames[key] == nil {
                let fallback = fallbackMonthSchedule(for: key)
                if fallback.isEmpty == false {
                    monthlyScheduleGames[key] = fallback
                }
            }
        }
    }

    private func refreshGames(for scopes: Set<RefreshScope>) async {
        guard activeRefreshScopes.isDisjoint(with: scopes) else { return }
        activeRefreshScopes.formUnion(scopes)
        defer { activeRefreshScopes.subtract(scopes) }

        do {
            games = try await repository.fetchGames()
            if repositoryRuntimeState == nil {
                markRefreshSuccess(for: .games, at: Date(), isStale: false)
            }
            await refreshRepositoryDebugInfo(dataSets: [.games])
        } catch {
            markRefreshFailure(for: .games, hasUsableData: !games.isEmpty)
        }
    }

    private func refreshNotifications(for scopes: Set<RefreshScope>) async {
        guard activeRefreshScopes.isDisjoint(with: scopes) else { return }
        activeRefreshScopes.formUnion(scopes)
        defer { activeRefreshScopes.subtract(scopes) }

        do {
            notifications = try await repository.fetchNotifications()
            if repositoryRuntimeState == nil {
                markRefreshSuccess(for: .notifications, at: Date(), isStale: false)
            }
            await refreshRepositoryDebugInfo(dataSets: [.notifications])
        } catch {
            markRefreshFailure(for: .notifications, hasUsableData: !notifications.isEmpty)
        }
    }

    private func refreshRepositoryDebugInfo(dataSets: Set<RefreshDataSet>) async {
        guard let repositoryRuntimeState else { return }
        let snapshot = await repositoryRuntimeState.snapshot()
        debugActiveDataSource = snapshot.activeSource.rawValue
        debugDeliverySource = snapshot.deliverySource.rawValue
        debugBaseURL = snapshot.baseURL
        lastUpdatedAt = snapshot.lastRefreshAt ?? lastUpdatedAt

        if let lastRefreshAt = snapshot.lastRefreshAt {
            if dataSets.contains(.games), !games.isEmpty {
                    markRefreshSuccess(for: .games, at: lastRefreshAt, isStale: snapshot.isUsingStaleCache)
            }
            if dataSets.contains(.notifications), !notifications.isEmpty {
                    markRefreshSuccess(for: .notifications, at: lastRefreshAt, isStale: snapshot.isUsingStaleCache)
            }
        }

        isShowingStaleData = snapshot.isUsingStaleCache || isGamesStale || isNotificationsStale
    }

    private var isGamesStale: Bool {
        isDataSetStale(.games)
    }

    private var isNotificationsStale: Bool {
        isDataSetStale(.notifications)
    }

    private func isDataSetStale(_ dataSet: RefreshDataSet) -> Bool {
        if refreshFailures.contains(dataSet) {
            return true
        }

        guard let lastRefreshAt = lastSuccessfulRefresh[dataSet] else {
            return false
        }

        return Date().timeIntervalSince(lastRefreshAt) > Self.staleThreshold
    }

    private func markRefreshSuccess(for dataSet: RefreshDataSet, at date: Date, isStale: Bool) {
        lastSuccessfulRefresh[dataSet] = date
        if isStale {
            refreshFailures.insert(dataSet)
        } else {
            refreshFailures.remove(dataSet)
        }
        loadErrorMessage = nil
        lastUpdatedAt = date
        isShowingStaleData = isGamesStale || isNotificationsStale
    }

    private func markRefreshFailure(for dataSet: RefreshDataSet, hasUsableData: Bool) {
        refreshFailures.insert(dataSet)
        isShowingStaleData = isGamesStale || isNotificationsStale

        guard !hasUsableData else { return }

        switch dataSet {
        case .games:
            loadErrorMessage = "최신 경기 데이터를 가져오지 못했습니다."
        case .notifications:
            loadErrorMessage = "최신 알림 데이터를 가져오지 못했습니다."
        }
    }

    private func staleStatusMessage(lastRefreshAt: Date?) -> String {
        guard let lastRefreshAt else {
            return "업데이트가 지연되고 있습니다."
        }
        return "업데이트 지연 · 마지막 갱신 \(lastRefreshAt.formatted(date: .omitted, time: .shortened))"
    }

    private func persistSettings() {
        guard usesPersistedSettings else { return }
        guard let encoded = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(encoded, forKey: Self.settingsStorageKey)
    }

    private static func loadPersistedSettings() -> AppSettings? {
        guard let data = UserDefaults.standard.data(forKey: Self.settingsStorageKey) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    private func homePriority(for summary: GameSummary) -> Int {
        switch summary.status {
        case .live, .rainDelay:
            return summary.isMyTeamGame ? 0 : 1
        case .upcoming:
            return 2
        case .final, .cancelled:
            return 3
        }
    }

    private func matchesHomeFilter(_ summary: GameSummary) -> Bool {
        switch homeFilter {
        case .all:
            true
        case .live:
            summary.status.isLiveLike
        case .upcoming:
            summary.status == .upcoming
        case .final:
            summary.status.isFinishedLike
        case .myTeam:
            summary.isMyTeamGame
        }
    }

    private func homeSummaryComparator(_ lhs: GameSummary, _ rhs: GameSummary) -> Bool {
        let lhsPriority = homePriority(for: lhs)
        let rhsPriority = homePriority(for: rhs)

        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        if lhs.status.isLiveLike && rhs.status.isLiveLike, lhs.isMyTeamGame == rhs.isMyTeamGame {
            return lhs.scheduledStart > rhs.scheduledStart
        }

        return lhs.scheduledStart < rhs.scheduledStart
    }

    private func todayGameComparator(_ lhs: GameDetail, _ rhs: GameDetail) -> Bool {
        homeSummaryComparator(
            lhs.summary(isMyTeamGame: lhs.involves(teamID: settings.favoriteTeamID)),
            rhs.summary(isMyTeamGame: rhs.involves(teamID: settings.favoriteTeamID))
        )
    }

    private func dominantStatus(for games: [GameDetail]) -> GameStatus? {
        if games.contains(where: { $0.status == .live }) {
            return .live
        }
        if games.contains(where: { $0.status == .rainDelay }) {
            return .rainDelay
        }
        if games.contains(where: { $0.status == .upcoming }) {
            return .upcoming
        }
        if games.contains(where: { $0.status == .final }) {
            return .final
        }
        if games.contains(where: { $0.status == .cancelled }) {
            return .cancelled
        }
        return nil
    }

    private func myTeamMonthScheduleSource(for date: Date) -> [GameDetail] {
        let key = KBOMonthScheduleKey(date: date, calendar: calendar)
        return monthlyScheduleGames[key] ?? fallbackMonthSchedule(for: key)
    }

    private func fallbackMonthSchedule(for key: KBOMonthScheduleKey) -> [GameDetail] {
        games
            .filter {
                let components = calendar.dateComponents([.year, .month], from: $0.scheduledStart)
                return components.year == key.year && components.month == key.month
            }
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }
}
