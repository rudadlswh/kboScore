//
//  AppModel.swift
//  kboScore
//
//  Created by Codex on 3/25/26.
//

import Foundation
import Observation
import UIKit
import UserNotifications

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

enum ScheduleFilter: String, CaseIterable, Identifiable {
    case all = "전체"
    case myTeam = "마이팀"

    var id: String { rawValue }
}

enum AppTab: Hashable, Sendable {
    case home
    case myTeam
    case schedule
    case settings
}

@MainActor
@Observable
final class AppModel {
    private static let settingsStorageKey = "kbo_live_app_settings"
    private static let deviceTokenStorageKey = "kbo_live_apns_device_token"
    private static let staleThreshold: TimeInterval = 90

    private let repository: any KBORepository
    private let repositoryRuntimeState: RepositoryRuntimeState?
    private let notificationRegistrationClient: any NotificationRegistrationClient
    private let liveActivityController: any FavoriteTeamLiveActivityControlling
    private let calendar = Calendar(identifier: .gregorian)
    private let scheduleTimeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
    private(set) var hasLoaded = false
    private(set) var activeRefreshScopes: Set<RefreshScope> = []
    private let usesPersistedSettings: Bool
    private let hasPersistedSettingsAtLaunch: Bool
    private var hasConnectedNotificationDelegate = false
    private var lastSyncedNotificationRegistrationPayload: NotificationRegistrationPayload?
    private var notificationRegistrationSyncTask: Task<Void, Never>?

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
    var selectedTab: AppTab = .home
    var presentedGameID: UUID?
    var isNotificationsPresented = false
    var notificationAuthorizationStatus: AppNotificationAuthorizationStatus = .notDetermined
    var apnsDeviceToken: String?
    var notificationRegistrationSyncStatus: NotificationRegistrationSyncStatus = .waitingForToken
    var notificationRegistrationLastAttemptAt: Date?
    var notificationRegistrationEndpointDescription: String?
    var settings: AppSettings {
        didSet {
            persistSettings()
            scheduleNotificationRegistrationSyncIfNeeded(oldSettings: oldValue)
            if oldValue.liveActivitiesEnabled != settings.liveActivitiesEnabled ||
                oldValue.favoriteTeamID != settings.favoriteTeamID {
                Task { [weak self] in
                    await self?.syncFavoriteTeamLiveActivity()
                }
            }
        }
    }
    var homeFilter: HomeGameFilter = .all
    var notificationFilter: NotificationListFilter = .all
    private(set) var liveActivitySupported: Bool
    private(set) var activeLiveActivityGameID: UUID?
    var gameAlertOverrides: [UUID: Bool] = [:]
    private var lastSuccessfulRefresh: [RefreshDataSet: Date] = [:]
    private var refreshFailures: Set<RefreshDataSet> = []
    private(set) var monthlyScheduleGames: [KBOMonthScheduleKey: [GameDetail]] = [:]
    private(set) var monthlyScheduleDebugSnapshots: [KBOMonthScheduleKey: RepositoryDebugSnapshot] = [:]
    private(set) var loadingScheduleMonths: Set<KBOMonthScheduleKey> = []
    private(set) var failedScheduleMonths: Set<KBOMonthScheduleKey> = []

    init(
        repository: any KBORepository = MockKBORepository(),
        repositoryRuntimeState: RepositoryRuntimeState? = nil,
        notificationRegistrationClient: any NotificationRegistrationClient = NoOpNotificationRegistrationClient(),
        liveActivityController: (any FavoriteTeamLiveActivityControlling)? = nil,
        bootstrap: KBOBootstrapData? = nil,
        usePersistedSettings: Bool = true
    ) {
        self.repository = repository
        self.repositoryRuntimeState = repositoryRuntimeState
        self.notificationRegistrationClient = notificationRegistrationClient
        #if canImport(ActivityKit)
        self.liveActivityController = liveActivityController ?? FavoriteTeamLiveActivityManager()
        #else
        self.liveActivityController = liveActivityController ?? NoOpFavoriteTeamLiveActivityController()
        #endif
        self.usesPersistedSettings = usePersistedSettings
        let persistedSettings = usePersistedSettings ? Self.loadPersistedSettings() : nil
        let persistedDeviceToken = Self.loadPersistedDeviceToken()
        self.hasPersistedSettingsAtLaunch = persistedSettings != nil
        self.settings = persistedSettings ?? .default
        self.debugActiveDataSource = "목 데이터"
        self.debugDeliverySource = "목 데이터"
        self.debugBaseURL = nil
        self.apnsDeviceToken = persistedDeviceToken
        self.notificationRegistrationEndpointDescription = notificationRegistrationClient.debugEndpointDescription
        self.liveActivitySupported = self.liveActivityController.isSupported
        self.notificationRegistrationSyncStatus = persistedDeviceToken == nil ? .waitingForToken : .idle
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
            await syncFavoriteTeamLiveActivity()
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

    var notificationRegistrationLastAttemptText: String {
        guard let notificationRegistrationLastAttemptAt else { return "없음" }
        return notificationRegistrationLastAttemptAt.formatted(date: .omitted, time: .shortened)
    }

    var notificationRegistrationPayloadPreviewText: String {
        guard let payload = currentNotificationRegistrationPayload else { return "토큰 대기 중" }
        let favoriteTeam = payload.favoriteTeamID ?? "선택 안 함"
        return "\(favoriteTeam) · \(payload.alertTypes.count)개 알림 유형"
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

    var unreadNotificationsCount: Int {
        notifications.reduce(into: 0) { partialResult, item in
            if item.isRead == false {
                partialResult += 1
            }
        }
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

    var favoriteTeamLiveGame: GameDetail? {
        games.first { $0.status.isLiveLike && $0.involves(teamID: settings.favoriteTeamID) }
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

    func scheduleGames(on date: Date, filter: ScheduleFilter) -> [GameDetail] {
        let selectedDayKey = scheduleDayKey(for: date)
        let dayGames = filteredScheduleGames(for: date, filter: filter)
            .filter { scheduleDayKey(for: $0.scheduledStart) == selectedDayKey }

        return dayGames.sorted { lhs, rhs in
            let lhsIsMyTeam = lhs.involves(teamID: settings.favoriteTeamID)
            let rhsIsMyTeam = rhs.involves(teamID: settings.favoriteTeamID)
            if lhs.status == rhs.status {
                return lhs.scheduledStart < rhs.scheduledStart
            }
            return homePriority(for: lhs.summary(isMyTeamGame: lhsIsMyTeam)) < homePriority(for: rhs.summary(isMyTeamGame: rhsIsMyTeam))
        }
    }

    func myTeamGames(on date: Date) -> [GameDetail] {
        scheduleGames(on: date, filter: .myTeam)
    }

    func scheduleCalendarDays(for month: Date, filter: ScheduleFilter) -> [MyTeamCalendarDay] {
        let monthGames = filteredScheduleGames(for: month, filter: filter)
        let gamesByDayKey = Dictionary(grouping: monthGames) { scheduleDayKey(for: $0.scheduledStart) }
        #if DEBUG
        print("[ScheduleDebug] markerStateNonEmpty=\(gamesByDayKey.isEmpty == false)")
        if gamesByDayKey.isEmpty == false {
            let groupedKeys = gamesByDayKey.keys.sorted()
            print("[ScheduleDebug] groupedCalendarDateKeys=\(groupedKeys)")
        }
        #endif
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
            let cursorKey = scheduleDayKey(for: cursor)
            let dayGames = gamesByDayKey[cursorKey] ?? []
            #if DEBUG
            if calendar.isDate(cursor, equalTo: monthStart, toGranularity: .month) {
                print("[ScheduleDebug] calendarLookup date=\(cursorKey) gameCount=\(dayGames.count)")
            }
            #endif
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

    func myTeamCalendarDays(for month: Date) -> [MyTeamCalendarDay] {
        scheduleCalendarDays(for: month, filter: .myTeam)
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

    func loadScheduleIfNeeded(for month: Date) async {
        await loadIfNeeded()
        await loadMyTeamSchedule(for: month, forceRefresh: false)
    }

    func refreshSchedule(for month: Date) async {
        await loadIfNeeded()
        await loadMyTeamSchedule(for: month, forceRefresh: true)
    }

    func loadMyTeamScheduleIfNeeded(for month: Date) async {
        await loadScheduleIfNeeded(for: month)
    }

    func refreshMyTeamSchedule(for month: Date) async {
        await refreshSchedule(for: month)
    }

    func isLoadingSchedule(for month: Date) -> Bool {
        loadingScheduleMonths.contains(KBOMonthScheduleKey(date: month, calendar: calendar))
    }

    func isLoadingMyTeamSchedule(for month: Date) -> Bool {
        isLoadingSchedule(for: month)
    }

    func scheduleStatusMessage(for month: Date) -> String? {
        let key = KBOMonthScheduleKey(date: month, calendar: calendar)
        if let snapshot = monthlyScheduleDebugSnapshots[key] {
            if snapshot.activeSource == .mock, snapshot.baseURL == nil {
                return "실데이터 URL 미설정 · 목 일정으로 표시 중입니다."
            }

            if snapshot.deliverySource == .cache, snapshot.isUsingStaleCache {
                return "공식 일정 갱신 실패 · 이전 캐시 일정으로 표시 중입니다."
            }

            if snapshot.activeSource == .mockFallback {
                return "공식 일정 실패 · 목 일정으로 표시 중입니다."
            }
        }

        guard failedScheduleMonths.contains(key), monthlyScheduleGames[key] == nil else { return nil }
        if fallbackMonthSchedule(for: key).isEmpty == false {
            return "공식 월간 일정이 지연되어 현재 경기 목록 기반 일정으로 표시 중입니다."
        }
        return "월간 일정을 불러오지 못했습니다."
    }

    func myTeamScheduleStatusMessage(for month: Date) -> String? {
        scheduleStatusMessage(for: month)
    }

    func scheduleDebugSummary(for month: Date) -> String? {
        let key = KBOMonthScheduleKey(date: month, calendar: calendar)
        guard let snapshot = monthlyScheduleDebugSnapshots[key] else { return nil }

        var parts = [
            "소스 \(snapshot.activeSource.rawValue)",
            "표시 \(snapshot.deliverySource.rawValue)"
        ]

        if snapshot.isUsingStaleCache {
            parts.append("지연 캐시")
        }

        if let baseURL = snapshot.baseURL {
            parts.append(baseURL)
        } else {
            parts.append("실데이터 URL 없음")
        }

        return parts.joined(separator: " · ")
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

    func shouldShowLiveActivityAction(for game: GameDetail) -> Bool {
        game.status.isLiveLike && game.involves(teamID: settings.favoriteTeamID)
    }

    func isLiveActivityOn(for gameID: UUID) -> Bool {
        activeLiveActivityGameID == gameID
    }

    func isLiveActivityActionEnabled(for game: GameDetail) -> Bool {
        shouldShowLiveActivityAction(for: game) && settings.liveActivitiesEnabled && liveActivitySupported
    }

    func liveActivityButtonTitle(for game: GameDetail) -> String {
        guard shouldShowLiveActivityAction(for: game) else {
            return "Live Activity"
        }
        if settings.liveActivitiesEnabled == false {
            return "Live Activity 꺼짐"
        }
        if liveActivitySupported == false {
            return "Live Activity 사용 불가"
        }
        if isLiveActivityOn(for: game.id) {
            return "Live Activity 중지"
        }
        return "Live Activity 시작"
    }

    func liveActivityButtonSystemImage(for game: GameDetail) -> String {
        if isLiveActivityOn(for: game.id) {
            return "dot.radiowaves.left.and.right.circle.fill"
        }
        return "dot.radiowaves.left.and.right"
    }

    func toggleLiveActivity(for game: GameDetail) async {
        guard shouldShowLiveActivityAction(for: game) else { return }

        if isLiveActivityOn(for: game.id) {
            await liveActivityController.endCurrent()
            activeLiveActivityGameID = nil
            return
        }

        guard isLiveActivityActionEnabled(for: game),
              let snapshot = FavoriteTeamLiveActivitySnapshot.make(from: game, favoriteTeamID: settings.favoriteTeamID) else {
            return
        }

        do {
            try await liveActivityController.startOrUpdate(using: snapshot)
            activeLiveActivityGameID = game.id
        } catch {
            activeLiveActivityGameID = nil
        }
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

    func connectNotificationDelegate(_ delegate: AppNotificationDelegate) {
        guard !hasConnectedNotificationDelegate else { return }
        hasConnectedNotificationDelegate = true

        delegate.connect(
            onDeviceToken: { [weak self] token in
                self?.updateAPNsDeviceToken(token)
            },
            onNotificationUserInfo: { [weak self] userInfo in
                self?.handleNotificationUserInfo(userInfo)
            }
        )
    }

    func refreshNotificationAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorizationStatus = AppNotificationAuthorizationStatus(settings.authorizationStatus)
        scheduleNotificationRegistrationSync(force: true)
    }

    func syncNotificationRegistrationState() async {
        await refreshNotificationAuthorizationStatus()
        if notificationAuthorizationStatus.allowsNotifications {
            UIApplication.shared.registerForRemoteNotifications()
        }
        scheduleNotificationRegistrationSync(force: false)
    }

    func requestNotificationAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshNotificationAuthorizationStatus()
            guard granted else { return }
            UIApplication.shared.registerForRemoteNotifications()
            scheduleNotificationRegistrationSync(force: true)
        } catch {
            await refreshNotificationAuthorizationStatus()
        }
    }

    func scheduleDebugNotification() async {
        #if DEBUG
        let targetGame = myTeamTodayGame ?? todayGames.first ?? games.first
        let payload = ScoreNotificationPayload(
            gameID: targetGame.map { resolvedRawGameID(for: $0) },
            eventType: .scoreChange,
            title: "테스트 스코어 알림",
            body: targetGame.map { "\($0.awayTeam.shortName) vs \($0.homeTeam.shortName) 상세로 이동합니다." } ?? "게임 상세 이동 경로를 확인합니다.",
            teamIDs: [targetGame?.awayTeam.id, targetGame?.homeTeam.id].compactMap { $0 },
            routeHint: targetGame == nil ? .notifications : .gameDetail
        )

        guard notificationAuthorizationStatus.allowsNotifications else {
            routeNotification(payload)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.sound = .default
        content.userInfo = payload.userInfo()

        let request = UNNotificationRequest(
            identifier: "debug-score-notification-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            routeNotification(payload)
        }
        #endif
    }

    func dismissPresentedGameDetail() {
        presentedGameID = nil
    }

    func presentNotifications() {
        isNotificationsPresented = true
    }

    func dismissNotifications() {
        isNotificationsPresented = false
    }

    static func previewModel() -> AppModel {
        AppModel(bootstrap: MockKBOData.makeBootstrap(), usePersistedSettings: false)
    }

    private func loadMyTeamSchedule(for month: Date, forceRefresh: Bool) async {
        let key = KBOMonthScheduleKey(date: month, calendar: calendar)
        guard forceRefresh || monthlyScheduleGames[key] == nil else { return }
        guard !loadingScheduleMonths.contains(key) else { return }

        loadingScheduleMonths.insert(key)
        defer { loadingScheduleMonths.remove(key) }

        do {
            let schedule = try await repository.fetchMonthlySchedule(for: key)
            monthlyScheduleGames[key] = schedule.sorted { $0.scheduledStart < $1.scheduledStart }
            failedScheduleMonths.remove(key)
            await refreshMonthlyScheduleDebugInfo(for: key)
        } catch {
            failedScheduleMonths.insert(key)
            await refreshMonthlyScheduleDebugInfo(for: key)
            if monthlyScheduleGames[key] == nil {
                let fallback = fallbackMonthSchedule(for: key)
                if fallback.isEmpty == false {
                    monthlyScheduleGames[key] = fallback
                }
            }
        }
    }

    private func refreshMonthlyScheduleDebugInfo(for key: KBOMonthScheduleKey) async {
        guard let repositoryRuntimeState else { return }
        let snapshot = await repositoryRuntimeState.snapshot()
        monthlyScheduleDebugSnapshots[key] = snapshot
        debugActiveDataSource = snapshot.activeSource.rawValue
        debugDeliverySource = snapshot.deliverySource.rawValue
        debugBaseURL = snapshot.baseURL
        lastUpdatedAt = snapshot.lastRefreshAt ?? lastUpdatedAt
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
            await syncFavoriteTeamLiveActivity()
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

    private func updateAPNsDeviceToken(_ token: String) {
        guard apnsDeviceToken != token else {
            scheduleNotificationRegistrationSync(force: false)
            return
        }

        apnsDeviceToken = token
        if usesPersistedSettings {
            UserDefaults.standard.set(token, forKey: Self.deviceTokenStorageKey)
        }
        scheduleNotificationRegistrationSync(force: true)
    }

    private static func loadPersistedDeviceToken() -> String? {
        UserDefaults.standard.string(forKey: Self.deviceTokenStorageKey)
    }

    private func handleNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        guard let payload = ScoreNotificationPayloadExtractor.payload(from: userInfo) else { return }
        routeNotification(payload)
    }

    private func routeNotification(_ payload: ScoreNotificationPayload) {
        switch ScoreNotificationPayloadExtractor.route(from: payload) {
        case .gameDetail(let gameID):
            isNotificationsPresented = false
            selectedTab = .home
            presentedGameID = gameID
        case .notifications:
            presentNotifications()
        case .home:
            isNotificationsPresented = false
            selectedTab = .home
        case .none:
            break
        }
    }

    private var currentNotificationRegistrationPayload: NotificationRegistrationPayload? {
        NotificationRegistrationPayload(
            deviceToken: apnsDeviceToken,
            settings: settings,
            authorizationStatus: notificationAuthorizationStatus
        )
    }

    private func scheduleNotificationRegistrationSyncIfNeeded(oldSettings: AppSettings) {
        guard oldSettings.favoriteTeamID != settings.favoriteTeamID ||
                oldSettings.notificationPreferences != settings.notificationPreferences ||
                oldSettings.quietHours != settings.quietHours else {
            return
        }

        scheduleNotificationRegistrationSync(force: false)
    }

    private func scheduleNotificationRegistrationSync(force: Bool) {
        guard let payload = currentNotificationRegistrationPayload else {
            notificationRegistrationSyncStatus = .waitingForToken
            return
        }

        if force == false, payload == lastSyncedNotificationRegistrationPayload {
            return
        }

        notificationRegistrationSyncTask?.cancel()
        notificationRegistrationSyncTask = Task { [weak self] in
            await self?.performNotificationRegistrationSync(payload)
        }
    }

    private func performNotificationRegistrationSync(_ payload: NotificationRegistrationPayload) async {
        notificationRegistrationSyncStatus = .syncing
        notificationRegistrationLastAttemptAt = Date()

        do {
            let status = try await notificationRegistrationClient.syncRegistration(payload)
            notificationRegistrationSyncStatus = status
            if status == .synced || status == .skipped {
                lastSyncedNotificationRegistrationPayload = payload
            }
        } catch {
            notificationRegistrationSyncStatus = .failed
        }
    }

    private func syncFavoriteTeamLiveActivity() async {
        liveActivitySupported = liveActivityController.isSupported

        guard settings.liveActivitiesEnabled else {
            await liveActivityController.endCurrent()
            activeLiveActivityGameID = nil
            return
        }

        guard let activeGameID = activeLiveActivityGameID else { return }
        guard let activeGame = games.first(where: { $0.id == activeGameID }),
              shouldShowLiveActivityAction(for: activeGame),
              let snapshot = FavoriteTeamLiveActivitySnapshot.make(from: activeGame, favoriteTeamID: settings.favoriteTeamID) else {
            await liveActivityController.endCurrent()
            activeLiveActivityGameID = nil
            return
        }

        guard liveActivitySupported else {
            activeLiveActivityGameID = nil
            return
        }

        do {
            try await liveActivityController.startOrUpdate(using: snapshot)
            activeLiveActivityGameID = activeGameID
        } catch {
            activeLiveActivityGameID = nil
        }
    }

    private func resolvedRawGameID(for game: GameDetail) -> String {
        if let officialGame = games.first(where: { $0.id == game.id }) {
            return officialGame.id.uuidString
        }
        return game.id.uuidString
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

    private func filteredScheduleGames(for date: Date, filter: ScheduleFilter) -> [GameDetail] {
        let monthGames = myTeamMonthScheduleSource(for: date)
        switch filter {
        case .all:
            return monthGames
        case .myTeam:
            guard let favoriteTeamID = settings.favoriteTeamID else { return [] }
            return monthGames.filter { $0.involves(teamID: favoriteTeamID) }
        }
    }

    private func fallbackMonthSchedule(for key: KBOMonthScheduleKey) -> [GameDetail] {
        games
            .filter {
                let components = calendar.dateComponents([.year, .month], from: $0.scheduledStart)
                return components.year == key.year && components.month == key.month
            }
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    private func scheduleDayKey(for date: Date) -> String {
        var scheduleCalendar = calendar
        scheduleCalendar.timeZone = scheduleTimeZone
        let components = scheduleCalendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
