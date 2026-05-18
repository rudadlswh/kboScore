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
#if canImport(WidgetKit)
import WidgetKit
#endif

typealias GameCancellationNotificationScheduler = (UNNotificationRequest) async throws -> Void
typealias CurrentDateProvider = () -> Date

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
    case standings
    case schedule
    case settings
}

private struct HomeFavoriteGameRefreshKey: Hashable {
    let dayKey: String
    let favoriteTeamID: String
}

@MainActor
@Observable
final class AppModel {
    private static let staleThreshold: TimeInterval = 90
    private static let gameDetailFreshnessThreshold: TimeInterval = 8
    private static let previousRegularSeasonRankByTeamID: [String: Int] = [
        "lg": 1,
        "hanwha": 2,
        "ssg": 3,
        "samsung": 4,
        "nc": 5,
        "kt": 6,
        "lotte": 7,
        "kia": 8,
        "doosan": 9,
        "kiwoom": 10
    ]

    private let repository: any KBORepository
    private let repositoryRuntimeState: RepositoryRuntimeState?
    private let notificationRegistrationClient: any NotificationRegistrationClient
    private let liveActivityController: any FavoriteTeamLiveActivityControlling
    private let cancellationNotificationScheduler: GameCancellationNotificationScheduler
    private let currentDateProvider: CurrentDateProvider
    private let cancellationNotificationCoordinator = GameCancellationNotificationCoordinator()
    private let officialGameCenterClient = OfficialKBOGameCenterClient()
    private let localPostseasonQualificationCalculator = LocalPostseasonQualificationCalculator()
    private let calendar = Calendar(identifier: .gregorian)
    private let scheduleTimeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
    private(set) var hasLoaded = false
    private(set) var activeRefreshScopes: Set<RefreshScope> = []
    private let usesPersistedSettings: Bool
    private let hasPersistedSettingsAtLaunch: Bool
    private var hasConnectedNotificationDelegate = false
    private var notificationRegistrationDeduplicationState = NotificationRegistrationDeduplicationState()
    private var notificationRegistrationSyncTask: Task<Void, Never>?
    private var lastNotifiedGameStates: [String: GameContentNotificationState] = [:]
    private var notifiedGameContentKeys: Set<String> = []
    private var lastFavoriteTeamWidgetSemanticKey: String?

    var isLoading = false
    var loadErrorMessage: String?
    var lastUpdatedAt: Date?
    var debugActiveDataSource: String
    var debugDeliverySource: String
    var debugBaseURL: String?
    var debugBootstrapAPIEnabled: String
    var debugBootstrapETag: String
    var debugBootstrapLastFetchAt: Date?
    var debugBootstrapLastWriteAt: Date?
    var debugBootstrapLastResult: String
    var debugLocalBootstrapSource: String
    var debugLocalBootstrapMessage: String?
    let debugLocalBootstrapPath: String
    var debugLocalBootstrapResolvedPath: String?
    var debugLocalBootstrapLoadedAt: Date?
    var isShowingStaleData = false
    var teams: [Team] = []
    var games: [GameDetail] = []
    private(set) var homeFavoriteTeamGames: [GameDetail] = []
    var notifications: [NotificationItem] = []
    var selectedTab: AppTab = .home
    var presentedGameID: UUID?
    var isNotificationsPresented = false
    var notificationAuthorizationStatus: AppNotificationAuthorizationStatus = .notDetermined
    var apnsDeviceToken: String?
    var notificationRegistrationSyncStatus: NotificationRegistrationSyncStatus = .waitingForToken
    var notificationRegistrationLastAttemptAt: Date?
    var notificationRegistrationEndpointDescription: String?
    private(set) var attendedGameKeys: Set<String> = []
    private var notifiedCancellationKeys: Set<String> = []
    var settings: AppSettings {
        didSet {
            let favoriteTeamChanged = oldValue.favoriteTeamID != settings.favoriteTeamID
            persistSettings()
            scheduleNotificationRegistrationSyncIfNeeded(oldSettings: oldValue)
            if oldValue.liveActivitiesEnabled != settings.liveActivitiesEnabled ||
                oldValue.favoriteTeamID != settings.favoriteTeamID {
                Task { [weak self] in
                    await self?.syncFavoriteTeamLiveActivity()
                    await self?.syncFavoriteTeamWidgetSnapshot(includePrefetch: true)
                }
            }
            if favoriteTeamChanged {
                invalidateScheduleDerivedCaches()
            }
        }
    }
    var homeFilter: HomeGameFilter = .all
    var notificationFilter: NotificationListFilter = .all
    private(set) var liveActivitySupported: Bool
    private(set) var activeLiveActivityGameID: UUID?
    var gameAlertOverrides: [UUID: Bool] = [:]
    var hasCompletedOnboarding: Bool
    private var lastSuccessfulRefresh: [RefreshDataSet: Date] = [:]
    private var refreshFailures: Set<RefreshDataSet> = []
    private(set) var monthlyScheduleGames: [KBOMonthScheduleKey: [GameDetail]] = [:]
    private(set) var monthlyScheduleDebugSnapshots: [KBOMonthScheduleKey: RepositoryDebugSnapshot] = [:]
    private(set) var loadingScheduleMonths: Set<KBOMonthScheduleKey> = []
    private(set) var failedScheduleMonths: Set<KBOMonthScheduleKey> = []
    private var monthlyScheduleRefreshDayKeys: [KBOMonthScheduleKey: String] = [:]
    private var monthlyScheduleDecisionLogKeys: [KBOMonthScheduleKey: String] = [:]
    private var inFlightScheduleMonthTasks: [KBOMonthScheduleKey: Task<Void, Never>] = [:]
    private var inFlightGameDetailRefreshTasks: [String: Task<GameDetail?, Never>] = [:]
    private var lastGameDetailRefreshAt: [String: Date] = [:]
    private var inFlightHomeFavoriteGameTasks: [HomeFavoriteGameRefreshKey: Task<Void, Never>] = [:]
    private var lastHomeFavoriteGameRefreshAt: [HomeFavoriteGameRefreshKey: Date] = [:]
    private var inFlightTodayLiveRefreshTasks: [String: Task<Void, Never>] = [:]
    private var lastTodayLiveRefreshAt: [String: Date] = [:]
    private var scheduleStartupSyncState: ScheduleStartupSyncState = .notStarted
    private var scheduleCalendarDaysCache: [ScheduleCalendarCacheKey: [MyTeamCalendarDay]] = [:]
    private var scheduleGamesByDayCache: [ScheduleCalendarCacheKey: [String: [GameDetail]]] = [:]
    private var localStandingsProbabilitySignalsByTeamID: [String: LocalStandingsProbabilitySignal] = [:]
    private var localStandingsProbabilityRefreshTask: Task<Void, Never>?
    private var localStandingsProbabilityGeneration = 0
    private var standingsSnapshotCacheBySeason: [Int: [TeamStandingsSnapshot]] = [:]
    private var standingsSourceGamesBySeason: [Int: [GameDetail]] = [:]
    private var inFlightStandingsTasks: [Int: Task<Void, Never>] = [:]
    private let isRunningTests: Bool

    init(
        repository: any KBORepository = MockKBORepository(),
        repositoryRuntimeState: RepositoryRuntimeState? = nil,
        notificationRegistrationClient: any NotificationRegistrationClient = NoOpNotificationRegistrationClient(),
        liveActivityController: (any FavoriteTeamLiveActivityControlling)? = nil,
        bootstrap: KBOBootstrapData? = nil,
        usePersistedSettings: Bool = true,
        currentDateProvider: @escaping CurrentDateProvider = Date.init,
        cancellationNotificationScheduler: @escaping GameCancellationNotificationScheduler = { request in
            try await UNUserNotificationCenter.current().add(request)
        }
    ) {
        self.repository = repository
        self.repositoryRuntimeState = repositoryRuntimeState
        self.notificationRegistrationClient = notificationRegistrationClient
        self.cancellationNotificationScheduler = cancellationNotificationScheduler
        self.currentDateProvider = currentDateProvider
        #if canImport(ActivityKit)
        self.liveActivityController = liveActivityController ?? FavoriteTeamLiveActivityManager()
        #else
        self.liveActivityController = liveActivityController ?? NoOpFavoriteTeamLiveActivityController()
        #endif
        self.usesPersistedSettings = usePersistedSettings
        let persistedSettings = usePersistedSettings ? AppModelPersistenceStore.loadSettings() : nil
        let persistedOnboardingCompletion = usePersistedSettings ? AppModelPersistenceStore.loadOnboardingCompletion() : nil
        let persistedDeviceToken = usePersistedSettings ? AppModelPersistenceStore.loadDeviceToken() : nil
        let persistedNotificationHistory = usePersistedSettings ? AppModelPersistenceStore.loadNotificationHistory() : []
        let persistedAttendedGameKeys = usePersistedSettings ? AppModelPersistenceStore.loadAttendedGameKeys() : []
        let persistedCancellationNotificationKeys = usePersistedSettings ? AppModelPersistenceStore.loadCancellationNotificationKeys() : []
        let hasPersistedFavoriteTeam = Self.canonicalTeamIdentifier(persistedSettings?.favoriteTeamID) != nil
        let initialHasCompletedOnboarding: Bool
        self.hasPersistedSettingsAtLaunch = persistedSettings != nil
        if let persistedOnboardingCompletion {
            initialHasCompletedOnboarding = persistedOnboardingCompletion
        } else if usePersistedSettings == false {
            initialHasCompletedOnboarding = true
        } else {
            // Upgrade compatibility: if an existing user already had a persisted favorite team,
            // treat onboarding as completed even when the explicit flag is absent.
            initialHasCompletedOnboarding = hasPersistedFavoriteTeam
        }
        self.hasCompletedOnboarding = initialHasCompletedOnboarding
        var initialSettings = persistedSettings ?? .default
        if initialHasCompletedOnboarding == false {
            initialSettings.favoriteTeamID = nil
        }
        initialSettings.favoriteTeamID = Self.canonicalTeamIdentifier(initialSettings.favoriteTeamID)
        self.settings = initialSettings
        self.debugActiveDataSource = "목 데이터"
        self.debugDeliverySource = "목 데이터"
        self.debugBaseURL = nil
        self.debugBootstrapAPIEnabled = "비활성"
        self.debugBootstrapETag = "없음"
        self.debugBootstrapLastFetchAt = nil
        self.debugBootstrapLastWriteAt = nil
        self.debugBootstrapLastResult = "비활성"
        self.debugLocalBootstrapSource = "확인 전"
        self.debugLocalBootstrapMessage = nil
        self.debugLocalBootstrapPath = Self.localBootstrapDocumentsPath() ?? "확인 불가"
        self.debugLocalBootstrapResolvedPath = nil
        self.debugLocalBootstrapLoadedAt = nil
        self.apnsDeviceToken = persistedDeviceToken
        self.attendedGameKeys = persistedAttendedGameKeys
        self.notifiedCancellationKeys = persistedCancellationNotificationKeys
        self.notificationRegistrationEndpointDescription = notificationRegistrationClient.debugEndpointDescription
        self.liveActivitySupported = self.liveActivityController.isSupported
        self.notificationRegistrationSyncStatus = persistedDeviceToken == nil ? .waitingForToken : .idle
        self.isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.notifications = persistedNotificationHistory
        FavoriteTeamScheduleWidgetShared.saveFavoriteTeamID(initialSettings.favoriteTeamID)
        if let bootstrap {
            apply(bootstrap, refreshProbabilitySignalsSynchronously: isRunningTests)
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

        if teams.isEmpty {
            teams = Self.catalogTeams()
        }
        hasLoaded = true

        guard settings.favoriteTeamID != nil else {
            #if DEBUG
            print("[AppStartup] skipped team/home refresh reason=noFavoriteTeam")
            #endif
            isLoading = false
            return
        }

        await refreshFavoriteTeamGameForHome(reason: "launch", bypassingCache: true)
        await syncFavoriteTeamLiveActivity()
        await syncFavoriteTeamWidgetSnapshot(includePrefetch: false)
        isLoading = false
    }

    private func apply(
        _ bootstrap: KBOBootstrapData,
        refreshProbabilitySignalsSynchronously: Bool = false
    ) {
        teams = bootstrap.teams
        games = bootstrap.games.sorted { $0.scheduledStart > $1.scheduledStart }
        notifications = mergedNotifications(with: bootstrap.notifications)
        invalidateScheduleDerivedCaches()
        if refreshProbabilitySignalsSynchronously {
            refreshLocalStandingsProbabilitySignalsSynchronously()
        } else {
            scheduleLocalStandingsProbabilityRefresh()
        }
        if !hasPersistedSettingsAtLaunch {
            settings = bootstrap.settings
        }
        normalizeFavoriteTeamSelectionIfNeeded()
    }

    private func normalizeFavoriteTeamSelectionIfNeeded() {
        guard let favoriteTeamID = Self.canonicalTeamIdentifier(settings.favoriteTeamID) else {
            if settings.favoriteTeamID != nil {
                settings.favoriteTeamID = nil
            }
            return
        }

        if settings.favoriteTeamID != favoriteTeamID {
            settings.favoriteTeamID = favoriteTeamID
        }

        if let canonical = teams.first(where: { Self.canonicalTeamIdentifier($0.id) == favoriteTeamID })?.id {
            if settings.favoriteTeamID != canonical {
                settings.favoriteTeamID = canonical
            }
            return
        }

        settings.favoriteTeamID = nil
    }

    private static func catalogTeams() -> [Team] {
        TeamIdentity.catalog.values
            .map { identity in
                Team(
                    id: identity.id,
                    name: identity.displayName,
                    shortName: identity.shortLabel,
                    englishName: identity.monogram,
                    markText: identity.monogram
                )
            }
            .sorted { $0.displayName < $1.displayName }
    }

    private func ensureCatalogTeamsLoadedIfNeeded() {
        guard teams.isEmpty else { return }
        teams = Self.catalogTeams()
        normalizeFavoriteTeamSelectionIfNeeded()
    }

    private func refreshFavoriteTeamGameForHome(
        reason: String,
        bypassingCache: Bool
    ) async {
        guard let favoriteTeamID = settings.favoriteTeamID else {
            #if DEBUG
            print("HomeFavoriteGameRefresh skipped reason=noFavoriteTeam")
            #endif
            return
        }
        guard let favoriteScheduleSource = repository as? any KBOFavoriteTeamScheduleDataSource else {
            #if DEBUG
            print("HomeFavoriteGameRefresh skipped reason=unsupportedRepository")
            #endif
            return
        }

        let dayKey = scheduleDayKey(for: currentDateProvider())
        let refreshKey = HomeFavoriteGameRefreshKey(dayKey: dayKey, favoriteTeamID: favoriteTeamID)
        if let existingTask = inFlightHomeFavoriteGameTasks[refreshKey] {
            #if DEBUG
            print("HomeFavoriteGameRefresh skipped reason=inFlight date=\(dayKey) favoriteTeamId=\(favoriteTeamID)")
            #endif
            await existingTask.value
            return
        }
        let shouldThrottleRecentRefresh = reason != "homeRefresh" && reason != "favoriteTeamSelected"
        if shouldThrottleRecentRefresh,
           let refreshedAt = lastHomeFavoriteGameRefreshAt[refreshKey],
           Date().timeIntervalSince(refreshedAt) < 15 {
            #if DEBUG
            print("HomeFavoriteGameRefresh skipped reason=recent date=\(dayKey) favoriteTeamId=\(favoriteTeamID)")
            #endif
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performFavoriteTeamGameRefreshForHome(
                reason: reason,
                favoriteTeamID: favoriteTeamID,
                refreshKey: refreshKey,
                favoriteScheduleSource: favoriteScheduleSource,
                bypassingCache: bypassingCache
            )
        }
        inFlightHomeFavoriteGameTasks[refreshKey] = task
        await task.value
        inFlightHomeFavoriteGameTasks[refreshKey] = nil
    }

    private func performFavoriteTeamGameRefreshForHome(
        reason: String,
        favoriteTeamID: Team.ID,
        refreshKey: HomeFavoriteGameRefreshKey,
        favoriteScheduleSource: any KBOFavoriteTeamScheduleDataSource,
        bypassingCache: Bool
    ) async {
        do {
            let previousKnownGames = allKnownGames()
            let fetched = try await favoriteScheduleSource.fetchFavoriteTeamSchedule(
                date: currentDateProvider(),
                favoriteTeamId: favoriteTeamID,
                bypassingCache: bypassingCache
            )
            homeFavoriteTeamGames = fetched
            let upsertResult = upsertScheduleGamesIntoLocalStore(fetched)
            let cacheUpsertResult = await upsertScheduleGamesIntoRepositoryCache(fetched)
            let didChange = upsertResult.inserted > 0 ||
                upsertResult.updated > 0 ||
                cacheUpsertResult.inserted > 0 ||
                cacheUpsertResult.updated > 0
            if didChange {
                await notifyCancellationTransitions(previousGames: previousKnownGames, updatedGames: fetched)
                await notifyGameContentTransitions(previousGames: previousKnownGames, updatedGames: fetched)
            }
            await syncFavoriteTeamLiveActivity()
            if didChange {
                await syncFavoriteTeamWidgetSnapshot(includePrefetch: false)
            }
            markRefreshSuccess(for: .games, at: Date(), isStale: false)
            lastHomeFavoriteGameRefreshAt[refreshKey] = Date()
            await refreshRepositoryDebugInfo(dataSets: [.games])
        } catch is CancellationError {
            #if DEBUG
            print("HomeFavoriteGameRefresh cancelled reason=\(reason)")
            #endif
        } catch {
            #if DEBUG
            print("HomeFavoriteGameRefresh failed reason=\(reason) error=\(error)")
            #endif
            markRefreshFailure(for: .games, hasUsableData: !games.isEmpty)
        }
    }

    func refreshHome() async {
        await refreshFavoriteTeamGameForHome(reason: "homeRefresh", bypassingCache: true)
    }

    func refreshTodayOnForeground() async {
        guard hasLoaded else { return }
        await refreshFavoriteTeamGameForHome(reason: "foreground", bypassingCache: true)
        await syncFavoriteTeamLiveActivity()
        await syncFavoriteTeamWidgetSnapshot(includePrefetch: false)
    }

    func refreshMyTeam() async {
        await refreshGames(for: [.myTeam, .home])
    }

    func loadStandingsIfNeeded() async {
        let season = currentStandingsSeason()
        guard standingsSnapshotCacheBySeason[season] == nil,
              standingsSourceGamesBySeason[season] == nil else {
            return
        }
        let localRankCount = await loadLocalTeamRanks(season: season)
        guard localRankCount == 0 else { return }
        await bootstrapStandingsRankIfNeeded(season: season)
    }

    func refreshStandings() async {
        let season = currentStandingsSeason()
        await refreshStandings(season: season, logsBootstrapJoin: false)
    }

    private func bootstrapStandingsRankIfNeeded(season: Int) async {
        if let task = inFlightStandingsTasks[season] {
            #if DEBUG
            print("[StandingsRank] remote bootstrap skipped reason=inFlight season=\(season)")
            #endif
            await task.value
            return
        }

        #if DEBUG
        print("[StandingsRank] local empty bootstrap start season=\(season)")
        #endif
        await refreshStandings(season: season, logsBootstrapJoin: true)
    }

    private func refreshStandings(season: Int, logsBootstrapJoin: Bool) async {
        if let task = inFlightStandingsTasks[season] {
            #if DEBUG
            let inFlightLog = logsBootstrapJoin
                ? "[StandingsRank] remote bootstrap joined reason=inFlight season=\(season)"
                : "[StandingsCache] season=\(season) source=inFlight reason=awaitExistingFetch"
            print(inFlightLog)
            #endif
            await task.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefreshStandings(season: season)
        }
        inFlightStandingsTasks[season] = task
        await task.value
        inFlightStandingsTasks[season] = nil
    }

    private func performRefreshStandings(season: Int) async {
        ensureCatalogTeamsLoadedIfNeeded()
        if await refreshTeamRanksFromRemote(season: season) {
            return
        }

        await refreshStandingsFromGamesFallback(season: season, reason: "rankFetchUnavailable")
    }

    private func loadLocalTeamRanks(season: Int) async -> Int {
        guard let localRankCache = repository as? any KBOLocalTeamRankCacheDataSource else {
            #if DEBUG
            print("[StandingsRank] local load count=0")
            #endif
            return 0
        }
        let rows = await localRankCache.fetchLocalTeamRanks(season: season)
            .sorted { $0.rank < $1.rank }
        #if DEBUG
        print("[StandingsRank] local load count=\(rows.count)")
        #endif
        guard rows.isEmpty == false else { return 0 }
        standingsSnapshotCacheBySeason[season] = StandingsRowBuilder.makeSnapshots(from: rows, teams: teams)
        standingsSourceGamesBySeason[season] = nil
        #if DEBUG
        print("[StandingsRank] local render rows=\(standingsSnapshotCacheBySeason[season]?.count ?? 0) season=\(season)")
        #endif
        return rows.count
    }

    private func refreshTeamRanksFromRemote(season: Int) async -> Bool {
        guard let teamRankSource = repository as? any KBOTeamRankDataSource else {
            #if DEBUG
            print("[StandingsRank] fallback to games reason=unsupportedRepository")
            #endif
            return false
        }

        do {
            #if DEBUG
            print("[StandingsRank] remote fetch start view=team_rank_2026 season=\(season)")
            #endif
            let rows = try await teamRankSource.fetchTeamRanks(season: season)
                .sorted { $0.rank < $1.rank }
            #if DEBUG
            print("[StandingsRank] remote fetch success count=\(rows.count) season=\(season)")
            #endif

            guard rows.isEmpty == false else {
                #if DEBUG
                print("[StandingsRank] fallback to games reason=emptyRows")
                #endif
                return false
            }

            if let localRankCache = repository as? any KBOLocalTeamRankCacheUpserting {
                let count = await localRankCache.replaceLocalTeamRanks(rows, season: season)
                #if DEBUG
                print("[StandingsRank] remote cache write count=\(count) season=\(season)")
                #endif
                _ = await loadLocalTeamRanks(season: season)
            } else {
                standingsSnapshotCacheBySeason[season] = StandingsRowBuilder.makeSnapshots(from: rows, teams: teams)
                standingsSourceGamesBySeason[season] = nil
                #if DEBUG
                print("[StandingsRank] remote cache write count=0 season=\(season)")
                print("[StandingsRank] local render rows=\(standingsSnapshotCacheBySeason[season]?.count ?? 0) season=\(season)")
                #endif
            }

            markRefreshSuccess(for: .games, at: Date(), isStale: false)
            await refreshRepositoryDebugInfo(dataSets: [])
            return true
        } catch {
            #if DEBUG
            print("[StandingsRank] refresh failed keeping local data error=\(error)")
            #endif
            guard standingsSnapshotCacheBySeason[season]?.isEmpty != false else {
                markRefreshFailure(for: .games, hasUsableData: true)
                return true
            }
            #if DEBUG
            print("[StandingsRank] fallback to games reason=remoteError")
            #endif
            return false
        }
    }

    private func refreshStandingsFromGamesFallback(season: Int, reason: String) async {
        do {
            #if DEBUG
            print("[StandingsRank] fallback to games reason=\(reason)")
            #endif

            let sourceGames: [GameDetail]
            if let standingsGameSource = repository as? any KBOStandingsGameDataSource {
                sourceGames = try await standingsGameSource.fetchStandingsSource(season: season)
            } else {
                sourceGames = try await repository.fetchGames()
                    .filter { $0.isRegularSeason && $0.hasCompleteFinalScore }
            }

            let snapshot = await repositoryRuntimeState?.snapshot()
            let normalizedGames = await reconcileOfficialScheduleStartTimesIfNeeded(
                in: sourceGames,
                snapshot: snapshot
            )
            standingsSourceGamesBySeason[season] = normalizedGames
            standingsSnapshotCacheBySeason[season] = nil
            refreshLocalStandingsProbabilitySignals(for: normalizedGames)
            let refreshedAt = Date()
            markRefreshSuccess(for: .games, at: refreshedAt, isStale: false)
            await refreshRepositoryDebugInfo(dataSets: [])
            #if DEBUG
            print("[StandingsCache] season=\(season) source=games count=\(normalizedGames.count)")
            logGameDiagnostics(context: "refreshStandings")
            #endif
        } catch {
            markRefreshFailure(for: .games, hasUsableData: !games.isEmpty)
        }
    }

    private func currentStandingsSeason() -> Int {
        var calendar = calendar
        calendar.timeZone = scheduleTimeZone
        return calendar.component(.year, from: currentDateProvider())
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

    var debugBootstrapLastFetchText: String {
        guard let debugBootstrapLastFetchAt else { return "없음" }
        return debugBootstrapLastFetchAt.formatted(date: .omitted, time: .standard)
    }

    var debugBootstrapLastWriteText: String {
        guard let debugBootstrapLastWriteAt else { return "없음" }
        return debugBootstrapLastWriteAt.formatted(date: .omitted, time: .standard)
    }

    var debugLocalBootstrapLoadedText: String {
        guard let debugLocalBootstrapLoadedAt else { return "없음" }
        return debugLocalBootstrapLoadedAt.formatted(date: .omitted, time: .standard)
    }

    var notificationRegistrationLastAttemptText: String {
        guard let notificationRegistrationLastAttemptAt else { return "없음" }
        return notificationRegistrationLastAttemptAt.formatted(date: .omitted, time: .shortened)
    }

    var notificationRegistrationPayloadPreviewText: String {
        guard let payload = currentNotificationRegistrationPayload else { return "토큰 대기 중" }
        let favoriteTeam = payload.favoriteTeamID ?? "미설정"
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

    var isDoosanFavoriteSelected: Bool {
        Self.canonicalTeamIdentifier(settings.favoriteTeamID) == "doosan"
    }

    var favoriteTeam: Team? {
        teams.first { $0.id == settings.favoriteTeamID }
    }

    var shouldShowFavoriteTeamOnboarding: Bool {
        hasCompletedOnboarding == false
    }

    func completeFavoriteTeamOnboarding(with teamID: String) {
        #if DEBUG
        print("[FavoriteTeamOnboarding] selected favoriteTeamID=\(teamID)")
        #endif
        settings.favoriteTeamID = teamID
        guard hasCompletedOnboarding == false else { return }
        hasCompletedOnboarding = true
        persistOnboardingCompletion()
        Task { [weak self] in
            await self?.refreshFavoriteTeamGameForHome(reason: "favoriteTeamSelected", bypassingCache: true)
        }
    }

    var unreadNotificationsCount: Int {
        notifications.reduce(into: 0) { partialResult, item in
            if item.isRead == false {
                partialResult += 1
            }
        }
    }

    var todayGames: [GameDetail] {
        let todayKey = scheduleDayKey(for: currentDateProvider())
        return games.filter { scheduleDayKey(for: $0.scheduledStart) == todayKey }
            .sorted(by: todayGameComparator)
    }

    private var homeTodayGames: [GameDetail] {
        let todayKey = scheduleDayKey(for: currentDateProvider())
        let sourceGames = homeFavoriteTeamGames.isEmpty ? todayGames : homeFavoriteTeamGames
        return sourceGames.filter { scheduleDayKey(for: $0.scheduledStart) == todayKey }
            .sorted(by: todayGameComparator)
    }

    var filteredHomeGames: [GameSummary] {
        homeTodayGames
            .map { makeHomeSummary(from: $0) }
            .filter(matchesHomeFilter)
            .sorted(by: homeSummaryComparator)
    }

    var filteredHomeGameDetails: [GameDetail] {
        homeTodayGames
            .filter { matchesHomeFilter(makeHomeSummary(from: $0)) }
            .sorted { lhs, rhs in
                homeSummaryComparator(makeHomeSummary(from: lhs), makeHomeSummary(from: rhs))
            }
    }

    var homeFallbackStandingsSnapshots: [TeamStandingsSnapshot] {
        HomeFallbackStandingsBuilder.makeSnapshots(
            teams: teams,
            referenceCompletedGames: homeFallbackReferenceWeekCompletedGames,
            seasonGames: regularSeasonGames,
            previousRankProvider: previousRegularSeasonRank
        )
    }

    var homeFallbackTitleText: String {
        guard homeFallbackWeekNumber != nil else {
            return "직전 완료 경기 기준 순위"
        }
        return "주간 순위"
    }

    var homeFallbackSubtitleText: String {
        guard homeFallbackWeekNumber != nil else {
            return "오늘 경기가 없어 기준일 이전 완료 경기로 표시합니다."
        }
        return "오늘 경기가 없어 직전주차 기준 순위를 표시합니다."
    }

    var todayGamesCount: Int {
        homeTodayGames.count
    }

    var liveGamesCount: Int {
        homeTodayGames.filter { $0.status.isLiveLike }.count
    }

    var myGamesCount: Int {
        homeTodayGames.filter { $0.involves(teamID: settings.favoriteTeamID) }.count
    }

    var myTeamTodayGame: GameDetail? {
        homeTodayGames.first { $0.involves(teamID: settings.favoriteTeamID) }
    }

    private var homeFallbackWeekNumber: Int? {
        let completedGames = homeFallbackCompletedRegularSeasonGamesBeforeToday
        guard let latestCompletedGameDate = completedGames.map(\.scheduledStart).max(),
              let latestWeekStart = homeFallbackWeekStart(for: latestCompletedGameDate) else {
            return nil
        }

        let orderedWeekStarts = Array(
            Set(
                completedGames.compactMap { homeFallbackWeekStart(for: $0.scheduledStart) }
            )
        ).sorted()

        guard let weekIndex = orderedWeekStarts.firstIndex(of: latestWeekStart) else {
            return nil
        }
        return weekIndex + 1
    }

    private var homeFallbackCompletedRegularSeasonGamesBeforeToday: [GameDetail] {
        let cutoffDate = homeFallbackScheduleCalendar.startOfDay(for: currentDateProvider())
        return regularSeasonGames
            .filter { $0.scheduledStart < cutoffDate }
            .filter(\.hasCompleteFinalScore)
    }

    private var homeFallbackReferenceWeekCompletedGames: [GameDetail] {
        let completedGames = homeFallbackCompletedRegularSeasonGamesBeforeToday
        guard let latestCompletedGameDate = completedGames.map(\.scheduledStart).max(),
              let referenceWeek = homeFallbackWeekInterval(for: latestCompletedGameDate) else {
            return []
        }

        return completedGames.filter { referenceWeek.contains($0.scheduledStart) }
    }

    var favoriteTeamLiveGame: GameDetail? {
        (homeFavoriteTeamGames.isEmpty ? games : homeFavoriteTeamGames)
            .first { $0.status.isLiveLike && $0.involves(teamID: settings.favoriteTeamID) }
    }

    private func makeHomeSummary(from game: GameDetail) -> GameSummary {
        HomeGameSummaryBuilder.makeSummary(
            game: game,
            teams: teams,
            favoriteTeamID: settings.favoriteTeamID
        )
    }

    private func homeFallbackWeekStart(for date: Date) -> Date? {
        homeFallbackWeekInterval(for: date)?.start
    }

    private var homeFallbackScheduleCalendar: Calendar {
        var weekCalendar = calendar
        weekCalendar.timeZone = scheduleTimeZone
        weekCalendar.firstWeekday = 2
        weekCalendar.minimumDaysInFirstWeek = 1
        return weekCalendar
    }

    private func homeFallbackWeekInterval(for date: Date) -> DateInterval? {
        homeFallbackScheduleCalendar.dateInterval(of: .weekOfYear, for: date)
    }

    var myTeamNextGame: GameDetail? {
        guard let favoriteTeamID = settings.favoriteTeamID else { return nil }
        let todayIdentity = myTeamTodayGame?.canonicalGameIdentityKey
        return games
            .filter {
                $0.involves(teamID: favoriteTeamID) &&
                    $0.status == .upcoming &&
                    $0.canonicalGameIdentityKey != todayIdentity
            }
            .sorted { $0.scheduledStart < $1.scheduledStart }
            .first
    }

    var myTeamRecentResult: GameDetail? {
        guard let favoriteTeamID = settings.favoriteTeamID else { return nil }
        let todayKey = scheduleDayKey(for: currentDateProvider())
        return games
            .filter {
                $0.involves(teamID: favoriteTeamID) &&
                    $0.status.isFinishedLike &&
                    scheduleDayKey(for: $0.scheduledStart) != todayKey
            }
            .sorted { $0.scheduledStart > $1.scheduledStart }
            .first
    }

    var myTeamAttendanceSummary: AttendedGameSummary {
        guard let favoriteTeamID = settings.favoriteTeamID else {
            return AttendedGameSummary(completedGames: 0, wins: 0, losses: 0, ties: 0)
        }

        var seenKeys: Set<String> = []
        var wins = 0
        var losses = 0
        var ties = 0

        for game in knownScheduleGames(filter: .myTeam) {
            let key = game.attendanceStorageKey
            guard seenKeys.insert(key).inserted,
                  isGameAttended(game) else {
                #if DEBUG
                debugLogAttendanceSummaryCandidate(game, favoriteTeamID: favoriteTeamID, result: nil, included: false)
                #endif
                continue
            }

            guard let result = game.finalResult(for: favoriteTeamID) else {
                #if DEBUG
                debugLogAttendanceSummaryCandidate(game, favoriteTeamID: favoriteTeamID, result: nil, included: false)
                #endif
                continue
            }

            #if DEBUG
            debugLogAttendanceSummaryCandidate(game, favoriteTeamID: favoriteTeamID, result: result, included: true)
            #endif

            switch result {
            case .win:
                wins += 1
            case .loss:
                losses += 1
            case .tie:
                ties += 1
            }
        }

        return AttendedGameSummary(
            completedGames: wins + losses + ties,
            wins: wins,
            losses: losses,
            ties: ties
        )
    }

    var regularSeasonGames: [GameDetail] {
        standingsCalculationGames.filter(\.isRegularSeason)
    }

    var standingsSnapshots: [TeamStandingsSnapshot] {
        let season = currentStandingsSeason()
        if let cached = standingsSnapshotCacheBySeason[season], cached.isEmpty == false {
            return cached.sorted { left, right in
                if left.rank != right.rank {
                    return left.rank < right.rank
                }
                return left.team.name.localizedStandardCompare(right.team.name) == .orderedAscending
            }
        }

        let rankedSnapshots = teams
            .map { makeStandingsSnapshot(for: $0, probabilitySignalsByTeamID: localStandingsProbabilitySignalsByTeamID) }
            .sorted(by: standingsComparator)

        return rankedSnapshots.enumerated().map { index, snapshot in
            TeamStandingsSnapshot(
                team: snapshot.team,
                rank: index + 1,
                wins: snapshot.wins,
                losses: snapshot.losses,
                ties: snapshot.ties,
                runsScored: snapshot.runsScored,
                runsAllowed: snapshot.runsAllowed,
                remainingRegularSeasonGames: snapshot.remainingRegularSeasonGames,
                recentResults: snapshot.recentResults,
                unknownClassificationGames: snapshot.unknownClassificationGames,
                rankingResolution: snapshot.rankingResolution,
                rankingResolutionPosition: snapshot.rankingResolutionPosition,
                postseasonQualificationProbability: snapshot.postseasonQualificationProbability,
                postseasonQualificationStatus: snapshot.postseasonQualificationStatus,
                postseasonProbabilityUnavailableReason: snapshot.postseasonProbabilityUnavailableReason
            )
        }
    }

    private var standingsCalculationGames: [GameDetail] {
        let season = currentStandingsSeason()
        return standingsSourceGamesBySeason[season] ?? games
    }

#if DEBUG
    var debugStandingsDiagnosticMessage: String? {
        if standingsSnapshotCacheBySeason[currentStandingsSeason()]?.isEmpty == false {
            return nil
        }
        let sourceGames = standingsCalculationGames
        let completedGames = sourceGames.filter(\.hasCompleteFinalScore)
        let completedRegularSeasonGames = regularSeasonGames.filter(\.hasCompleteFinalScore)
        let unknownCompletedGames = completedGames.filter { $0.seasonClassification == .unknown }

        if completedGames.isEmpty {
            return "디버그: 완료 경기 0건입니다. games 쿼리 결과 또는 상태 필터를 확인하세요."
        }

        if completedRegularSeasonGames.isEmpty {
            return "디버그: 완료 경기 \(completedGames.count)건, 정규시즌 완료 경기 0건, 미분류 완료 경기 \(unknownCompletedGames.count)건"
        }

        if let commonUnavailableReason = commonStandingsUnavailableReason {
            return "디버그: 정규시즌 완료 경기 \(completedRegularSeasonGames.count)건, 포스트시즌 확률 산출 불가 사유=\(commonUnavailableReason.rawValue)"
        }

        return nil
    }

    var debugHomeFallbackDiagnosticMessage: String? {
        guard todayGames.isEmpty, homeFallbackStandingsSnapshots.isEmpty else { return nil }

        let cutoffDate = homeFallbackScheduleCalendar.startOfDay(for: currentDateProvider())
        let completedGamesBeforeToday = games.filter { $0.hasCompleteFinalScore && $0.scheduledStart < cutoffDate }

        if completedGamesBeforeToday.isEmpty {
            return "디버그: 오늘 이전 완료 경기 0건입니다. 요청 범위 또는 상태 필터를 확인하세요."
        }

        let unknownCompletedGames = completedGamesBeforeToday.filter { $0.seasonClassification == .unknown }
        return "디버그: 오늘 이전 완료 경기 \(completedGamesBeforeToday.count)건, 홈 폴백용 정규시즌 완료 경기 \(homeFallbackCompletedRegularSeasonGamesBeforeToday.count)건, 미분류 완료 경기 \(unknownCompletedGames.count)건"
    }
#endif

    func scheduleGames(on date: Date, filter: ScheduleFilter) -> [GameDetail] {
        let selectedDayKey = scheduleDayKey(for: date)
        let dayGames = groupedScheduleGamesByDay(for: date, filter: filter)[selectedDayKey] ?? []

        return ScheduleGameSelector.sortSelectedGames(dayGames, favoriteTeamID: settings.favoriteTeamID)
    }

    func myTeamGames(on date: Date) -> [GameDetail] {
        scheduleGames(on: date, filter: .myTeam)
    }

    func scheduleHasAvailableMonths(filter: ScheduleFilter) -> Bool {
        availableScheduleMonths(filter: filter).isEmpty == false
    }

    func isScheduleMonthAvailable(_ date: Date, filter: ScheduleFilter) -> Bool {
        let monthStart = startOfMonth(for: date)
        return availableScheduleMonths(filter: filter).contains(monthStart)
    }

    func nearestScheduleMonth(to date: Date, filter: ScheduleFilter) -> Date? {
        let months = availableScheduleMonths(filter: filter)
        guard months.isEmpty == false else { return nil }

        let monthStart = startOfMonth(for: date)
        if let nextMonth = months.first(where: { $0 >= monthStart }) {
            return nextMonth
        }
        return months.last
    }

    func shiftedScheduleMonth(from date: Date, by offset: Int, filter: ScheduleFilter) -> Date? {
        let months = availableScheduleMonths(filter: filter)
        guard months.isEmpty == false else { return nil }

        let monthStart = startOfMonth(for: date)
        guard let currentIndex = months.firstIndex(of: monthStart) else {
            return nearestScheduleMonth(to: date, filter: filter)
        }

        let targetIndex = currentIndex + offset
        guard months.indices.contains(targetIndex) else { return nil }
        return months[targetIndex]
    }

    func scheduleCalendarDays(for month: Date, filter: ScheduleFilter) -> [MyTeamCalendarDay] {
        let cacheKey = makeScheduleCalendarCacheKey(for: month, filter: filter)
        if let cached = scheduleCalendarDaysCache[cacheKey] {
            return cached
        }

        let gamesByDayKey = groupedScheduleGamesByDay(for: month, filter: filter)
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
            let myTeamDayGames = calendarMyTeamGames(for: dayGames)
            days.append(
                MyTeamCalendarDay(
                    date: cursor,
                    isInDisplayedMonth: calendar.isDate(cursor, equalTo: monthStart, toGranularity: .month),
                    isToday: calendar.isDateInToday(cursor),
                    gameCount: dayGames.count,
                    hasAttendedGame: dayGames.contains(where: isGameAttended),
                    dominantStatus: dominantStatus(for: myTeamDayGames),
                    opponentTeam: calendarOpponentTeam(for: dayGames, filter: filter),
                    favoriteTeamIsHome: calendarFavoriteTeamIsHome(for: dayGames, filter: filter),
                    favoriteTeamResult: calendarFavoriteTeamResult(for: myTeamDayGames)
                )
            )
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = nextDay
        }
        scheduleCalendarDaysCache[cacheKey] = days
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
        ensureCatalogTeamsLoadedIfNeeded()
        await loadMyTeamSchedule(for: month, forceRefresh: false)
    }

    func refreshSchedule(for month: Date) async {
        ensureCatalogTeamsLoadedIfNeeded()
        await loadMyTeamSchedule(for: month, forceRefresh: true)
    }

    func fetchIsolatedScheduleMonth(
        for key: KBOMonthScheduleKey,
        bypassingCache: Bool
    ) async throws -> [GameDetail] {
        ensureCatalogTeamsLoadedIfNeeded()
        let fetched = try await repository.fetchMonthlySchedule(for: key, bypassingCache: bypassingCache)
        let snapshot = await repositoryRuntimeState?.snapshot()
        let normalized = await reconcileOfficialScheduleStartTimesIfNeeded(
            in: fetched,
            snapshot: snapshot
        )
        return normalized.sorted { $0.scheduledStart < $1.scheduledStart }
    }

    func currentScheduleMonthSnapshot(for key: KBOMonthScheduleKey) -> [GameDetail] {
        mergeMonthlyScheduleGames(fallbackMonthSchedule(for: key), for: key)
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    func loadScheduleDayIfNeeded(for date: Date) async {
        ensureCatalogTeamsLoadedIfNeeded()
        await loadScheduleDay(for: date, forceRefresh: false)
    }

    func refreshScheduleDay(for date: Date) async {
        ensureCatalogTeamsLoadedIfNeeded()
        await loadScheduleDay(for: date, forceRefresh: true)
    }

    private func loadScheduleDay(for date: Date, forceRefresh: Bool) async {
        let dayKey = scheduleDayKey(for: date)
        let todayKey = scheduleDayKey(for: currentDateProvider())
        let monthKey = KBOMonthScheduleKey(date: date, calendar: calendar)
        if let inFlightMonthTask = inFlightScheduleMonthTasks[monthKey] {
            #if DEBUG
            print("[ScheduleCache] month=\(monthKey.yearMonthText) source=inFlight reason=awaitExistingFetch")
            #endif
            await inFlightMonthTask.value
        }
        let hasLoadedMonth = monthlyScheduleGames[monthKey] != nil
        let localDayGames = groupedScheduleGamesByDay(for: date, filter: .all)[dayKey] ?? []

        let shouldFetch: Bool
        let reason: String

        if forceRefresh {
            shouldFetch = dayKey == todayKey
            reason = dayKey == todayKey ? "manualTodayRefresh" : "manualLocalOnly"
        } else if dayKey == todayKey {
            shouldFetch = false
            reason = localDayGames.isEmpty ? "todayLocalOnlyMissing" : "todayCached"
        } else if dayKey < todayKey {
            let isStableCompletedDay = localDayGames.isEmpty == false && localDayGames.allSatisfy { $0.status == .final || $0.status == .cancelled }
            if isStableCompletedDay {
                shouldFetch = false
                reason = "pastCompleted"
            } else if hasLoadedMonth, localDayGames.isEmpty {
                shouldFetch = false
                reason = "noScheduledGames"
            } else {
                shouldFetch = false
                reason = localDayGames.isEmpty ? "pastMissingLocalOnly" : "pastIncompleteLocal"
            }
        } else {
            if localDayGames.isEmpty == false {
                shouldFetch = false
                reason = "futureCached"
            } else if hasLoadedMonth {
                shouldFetch = false
                reason = "noScheduledGames"
            } else {
                shouldFetch = false
                reason = "futureMissingLocalOnly"
            }
        }

        guard shouldFetch else {
            #if DEBUG
            print("[ScheduleCache] selectedDate=\(dayKey) source=local reason=\(reason) gameCount=\(localDayGames.count)")
            #endif
            return
        }

        await refreshTodayGamesFromSupabase(for: date, monthKey: monthKey, reason: reason)
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
        game(withIdentity: gameID.uuidString)
    }

    func initialGameSnapshot(for gameIdentity: String) -> GameDetail? {
        game(withIdentity: gameIdentity)
    }

    func game(withIdentity gameIdentity: String) -> GameDetail? {
        selectedGameMatch(for: gameIdentity)?.game
    }

    func resolveGameDetailSelection(for gameIdentity: String) async -> GameDetail? {
        if let match = selectedGameMatch(for: gameIdentity) {
            #if DEBUG
            print("[GameDetailFetch] selectedGame resolved selectedIdentity=\(gameIdentity) id=\(match.game.publicGameID ?? match.game.canonicalGameIdentityValue) reason=\(match.reason)")
            #endif
            return match.game
        }
        return await fetchSelectedGameFromRepository(for: gameIdentity)
    }

    func fetchIsolatedGameDetailSnapshot(
        for game: GameDetail,
        identity: String
    ) async -> GameDetail? {
        guard let detailSource = repository as? any KBOGameDetailSnapshotDataSource else {
            return game
        }
        do {
            return try await detailSource.fetchGameDetailSnapshot(
                for: game,
                identity: identity,
                cachedTeams: teams
            ) ?? game
        } catch is CancellationError {
            return game
        } catch {
            #if DEBUG
            print("[GameDetailFetch] failed stableIdentity=\(identity) error=\(error)")
            #endif
            return game
        }
    }

    @discardableResult
    func refreshGameDetail(for gameIdentity: String, forceRefresh: Bool = false) async -> GameDetail? {
        guard let selectedGame = await resolveGameDetailSelection(for: gameIdentity) else {
            #if DEBUG
            debugLogMissingSelectedGame(gameIdentity)
            #endif
            return nil
        }
        let stableRefreshKey = selectedGame.stableDetailIdentity
        if let existingTask = inFlightGameDetailRefreshTasks[stableRefreshKey] {
            #if DEBUG
            print("[GameDetailFetch] mode=singleGame selectedIdentity=\(gameIdentity) stableIdentity=\(stableRefreshKey) skipped=inFlight")
            #endif
            return await existingTask.value
        }
        if forceRefresh == false,
           let refreshedAt = lastGameDetailRefreshAt[stableRefreshKey],
           currentDateProvider().timeIntervalSince(refreshedAt) < Self.gameDetailFreshnessThreshold {
            #if DEBUG
            print("[GameDetailFetch] mode=singleGame selectedIdentity=\(gameIdentity) stableIdentity=\(stableRefreshKey) skipped=freshEnough")
            #endif
            return selectedGame
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return Optional(selectedGame) }
            return await self.performRefreshGameDetail(
                selectedGame: selectedGame,
                gameIdentity: gameIdentity,
                forceRefresh: forceRefresh
            )
        }
        inFlightGameDetailRefreshTasks[stableRefreshKey] = task
        let result = await task.value
        inFlightGameDetailRefreshTasks[stableRefreshKey] = nil
        lastGameDetailRefreshAt[stableRefreshKey] = currentDateProvider()
        return result
    }

    private func fetchSelectedGameFromRepository(for gameIdentity: String) async -> GameDetail? {
        #if DEBUG
        debugLogLocalCandidateMiss(gameIdentity)
        #endif
        guard let identitySource = repository as? any KBOGameIdentityResolutionDataSource else {
            #if DEBUG
            print("[GameDetailFetch] fallback failure selectedIdentity=\(gameIdentity) reason=unsupportedRepository")
            #endif
            return nil
        }

        do {
            guard let fetchedGame = try await identitySource.fetchGameDetailIdentitySnapshot(
                identity: gameIdentity,
                cachedTeams: teams
            ) else {
                #if DEBUG
                print("[GameDetailFetch] fallback failure selectedIdentity=\(gameIdentity) reason=noRows")
                #endif
                return nil
            }
            let upsertResult = upsertScheduleGamesIntoLocalStore([fetchedGame])
            let cacheUpsertResult = await upsertScheduleGamesIntoRepositoryCache([fetchedGame])
            refreshLoadedScheduleMonthsFromLocalStore(including: scheduleMonthKey(for: fetchedGame.scheduledStart))
            #if DEBUG
            print("[GameDetailFetch] fallback selectedGame resolved selectedIdentity=\(gameIdentity) publicGameID=\(fetchedGame.publicGameID ?? "<nil>") providerGameID=\(fetchedGame.providerGameID ?? "<nil>") officialProviderGameID=\(fetchedGame.officialProviderGameID ?? "<nil>") localInserted=\(upsertResult.inserted) localUpdated=\(upsertResult.updated) cacheInserted=\(cacheUpsertResult.inserted) cacheUpdated=\(cacheUpsertResult.updated)")
            #endif
            return game(withIdentity: fetchedGame.canonicalGameIdentityValue) ??
                game(withIdentity: gameIdentity) ??
                fetchedGame
        } catch is CancellationError {
            #if DEBUG
            print("[GameDetailFetch] fallback failure selectedIdentity=\(gameIdentity) reason=cancelled")
            #endif
            return nil
        } catch {
            #if DEBUG
            print("[GameDetailFetch] fallback failure selectedIdentity=\(gameIdentity) error=\(error)")
            #endif
            return nil
        }
    }

    private func performRefreshGameDetail(
        selectedGame: GameDetail,
        gameIdentity: String,
        forceRefresh: Bool
    ) async -> GameDetail? {
        guard let detailSource = repository as? any KBOGameDetailSnapshotDataSource else {
            #if DEBUG
            print("[GameDetailFetch] mode=singleGame selectedIdentity=\(gameIdentity) skipped=unsupportedRepository")
            #endif
            return selectedGame
        }

        #if DEBUG
            print("[GameDetailFetch] mode=singleGame selectedIdentity=\(gameIdentity) stableIdentity=\(selectedGame.stableDetailIdentity) start before=\(debugGameIdentifier(for: selectedGame)) status=\(selectedGame.status.rawValue) score=\(scoreDebugText(selectedGame)) inning=\(selectedGame.inningText ?? "<nil>") force=\(forceRefresh)")
        #endif

        do {
            let previousKnownGames = allKnownGames()
            guard let incomingGame = try await detailSource.fetchGameDetailSnapshot(
                for: selectedGame,
                identity: gameIdentity,
                cachedTeams: teams
            ) else {
                #if DEBUG
                print("[GameDetailFetch] mode=singleGame selectedIdentity=\(gameIdentity) fetched count=0 sharedUpdated=false")
                #endif
                return selectedGame
            }

            let upsertResult = upsertScheduleGamesIntoLocalStore([incomingGame])
            let cacheUpsertResult = await upsertScheduleGamesIntoRepositoryCache([incomingGame])
            refreshLoadedScheduleMonthsFromLocalStore(including: scheduleMonthKey(for: incomingGame.scheduledStart))
            let resolved = game(withIdentity: incomingGame.canonicalGameIdentityValue) ??
                game(withIdentity: gameIdentity) ??
                incomingGame
            let sharedUpdated = upsertResult.inserted > 0 ||
                upsertResult.updated > 0 ||
                cacheUpsertResult.inserted > 0 ||
                cacheUpsertResult.updated > 0
            #if DEBUG
            print("[GameDetailFetch] mode=singleGame selectedIdentity=\(gameIdentity) stableIdentity=\(selectedGame.stableDetailIdentity) completed changed=\(resolved != selectedGame) before=\(selectedGame.status.rawValue) \(scoreDebugText(selectedGame)) incoming=\(incomingGame.status.rawValue) \(scoreDebugText(incomingGame)) after=\(resolved.status.rawValue) \(scoreDebugText(resolved)) sharedUpdated=\(sharedUpdated) dateWideFetch=false")
            #endif
            await notifyCancellationTransitions(previousGames: previousKnownGames, updatedGames: [resolved])
            await notifyGameContentTransitions(previousGames: previousKnownGames, updatedGames: [resolved])
            await syncFavoriteTeamLiveActivity()
            await syncFavoriteTeamWidgetSnapshot(includePrefetch: false)
            return resolved
        } catch is CancellationError {
            #if DEBUG
            print("[GameDetailFetch] mode=singleGame selectedIdentity=\(gameIdentity) cancelled=true")
            #endif
            return selectedGame
        } catch {
            #if DEBUG
            print("[GameDetailFetch] mode=singleGame selectedIdentity=\(gameIdentity) failed error=\(error)")
            #endif
            return selectedGame
        }
    }

    func gameNavigationIdentity(for game: GameDetail) -> String {
        game.canonicalGameIdentityValue
    }

    func gameNavigationIdentity(for summary: GameSummary) -> String {
        game(withID: summary.id)?.canonicalGameIdentityValue ?? summary.id.uuidString
    }

    func shouldShowLiveActivityAction(for game: GameDetail) -> Bool {
        LiveActivityActionPresentation.shouldShow(
            game: game,
            favoriteTeamID: settings.favoriteTeamID
        )
    }

    func shouldAutoStartLiveActivity(for game: GameDetail) -> Bool {
        game.involves(teamID: settings.favoriteTeamID) &&
            LiveActivityAutoStartEligibility.isEligibleForAutomaticLiveActivityStart(
                game: game,
                now: currentDateProvider()
            )
    }

    func isLiveActivityOn(for gameID: UUID) -> Bool {
        activeLiveActivityGameID == gameID
    }

    func isLiveActivityActionEnabled(for game: GameDetail) -> Bool {
        LiveActivityActionPresentation.isEnabled(
            game: game,
            favoriteTeamID: settings.favoriteTeamID,
            liveActivitiesEnabled: settings.liveActivitiesEnabled,
            liveActivitySupported: liveActivitySupported
        )
    }

    func liveActivityButtonTitle(for game: GameDetail) -> String {
        LiveActivityActionPresentation.buttonTitle(
            game: game,
            favoriteTeamID: settings.favoriteTeamID,
            liveActivitiesEnabled: settings.liveActivitiesEnabled,
            liveActivitySupported: liveActivitySupported,
            isActive: isLiveActivityOn(for: game.id)
        )
    }

    func liveActivityButtonSystemImage(for game: GameDetail) -> String {
        LiveActivityActionPresentation.buttonSystemImage(isActive: isLiveActivityOn(for: game.id))
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

    func startOrUpdateLiveActivityIfNeeded(for game: GameDetail) async {
        liveActivitySupported = liveActivityController.isSupported
        let resolvedGame = self.game(withIdentity: game.canonicalGameIdentityValue) ??
            self.game(withIdentity: game.stableDetailIdentity) ??
            game

        guard settings.liveActivitiesEnabled else {
            #if DEBUG
            logLiveActivityAutoStartSkipped(reason: "disabledInSettings", game: resolvedGame)
            #endif
            return
        }

        guard liveActivitySupported else {
            return
        }

        guard resolvedGame.involves(teamID: settings.favoriteTeamID) else {
            return
        }

        let eligibilityDecision = LiveActivityAutoStartEligibility.decision(
            for: resolvedGame,
            now: currentDateProvider()
        )
        guard eligibilityDecision == .eligible else {
            #if DEBUG
            logLiveActivityAutoStartSkipped(reason: eligibilityDecision.logReason, game: resolvedGame)
            #endif
            return
        }

        #if DEBUG
        print("[LiveActivityAutoStart] eligible gameID=\(resolvedGame.id.uuidString) status=\(resolvedGame.status.rawValue) scheduledAt=\(resolvedGame.scheduledStart)")
        #endif

        guard let snapshot = FavoriteTeamLiveActivitySnapshot.make(from: resolvedGame, favoriteTeamID: settings.favoriteTeamID) else {
            return
        }

        do {
            try await liveActivityController.startOrUpdate(using: snapshot)
            activeLiveActivityGameID = resolvedGame.id
        } catch {
            #if DEBUG
            print("[LiveActivityPayload] auto start/update failed gameID=\(resolvedGame.id.uuidString) error=\(error)")
            #endif
        }
    }

    #if DEBUG
    private func logLiveActivityAutoStartSkipped(reason: String, game: GameDetail) {
        print("[LiveActivityAutoStart] skipped reason=\(reason) gameID=\(game.id.uuidString) status=\(game.status.rawValue) scheduledAt=\(game.scheduledStart)")
    }
    #endif

    func isGameAlertEnabled(for gameID: UUID) -> Bool {
        gameAlertOverrides[gameID, default: true]
    }

    func setGameAlert(_ isEnabled: Bool, for gameID: UUID) {
        gameAlertOverrides[gameID] = isEnabled
    }

    func isGameAttended(_ game: GameDetail) -> Bool {
        AttendanceKeyResolver.isAttended(
            game: game,
            equivalentGames: equivalentGames(to: game),
            attendedKeys: attendedGameKeys
        )
    }

    func toggleGameAttendance(for game: GameDetail) {
        let equivalentGames = equivalentGames(to: game)
        let equivalentKeys = AttendanceKeyResolver.equivalentKeys(for: game, equivalentGames: equivalentGames)
        let key = AttendanceKeyResolver.canonicalStorageKey(for: game, equivalentKeys: equivalentKeys)
        let isAttended = attendedGameKeys.isDisjoint(with: equivalentKeys) == false
        attendedGameKeys = AttendanceKeyResolver.toggledKeys(
            for: game,
            equivalentGames: equivalentGames,
            attendedKeys: attendedGameKeys
        )
        #if DEBUG
        debugLogAttendanceToggle(game: game, storedKey: key, equivalentKeys: equivalentKeys, isAttended: !isAttended)
        #endif
        persistAttendedGameKeys()
        invalidateScheduleDerivedCaches()
    }

    func markNotificationRead(_ notificationID: UUID) {
        guard let index = notifications.firstIndex(where: { $0.id == notificationID }) else { return }
        notifications[index].isRead = true
        persistNotificationHistory()
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
        #if DEBUG
        print("[NotificationPipeline] authorizationStatus=\(notificationAuthorizationStatus.rawValue)")
        #endif
        scheduleNotificationRegistrationSync(force: true)
    }

    func syncNotificationRegistrationState() async {
        guard shouldShowFavoriteTeamOnboarding == false,
              settings.favoriteTeamID != nil else {
            #if DEBUG
            print("[AppStartup] skipped notification registration reason=noFavoriteTeam")
            #endif
            return
        }
        await refreshNotificationAuthorizationStatus()
        if notificationAuthorizationStatus.allowsNotifications {
            #if DEBUG
            print("[NotificationPipeline] registerForRemoteNotifications called")
            #endif
            UIApplication.shared.registerForRemoteNotifications()
        }
        scheduleNotificationRegistrationSync(force: false)
    }

    func requestNotificationAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshNotificationAuthorizationStatus()
            #if DEBUG
            print("[NotificationPipeline] requestAuthorization granted=\(granted)")
            #endif
            guard granted else { return }
            #if DEBUG
            print("[NotificationPipeline] registerForRemoteNotifications called")
            #endif
            UIApplication.shared.registerForRemoteNotifications()
            scheduleNotificationRegistrationSync(force: true)
        } catch {
            await refreshNotificationAuthorizationStatus()
            #if DEBUG
            print("[NotificationPipeline] requestAuthorization failed error=\(error)")
            #endif
        }
    }

    func scheduleDebugNotification() async {
        #if DEBUG
        let targetGame = myTeamTodayGame ?? todayGames.first ?? games.first
        let payload = ScoreNotificationPayload(
            gameID: targetGame.map { resolvedRawGameID(for: $0) },
            eventType: .scoreChange,
            title: "테스트 스코어 알림",
            body: targetGame.map { "\($0.awayTeam.displayName) vs \($0.homeTeam.displayName) 상세로 이동합니다." } ?? "게임 상세 이동 경로를 확인합니다.",
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
        if let existingTask = inFlightScheduleMonthTasks[key] {
            #if DEBUG
            print("[ScheduleCache] month=\(key.yearMonthText) source=inFlight reason=awaitExistingFetch")
            #endif
            await existingTask.value
            return
        }

        let loadID = UUID().uuidString
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performLoadMyTeamSchedule(
                for: month,
                key: key,
                forceRefresh: forceRefresh,
                loadID: loadID
            )
        }
        inFlightScheduleMonthTasks[key] = task
        await task.value
        inFlightScheduleMonthTasks[key] = nil
    }

    private func performLoadMyTeamSchedule(
        for month: Date,
        key: KBOMonthScheduleKey,
        forceRefresh: Bool,
        loadID: String
    ) async {
        let hasLocalMonth = monthlyScheduleGames[key] != nil

        if forceRefresh == false, hasLocalMonth {
            #if DEBUG
            let logKey = "local:monthNavigation"
            if monthlyScheduleDecisionLogKeys[key] != logKey {
                print("[ScheduleCache] month=\(key.yearMonthText) source=local reason=monthNavigation")
                monthlyScheduleDecisionLogKeys[key] = logKey
            }
            #endif
            return
        }

        guard !loadingScheduleMonths.contains(key) else { return }

        loadingScheduleMonths.insert(key)
        defer { loadingScheduleMonths.remove(key) }

        let localReason = forceRefresh ? "manualRefreshLocal" : "monthNavigation"
        await loadScheduleMonthFromRepository(for: key, reason: localReason, loadID: loadID, bypassingCache: forceRefresh)
    }

    private func loadScheduleMonthFromRepository(
        for key: KBOMonthScheduleKey,
        reason: String,
        loadID: String,
        bypassingCache: Bool
    ) async {
        do {
            let previousKnownGames = allKnownGames()
            let fetched = try await repository.fetchMonthlySchedule(for: key, bypassingCache: bypassingCache)
            let snapshot = await refreshMonthlyScheduleDebugInfo(for: key)
            let normalized = await reconcileOfficialScheduleStartTimesIfNeeded(
                in: fetched,
                snapshot: snapshot
            )
            monthlyScheduleGames[key] = mergeMonthlyScheduleGames(normalized, for: key)
                .sorted { $0.scheduledStart < $1.scheduledStart }
            _ = upsertScheduleGamesIntoLocalStore(normalized)
            failedScheduleMonths.remove(key)
            invalidateScheduleDerivedCaches(for: key)
            #if DEBUG
            print("[ScheduleCache] month=\(key.yearMonthText) source=repository reason=\(reason) loadID=\(loadID) gameCount=\(monthlyScheduleGames[key]?.count ?? 0)")
            #endif
            await notifyCancellationTransitions(previousGames: previousKnownGames, updatedGames: monthlyScheduleGames[key] ?? [])
            await notifyGameContentTransitions(previousGames: previousKnownGames, updatedGames: monthlyScheduleGames[key] ?? [])
        } catch {
            failedScheduleMonths.insert(key)
            #if DEBUG
            print("[ScheduleCache] month=\(key.yearMonthText) source=repository reason=\(reason) failed error=\(error)")
            #endif
            await hydrateScheduleMonthFromLocalStore(for: key, reason: reason, loadID: loadID)
        }
    }

    private func hydrateScheduleMonthFromLocalStore(
        for key: KBOMonthScheduleKey,
        reason: String,
        loadID: String
    ) async {
        let previousKnownGames = allKnownGames()
        let todayKey = scheduleDayKey(for: currentDateProvider())
        let localTodayLiveGames = previousKnownGames.filter {
            scheduleDayKey(for: $0.scheduledStart) == todayKey && $0.status.isLiveLike
        }
        let fallback = fallbackMonthSchedule(for: key)
        let snapshot = await refreshMonthlyScheduleDebugInfo(for: key)
        let normalizedFallback = await reconcileOfficialScheduleStartTimesIfNeeded(
            in: fallback,
            snapshot: snapshot
        )
        monthlyScheduleGames[key] = mergeMonthlyScheduleGames(normalizedFallback, for: key)
            .sorted { $0.scheduledStart < $1.scheduledStart }
        failedScheduleMonths.remove(key)
        invalidateScheduleDerivedCaches(for: key)
        #if DEBUG
        print("[ScheduleCache] month=\(key.yearMonthText) source=local reason=\(reason) loadID=\(loadID) gameCount=\(monthlyScheduleGames[key]?.count ?? 0)")
        if scheduleMonthKey(for: currentDateProvider()) == key {
            let mergedTodayGames = monthlyScheduleGames[key]?.filter { scheduleDayKey(for: $0.scheduledStart) == todayKey } ?? []
            for liveGame in localTodayLiveGames {
                let resolved = equivalentGame(to: liveGame, in: mergedTodayGames) ?? liveGame
                let attemptedOverwrite = resolved.status != liveGame.status || resolved.awayScore != liveGame.awayScore || resolved.homeScore != liveGame.homeScore
                print("[ScheduleCache] todayLivePreserve attemptedOverwrite=\(attemptedOverwrite) id=\(debugGameIdentifier(for: resolved)) before=\(liveGame.status.rawValue) \(scoreDebugText(liveGame)) after=\(resolved.status.rawValue) \(scoreDebugText(resolved))")
            }
        }
        monthlyScheduleDecisionLogKeys[key] = "local:\(reason)"
        #endif
        await notifyCancellationTransitions(
            previousGames: previousKnownGames,
            updatedGames: monthlyScheduleGames[key] ?? []
        )
        await notifyGameContentTransitions(
            previousGames: previousKnownGames,
            updatedGames: monthlyScheduleGames[key] ?? []
        )
        await syncFavoriteTeamWidgetSnapshot(includePrefetch: false)
    }

    private func runStartupScheduleCountCheckIfNeeded() async {
        switch scheduleStartupSyncState {
        case .completed:
            #if DEBUG
            print("[ScheduleSync] startupCountCheck skipped state=completed")
            #endif
            return
        case .failedButDoNotRetryAutomatically:
            #if DEBUG
            print("[ScheduleSync] startupCountCheck skipped state=failedButDoNotRetryAutomatically")
            #endif
            return
        case .inFlight(let task):
            #if DEBUG
            print("[ScheduleSync] startupCountCheck source=inFlight awaitingExistingSync")
            #endif
            await task.value
            return
        case .notStarted:
            break
        }

        guard let scheduleSyncRepository = repository as? any KBOScheduleRemoteSyncDataSource else {
            #if DEBUG
            print("[ScheduleSync] startupCountCheck unsupported=true usingLocalOnly")
            #endif
            scheduleStartupSyncState = .completed
            return
        }

        #if DEBUG
        print("[ScheduleSync] startupCountCheck start")
        #endif
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performStartupScheduleCountCheck(repository: scheduleSyncRepository)
        }
        scheduleStartupSyncState = .inFlight(task)
        await task.value
    }

    private func performStartupScheduleCountCheck(
        repository scheduleSyncRepository: any KBOScheduleRemoteSyncDataSource
    ) async {
        do {
            let localGames = mergeEquivalentGames(games)
            let localCount = localGames.count
            let remoteCount = try await scheduleSyncRepository.fetchRemoteGameCount()
            #if DEBUG
            print("[ScheduleSync] localCount=\(localCount) remoteCount=\(remoteCount)")
            #endif

            guard localCount != remoteCount else {
                #if DEBUG
                print("[ScheduleSync] countsEqual=true usingLocalOnly")
                print("[ScheduleSync] startupCountCheck completed")
                #endif
                scheduleStartupSyncState = .completed
                return
            }

            #if DEBUG
            print("[ScheduleSync] countsDiffer=true syncingMissingGames")
            #endif
            let previousKnownGames = allKnownGames()
            let result = try await scheduleSyncRepository.fetchMissingScheduleGames(excludingKnownGames: localGames)
            let upsertResult = upsertScheduleGamesIntoLocalStore(result.games)
            refreshLoadedScheduleMonthsFromLocalStore()
            scheduleStartupSyncState = .completed
            #if DEBUG
            print(
                "[ScheduleSync] missingGamesFetched=\(result.games.count) inserted=\(upsertResult.inserted) " +
                "skippedExisting=\(upsertResult.skippedExisting) localCount=\(localCount) remoteCount=\(remoteCount)"
            )
            print("[ScheduleSync] startupCountCheck completed")
            #endif
            await notifyCancellationTransitions(previousGames: previousKnownGames, updatedGames: allKnownGames())
            await notifyGameContentTransitions(previousGames: previousKnownGames, updatedGames: allKnownGames())
            await syncFavoriteTeamWidgetSnapshot(includePrefetch: false)
        } catch {
            scheduleStartupSyncState = .failedButDoNotRetryAutomatically
            #if DEBUG
            print("[ScheduleSync] startupCountCheck failed usingLocalOnly error=\(error)")
            #endif
        }
    }

    private func refreshTodayGamesFromSupabase(
        for date: Date,
        monthKey: KBOMonthScheduleKey,
        reason: String
    ) async {
        let dayKey = scheduleDayKey(for: date)
        let todayKey = scheduleDayKey(for: currentDateProvider())
        guard dayKey == todayKey else {
            #if DEBUG
            print("[ScheduleCache] selectedDate=\(dayKey) source=local reason=\(reason) gameCount=\((groupedScheduleGamesByDay(for: date, filter: .all)[dayKey] ?? []).count)")
            #endif
            return
        }
        let explicitReasons: Set<String> = ["manualTodayRefresh", "manualRefresh", "liveActivity", "notification"]
        guard explicitReasons.contains(reason) else {
            #if DEBUG
            print("[ScheduleSync] todayLiveRefresh skipped date=\(dayKey) reason=\(reason)")
            #endif
            return
        }
        if let existingTask = inFlightTodayLiveRefreshTasks[dayKey] {
            #if DEBUG
            print("[ScheduleSync] todayLiveRefresh source=inFlight reason=awaitExistingFetch date=\(dayKey)")
            #endif
            await existingTask.value
            return
        }
        if reason != "manualTodayRefresh",
           let refreshedAt = lastTodayLiveRefreshAt[dayKey],
           Date().timeIntervalSince(refreshedAt) < 15 {
            #if DEBUG
            print("[ScheduleSync] todayLiveRefresh skipped date=\(dayKey) reason=recent")
            #endif
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefreshTodayGamesFromSupabase(
                for: date,
                monthKey: monthKey,
                dayKey: dayKey,
                todayKey: todayKey,
                reason: reason
            )
        }
        inFlightTodayLiveRefreshTasks[dayKey] = task
        await task.value
        inFlightTodayLiveRefreshTasks[dayKey] = nil
    }

    private func performRefreshTodayGamesFromSupabase(
        for date: Date,
        monthKey: KBOMonthScheduleKey,
        dayKey: String,
        todayKey: String,
        reason: String
    ) async {
        do {
            let previousKnownGames = allKnownGames()
            #if DEBUG
            print("[ScheduleSync] todayLiveRefresh start date=\(dayKey) reason=\(reason)")
            #endif
            let fetched = try await repository.fetchSchedule(for: date, bypassingCache: true)
            #if DEBUG
            print("[ScheduleSync] todayRefresh date=\(dayKey) fetched=\(fetched.count)")
            #endif
            let upsertResult = upsertScheduleGamesIntoLocalStore(fetched)
            let cacheUpsertResult = await upsertScheduleGamesIntoRepositoryCache(fetched)
            refreshLoadedScheduleMonthsFromLocalStore(including: monthKey)
            monthlyScheduleRefreshDayKeys[monthKey] = todayKey
            lastTodayLiveRefreshAt[dayKey] = Date()
            #if DEBUG
            print("[ScheduleSync] todayRefreshUpsert inserted=\(upsertResult.inserted) updated=\(upsertResult.updated) skippedExisting=\(upsertResult.skippedExisting)")
            print("[ScheduleSync] todayRefreshCacheUpsert inserted=\(cacheUpsertResult.inserted) updated=\(cacheUpsertResult.updated) skippedExisting=\(cacheUpsertResult.skippedExisting)")
            #endif
            await notifyCancellationTransitions(previousGames: previousKnownGames, updatedGames: fetched)
            await notifyGameContentTransitions(previousGames: previousKnownGames, updatedGames: fetched)
            await syncFavoriteTeamLiveActivity()
            await syncFavoriteTeamWidgetSnapshot(includePrefetch: false)
        } catch is CancellationError {
            #if DEBUG
            print("[ScheduleSync] todayRefresh date=\(dayKey) cancelled=true usingLocalOnly")
            #endif
        } catch {
            #if DEBUG
            print("[ScheduleSync] todayRefresh date=\(dayKey) failed usingLocalOnly error=\(error)")
            #endif
        }
    }

    private func upsertScheduleGamesIntoRepositoryCache(_ incomingGames: [GameDetail]) async -> (inserted: Int, updated: Int, skippedExisting: Int) {
        guard let localStore = repository as? any KBOLocalGameCacheUpserting else {
            return (0, 0, incomingGames.count)
        }
        return await localStore.upsertLocalGames(incomingGames)
    }

    private func upsertScheduleGamesIntoLocalStore(_ incomingGames: [GameDetail]) -> (inserted: Int, updated: Int, skippedExisting: Int) {
        var updatedGames = games
        var inserted = 0
        var updated = 0
        var skippedExisting = 0

        for candidate in incomingGames {
            let candidateAliases = identityAliases(for: candidate)
            if let existingIndex = updatedGames.firstIndex(where: { existing in
                identityAliases(for: existing).isDisjoint(with: candidateAliases) == false
            }) {
                let existing = updatedGames[existingIndex]
                let selected = preferredKnownScheduleGame(existing: existing, candidate: candidate)
                #if DEBUG
                logPitcherMerge(existing: existing, incoming: candidate, merged: selected)
                #endif
                if selected != existing {
                    updatedGames[existingIndex] = selected
                    updated += 1
                } else {
                    skippedExisting += 1
                }
            } else {
                updatedGames.append(candidate)
                inserted += 1
            }
        }

        let mergedGames = mergeEquivalentGames(updatedGames)
            .sorted { $0.scheduledStart > $1.scheduledStart }
        if mergedGames != games {
            games = mergedGames
            invalidateScheduleDerivedCaches()
            scheduleLocalStandingsProbabilityRefresh()
        }
        #if DEBUG
        print("[ScheduleSync] mergeSummary fetched=\(incomingGames.count) inserted=\(inserted) updated=\(updated) skipped=\(skippedExisting)")
        #endif
        return (inserted, updated, skippedExisting)
    }

#if DEBUG
    private func logPitcherMerge(existing: GameDetail, incoming: GameDetail, merged: GameDetail) {
        if existing.awayStartingPitcherName != merged.awayStartingPitcherName ||
            incoming.awayStartingPitcherName != merged.awayStartingPitcherName {
            print("pitcherMerge side=away before=\(existing.awayStartingPitcherName ?? "<nil>") incoming=\(incoming.awayStartingPitcherName ?? "<nil>") after=\(merged.awayStartingPitcherName ?? "<nil>")")
        }
        if existing.homeStartingPitcherName != merged.homeStartingPitcherName ||
            incoming.homeStartingPitcherName != merged.homeStartingPitcherName {
            print("pitcherMerge side=home before=\(existing.homeStartingPitcherName ?? "<nil>") incoming=\(incoming.homeStartingPitcherName ?? "<nil>") after=\(merged.homeStartingPitcherName ?? "<nil>")")
        }
    }
#endif

    private func refreshLoadedScheduleMonthsFromLocalStore(including key: KBOMonthScheduleKey? = nil) {
        var keys = Set(monthlyScheduleGames.keys)
        if let key {
            keys.insert(key)
        }
        for monthKey in keys {
            monthlyScheduleGames[monthKey] = mergeMonthlyScheduleGames(fallbackMonthSchedule(for: monthKey), for: monthKey)
                .sorted { $0.scheduledStart < $1.scheduledStart }
        }
        invalidateScheduleDerivedCaches()
    }

    private func scheduleMonthKey(for date: Date) -> KBOMonthScheduleKey {
        var scheduleCalendar = calendar
        scheduleCalendar.timeZone = scheduleTimeZone
        return KBOMonthScheduleKey(date: date, calendar: scheduleCalendar)
    }

    private func refreshMonthlyScheduleDebugInfo(for key: KBOMonthScheduleKey) async -> RepositoryDebugSnapshot? {
        guard let repositoryRuntimeState else { return nil }
        let snapshot = await repositoryRuntimeState.snapshot()
        monthlyScheduleDebugSnapshots[key] = snapshot
        applyRepositoryDebugSnapshot(snapshot)
        lastUpdatedAt = snapshot.lastRefreshAt ?? lastUpdatedAt
        return snapshot
    }

    private func refreshGames(for scopes: Set<RefreshScope>) async {
        guard activeRefreshScopes.isDisjoint(with: scopes) else { return }
        activeRefreshScopes.formUnion(scopes)
        defer { activeRefreshScopes.subtract(scopes) }

        do {
            if await shouldReloadBootstrapForLocalData() {
                try await reloadBootstrapFromRepository()
                if repositoryRuntimeState == nil {
                    let refreshedAt = Date()
                    markRefreshSuccess(for: .games, at: refreshedAt, isStale: false)
                    markRefreshSuccess(for: .notifications, at: refreshedAt, isStale: false)
                }
                await refreshRepositoryDebugInfo(dataSets: [.games, .notifications])
            } else {
                let previousKnownGames = allKnownGames()
                let fetchedGames = try await repository.fetchGames()
                let snapshot = await repositoryRuntimeState?.snapshot()
                games = await reconcileOfficialScheduleStartTimesIfNeeded(
                    in: fetchedGames,
                    snapshot: snapshot
                )
                await notifyCancellationTransitions(previousGames: previousKnownGames, updatedGames: games)
                await notifyGameContentTransitions(previousGames: previousKnownGames, updatedGames: games)
                scheduleLocalStandingsProbabilityRefresh()
                if repositoryRuntimeState == nil {
                    markRefreshSuccess(for: .games, at: Date(), isStale: false)
                }
                await refreshRepositoryDebugInfo(dataSets: [.games])
            }
            await refreshTodayGamesFromSupabase(
                for: currentDateProvider(),
                monthKey: scheduleMonthKey(for: currentDateProvider()),
                reason: scopes.contains(.home) ? "homeRefresh" : "refresh"
            )
            await syncFavoriteTeamLiveActivity()
            await syncFavoriteTeamWidgetSnapshot(includePrefetch: true)
        } catch {
            markRefreshFailure(for: .games, hasUsableData: !games.isEmpty)
        }
    }

    private func refreshNotifications(for scopes: Set<RefreshScope>) async {
        guard activeRefreshScopes.isDisjoint(with: scopes) else { return }
        activeRefreshScopes.formUnion(scopes)
        defer { activeRefreshScopes.subtract(scopes) }

        do {
            if await shouldReloadBootstrapForLocalData() {
                try await reloadBootstrapFromRepository()
                if repositoryRuntimeState == nil {
                    let refreshedAt = Date()
                    markRefreshSuccess(for: .games, at: refreshedAt, isStale: false)
                    markRefreshSuccess(for: .notifications, at: refreshedAt, isStale: false)
                }
                await refreshRepositoryDebugInfo(dataSets: [.games, .notifications])
            } else {
                notifications = mergedNotifications(with: try await repository.fetchNotifications())
                if repositoryRuntimeState == nil {
                    markRefreshSuccess(for: .notifications, at: Date(), isStale: false)
                }
                await refreshRepositoryDebugInfo(dataSets: [.notifications])
            }
        } catch {
            markRefreshFailure(for: .notifications, hasUsableData: !notifications.isEmpty)
        }
    }

    private func refreshRepositoryDebugInfo(dataSets: Set<RefreshDataSet>) async {
        guard let repositoryRuntimeState else { return }
        let snapshot = await repositoryRuntimeState.snapshot()
        applyRepositoryDebugSnapshot(snapshot)
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

    private func applyRepositoryDebugSnapshot(_ snapshot: RepositoryDebugSnapshot) {
        debugActiveDataSource = snapshot.activeSource.rawValue
        debugDeliverySource = snapshot.deliverySource.rawValue
        debugBaseURL = snapshot.baseURL
        debugBootstrapAPIEnabled = snapshot.bootstrapAPIEnabled ? "사용" : "비활성"
        debugBootstrapETag = snapshot.bootstrapRefreshETag ?? "없음"
        debugBootstrapLastFetchAt = snapshot.bootstrapLastFetchAt
        debugBootstrapLastWriteAt = snapshot.bootstrapLastWriteAt
        debugBootstrapLastResult = snapshot.bootstrapLastResult.rawValue
        debugLocalBootstrapSource = snapshot.localBootstrapSource?.rawValue ?? "사용 안 함"
        debugLocalBootstrapMessage = snapshot.localBootstrapMessage
        debugLocalBootstrapResolvedPath = snapshot.localBootstrapResolvedPath
        debugLocalBootstrapLoadedAt = snapshot.localBootstrapLoadedAt
    }

#if DEBUG
    private func debugGameIdentifier(for game: GameDetail) -> String {
        gameNoteValue("public_game_id", in: game.note) ??
            game.officialGameCenterID ??
            game.id.uuidString
    }

    private var commonStandingsUnavailableReason: PostseasonProbabilityUnavailableReason? {
        let reasons = Set(standingsSnapshots.compactMap(\.postseasonProbabilityUnavailableReason))
        guard reasons.count == 1 else { return nil }
        return reasons.first
    }

    private func logGameDiagnostics(context: String) {
        let sourceGames = standingsCalculationGames
        let completedGames = sourceGames.filter(\.hasCompleteFinalScore)
        let completedRegularSeasonGames = regularSeasonGames.filter(\.hasCompleteFinalScore)
        let fallbackCompletedGames = homeFallbackCompletedRegularSeasonGamesBeforeToday
        let preseasonGames = sourceGames.filter { $0.seasonClassification == .exhibitionPreseason }
        let postseasonGames = sourceGames.filter { $0.seasonClassification == .postseason }
        let unknownGames = sourceGames.filter { $0.seasonClassification == .unknown }
        let backend = debugBaseURL ?? "<none>"
        let standingsReason = commonStandingsUnavailableReason?.rawValue ?? "none"
        let homeReason = debugHomeFallbackDiagnosticMessage ?? "none"

        print("[StandingsDebug] context=\(context) backend=\(backend) schema=\(SupabaseConfiguration.exposedSchema) source=\(debugActiveDataSource) delivery=\(debugDeliverySource)")
        print("[StandingsDebug] endpoint=rest/v1/games standingsMode=local-calculation todayKST=\(scheduleDayKey(for: currentDateProvider())) gameCount=\(sourceGames.count) completedGames=\(completedGames.count) completedRegularSeasonGames=\(completedRegularSeasonGames.count)")
        print("[StandingsDebug] classificationCounts total=\(sourceGames.count) regularSeason=\(regularSeasonGames.count) preseason=\(preseasonGames.count) postseason=\(postseasonGames.count) unknown=\(unknownGames.count)")
        print("[StandingsDebug] homeFallbackCompletedGames=\(fallbackCompletedGames.count) homeFallbackSnapshots=\(homeFallbackStandingsSnapshots.count) standingsReason=\(standingsReason) homeReason=\(homeReason)")
        for (index, game) in unknownGames.prefix(5).enumerated() {
            print(
                "[StandingsDebug] unknownGameSample index=\(index + 1) providerGameID=\(game.providerGameID ?? "<nil>") scheduledStart=\(game.scheduledStart.ISO8601Format()) status=\(game.status.rawValue) note=\(game.note ?? "<nil>")"
            )
        }
    }
#endif

    private func shouldReloadBootstrapForLocalData() async -> Bool {
        if repository is BundledJSONKBORepository {
            return true
        }

        guard let repositoryRuntimeState else { return false }
        let snapshot = await repositoryRuntimeState.snapshot()
        return snapshot.localBootstrapSource != nil ||
            (snapshot.activeSource == .mock && snapshot.baseURL == nil)
    }

    private func reloadBootstrapFromRepository() async throws {
        let bootstrap = try await repository.fetchBootstrapData()
        if hasLoaded,
           let repositoryRuntimeState,
           (await repositoryRuntimeState.snapshot()).bootstrapLastResult == .notModified {
            return
        }
        let snapshot = await repositoryRuntimeState?.snapshot()
        let normalizedBootstrap = await reconcileOfficialScheduleStartTimesIfNeeded(
            in: bootstrap,
            snapshot: snapshot
        )
        let previousKnownGames = allKnownGames()
        apply(normalizedBootstrap)
        await notifyCancellationTransitions(previousGames: previousKnownGames, updatedGames: games)
        await notifyGameContentTransitions(previousGames: previousKnownGames, updatedGames: games)
        invalidateMonthlyScheduleCache()
    }

    private func invalidateMonthlyScheduleCache() {
        monthlyScheduleGames = [:]
        monthlyScheduleDebugSnapshots = [:]
        failedScheduleMonths = []
        monthlyScheduleRefreshDayKeys = [:]
        monthlyScheduleDecisionLogKeys = [:]
        inFlightScheduleMonthTasks = [:]
        scheduleStartupSyncState = .notStarted
        invalidateScheduleDerivedCaches()
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

    private static func localBootstrapDocumentsPath() -> String? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LocalBootstrapData.json", isDirectory: false)
            .path
    }

    private func staleStatusMessage(lastRefreshAt: Date?) -> String {
        guard let lastRefreshAt else {
            return "업데이트가 지연되고 있습니다."
        }
        return "업데이트 지연 · 마지막 갱신 \(lastRefreshAt.formatted(date: .omitted, time: .shortened))"
    }

    private static func canonicalTeamIdentifier(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else {
            return nil
        }

        let lowered = raw.lowercased()
        if TeamIdentity.catalog[lowered] != nil {
            return lowered
        }

        if let matched = TeamIdentity.catalog.first(where: { _, identity in
            identity.shortLabel.caseInsensitiveCompare(raw) == .orderedSame ||
            identity.monogram.caseInsensitiveCompare(raw) == .orderedSame ||
            identity.displayName == raw
        })?.key {
            return matched
        }

        return lowered
    }

    private func syncFavoriteTeamWidgetSnapshot(includePrefetch: Bool) async {
        guard settings.favoriteTeamID != nil else {
            guard lastFavoriteTeamWidgetSemanticKey != "nil" else { return }
            FavoriteTeamScheduleWidgetShared.saveState(favoriteTeamID: nil, snapshot: nil)
            lastFavoriteTeamWidgetSemanticKey = "nil"
            reloadFavoriteTeamWidgetTimelines()
            return
        }

        if includePrefetch {
            await prepareFavoriteTeamWidgetScheduleIfNeeded()
        }

        let snapshot = makeFavoriteTeamWidgetSnapshot()
        let semanticKey = FavoriteTeamWidgetSnapshotBuilder.semanticKey(
            favoriteTeamID: settings.favoriteTeamID,
            snapshot: snapshot
        )
        guard semanticKey != lastFavoriteTeamWidgetSemanticKey else { return }
        FavoriteTeamScheduleWidgetShared.saveState(favoriteTeamID: settings.favoriteTeamID, snapshot: snapshot)
        lastFavoriteTeamWidgetSemanticKey = semanticKey
        reloadFavoriteTeamWidgetTimelines()
    }

    private func prepareFavoriteTeamWidgetScheduleIfNeeded() async {
        guard settings.favoriteTeamID != nil else { return }

        let scheduleCalendar = widgetScheduleCalendar()
        let today = scheduleCalendar.startOfDay(for: Date())
        let requestedMonth = startOfMonth(for: today)

        await loadMyTeamSchedule(for: requestedMonth, forceRefresh: false)

        if let resolvedMonth = nearestScheduleMonth(to: requestedMonth, filter: .myTeam),
           scheduleCalendar.isDate(resolvedMonth, equalTo: requestedMonth, toGranularity: .month) == false {
            await loadMyTeamSchedule(for: resolvedMonth, forceRefresh: false)
        }
    }

    private func makeFavoriteTeamWidgetSnapshot(referenceDate: Date = Date()) -> FavoriteTeamScheduleWidgetSnapshot? {
        guard let favoriteTeam = favoriteTeamWidgetMetadata() else { return nil }

        let scheduleCalendar = widgetScheduleCalendar()
        let requestedMonth = startOfMonth(for: referenceDate)
        let hasAnyMyTeamGames = knownScheduleGames(filter: .myTeam).isEmpty == false
        let displayedMonth = nearestScheduleMonth(to: requestedMonth, filter: .myTeam) ?? requestedMonth
        let calendarDays = scheduleCalendarDays(for: displayedMonth, filter: .myTeam)

        if hasAnyMyTeamGames == false && games.isEmpty && monthlyScheduleGames.isEmpty {
            return nil
        }

        return FavoriteTeamWidgetSnapshotBuilder.makeSnapshot(
            teamID: favoriteTeam.id,
            teamName: favoriteTeam.name,
            teamShortName: favoriteTeam.shortName,
            displayedMonth: displayedMonth,
            monthTitle: calendarMonthTitle(for: displayedMonth),
            days: calendarDays,
            referenceDate: referenceDate,
            calendar: scheduleCalendar
        )
    }

    private func favoriteTeamWidgetMetadata() -> (id: String, name: String, shortName: String)? {
        guard let favoriteTeamID = settings.favoriteTeamID else { return nil }

        if let team = teams.first(where: { $0.id == favoriteTeamID }) {
            return (team.id, team.displayName, team.displayName)
        }

        if let identity = TeamIdentity.catalog[favoriteTeamID] {
            return (identity.id, identity.teamDisplayName, identity.teamDisplayName)
        }

        return (favoriteTeamID, favoriteTeamID.uppercased(), favoriteTeamID.uppercased())
    }

    private func widgetScheduleCalendar() -> Calendar {
        var scheduleCalendar = calendar
        scheduleCalendar.timeZone = scheduleTimeZone
        return scheduleCalendar
    }

    private func reloadFavoriteTeamWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: FavoriteTeamScheduleWidgetShared.widgetKind)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func persistSettings() {
        FavoriteTeamScheduleWidgetShared.saveState(
            favoriteTeamID: settings.favoriteTeamID,
            snapshot: FavoriteTeamScheduleWidgetShared.loadSnapshot()
        )
        guard usesPersistedSettings else { return }
        AppModelPersistenceStore.saveSettings(settings)
    }

    private func updateAPNsDeviceToken(_ token: String) {
        #if DEBUG
        print("[NotificationPipeline] APNs token stored prefix=\(token.prefix(12)) length=\(token.count)")
        #endif
        guard apnsDeviceToken != token else {
            scheduleNotificationRegistrationSync(force: false)
            return
        }

        apnsDeviceToken = token
        if usesPersistedSettings {
            AppModelPersistenceStore.saveDeviceToken(token)
        }
        scheduleNotificationRegistrationSync(force: true)
    }

    private func persistNotificationHistory() {
        guard usesPersistedSettings else { return }
        AppModelPersistenceStore.saveNotificationHistory(notifications)
    }

    private func mergedNotifications(with incoming: [NotificationItem]) -> [NotificationItem] {
        var byID: [UUID: NotificationItem] = [:]
        for item in notifications {
            byID[item.id] = item
        }
        for item in incoming {
            byID[item.id] = item
        }
        return byID.values.sorted { $0.sentAt > $1.sentAt }
    }

    private func persistAttendedGameKeys() {
        guard usesPersistedSettings else { return }
        AppModelPersistenceStore.saveAttendedGameKeys(attendedGameKeys)
    }

    private func persistCancellationNotificationKeys() {
        guard usesPersistedSettings else { return }
        AppModelPersistenceStore.saveCancellationNotificationKeys(notifiedCancellationKeys)
    }

    private func persistOnboardingCompletion() {
        guard usesPersistedSettings else { return }
        AppModelPersistenceStore.saveOnboardingCompletion(hasCompletedOnboarding)
    }

    func handleNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        guard let payload = ScoreNotificationPayloadExtractor.payload(from: userInfo) else { return }
        recordReceivedNotification(payload)
        routeNotification(payload)
    }

    private func recordReceivedNotification(_ payload: ScoreNotificationPayload) {
        let receivedAt = currentDateProvider()
        let item = NotificationHistoryBuilder.makeItem(from: payload, receivedAt: receivedAt)
        notifications.insert(item, at: 0)
        notifications = notifications.sorted { $0.sentAt > $1.sentAt }
        persistNotificationHistory()
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

    private func scheduleNotificationRegistrationSync(force _: Bool) {
        guard let payload = currentNotificationRegistrationPayload else {
            notificationRegistrationSyncStatus = .waitingForToken
            return
        }
        guard let favoriteTeamID = payload.favoriteTeamID,
              favoriteTeamID.isEmpty == false else {
            notificationRegistrationSyncStatus = .idle
            #if DEBUG
            print("[NotificationPipeline] registration skipped reason=noFavoriteTeam")
            #endif
            return
        }
        guard payload.alertTypes.isEmpty == false else {
            notificationRegistrationSyncStatus = .idle
            #if DEBUG
            print("[NotificationPipeline] registration skipped reason=notificationsDisabled favoriteTeamID=\(favoriteTeamID)")
            #endif
            return
        }
        guard notificationAuthorizationStatus == .authorized ||
                notificationAuthorizationStatus == .provisional else {
            notificationRegistrationSyncStatus = .idle
            #if DEBUG
            print("[NotificationPipeline] registration skipped reason=authorizationNotGranted status=\(notificationAuthorizationStatus.rawValue)")
            #endif
            return
        }

        let key = NotificationRegistrationKey(
            payload: payload,
            endpointDescription: notificationRegistrationClient.debugEndpointDescription
        )
        switch notificationRegistrationDeduplicationState.start(key) {
        case .skipInFlight:
            #if DEBUG
            print("[NotificationPipeline] registration skipped reason=inFlight key=\(key)")
            #endif
            return
        case .skipAlreadyRegistered:
            notificationRegistrationSyncStatus = .synced
            #if DEBUG
            print("[NotificationPipeline] registration skipped reason=alreadyRegistered key=\(key)")
            #endif
            return
        case .start(let keyChanged):
            if keyChanged {
                #if DEBUG
                print("[NotificationPipeline] registration key changed key=\(key)")
                #endif
            }
        }

        notificationRegistrationSyncTask = Task { [weak self] in
            await self?.performNotificationRegistrationSync(payload, key: key)
        }
    }

    private func performNotificationRegistrationSync(
        _ payload: NotificationRegistrationPayload,
        key: NotificationRegistrationKey
    ) async {
        notificationRegistrationSyncStatus = .syncing
        notificationRegistrationLastAttemptAt = Date()

        do {
            #if DEBUG
            print("[NotificationPipeline] registration request start endpoint=\(notificationRegistrationClient.debugEndpointDescription ?? "missing")")
            #endif
            let status = try await notificationRegistrationClient.syncRegistration(payload)
            notificationRegistrationSyncStatus = status
            #if DEBUG
            print("[NotificationPipeline] registration sync status=\(status.rawValue)")
            if status == .synced {
                print("[NotificationPipeline] backend token registration success")
            } else if status == .skipped {
                print("[NotificationPipeline] backend token registration skipped")
            }
            #endif
            notificationRegistrationDeduplicationState.complete(key, status: status)
        } catch {
            notificationRegistrationSyncStatus = .failed
            notificationRegistrationDeduplicationState.fail(key)
            #if DEBUG
            print("[NotificationPipeline] backend token registration failure error=\(error)")
            print("[NotificationPipeline] registration failure error=\(error)")
            #endif
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
        guard let activeGame = game(withID: activeGameID),
              shouldAutoStartLiveActivity(for: activeGame),
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
        if let officialGame = self.game(withIdentity: game.canonicalGameIdentityValue) {
            return officialGame.canonicalGameIdentityValue
        }
        return game.canonicalGameIdentityValue
    }

    private func homePriority(for summary: GameSummary) -> Int {
        HomeGameSelector.priority(for: summary)
    }

    private func matchesHomeFilter(_ summary: GameSummary) -> Bool {
        HomeGameSelector.matches(summary, filter: homeFilter)
    }

    private func homeSummaryComparator(_ lhs: GameSummary, _ rhs: GameSummary) -> Bool {
        HomeGameSelector.compare(lhs, rhs)
    }

    private func todayGameComparator(_ lhs: GameDetail, _ rhs: GameDetail) -> Bool {
        HomeGameSelector.compareTodayGames(lhs, rhs, favoriteTeamID: settings.favoriteTeamID)
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

    private func calendarMyTeamGames(for games: [GameDetail]) -> [GameDetail] {
        guard let favoriteTeamID = settings.favoriteTeamID else { return [] }
        return games.filter { $0.involves(teamID: favoriteTeamID) }
    }

    private func calendarOpponentTeam(for games: [GameDetail], filter: ScheduleFilter) -> Team? {
        guard filter == .myTeam, let favoriteTeamID = settings.favoriteTeamID else { return nil }

        for game in games {
            if game.awayTeam.id == favoriteTeamID {
                return game.homeTeam
            }
            if game.homeTeam.id == favoriteTeamID {
                return game.awayTeam
            }
        }

        return nil
    }

    private func calendarFavoriteTeamResult(for games: [GameDetail]) -> TeamGameResult? {
        for game in games {
            if let result = game.finalResult(for: settings.favoriteTeamID) {
                return result
            }
        }
        return nil
    }

    private func calendarFavoriteTeamIsHome(for games: [GameDetail], filter: ScheduleFilter) -> Bool? {
        guard filter == .myTeam, let favoriteTeamID = settings.favoriteTeamID else { return nil }

        for game in games {
            if game.homeTeam.id == favoriteTeamID {
                return true
            }
            if game.awayTeam.id == favoriteTeamID {
                return false
            }
        }

        return nil
    }

    private func makeStandingsSnapshot(
        for team: Team,
        probabilitySignalsByTeamID: [String: LocalStandingsProbabilitySignal] = [:]
    ) -> TeamStandingsSnapshot {
        let completedGames = regularSeasonGames
            .filter { $0.involves(teamID: team.id) }
            .filter(\.hasCompleteFinalScore)
            .sorted { $0.scheduledStart > $1.scheduledStart }
        return makeStandingsSnapshot(
            for: team,
            completedGames: completedGames,
            probabilitySignalsByTeamID: probabilitySignalsByTeamID,
            recentResultsLimit: 5
        )
    }

    private func makeStandingsSnapshot(
        for team: Team,
        completedGames: [GameDetail],
        probabilitySignalsByTeamID: [String: LocalStandingsProbabilitySignal] = [:],
        recentResultsLimit: Int = 5
    ) -> TeamStandingsSnapshot {
        StandingsCalculator.makeSnapshot(
            for: team,
            completedGames: completedGames,
            seasonGames: regularSeasonGames,
            probabilitySignalsByTeamID: probabilitySignalsByTeamID,
            recentResultsLimit: recentResultsLimit
        )
    }

    private func refreshLocalStandingsProbabilitySignalsSynchronously() {
        localStandingsProbabilityRefreshTask?.cancel()
        localStandingsProbabilitySignalsByTeamID = localPostseasonQualificationCalculator.makeSignals(
            teams: teams,
            games: standingsCalculationGames
        )
    }

    private func refreshLocalStandingsProbabilitySignals(for sourceGames: [GameDetail]) {
        localStandingsProbabilityRefreshTask?.cancel()
        localStandingsProbabilityGeneration += 1
        localStandingsProbabilitySignalsByTeamID = localPostseasonQualificationCalculator.makeSignals(
            teams: teams,
            games: sourceGames
        )
    }

    private func scheduleLocalStandingsProbabilityRefresh() {
        guard standingsSourceGamesBySeason[currentStandingsSeason()] == nil else { return }
        localStandingsProbabilityRefreshTask?.cancel()
        localStandingsProbabilityGeneration += 1
        let generation = localStandingsProbabilityGeneration
        let teams = teams
        let games = standingsCalculationGames
        let calculator = localPostseasonQualificationCalculator

        localStandingsProbabilitySignalsByTeamID = [:]
        localStandingsProbabilityRefreshTask = Task(priority: .utility) { [weak self] in
            let signals = await Task.detached(priority: .utility) {
                calculator.makeSignals(teams: teams, games: games)
            }.value

            await MainActor.run {
                guard let self,
                      self.localStandingsProbabilityGeneration == generation else {
                    return
                }
                self.localStandingsProbabilitySignalsByTeamID = signals
                self.localStandingsProbabilityRefreshTask = nil
            }
        }
    }

    private func standingsComparator(_ lhs: TeamStandingsSnapshot, _ rhs: TeamStandingsSnapshot) -> Bool {
        StandingsSorter.compare(lhs, rhs, previousRankProvider: previousRegularSeasonRank)
    }

    private func previousRegularSeasonRank(for team: Team) -> Int? {
        if let previousRegularSeasonRank = team.previousRegularSeasonRank {
            return previousRegularSeasonRank
        }
        guard let teamID = Self.canonicalTeamIdentifier(team.id) else {
            return nil
        }
        return Self.previousRegularSeasonRankByTeamID[teamID]
    }

    private func notifyGameContentTransitions(
        previousGames: [GameDetail],
        updatedGames: [GameDetail]
    ) async {
        guard notificationAuthorizationStatus.allowsNotifications else {
            return
        }
        #if DEBUG
        print("[NotificationPipeline] authorizationStatus=\(notificationAuthorizationStatus.rawValue)")
        #endif
        guard let favoriteTeamID = settings.favoriteTeamID else {
            #if DEBUG
            print("[NotificationPipeline] skipped reason=noFavoriteTeam")
            #endif
            return
        }

        for updatedGame in updatedGames where updatedGame.involves(teamID: favoriteTeamID) && isTodayInKorea(updatedGame) {
            let key = updatedGame.canonicalGameIdentityKey
            let hadPreviousState = equivalentGame(to: updatedGame, in: previousGames) != nil || lastNotifiedGameStates[key] != nil
            let currentState = GameContentNotificationState(game: updatedGame)
            lastNotifiedGameStates[key] = currentState
            #if DEBUG
            print("[NotificationPipeline] skipped reason=backendDriven game=\(debugGameIdentifier(for: updatedGame)) hadPreviousState=\(hadPreviousState)")
            #endif
        }
    }

    private func notificationEvent(
        previous: GameContentNotificationState,
        current: GameContentNotificationState
    ) -> ScoreNotificationEventType? {
        if previous.awayScore != current.awayScore || previous.homeScore != current.homeScore {
            return .scoreChange
        }
        if current.status.isLiveLike,
           nonBlank(current.currentBatterName) != nil,
           nonBlank(current.currentPitcherName) != nil,
           baseOccupancyCount(current.bases) > baseOccupancyCount(previous.bases),
           (current.outs ?? previous.outs ?? 0) <= (previous.outs ?? current.outs ?? 0) {
            return .onBase
        }
        return nil
    }

    private func notificationPreferenceAllows(_ event: ScoreNotificationEventType) -> Bool {
        switch event {
        case .gameStart:
            return settings.notificationPreferences.gameStart
        case .scoreChange:
            return settings.notificationPreferences.scoreChange
        case .onBase:
            return settings.notificationPreferences.scoreChange
        case .leadChange:
            return settings.notificationPreferences.leadChange
        case .gameEnd:
            return settings.notificationPreferences.gameEnd
        case .inningChange:
            return settings.notificationPreferences.inningChangeEnabled
        case .rainDelay:
            return settings.notificationPreferences.rainDelay
        case .general:
            return true
        }
    }

    private func baseOccupancyCount(_ bases: RunnerState?) -> Int {
        guard let bases else { return 0 }
        return (bases.first ? 1 : 0) + (bases.second ? 1 : 0) + (bases.third ? 1 : 0)
    }

    private func baseFingerprint(_ bases: RunnerState?) -> String {
        guard let bases else { return "---" }
        return "\(bases.first ? "1" : "-")\(bases.second ? "2" : "-")\(bases.third ? "3" : "-")"
    }

    private func notifyCancellationTransitions(
        previousGames: [GameDetail],
        updatedGames: [GameDetail]
    ) async {
        guard notificationAuthorizationStatus.allowsNotifications else {
            return
        }
        guard settings.notificationPreferences.rainDelay,
              let favoriteTeamID = settings.favoriteTeamID else {
            #if DEBUG
            print("[NotificationPipeline] skipped reason=cancellationGuard authorization=\(notificationAuthorizationStatus.rawValue)")
            #endif
            return
        }

        var attemptedFingerprints: Set<String> = []
        for updatedGame in updatedGames {
            guard updatedGame.involves(teamID: favoriteTeamID),
                  isTodayInKorea(updatedGame),
                  let currentState = cancellationNotificationState(for: updatedGame),
                  let previousGame = equivalentGame(to: updatedGame, in: previousGames) else {
                continue
            }

            let previousState = cancellationNotificationState(for: previousGame)
            guard previousState != currentState else { continue }

            let fingerprint = cancellationNotificationFingerprint(for: updatedGame, state: currentState)
            #if DEBUG
            print("[NotificationPipeline] candidate event=rainDelay game=\(debugGameIdentifier(for: updatedGame))")
            #endif
            guard notifiedCancellationKeys.contains(fingerprint) == false,
                  attemptedFingerprints.insert(fingerprint).inserted else {
                #if DEBUG
                print("[NotificationPipeline] skipped reason=duplicate event=rainDelay")
                #endif
                continue
            }

            let request = cancellationNotificationCoordinator.makeRequest(
                for: updatedGame,
                favoriteTeam: favoriteTeam,
                fingerprint: fingerprint,
                isWeatherRelated: currentState.isWeatherRelated
            )

            do {
                try await cancellationNotificationScheduler(request)
                notifiedCancellationKeys.insert(fingerprint)
                persistCancellationNotificationKeys()
                #if DEBUG
                print("[NotificationPipeline] scheduled id=\(request.identifier) event=rainDelay")
                #endif
            } catch {
                #if DEBUG
                print("[NotificationPipeline] skipped reason=scheduleFailed event=rainDelay error=\(error)")
                #endif
                continue
            }
        }
    }

    private func cancellationNotificationState(for game: GameDetail) -> GameCancellationNotificationState? {
        switch game.status {
        case .cancelled:
            return GameCancellationNotificationState(
                status: game.status,
                isWeatherRelated: isWeatherRelatedCancellation(game)
            )
        case .rainDelay:
            return GameCancellationNotificationState(status: game.status, isWeatherRelated: true)
        case .upcoming, .live, .final:
            return nil
        }
    }

    private func cancellationNotificationFingerprint(
        for game: GameDetail,
        state: GameCancellationNotificationState
    ) -> String {
        [
            game.canonicalGameIdentityKey,
            scheduleDayKey(for: game.scheduledStart),
            state.status.rawValue,
            state.isWeatherRelated ? "weather" : "generic"
        ].joined(separator: "|")
    }

    private func equivalentGame(to game: GameDetail, in candidates: [GameDetail]) -> GameDetail? {
        let lookupAliases = identityAliases(for: game)
        return candidates.reduce(nil) { preferred, candidate in
            guard identityAliases(for: candidate).isDisjoint(with: lookupAliases) == false else {
                return preferred
            }
            return preferredKnownScheduleGame(existing: preferred, candidate: candidate)
        }
    }

    private func isTodayInKorea(_ game: GameDetail) -> Bool {
        scheduleDayKey(for: game.scheduledStart) == scheduleDayKey(for: currentDateProvider())
    }

    private func isWeatherRelatedCancellation(_ game: GameDetail) -> Bool {
        let text = ([game.note, game.highlightText, game.inningText].compactMap { $0 } + game.events.map(\.headline))
            .joined(separator: " ")
            .lowercased()
        let weatherTokens = ["우천", "강우", "폭우", "호우", "기상", "rain", "weather"]
        return weatherTokens.contains { text.contains($0) }
    }

    private func availableScheduleMonths(filter: ScheduleFilter) -> [Date] {
        let monthStarts = knownScheduleGames(filter: filter)
            .map { startOfMonth(for: $0.scheduledStart) }

        return Array(Set(monthStarts)).sorted()
    }

    private func knownScheduleGames(filter: ScheduleFilter) -> [GameDetail] {
        let mergedGames = mergeEquivalentGames(games + monthlyScheduleGames.values.flatMap { $0 })
        switch filter {
        case .all:
            return mergedGames
        case .myTeam:
            guard let favoriteTeamID = settings.favoriteTeamID else { return [] }
            return mergedGames.filter { $0.involves(teamID: favoriteTeamID) }
        }
    }

    private func mergeMonthlyScheduleGames(_ monthGames: [GameDetail], for key: KBOMonthScheduleKey) -> [GameDetail] {
        let stateGamesInMonth = games.filter {
            let components = calendar.dateComponents([.year, .month], from: $0.scheduledStart)
            return components.year == key.year && components.month == key.month
        }
        return mergeEquivalentGames(monthGames + stateGamesInMonth)
    }

    private func mergeEquivalentGames(_ sourceGames: [GameDetail]) -> [GameDetail] {
        var gamesByMergeKey: [String: GameDetail] = [:]
        var mergeKeyByAlias: [String: String] = [:]

        for candidate in sourceGames {
            let candidateAliases = identityAliases(for: candidate)
            let mergeKey = candidateAliases
                .compactMap { mergeKeyByAlias[$0] }
                .sorted()
                .first ?? candidate.canonicalGameIdentityKey

            let selected = preferredKnownScheduleGame(existing: gamesByMergeKey[mergeKey], candidate: candidate)
            gamesByMergeKey[mergeKey] = selected

            let selectedAliases = identityAliases(for: selected)
            for alias in candidateAliases.union(selectedAliases) {
                mergeKeyByAlias[alias] = mergeKey
            }
        }

        return Array(gamesByMergeKey.values)
    }

    private func preferredKnownScheduleGame(existing: GameDetail?, candidate: GameDetail) -> GameDetail {
        guard let existing else { return candidate }
        let stateSource = preferredGameStateSource(existing: existing, candidate: candidate)
        let supplementalSource = stateSource == candidate ? existing : candidate
        return GameDetail(
            id: existing.id,
            scheduledStart: stateSource.scheduledStart,
            venue: nonBlank(candidate.venue) ?? existing.venue,
            awayTeam: preferredTeam(candidate.awayTeam, fallback: existing.awayTeam),
            homeTeam: preferredTeam(candidate.homeTeam, fallback: existing.homeTeam),
            awayScore: stateSource.awayScore ?? supplementalSource.awayScore,
            homeScore: stateSource.homeScore ?? supplementalSource.homeScore,
            status: stateSource.status,
            seasonClassification: stateSource.seasonClassification == .unknown ? existing.seasonClassification : stateSource.seasonClassification,
            inningText: nonBlank(stateSource.inningText) ?? supplementalSource.inningText,
            bases: stateSource.bases,
            baseRunners: mergedBaseRunners(
                primary: stateSource.baseRunners,
                supplemental: supplementalSource.baseRunners,
                bases: stateSource.bases
            ),
            balls: stateSource.balls,
            strikes: stateSource.strikes,
            outs: stateSource.outs,
            highlightText: nonBlank(candidate.highlightText) ?? existing.highlightText,
            events: candidate.events.isEmpty ? existing.events : candidate.events,
            note: mergedGameNote(existing: existing.note, candidate: candidate.note),
            providerGameID: nonBlank(candidate.providerGameID) ?? existing.providerGameID,
            awayStartingPitcherName: nonBlank(candidate.awayStartingPitcherName) ?? existing.awayStartingPitcherName,
            homeStartingPitcherName: nonBlank(candidate.homeStartingPitcherName) ?? existing.homeStartingPitcherName,
            currentPitcherName: nonBlank(stateSource.currentPitcherName),
            currentBatterName: nonBlank(stateSource.currentBatterName)
        )
    }

    private func mergedBaseRunners(
        primary: GameBaseRunners?,
        supplemental: GameBaseRunners?,
        bases: RunnerState?
    ) -> GameBaseRunners? {
        guard let bases else {
            return primary ?? supplemental
        }
        let first = bases.first ? (nonBlank(primary?.first) ?? nonBlank(supplemental?.first)) : nil
        let second = bases.second ? (nonBlank(primary?.second) ?? nonBlank(supplemental?.second)) : nil
        let third = bases.third ? (nonBlank(primary?.third) ?? nonBlank(supplemental?.third)) : nil
        guard first != nil || second != nil || third != nil else {
            return nil
        }
        return GameBaseRunners(first: first, second: second, third: third)
    }

    private func preferredGameStateSource(existing: GameDetail, candidate: GameDetail) -> GameDetail {
        let candidatePriority = gameStateMergePriority(candidate)
        let existingPriority = gameStateMergePriority(existing)
        if candidatePriority != existingPriority {
            return candidatePriority > existingPriority ? candidate : existing
        }
        let candidateFreshness = freshnessDate(for: candidate)
        let existingFreshness = freshnessDate(for: existing)
        if let candidateFreshness, let existingFreshness, candidateFreshness != existingFreshness {
            return candidateFreshness > existingFreshness ? candidate : existing
        }
        if candidateFreshness != nil, existingFreshness == nil {
            return candidate
        }
        if candidate.hasCompleteFinalScore != existing.hasCompleteFinalScore {
            return candidate.hasCompleteFinalScore ? candidate : existing
        }
        let candidateHasProvider = candidate.officialGameCenterID != nil
        let existingHasProvider = existing.officialGameCenterID != nil
        if candidateHasProvider != existingHasProvider {
            return candidateHasProvider ? candidate : existing
        }
        return candidate
    }

    private func preferredTeam(_ candidate: Team, fallback: Team) -> Team {
        candidate.id.hasPrefix("unknown-") ? fallback : candidate
    }

    private func mergedGameNote(existing: String?, candidate: String?) -> String? {
        let components = [candidate, existing].compactMap(nonBlank)
        guard components.isEmpty == false else { return nil }

        var seen: Set<String> = []
        let merged = components
            .flatMap { $0.split(separator: " ").map(String.init) }
            .filter { seen.insert($0).inserted }
            .joined(separator: " ")
        return nonBlank(merged)
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func freshnessDate(for game: GameDetail) -> Date? {
        [
            gameNoteValue("live_last_checked_at", in: game.note),
            gameNoteValue("updated_at", in: game.note),
            gameNoteValue("source_updated_at", in: game.note)
        ]
        .compactMap(KBODateParser.parseTimestamp)
        .max()
    }

    private func gameNoteValue(_ key: String, in note: String?) -> String? {
        guard let note,
              let range = note.range(of: "\(key)=") else {
            return nil
        }
        let suffix = note[range.upperBound...]
        return suffix.split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map(String.init)
    }

    private func gameStateMergePriority(_ game: GameDetail) -> Int {
        switch game.status {
        case .final, .cancelled:
            return 3
        case .live, .rainDelay:
            return 2
        case .upcoming:
            return 1
        }
    }

    private func identityMatchDescription(existing: GameDetail, candidate: GameDetail) -> String {
        let sharedAliases = identityAliases(for: existing).intersection(identityAliases(for: candidate))
        let orderedPrefixes = [
            "provider:",
            "public:",
            "date-team:",
            "date-team-venue:",
            "match:",
            "id:"
        ]
        for prefix in orderedPrefixes {
            if let alias = sharedAliases.sorted().first(where: { $0.hasPrefix(prefix) }) {
                return alias
            }
        }
        return sharedAliases.sorted().first ?? "unknown"
    }

    private func scoreDebugText(_ game: GameDetail) -> String {
        "\(game.awayScore.map(String.init) ?? "-"):\(game.homeScore.map(String.init) ?? "-")"
    }

    private func baseDebugText(_ bases: RunnerState?) -> String {
        guard let bases else { return "---" }
        return [
            bases.first ? "1" : "-",
            bases.second ? "2" : "-",
            bases.third ? "3" : "-"
        ].joined()
    }

    private struct SelectedGameMatch {
        let game: GameDetail
        let priority: Int
        let token: String
        let reason: String
    }

    private func selectedGameMatch(for gameIdentity: String) -> SelectedGameMatch? {
        let requestTokens = GameIdentifier.requestedIdentityTokens(from: gameIdentity)
        guard requestTokens.isEmpty == false else { return nil }

        let matches = allKnownGames().compactMap { game -> SelectedGameMatch? in
            guard let match = GameIdentifier.bestMatch(
                requestTokens: requestTokens,
                candidateTokens: identityMatchTokens(for: game)
            ) else {
                return nil
            }
            return SelectedGameMatch(game: game, priority: match.priority, token: match.token, reason: match.reason)
        }

        guard let bestPriority = matches.map(\.priority).min() else { return nil }
        let bestMatches = matches.filter { $0.priority == bestPriority }
        let publicIDs = Set(bestMatches.compactMap { nonBlank($0.game.publicGameID) })
        if bestMatches.count > 1, publicIDs.count > 1 {
            #if DEBUG
            print("[GameDetailFetch] selectedGame ambiguous selectedIdentity=\(gameIdentity) priority=\(bestPriority) token=\(bestMatches.map(\.token).sorted().joined(separator: ",")) publicIDs=\(publicIDs.sorted().joined(separator: ","))")
            #endif
            return nil
        }

        let selected = bestMatches.reduce(nil as GameDetail?) { preferred, match in
            preferredKnownScheduleGame(existing: preferred, candidate: match.game)
        }
        guard let selected else { return nil }
        let reason = bestMatches.first?.reason ?? "unknown"
        let token = bestMatches.first?.token ?? ""
        return SelectedGameMatch(game: selected, priority: bestPriority, token: token, reason: reason)
    }

    #if DEBUG
    private func debugLogLocalCandidateMiss(_ gameIdentity: String) {
        let rawIdentifier = GameIdentifier.rawIdentifier(from: gameIdentity)
        let candidates = allKnownGames()
        let requestTokens = GameIdentifier.requestedIdentityTokens(from: gameIdentity)
            .sorted()
            .joined(separator: ",")
        print("[GameDetailFetch] selectedGame localMiss selectedIdentity=\(gameIdentity) rawIdentifier=\(rawIdentifier) candidateCount=\(candidates.count) requestedTokens=[\(requestTokens)]")
    }

    private func debugLogMissingSelectedGame(_ gameIdentity: String) {
        let rawIdentifier: String
        rawIdentifier = GameIdentifier.rawIdentifier(from: gameIdentity)
        let candidates = allKnownGames()
        let hasPublicIDs = candidates.contains { nonBlank($0.publicGameID) != nil }
        let hasProviderIDs = candidates.contains { nonBlank($0.providerGameID) != nil }
        let hasOfficialIDs = candidates.contains { nonBlank($0.officialProviderGameID) != nil }
        let requestTokens = GameIdentifier.requestedIdentityTokens(from: gameIdentity)
            .sorted()
            .joined(separator: ",")
        let candidateDescriptions = candidates.map { candidate in
            let tokens = identityMatchTokens(for: candidate)
                .map { "\($0.priority):\($0.value)" }
                .sorted()
                .joined(separator: "|")
            return "public=\(candidate.publicGameID ?? "<nil>") provider=\(candidate.providerGameID ?? "<nil>") official=\(candidate.officialProviderGameID ?? "<nil>") stable=\(candidate.stableDetailIdentity) tokens=[\(tokens)]"
        }
            .joined(separator: " ; ")
        print("[GameDetailFetch] mode=singleGame selectedIdentity=\(gameIdentity) rawIdentifier=\(rawIdentifier) skipped=noSelectedGame candidateCount=\(candidates.count) hasPublicIDs=\(hasPublicIDs) hasProviderIDs=\(hasProviderIDs) hasOfficialIDs=\(hasOfficialIDs) requestedTokens=[\(requestTokens)] candidates=\(candidateDescriptions)")
    }
    #endif

    private func equivalentGames(to game: GameDetail) -> [GameDetail] {
        var equivalentAliases = identityAliases(for: game)
        var didExpand = true

        while didExpand {
            didExpand = false
            for candidate in allKnownGames() {
                let candidateAliases = identityAliases(for: candidate)
                guard equivalentAliases.isDisjoint(with: candidateAliases) == false else { continue }
                let previousCount = equivalentAliases.count
                equivalentAliases.formUnion(candidateAliases)
                didExpand = equivalentAliases.count != previousCount
            }
        }

        return allKnownGames().filter { candidate in
            identityAliases(for: candidate).isDisjoint(with: equivalentAliases) == false
        }
    }

    private func allKnownGames() -> [GameDetail] {
        games + monthlyScheduleGames.values.flatMap { $0 }
    }

    private func identityAliases(for game: GameDetail) -> Set<String> {
        game.gameIdentityAliases
    }

    private func identityMatchTokens(for game: GameDetail) -> [GameIdentifier.IdentityMatchToken] {
        game.gameIdentityMatchTokens
    }

    #if DEBUG
    private func debugLogAttendanceToggle(game: GameDetail, storedKey: String, equivalentKeys: Set<String>, isAttended: Bool) {
    }

    private func debugLogAttendanceSummaryCandidate(
        _ game: GameDetail,
        favoriteTeamID: String,
        result: TeamGameResult?,
        included: Bool
    ) {
    }
    #endif

    private func makeScheduleCalendarCacheKey(for date: Date, filter: ScheduleFilter) -> ScheduleCalendarCacheKey {
        ScheduleCalendarCacheKey(
            month: KBOMonthScheduleKey(date: date, calendar: calendar),
            filter: filter,
            favoriteTeamID: settings.favoriteTeamID
        )
    }

    private func invalidateScheduleDerivedCaches(for month: KBOMonthScheduleKey? = nil) {
        guard let month else {
            scheduleCalendarDaysCache.removeAll()
            scheduleGamesByDayCache.removeAll()
            return
        }
        scheduleCalendarDaysCache = scheduleCalendarDaysCache.filter { $0.key.month != month }
        scheduleGamesByDayCache = scheduleGamesByDayCache.filter { $0.key.month != month }
    }

    private func groupedScheduleGamesByDay(for date: Date, filter: ScheduleFilter) -> [String: [GameDetail]] {
        let cacheKey = makeScheduleCalendarCacheKey(for: date, filter: filter)
        if let cached = scheduleGamesByDayCache[cacheKey] {
            return cached
        }

        let grouped = Dictionary(grouping: filteredScheduleGames(for: date, filter: filter)) { game in
            scheduleDayKey(for: game.scheduledStart)
        }
        scheduleGamesByDayCache[cacheKey] = grouped
        return grouped
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

    private func reconcileOfficialScheduleStartTimesIfNeeded(
        in games: [GameDetail],
        snapshot: RepositoryDebugSnapshot?
    ) async -> [GameDetail] {
        guard shouldReconcileOfficialScheduleStartTimes(snapshot: snapshot, games: games) else {
            return games
        }

        return await officialGameCenterClient.reconcileScheduledStartTimes(in: games)
    }

    private func reconcileOfficialScheduleStartTimesIfNeeded(
        in bootstrap: KBOBootstrapData,
        snapshot: RepositoryDebugSnapshot?
    ) async -> KBOBootstrapData {
        let normalizedGames = await reconcileOfficialScheduleStartTimesIfNeeded(
            in: bootstrap.games,
            snapshot: snapshot
        )
        return KBOBootstrapData(
            teams: bootstrap.teams,
            games: normalizedGames,
            notifications: bootstrap.notifications,
            settings: bootstrap.settings
        )
    }

    private func shouldReconcileOfficialScheduleStartTimes(
        snapshot: RepositoryDebugSnapshot?,
        games: [GameDetail]
    ) -> Bool {
        guard isRunningTests == false,
              games.isEmpty == false,
              let snapshot else {
            return false
        }

        if snapshot.activeSource != .live {
            return true
        }

        return snapshot.deliverySource != .live
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

private struct ScheduleCalendarCacheKey: Hashable {
    let month: KBOMonthScheduleKey
    let filter: ScheduleFilter
    let favoriteTeamID: String?
}

private enum ScheduleStartupSyncState {
    case notStarted
    case inFlight(Task<Void, Never>)
    case completed
    case failedButDoNotRetryAutomatically
}
