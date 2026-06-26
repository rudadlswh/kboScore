//
//  AppModel.swift
//  kboScore
//  기능 설명: 앱 전역 상태, 데이터 새로고침, 알림, 위젯, 라이브 액티비티 동기화를 관리합니다.
//  여러 화면과 시스템 기능이 같은 경기 데이터를 보도록 앱 전역 상태와 부수 효과를 한곳에서 조정합니다.
//  비동기 새로고침, 캐시, 알림, 위젯 갱신이 동시에 발생할 수 있어 중복 실행과 오래된 응답을 방어합니다.
//  TODO : 상태 전이를 더 작은 도메인 서비스로 나누고 관찰 가능한 부수 효과를 테스트로 고정합니다.
//
//  Created by Codex on 3/25/26.
//

import Foundation
import Observation
import UIKit
import UserNotifications
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

typealias GameCancellationNotificationScheduler = (UNNotificationRequest) async throws -> Void
typealias CurrentDateProvider = () -> Date

// RefreshScope 열거형는 RefreshScope 타입의 역할과 값을 정의합니다.
enum RefreshScope: Hashable, Sendable {
    case home
    case myTeam
    case notifications
}

// RefreshDataSet 열거형는 RefreshDataSet 타입의 역할과 값을 정의합니다.
private enum RefreshDataSet: Hashable {
    case games
    case notifications
}

// ScheduleGameMergeSource 열거형는 ScheduleGameMergeSource 타입의 역할과 값을 정의합니다.
private enum ScheduleGameMergeSource: String {
    case unspecified
    case scheduleMonthLoad
    case todayLiveRefresh
    case gameDetailRefresh
    case standingsRefresh
    case staleReconciliation
    case homeFavoriteRefresh
    case startupSync
}

private enum FavoriteTeamScheduleWidgetSnapshotSource: Int {
    case unspecified = 0
    case homeFavoriteRefresh = 100
    case todayLiveRefresh = 150
    case appModelMonthly = 300
    case scheduleTabCurrentMonth = 400

    var logName: String {
        switch self {
        case .unspecified:
            "unspecified"
        case .homeFavoriteRefresh:
            "homeFavoriteRefresh"
        case .todayLiveRefresh:
            "todayLiveRefresh"
        case .appModelMonthly:
            "appModelMonthly"
        case .scheduleTabCurrentMonth:
            "scheduleTabCurrentMonth"
        }
    }
}

private struct FavoriteTeamScheduleWidgetMonthSource {
    let monthKey: KBOMonthScheduleKey
    let games: [GameDetail]
    let source: FavoriteTeamScheduleWidgetSnapshotSource
    let updatedAt: Date
}

// HomeGameFilter 열거형는 HomeGameFilter 타입의 역할과 값을 정의합니다.
enum HomeGameFilter: String, CaseIterable, Identifiable {
    case all = "전체"
    case live = "라이브"
    case upcoming = "예정"
    case final = "종료"
    case myTeam = "마이팀"

    var id: String { rawValue }
}

// NotificationListFilter 열거형는 NotificationListFilter 타입의 역할과 값을 정의합니다.
enum NotificationListFilter: String, CaseIterable, Identifiable {
    case all = "전체"
    case myTeam = "마이팀"
    case score = "스코어"
    case final = "종료"
    case today = "오늘"

    var id: String { rawValue }
}

// ScheduleFilter 열거형는 ScheduleFilter 타입의 역할과 값을 정의합니다.
enum ScheduleFilter: String, CaseIterable, Identifiable {
    case all = "전체"
    case myTeam = "마이팀"

    var id: String { rawValue }
}

// AppTab 열거형는 AppTab 타입의 역할과 값을 정의합니다.
enum AppTab: Hashable, Sendable {
    case home
    case standings
    case schedule
    case attendance
    case settings
}

// HomeFavoriteGameRefreshKey 구조체는 HomeFavoriteGameRefreshKey 타입의 역할과 값을 정의합니다.
private struct HomeFavoriteGameRefreshKey: Hashable {
    let dayKey: String
    let favoriteTeamID: String
}

// RawSupabaseGameDetailIdentity 구조체는 RawSupabaseGameDetailIdentity 타입의 역할과 값을 정의합니다.
private struct RawSupabaseGameDetailIdentity: Sendable {
    let supabaseGameID: UUID
    let providerGameID: String?
    let publicGameID: String?
}

// GameDetailRefreshResult 구조체는 GameDetailRefreshResult 타입의 역할과 값을 정의합니다.
struct GameDetailRefreshResult: Sendable {
    let game: GameDetail
    let rawSupabaseGameID: UUID?
    let providerGameID: String?
    let publicGameID: String?
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
    private let liveActivityPushToStartTokenRegistrationClient: any LiveActivityPushToStartTokenRegistrationClient
    private let scheduleStaleGameReconciliationClient: any ScheduleStaleGameReconciliationClient
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
    private var notificationRegistrationSyncTaskKey: NotificationRegistrationKey?
    private var notificationRegistrationSyncGeneration = 0
    private var liveActivityPushToStartTokenObservationTask: Task<Void, Never>?
    private var registeredPushToStartTokenKeys: Set<LiveActivityPushToStartTokenRegistrationKey> = []
    private var lastLiveActivityPushToStartToken: String?
    private var lastNotifiedGameStates: [String: GameContentNotificationState] = [:]
    private var lastFavoriteTeamWidgetSemanticKey: String?
    private var lastFavoriteTeamWidgetSnapshot: FavoriteTeamScheduleWidgetSnapshot?
    private var favoriteTeamWidgetMonthSources: [KBOMonthScheduleKey: FavoriteTeamScheduleWidgetMonthSource] = [:]
    private var rawSupabaseGameDetailIdentities: [String: RawSupabaseGameDetailIdentity] = [:]

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
    private(set) var standingsSnapshots: [TeamStandingsSnapshot] = []
    private(set) var standingsRowsRevision = 0
    private(set) var homeFavoriteTeamGames: [GameDetail] = []
    var notifications: [NotificationItem] = []
    var selectedTab: AppTab = .home
    var presentedGameIdentity: String?
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
            if favoriteTeamChanged {
                invalidateScheduleDerivedCaches()
            }
            if oldValue.liveActivitiesEnabled != settings.liveActivitiesEnabled ||
                oldValue.liveActivityAutoStartEnabled != settings.liveActivityAutoStartEnabled ||
                oldValue.favoriteTeamID != settings.favoriteTeamID {
                Task { [weak self] in
                    await self?.registerLastKnownPushToStartTokenIfNeeded(reason: "settingsChanged")
                    await self?.syncFavoriteTeamLiveActivity()
                    await self?.syncFavoriteTeamWidgetSnapshot(
                        includePrefetch: true,
                        reason: favoriteTeamChanged ? "favoriteTeamChanged" : "settingsChanged"
                    )
                }
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
    private var inFlightGameDetailRefreshTasks: [String: Task<GameDetailRefreshResult?, Never>] = [:]
    private var inFlightGameDetailDatabaseReviewTasks: [String: Task<GameDetailDatabaseReviewFetchResult?, Never>] = [:]
    private var cachedGameDetailDatabaseReviewsByRequestKey: [String: GameDetailDatabaseReviewFetchResult] = [:]
    private var cachedGameDetailDatabaseReviewsByRawSupabaseID: [UUID: GameDetailDatabaseReviewFetchResult] = [:]
    private var lastGameDetailRefreshAt: [String: Date] = [:]
    private var inFlightHomeFavoriteGameTasks: [HomeFavoriteGameRefreshKey: Task<Void, Never>] = [:]
    private var lastHomeFavoriteGameRefreshAt: [HomeFavoriteGameRefreshKey: Date] = [:]
    private var inFlightTodayLiveRefreshTasks: [String: Task<[GameDetail], Never>] = [:]
    private var lastTodayLiveRefreshAt: [String: Date] = [:]
    private var inFlightScheduleStaleReconciliationTask: Task<Void, Error>?
    private var inFlightSchedulePostReconciliationRefreshDates: Set<String> = []
    private var recentlyReconciledScheduleDates: [String: Date] = [:]
    private let scheduleReconciliationCooldown: TimeInterval = 120
    private(set) var schedulePostReconciliationRefreshGeneration = 0
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

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    init(
        repository: any KBORepository = MockKBORepository(),
        repositoryRuntimeState: RepositoryRuntimeState? = nil,
        notificationRegistrationClient: any NotificationRegistrationClient = NoOpNotificationRegistrationClient(),
        liveActivityPushToStartTokenRegistrationClient: any LiveActivityPushToStartTokenRegistrationClient = NoOpLiveActivityPushToStartTokenRegistrationClient(),
        scheduleStaleGameReconciliationClient: any ScheduleStaleGameReconciliationClient = NoOpScheduleStaleGameReconciliationClient(),
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
        self.liveActivityPushToStartTokenRegistrationClient = liveActivityPushToStartTokenRegistrationClient
        self.scheduleStaleGameReconciliationClient = scheduleStaleGameReconciliationClient
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
            apply(bootstrap)
            hasLoaded = true
            let now = Date()
            lastSuccessfulRefresh[.games] = now
            lastSuccessfulRefresh[.notifications] = now
            lastUpdatedAt = now
        }
    }

    // loadIfNeeded 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else {
            logStandingsLocalCalculationSkipped(reason: "remoteRankSource", source: "loadIfNeededAlreadyLoaded")
            return
        }

        isLoading = true
        loadErrorMessage = nil

        if teams.isEmpty {
            teams = Self.catalogTeams()
        }
        hasLoaded = true
        logStandingsLocalCalculationSkipped(reason: "remoteRankSource", source: "launch")

        guard settings.favoriteTeamID != nil else {
            #if DEBUG
            print("[AppStartup] skipped team/home refresh reason=noFavoriteTeam")
            #endif
            isLoading = false
            return
        }

        await refreshFavoriteTeamGameForHome(reason: "launch", bypassingCache: true)
        await loadHomeFallbackStandingsSourceIfNeeded(reason: "launch")
        await syncFavoriteTeamLiveActivity()
        await syncFavoriteTeamWidgetSnapshot(includePrefetch: false)
        isLoading = false
    }

    // apply 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    private func apply(_ bootstrap: KBOBootstrapData) {
        teams = bootstrap.teams
        games = bootstrap.games.sorted { $0.scheduledStart > $1.scheduledStart }
        notifications = mergedNotifications(with: bootstrap.notifications)
        invalidateScheduleDerivedCaches()
        if !hasPersistedSettingsAtLaunch {
            settings = bootstrap.settings
        }
        normalizeFavoriteTeamSelectionIfNeeded()
        logStandingsLocalCalculationSkipped(reason: "remoteRankSource", source: "bootstrap")
    }

    // normalizeFavoriteTeamSelectionIfNeeded 메서드는 외부 값이나 원본 데이터를 앱에서 쓰는 형태로 변환합니다.
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

    // catalogTeams 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // ensureCatalogTeamsLoadedIfNeeded 메서드는 이 타입의 주요 동작을 수행합니다.
    private func ensureCatalogTeamsLoadedIfNeeded() {
        guard teams.isEmpty else { return }
        teams = Self.catalogTeams()
        normalizeFavoriteTeamSelectionIfNeeded()
    }

    // refreshFavoriteTeamGameForHome 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
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
        if HomeFavoriteGameRefreshPolicy.shouldSkipRecentRefresh(
            reason: reason,
            lastRefreshedAt: lastHomeFavoriteGameRefreshAt[refreshKey],
            now: Date()
        ) {
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

    // performFavoriteTeamGameRefreshForHome 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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
            let upsertResult = upsertScheduleGamesIntoLocalStore(fetched, source: .homeFavoriteRefresh)
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
                await syncFavoriteTeamWidgetSnapshot(
                    includePrefetch: false,
                    reason: "homeFavoriteRefresh",
                    monthKey: scheduleMonthKey(for: currentDateProvider())
                )
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

    // refreshHome 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    func refreshHome() async {
        await refreshFavoriteTeamGameForHome(reason: "homeRefresh", bypassingCache: true)
        await loadHomeFallbackStandingsSourceIfNeeded(reason: "homeRefresh")
    }

    // refreshTodayOnForeground 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    func refreshTodayOnForeground() async {
        await refreshTodayForLiveActivity(reason: "foreground", includeHomeFallback: true)
    }

    // refreshTodayForBackgroundLiveActivity 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    @discardableResult
    func refreshTodayForBackgroundLiveActivity(reason: String) async -> Bool {
        #if DEBUG
        print("[LiveActivityBackgroundRefresh] start reason=\(reason) localUpdateOnly=true limitation=iOSMaySuspendBeforeLocalUpdateCompletes")
        #endif
        let backgroundTaskID = UIApplication.shared.beginBackgroundTask(
            withName: "LiveActivityBackgroundRefresh"
        ) {
            #if DEBUG
            print("[LiveActivityBackgroundRefresh] expiration reason=\(reason) limitation=iOSRequestedSuspend")
            #endif
        }
        defer {
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
            }
        }

        let didAttemptRefresh = await refreshTodayForLiveActivity(
            reason: reason,
            includeHomeFallback: false
        )
        #if DEBUG
        print("[LiveActivityBackgroundRefresh] completed reason=\(reason) attempted=\(didAttemptRefresh) limitation=localUpdatesNotGuaranteedAfterSuspend")
        #endif
        return didAttemptRefresh
    }

    // refreshTodayForLiveActivity 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    @discardableResult
    private func refreshTodayForLiveActivity(reason: String, includeHomeFallback: Bool) async -> Bool {
        guard hasLoaded else {
            #if DEBUG
            print("[LiveActivityBackgroundRefresh] skipped reason=\(reason) appLoaded=false")
            #endif
            return false
        }
        await refreshFavoriteTeamGameForHome(reason: reason, bypassingCache: true)
        _ = await refreshTodayGamesFromSupabase(
            for: currentDateProvider(),
            monthKey: scheduleMonthKey(for: currentDateProvider()),
            reason: "liveActivity"
        )
        await refreshActiveLiveActivityGameDetailIfNeeded(reason: reason)
        if includeHomeFallback {
            await loadHomeFallbackStandingsSourceIfNeeded(reason: reason)
        }
        await syncFavoriteTeamLiveActivity()
        await syncFavoriteTeamWidgetSnapshot(
            includePrefetch: false,
            reason: "liveActivity",
            monthKey: scheduleMonthKey(for: currentDateProvider())
        )
        return true
    }

    // refreshMyTeam 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    func refreshMyTeam() async {
        await refreshGames(for: [.myTeam, .home])
    }

    // loadStandingsIfNeeded 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func loadStandingsIfNeeded() async {
        let season = currentStandingsSeason()
        if standingsSnapshots.isEmpty == false {
            #if DEBUG
            print("[StandingsRank] load skipped reason=visibleRows season=\(season) rows=\(standingsSnapshots.count)")
            #endif
            return
        }
        if standingsSnapshotCacheBySeason[season]?.isEmpty == false {
            refreshPublishedStandingsRowsWithCurrentSource(
                season: season,
                reason: "cachedRankRows"
            )
            logStandingsLocalCalculationSkipped(reason: "remoteRankSource", source: "cachedRankRows")
            return
        }
        let localRankCount = await loadLocalTeamRanks(season: season)
        guard localRankCount == 0 else { return }
        await bootstrapStandingsRankIfNeeded(season: season)
    }

    // refreshStandings 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    func refreshStandings() async {
        let season = currentStandingsSeason()
        await refreshStandings(season: season, logsBootstrapJoin: false)
    }

    // prefetchStandingsSourceIfNeeded 메서드는 이 타입의 주요 동작을 수행합니다.
    func prefetchStandingsSourceIfNeeded(season requestedSeason: Int? = nil) async {
        let season = requestedSeason ?? currentStandingsSeason()
        logStandingsLocalCalculationSkipped(reason: "remoteRankSource", source: "prefetch:\(season)")
    }

    // bootstrapStandingsRankIfNeeded 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // refreshStandings 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
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

    // performRefreshStandings 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    private func performRefreshStandings(season: Int) async {
        ensureCatalogTeamsLoadedIfNeeded()
        if await refreshTeamRanksFromRemote(season: season) {
            return
        }

        await refreshStandingsFromGamesFallback(season: season, reason: "rankFetchUnavailable")
    }

    // loadLocalTeamRanks 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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
        #if DEBUG
        print("[StandingsRank] local render rows=\(standingsSnapshotCacheBySeason[season]?.count ?? 0) season=\(season)")
        #endif
        refreshPublishedStandingsRowsWithCurrentSource(
            season: season,
            reason: "localRankRowsInitial"
        )
        logStandingsLocalCalculationSkipped(reason: "remoteRankSource", source: "localRankRows")
        return rows.count
    }

    // refreshTeamRanksFromRemote 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
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
            print("[StandingsRank] standings source=team_rank_2026 season=\(season)")
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
                #if DEBUG
                print("[StandingsRank] remote cache write count=0 season=\(season)")
                print("[StandingsRank] local render rows=\(standingsSnapshotCacheBySeason[season]?.count ?? 0) season=\(season)")
                #endif
                refreshPublishedStandingsRowsWithCurrentSource(
                    season: season,
                    reason: "remoteRankRowsInitial"
                )
                logStandingsLocalCalculationSkipped(reason: "remoteRankSource", source: "remoteRankRows")
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

    // refreshStandingsFromGamesFallback 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    private func refreshStandingsFromGamesFallback(season: Int, reason: String) async {
        do {
            #if DEBUG
            print("[StandingsRank] fallback to games reason=\(reason)")
            #endif

            let normalizedGames = try await fetchNormalizedStandingsSourceGames(season: season)
            storeStandingsSourceGames(normalizedGames, season: season)
            standingsSnapshotCacheBySeason[season] = nil
            refreshLocalStandingsProbabilitySignals(for: normalizedGames)
            refreshPublishedStandingsRowsWithCurrentSource(
                season: season,
                reason: reason
            )
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

    // loadHomeFallbackStandingsSourceIfNeeded 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    private func loadHomeFallbackStandingsSourceIfNeeded(reason: String) async {
        let season = currentStandingsSeason()
        if standingsSourceGamesBySeason[season]?.isEmpty == false ||
            homeFallbackReferenceWeekCompletedGames.isEmpty == false {
            logStandingsLocalCalculationSkipped(reason: "homeFallbackSourceAvailable", source: "homeFallback:\(reason)")
            return
        }

        do {
            #if DEBUG
            print("[HomeFallback] standings source fetch start season=\(season) reason=\(reason)")
            #endif
            let normalizedGames = try await fetchNormalizedStandingsSourceGames(season: season)
            storeStandingsSourceGames(normalizedGames, season: season)
            refreshLocalStandingsProbabilitySignals(for: normalizedGames)
            markRefreshSuccess(for: .games, at: Date(), isStale: false)
            await refreshRepositoryDebugInfo(dataSets: [])
            #if DEBUG
            print("[HomeFallback] standings source fetch success season=\(season) count=\(normalizedGames.count) reason=\(reason)")
            #endif
        } catch is CancellationError {
            #if DEBUG
            print("[HomeFallback] standings source fetch cancelled season=\(season) reason=\(reason)")
            #endif
        } catch {
            #if DEBUG
            print("[HomeFallback] standings source fetch failed season=\(season) reason=\(reason) error=\(error)")
            #endif
            markRefreshFailure(for: .games, hasUsableData: !games.isEmpty)
        }
    }

    // fetchStandingsSourceGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    private func fetchStandingsSourceGames(season: Int) async throws -> [GameDetail] {
        if let standingsGameSource = repository as? any KBOStandingsGameDataSource {
            return try await standingsGameSource.fetchStandingsSource(season: season)
        }

        return try await repository.fetchGames()
            .filter { $0.isRegularSeason && $0.hasCompleteFinalScore }
    }

    // fetchNormalizedStandingsSourceGames 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    private func fetchNormalizedStandingsSourceGames(season: Int) async throws -> [GameDetail] {
        let sourceGames = try await fetchStandingsSourceGames(season: season)
        let snapshot = await repositoryRuntimeState?.snapshot()
        return await reconcileOfficialScheduleStartTimesIfNeeded(
            in: sourceGames,
            snapshot: snapshot
        )
    }

    // storeStandingsSourceGames 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    private func storeStandingsSourceGames(_ games: [GameDetail], season: Int) {
        standingsSourceGamesBySeason[season] = games
        #if DEBUG
        print("[StandingsRankMovement] source stored season=\(season) count=\(games.count)")
        #endif
    }

    // currentStandingsSeason 메서드는 이 타입의 주요 동작을 수행합니다.
    private func currentStandingsSeason() -> Int {
        var calendar = calendar
        calendar.timeZone = scheduleTimeZone
        return calendar.component(.year, from: currentDateProvider())
    }

    // refreshNotifications 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    func refreshNotifications() async {
        await refreshNotifications(for: [.notifications])
    }

    // isRefreshing 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    func isRefreshing(_ scope: RefreshScope) -> Bool {
        activeRefreshScopes.contains(scope)
    }

    // statusMessage 메서드는 이 타입의 주요 동작을 수행합니다.
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

    var favoriteTeam: Team? {
        teams.first { $0.id == settings.favoriteTeamID }
    }

    var shouldShowFavoriteTeamOnboarding: Bool {
        hasCompletedOnboarding == false
    }

    // completeFavoriteTeamOnboarding 메서드는 이 타입의 주요 동작을 수행합니다.
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

    var myTeamTodayGame: GameDetail? {
        homeTodayGames.first { $0.involves(teamID: settings.favoriteTeamID) }
    }

    private var homeFallbackWeekNumber: Int? {
        HomeFallbackStandingsResolver.weekNumber(
            games: regularSeasonGames,
            currentDate: currentDateProvider(),
            calendar: homeFallbackScheduleCalendar
        )
    }

    private var homeFallbackCompletedRegularSeasonGamesBeforeToday: [GameDetail] {
        HomeFallbackStandingsResolver.completedRegularSeasonGamesBeforeToday(
            games: regularSeasonGames,
            currentDate: currentDateProvider(),
            calendar: homeFallbackScheduleCalendar
        )
    }

    private var homeFallbackReferenceWeekCompletedGames: [GameDetail] {
        HomeFallbackStandingsResolver.referenceWeekCompletedGames(
            games: regularSeasonGames,
            currentDate: currentDateProvider(),
            calendar: homeFallbackScheduleCalendar
        )
    }

    var favoriteTeamLiveGame: GameDetail? {
        (homeFavoriteTeamGames.isEmpty ? games : homeFavoriteTeamGames)
            .first { $0.status.isLiveLike && $0.involves(teamID: settings.favoriteTeamID) }
    }

    // makeHomeSummary 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    private func makeHomeSummary(from game: GameDetail) -> GameSummary {
        HomeGameSummaryBuilder.makeSummary(
            game: game,
            teams: teams,
            favoriteTeamID: settings.favoriteTeamID
        )
    }

    private var homeFallbackScheduleCalendar: Calendar {
        var weekCalendar = calendar
        weekCalendar.timeZone = scheduleTimeZone
        weekCalendar.firstWeekday = 2
        weekCalendar.minimumDaysInFirstWeek = 1
        return weekCalendar
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

    var attendanceDashboard: AttendanceDashboard {
        AttendanceDashboardBuilder.build(
            attendedGames: knownScheduleGames(filter: .all).filter { isGameAttended($0) },
            favoriteTeamID: settings.favoriteTeamID
        )
    }

    var regularSeasonGames: [GameDetail] {
        standingsCalculationGames.filter(\.isRegularSeason)
    }

    // refreshPublishedStandingsRowsWithCurrentSource 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    private func refreshPublishedStandingsRowsWithCurrentSource(season: Int, reason: String) {
        let snapshots = makeStandingsSnapshotsForCurrentState(season: season)
        standingsSnapshots = snapshots
        standingsRowsRevision += 1
#if DEBUG
        let sourceGamesCount = standingsSourceGamesBySeason[season]?.count ?? 0
        let movementCount = snapshots.filter { $0.rankMovement != .unchanged }.count
        print("[StandingsRankMovement] published rows assigned season=\(season) rows=\(snapshots.count) movementCount=\(movementCount) revision=\(standingsRowsRevision)")
        print("[StandingsRankMovement] republish rows season=\(season) rows=\(snapshots.count) sourceGames=\(sourceGamesCount) reason=\(reason)")
        print("[StandingsRankMovement] republish complete movementCount=\(movementCount)")
#endif
    }

    // logStandingsLocalCalculationSkipped 메서드는 이 타입의 주요 동작을 수행합니다.
    private func logStandingsLocalCalculationSkipped(reason: String, source: String) {
#if DEBUG
        print("[StandingsRank] standings local calculation skipped reason=\(reason) source=\(source)")
#endif
    }

    // durationMilliseconds 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func durationMilliseconds(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1_000)
    }

    // makeStandingsSnapshotsForCurrentState 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    private func makeStandingsSnapshotsForCurrentState(season: Int) -> [TeamStandingsSnapshot] {
        if standingsSourceGamesBySeason[season]?.isEmpty == false {
            let preGameRanks = preGameRankByTeamID(for: season)
            return gameCalculatedStandingsSnapshots(season: season, preGameRanks: preGameRanks)
        }
        if let cached = standingsSnapshotCacheBySeason[season], cached.isEmpty == false {
            let snapshots = cached
                .sorted { left, right in
                    if left.rank != right.rank {
                        return left.rank < right.rank
                    }
                    return left.team.name.localizedStandardCompare(right.team.name) == .orderedAscending
                }
            logStandingsLocalCalculationSkipped(reason: "remoteRankSource", source: "team_rank_2026")
            return snapshots
        }

        let preGameRanks = preGameRankByTeamID(for: season)
        return gameCalculatedStandingsSnapshots(season: season, preGameRanks: preGameRanks)
    }

    // gameCalculatedStandingsSnapshots 메서드는 이 타입의 주요 동작을 수행합니다.
    private func gameCalculatedStandingsSnapshots(
        season: Int,
        preGameRanks: [String: Int]
    ) -> [TeamStandingsSnapshot] {
        let rankedSnapshots = teams
            .map { makeStandingsSnapshot(for: $0, probabilitySignalsByTeamID: localStandingsProbabilitySignalsByTeamID) }
            .sorted(by: standingsComparator)

        let snapshots = rankedSnapshots.enumerated().map { index, snapshot in
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
                virtualUnscheduledRemainingGames: snapshot.virtualUnscheduledRemainingGames,
                rankingResolution: snapshot.rankingResolution,
                rankingResolutionPosition: snapshot.rankingResolutionPosition,
                postseasonQualificationProbability: snapshot.postseasonQualificationProbability,
                postseasonQualificationStatus: snapshot.postseasonQualificationStatus,
                postseasonProbabilityUnavailableReason: snapshot.postseasonProbabilityUnavailableReason,
                precomputedStreakText: snapshot.precomputedStreakText,
                preGameRank: preGameRanks[snapshot.team.id]
            )
        }
        return logStandingsRankMovementDiagnostics(
            snapshots,
            season: season,
            preGameRanks: preGameRanks
        )
    }

    private var standingsCalculationGames: [GameDetail] {
        let season = currentStandingsSeason()
        return standingsSourceGamesBySeason[season] ?? games
    }

    // preGameRankByTeamID 메서드는 이 타입의 주요 동작을 수행합니다.
    private func preGameRankByTeamID(for season: Int) -> [String: Int] {
        StandingsRankMovementResolver.preGameRanks(
            teams: teams,
            games: standingsSourceGamesBySeason[season] ?? games,
            previousRankProvider: previousRegularSeasonRank
        )
    }

    // logStandingsRankMovementDiagnostics 메서드는 이 타입의 주요 동작을 수행합니다.
    private func logStandingsRankMovementDiagnostics(
        _ snapshots: [TeamStandingsSnapshot],
        season: Int,
        preGameRanks: [String: Int]
    ) -> [TeamStandingsSnapshot] {
#if DEBUG
        let sourceGames = standingsSourceGamesBySeason[season] ?? games
        let finalGames = sourceGames
            .filter(\.isRegularSeason)
            .filter(\.hasCompleteFinalScore)
        let latestFinalGameDate = StandingsRankMovementResolver.latestCompletedGameDay(
            games: finalGames,
            calendar: standingsMovementCalendar
        )
        let beforeGames = finalGames.filter { game in
            guard let latestFinalGameDate else { return false }
            return standingsMovementCalendar.startOfDay(for: game.scheduledStart) < latestFinalGameDate
        }
        let currentGames = finalGames.filter { game in
            guard let latestFinalGameDate else { return true }
            return standingsMovementCalendar.startOfDay(for: game.scheduledStart) <= latestFinalGameDate
        }
        let latestFinalGameDateText = latestFinalGameDate.map(scheduleDayKey(for:)) ?? "<nil>"
        print("[StandingsRankMovement] latestFinalGameDate=\(latestFinalGameDateText) finalGames.count=\(finalGames.count) beforeGames.count=\(beforeGames.count) currentGames.count=\(currentGames.count)")
        snapshots.forEach { snapshot in
            let previousRankText = preGameRanks[snapshot.team.id].map(String.init) ?? "<nil>"
            print("[StandingsRankMovement] teamId=\(snapshot.team.id) previousRank=\(previousRankText) currentRank=\(snapshot.rank) movement displayText=\(snapshot.rankMovement.displayText)")
        }
#endif
        return snapshots
    }

    private var standingsMovementCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = scheduleTimeZone
        return calendar
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

    // scheduleGames 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    func scheduleGames(on date: Date, filter: ScheduleFilter) -> [GameDetail] {
        let selectedDayKey = scheduleDayKey(for: date)
        let dayGames = groupedScheduleGamesByDay(for: date, filter: filter)[selectedDayKey] ?? []

        return ScheduleGameSelector.sortSelectedGames(dayGames, favoriteTeamID: settings.favoriteTeamID)
    }

    // myTeamGames 메서드는 이 타입의 주요 동작을 수행합니다.
    func myTeamGames(on date: Date) -> [GameDetail] {
        scheduleGames(on: date, filter: .myTeam)
    }

    // nearestScheduleMonth 메서드는 이 타입의 주요 동작을 수행합니다.
    func nearestScheduleMonth(to date: Date, filter: ScheduleFilter) -> Date? {
        let months = availableScheduleMonths(filter: filter)
        guard months.isEmpty == false else { return nil }

        let monthStart = startOfMonth(for: date)
        if let nextMonth = months.first(where: { $0 >= monthStart }) {
            return nextMonth
        }
        return months.last
    }

    // shiftedScheduleMonth 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // scheduleCalendarDays 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    func scheduleCalendarDays(for month: Date, filter: ScheduleFilter) -> [MyTeamCalendarDay] {
        let cacheKey = makeScheduleCalendarCacheKey(for: month, filter: filter)
        if let cached = scheduleCalendarDaysCache[cacheKey] {
            return cached
        }

        let gamesByDayKey = groupedScheduleGamesByDay(for: month, filter: filter)
        let days = ScheduleCalendarDayBuilder.makeDays(
            monthStart: startOfMonth(for: month),
            gamesByDate: gamesByDayKey,
            filter: filter,
            favoriteTeamID: settings.favoriteTeamID,
            calendar: calendar,
            dayKey: { [self] date in scheduleDayKey(for: date) },
            isToday: { [self] date, _ in calendar.isDateInToday(date) },
            hasAttendedGame: { [self] games in games.contains(where: isGameAttended) },
            favoriteTeamResult: { [self] games, _ in calendarFavoriteTeamResult(for: games) }
        )
        scheduleCalendarDaysCache[cacheKey] = days
        return days
    }

    // myTeamCalendarDays 메서드는 이 타입의 주요 동작을 수행합니다.
    func myTeamCalendarDays(for month: Date) -> [MyTeamCalendarDay] {
        scheduleCalendarDays(for: month, filter: .myTeam)
    }

    // startOfMonth 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    func startOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    // startOfMonth 메서드는 지정된 캘린더 기준 월 시작일을 반환합니다.
    private func startOfMonth(for date: Date, calendar sourceCalendar: Calendar) -> Date {
        let components = sourceCalendar.dateComponents([.year, .month], from: date)
        return sourceCalendar.date(from: components) ?? date
    }

    // monthStart 메서드는 월 키를 KST 캘린더의 월 시작일로 변환합니다.
    private func monthStart(for key: KBOMonthScheduleKey, calendar sourceCalendar: Calendar) -> Date {
        sourceCalendar.date(from: DateComponents(year: key.year, month: key.month, day: 1)) ?? currentDateProvider()
    }

    // shiftedMonth 메서드는 이 타입의 주요 동작을 수행합니다.
    func shiftedMonth(from date: Date, by offset: Int) -> Date {
        calendar.date(byAdding: .month, value: offset, to: startOfMonth(for: date)) ?? date
    }

    // calendarMonthTitle 메서드는 이 타입의 주요 동작을 수행합니다.
    func calendarMonthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: startOfMonth(for: date))
    }

    // loadScheduleIfNeeded 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func loadScheduleIfNeeded(for month: Date) async {
        ensureCatalogTeamsLoadedIfNeeded()
        await loadMyTeamSchedule(for: month, forceRefresh: false)
    }

    // refreshSchedule 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    func refreshSchedule(for month: Date) async {
        ensureCatalogTeamsLoadedIfNeeded()
        await loadMyTeamSchedule(for: month, forceRefresh: true)
    }

    // fetchIsolatedScheduleMonth 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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

    // fetchScheduleTabMonth 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func fetchScheduleTabMonth(
        for key: KBOMonthScheduleKey,
        bypassingCache: Bool,
        callSite: String,
        reason: String
    ) async throws -> [GameDetail] {
        ensureCatalogTeamsLoadedIfNeeded()
        let startedAt = Date()
        #if DEBUG
        print("[ScheduleRefresh] callSite=\(callSite) reason=\(reason) month=\(key.yearMonthText) source=scheduleTabMonth officialStartTimeReconciliation=false skippedGlobalMerge=true")
        #endif
        let fetched: [GameDetail]
        if let scheduleTabMonthSource = repository as? any KBOScheduleTabMonthDataSource {
            fetched = try await scheduleTabMonthSource.fetchScheduleTabMonth(
                for: key,
                bypassingCache: bypassingCache
            )
        } else {
            fetched = try await repository.fetchMonthlySchedule(
                for: key,
                bypassingCache: bypassingCache
            )
        }
        let sorted = fetched.sorted { $0.scheduledStart < $1.scheduledStart }
        #if DEBUG
        print("[ScheduleRefresh] callSite=\(callSite) reason=\(reason) month=\(key.yearMonthText) scheduleMonthLoad skippedGlobalMerge=true fetched=\(sorted.count) durationMs=\(Self.durationMilliseconds(since: startedAt))")
        #endif
        return sorted
    }

    // refreshTodayScheduleGamesForScheduleCache 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    func refreshTodayScheduleGamesForScheduleCache(
        selectedDate: Date,
        reason: String
    ) async -> [GameDetail] {
        await refreshTodayGamesFromSupabase(
            for: selectedDate,
            monthKey: scheduleMonthKey(for: selectedDate),
            reason: reason
        )
    }

    // currentScheduleMonthSnapshot 메서드는 이 타입의 주요 동작을 수행합니다.
    func currentScheduleMonthSnapshot(for key: KBOMonthScheduleKey) -> [GameDetail] {
        mergeMonthlyScheduleGames(fallbackMonthSchedule(for: key), for: key)
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    func updateFavoriteTeamScheduleWidgetSnapshot(
        fromScheduleTabMonthGames games: [GameDetail],
        monthKey: KBOMonthScheduleKey,
        reason: String
    ) async {
        let currentMonthKey = currentWidgetMonthKey()
        guard monthKey == currentMonthKey else {
            #if DEBUG
            print("[WidgetScheduleBridge] skipped reason=nonCurrentMonth displayedMonth=\(monthKey.yearMonthText) currentMonth=\(currentMonthKey.yearMonthText) source=scheduleTabMonth")
            #endif
            return
        }

        let sortedGames = mergeEquivalentGames(games)
            .filter { scheduleMonthKey(for: $0.scheduledStart) == monthKey }
            .sorted { $0.scheduledStart < $1.scheduledStart }
        favoriteTeamWidgetMonthSources[monthKey] = FavoriteTeamScheduleWidgetMonthSource(
            monthKey: monthKey,
            games: sortedGames,
            source: .scheduleTabCurrentMonth,
            updatedAt: currentDateProvider()
        )
        #if DEBUG
        print("[WidgetScheduleBridge] month=\(monthKey.yearMonthText) source=scheduleTabMonth count=\(sortedGames.count) favoriteTeam=\(settings.favoriteTeamID ?? "nil")")
        #endif
        await syncFavoriteTeamWidgetSnapshot(
            includePrefetch: false,
            reason: "scheduleTabCurrentMonth",
            monthKey: monthKey,
            preferredMonthGames: sortedGames,
            incomingSource: .scheduleTabCurrentMonth
        )
    }

    func favoriteTeamScheduleWidgetSnapshotForTesting() -> FavoriteTeamScheduleWidgetSnapshot? {
        lastFavoriteTeamWidgetSnapshot
    }

    func favoriteTeamScheduleWidgetSourceMonthlyCountForTesting(monthKey: KBOMonthScheduleKey) -> Int? {
        favoriteTeamWidgetMonthSources[monthKey]?.games.count
    }

    // loadScheduleDayIfNeeded 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func loadScheduleDayIfNeeded(for date: Date) async {
        ensureCatalogTeamsLoadedIfNeeded()
        await loadScheduleDay(for: date, forceRefresh: false)
    }

    // refreshScheduleDay 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    func refreshScheduleDay(for date: Date) async {
        ensureCatalogTeamsLoadedIfNeeded()
        await loadScheduleDay(for: date, forceRefresh: true)
    }

    // currentScheduleRefreshDate 메서드는 이 타입의 주요 동작을 수행합니다.
    func currentScheduleRefreshDate() -> Date {
        currentDateProvider()
    }

    // isScheduleStaleReconciliationInFlight 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    func isScheduleStaleReconciliationInFlight() -> Bool {
        inFlightScheduleStaleReconciliationTask != nil
    }

    // preflightRefreshStaleScheduleDates 메서드는 이 타입의 주요 동작을 수행합니다.
    func preflightRefreshStaleScheduleDates(_ dateKeys: [String]) async -> ScheduleStalePreflightRefreshResult {
        let uniqueDateKeys = Array(Set(dateKeys)).sorted(by: >)
        let task = Task { @MainActor in
            await self.performPreflightRefreshStaleScheduleDates(uniqueDateKeys)
        }
        return await task.value
    }

    // reconcileStaleScheduleGameDates 메서드는 이 타입의 주요 동작을 수행합니다.
    func reconcileStaleScheduleGameDates(_ dates: [String]) async throws -> [String] {
        pruneExpiredRecentlyReconciledScheduleDates()
        let uniqueDates = Array(Set(dates)).sorted(by: >)
        let reconciliableDates = uniqueDates.filter { recentlyReconciledScheduleDates[$0] == nil }
        guard uniqueDates.isEmpty == false else {
            return []
        }
        guard reconciliableDates.isEmpty == false else {
            #if DEBUG
            print("[ScheduleRefresh] stale reconciliation skipped reason=recentlyReconciled dates=\(uniqueDates.joined(separator: ","))")
            #endif
            return []
        }

        if inFlightScheduleStaleReconciliationTask != nil {
            #if DEBUG
            print("[ScheduleRefresh] stale reconciliation skipped reason=inFlight dates=\(reconciliableDates.joined(separator: ","))")
            #endif
            return []
        }

        let task = Task {
            try await scheduleStaleGameReconciliationClient.reconcileStaleGames(dates: reconciliableDates)
        }
        inFlightScheduleStaleReconciliationTask = task
        defer { inFlightScheduleStaleReconciliationTask = nil }

        try await task.value
        markScheduleDatesRecentlyReconciled(reconciliableDates)
        return reconciliableDates
    }

    // startPostReconciliationForceRefresh 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    func startPostReconciliationForceRefresh(_ dateKeys: [String]) {
        let uniqueDateKeys = Array(Set(dateKeys)).sorted(by: >)
        let refreshDateKeys = uniqueDateKeys.filter { inFlightSchedulePostReconciliationRefreshDates.contains($0) == false }
        guard refreshDateKeys.isEmpty == false else {
            #if DEBUG
            print("[ScheduleRefresh] post-reconciliation force refresh skipped reason=inFlight dates=\(uniqueDateKeys.joined(separator: ","))")
            #endif
            return
        }
        inFlightSchedulePostReconciliationRefreshDates.formUnion(refreshDateKeys)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performPostReconciliationForceRefresh(refreshDateKeys)
        }
    }

    // waitForSchedulePostReconciliationRefreshIfNeeded 메서드는 이 타입의 주요 동작을 수행합니다.
    func waitForSchedulePostReconciliationRefreshIfNeeded() async {
        while inFlightSchedulePostReconciliationRefreshDates.isEmpty == false {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // performPostReconciliationForceRefresh 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    private func performPostReconciliationForceRefresh(_ dateKeys: [String]) async {
        do {
            _ = try await forceRefreshScheduleDatesAfterReconciliation(dateKeys)
        } catch is CancellationError {
            #if DEBUG
            print("[ScheduleRefresh] post-reconciliation force refresh cancelled dates=\(dateKeys.joined(separator: ","))")
            #endif
        } catch {
            #if DEBUG
            print("[ScheduleRefresh] post-reconciliation force refresh failure dates=\(dateKeys.joined(separator: ",")) error=\(error)")
            #endif
        }
        inFlightSchedulePostReconciliationRefreshDates.subtract(dateKeys)
    }

    // performPreflightRefreshStaleScheduleDates 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    private func performPreflightRefreshStaleScheduleDates(_ dateKeys: [String]) async -> ScheduleStalePreflightRefreshResult {
        guard dateKeys.isEmpty == false else {
            return ScheduleStalePreflightRefreshResult(
                requestedDateKeys: [],
                remainingStaleDateKeys: [],
                resolvedDateKeys: [],
                failedDateKeys: []
            )
        }

        #if DEBUG
        print("[ScheduleRefresh] stale preflight force refresh dates=\(dateKeys.joined(separator: ","))")
        #endif

        var remainingStaleDateKeys = Set<String>()
        var resolvedDateKeys: [String] = []
        var failedDateKeys: [String] = []
        var refreshedMonthKeys = Set<KBOMonthScheduleKey>()
        var didMergeFreshGames = false

        for dateKey in dateKeys {
            do {
                let date = try scheduleDate(fromDayKey: dateKey)
                let fetched = try await repository.fetchSchedule(for: date, bypassingCache: true)
                #if DEBUG
                print("[ScheduleRefresh] stale preflight fetched date=\(dateKey) count=\(fetched.count)")
                #endif

                let monthKey = scheduleMonthKey(for: date)
                let overlayResult = await overlayScheduleGames(
                    fetched,
                    intoMonth: monthKey,
                    reason: "stalePreflightOverlay"
                )
                let upsertResult = upsertScheduleGamesIntoLocalStore(fetched, source: .staleReconciliation)
                _ = await upsertScheduleGamesIntoRepositoryCache(fetched)
                refreshedMonthKeys.insert(monthKey)
                didMergeFreshGames = true

                #if DEBUG
                print("[ScheduleRefresh] stale preflight merge date=\(dateKey) inserted=\(upsertResult.inserted) updated=\(upsertResult.updated) skipped=\(upsertResult.skippedExisting)")
                print("[ScheduleRefresh] stale preflight overlay month=\(monthKey.yearMonthText) before=\(overlayResult.before) fetched=\(fetched.count) inserted=\(overlayResult.inserted) updated=\(overlayResult.updated) unchanged=\(overlayResult.unchanged) after=\(overlayResult.after)")
                #endif

                let overlaidDateGames = overlayResult.games.filter {
                    scheduleDayKey(for: $0.scheduledStart) == dateKey
                }
                let freshStaleDates = ScheduleStaleGameReconciliationResolver.staleGameDates(
                    in: overlaidDateGames,
                    today: currentDateProvider(),
                    calendar: calendar
                )
                if overlaidDateGames.isEmpty || freshStaleDates.contains(dateKey) {
                    remainingStaleDateKeys.insert(dateKey)
                } else {
                    resolvedDateKeys.append(dateKey)
                }
            } catch {
                failedDateKeys.append(dateKey)
                remainingStaleDateKeys.insert(dateKey)
                #if DEBUG
                print("[ScheduleRefresh] stale preflight failure date=\(dateKey) error=\(error)")
                #endif
            }
        }

        for monthKey in refreshedMonthKeys {
            await refreshLoadedScheduleMonthsFromLocalStore(
                including: monthKey,
                reason: "stalePreflightLocalStoreRefresh"
            )
        }
        if didMergeFreshGames {
            schedulePostReconciliationRefreshGeneration += 1
        }

        let remainingOrdered = dateKeys.filter { remainingStaleDateKeys.contains($0) }
        #if DEBUG
        if resolvedDateKeys.isEmpty == false {
            print("[ScheduleRefresh] stale preflight resolved dates=\(resolvedDateKeys.joined(separator: ","))")
        }
        #endif

        return ScheduleStalePreflightRefreshResult(
            requestedDateKeys: dateKeys,
            remainingStaleDateKeys: remainingOrdered,
            resolvedDateKeys: resolvedDateKeys,
            failedDateKeys: failedDateKeys
        )
    }

    // forceRefreshScheduleDatesAfterReconciliation 메서드는 이 타입의 주요 동작을 수행합니다.
    private func forceRefreshScheduleDatesAfterReconciliation(_ dateKeys: [String]) async throws -> SchedulePostReconciliationRefreshResult {
        let uniqueDateKeys = Array(Set(dateKeys)).sorted(by: >)
        guard uniqueDateKeys.isEmpty == false else {
            return SchedulePostReconciliationRefreshResult(dateResults: [])
        }

        #if DEBUG
        print("[ScheduleRefresh] post-reconciliation force refresh source=AppModel dates=\(uniqueDateKeys.joined(separator: ","))")
        #endif

        var fetches: [(dateKey: String, date: Date, games: [GameDetail])] = []
        for dateKey in uniqueDateKeys {
            let date = try scheduleDate(fromDayKey: dateKey)
            let fetched = try await repository.fetchSchedule(for: date, bypassingCache: true)
            #if DEBUG
            print("[ScheduleRefresh] post-reconciliation fetched date=\(dateKey) count=\(fetched.count)")
            #endif
            fetches.append((dateKey, date, fetched))
        }

        var dateResults: [SchedulePostReconciliationDateRefreshResult] = []
        var refreshedMonthKeys = Set<KBOMonthScheduleKey>()
        for fetch in fetches {
            let monthKey = scheduleMonthKey(for: fetch.date)
            let overlayResult = await overlayScheduleGames(
                fetch.games,
                intoMonth: monthKey,
                reason: "postReconciliationOverlay"
            )
            let upsertResult = upsertScheduleGamesIntoLocalStore(fetch.games, source: .staleReconciliation)
            _ = await upsertScheduleGamesIntoRepositoryCache(fetch.games)
            refreshedMonthKeys.insert(monthKey)
            dateResults.append(
                SchedulePostReconciliationDateRefreshResult(
                    dateKey: fetch.dateKey,
                    games: fetch.games,
                    inserted: upsertResult.inserted,
                    updated: upsertResult.updated,
                    skippedExisting: upsertResult.skippedExisting
                )
            )
            #if DEBUG
            print("[ScheduleRefresh] post-reconciliation merge date=\(fetch.dateKey) inserted=\(upsertResult.inserted) updated=\(upsertResult.updated) skipped=\(upsertResult.skippedExisting)")
            print("[ScheduleRefresh] post-reconciliation overlay month=\(monthKey.yearMonthText) before=\(overlayResult.before) fetched=\(fetch.games.count) inserted=\(overlayResult.inserted) updated=\(overlayResult.updated) unchanged=\(overlayResult.unchanged) after=\(overlayResult.after)")
            #endif
        }

        for monthKey in refreshedMonthKeys {
            await refreshLoadedScheduleMonthsFromLocalStore(
                including: monthKey,
                reason: "postReconciliationLocalStoreRefresh"
            )
        }

        #if DEBUG
        print("[ScheduleRefresh] post-reconciliation completed dates=\(uniqueDateKeys.joined(separator: ","))")
        #endif
        clearRecentlyReconciledScheduleDates(uniqueDateKeys)
        schedulePostReconciliationRefreshGeneration += 1

        return SchedulePostReconciliationRefreshResult(dateResults: dateResults)
    }

    // loadScheduleDay 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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

        _ = await refreshTodayGamesFromSupabase(for: date, monthKey: monthKey, reason: reason)
    }

    // loadMyTeamScheduleIfNeeded 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func loadMyTeamScheduleIfNeeded(for month: Date) async {
        await loadScheduleIfNeeded(for: month)
    }

    // isLoadingSchedule 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    func isLoadingSchedule(for month: Date) -> Bool {
        loadingScheduleMonths.contains(KBOMonthScheduleKey(date: month, calendar: calendar))
    }

    // scheduleStatusMessage 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

    // scheduleDebugSummary 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

    // game 메서드는 이 타입의 주요 동작을 수행합니다.
    func game(withID gameID: UUID) -> GameDetail? {
        game(withIdentity: gameID.uuidString)
    }

    // initialGameSnapshot 메서드는 이 타입의 주요 동작을 수행합니다.
    func initialGameSnapshot(for gameIdentity: String) -> GameDetail? {
        game(withIdentity: gameIdentity)
    }

    // game 메서드는 이 타입의 주요 동작을 수행합니다.
    func game(withIdentity gameIdentity: String) -> GameDetail? {
        selectedGameMatch(for: gameIdentity)?.game
    }

    // resolveGameDetailSelection 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    func resolveGameDetailSelection(
        for gameIdentity: String,
        initialGame: GameDetail? = nil
    ) async -> GameDetail? {
        if let match = selectedGameMatch(for: gameIdentity) {
            #if DEBUG
            print("[GameDetailFetch] selectedGame resolved selectedIdentity=\(gameIdentity) id=\(match.game.publicGameID ?? match.game.canonicalGameIdentityValue) reason=\(match.reason)")
            #endif
            return match.game
        }
        if let initialGame,
           let match = SelectedGameResolver.match(for: gameIdentity, in: allKnownGames() + [initialGame]) {
            #if DEBUG
            print("[GameDetailFetch] selectedGame resolved source=routeInitialSnapshot selectedIdentity=\(gameIdentity) id=\(match.game.publicGameID ?? match.game.canonicalGameIdentityValue) reason=\(match.reason)")
            print("[GameDetailFetch] selectedGame localMiss avoided reason=routeInitialSnapshot selectedIdentity=\(gameIdentity)")
            #endif
            return match.game
        }
        return await fetchSelectedGameFromRepository(for: gameIdentity)
    }

    // fetchIsolatedGameDetailSnapshot 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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

    // fetchGameDetailDatabaseReview 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func fetchGameDetailDatabaseReview(for game: GameDetail) async -> GameCenterReview? {
        guard let recordSource = repository as? any KBOGameDetailDatabaseRecordDataSource else {
            #if DEBUG
            print("[GameDetailDBRecords] selectedRecordSource=none reason=unsupportedRepository gameID=\(game.id.uuidString)")
            #endif
            return nil
        }
        do {
            return try await recordSource.fetchGameDetailDatabaseReview(for: game)
        } catch is CancellationError {
            return nil
        } catch {
            #if DEBUG
            print("[GameDetailDBRecords] selectedRecordSource=none reason=fetchFailed gameID=\(game.id.uuidString) error=\(error)")
            #endif
            return nil
        }
    }

    // fetchGameDetailDatabaseReviewResult 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func fetchGameDetailDatabaseReviewResult(for game: GameDetail) async -> GameDetailDatabaseReviewFetchResult? {
        if let recordSource = repository as? any KBOGameDetailDatabaseRecordDiagnosticDataSource {
            let rawIdentity = rawSupabaseGameDetailIdentity(for: game)
            let providerGameID = game.providerGameID ?? rawIdentity?.providerGameID
            let publicGameID = game.publicGameID ?? rawIdentity?.publicGameID
            if let rawSupabaseGameID = rawIdentity?.supabaseGameID {
                return await fetchGameDetailDatabaseReviewResult(
                    rawSupabaseGameID: rawSupabaseGameID,
                    providerGameID: providerGameID,
                    publicGameID: publicGameID
                )
            }
            if providerGameID?.nilIfBlank != nil || publicGameID?.nilIfBlank != nil {
                #if DEBUG
                print("[GameDetailDBRecords] providerResolvedRequest invokedFrom=afterFetchGameSingleProviderResolved localGameId=\(game.id.uuidString) providerGameID=\(providerGameID ?? "<nil>") publicGameID=\(publicGameID ?? "<nil>")")
                #endif
                return await fetchGameDetailDatabaseReviewResultDeduped(
                    rawSupabaseGameID: nil,
                    providerGameID: providerGameID,
                    publicGameID: publicGameID,
                    recordType: "providerResolvedDbRecords",
                    forceRefresh: false
                ) {
                    try await recordSource.fetchGameDetailDatabaseReview(
                        providerGameID: providerGameID,
                        publicGameID: publicGameID,
                        invokedFrom: "afterFetchGameSingleProviderResolved"
                    )
                }
            }
            #if DEBUG
            print("[GameDetailDBRecords] providerResolvedRequest skipped reason=missingProviderAndPublicID localGameId=\(game.id.uuidString)")
            #endif
            return await fetchGameDetailDatabaseReviewResultDeduped(
                rawSupabaseGameID: nil,
                providerGameID: game.providerGameID,
                publicGameID: game.publicGameID,
                recordType: "localDbRecords",
                forceRefresh: false
            ) {
                try await recordSource.fetchGameDetailDatabaseReviewResult(for: game)
            }
        }

        return await fetchGameDetailDatabaseReviewResultDeduped(
            rawSupabaseGameID: nil,
            providerGameID: game.providerGameID,
            publicGameID: game.publicGameID,
            recordType: "simpleDbRecords",
            forceRefresh: false
        ) { [weak self] in
            guard let self,
                  let review = await self.fetchGameDetailDatabaseReview(for: game) else {
                return nil
            }
            return GameDetailDatabaseReviewFetchResult(
                review: review,
                inputLocalGameID: game.id,
                rawSupabaseGameID: nil,
                resolvedSupabaseGameID: nil,
                providerGameID: game.providerGameID,
                publicGameID: game.publicGameID,
                publicBatterRawRowCount: review.awayBatting.lines.count + review.homeBatting.lines.count,
                publicPitcherRawRowCount: review.awayPitching.lines.count + review.homePitching.lines.count,
                eventRawRowCount: 0
            )
        }
    }

    // fetchGameDetailDatabaseReviewResultDeduped 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    private func fetchGameDetailDatabaseReviewResultDeduped(
        rawSupabaseGameID: UUID?,
        providerGameID: String?,
        publicGameID: String?,
        recordType: String,
        forceRefresh: Bool,
        operation: @escaping () async throws -> GameDetailDatabaseReviewFetchResult?
    ) async -> GameDetailDatabaseReviewFetchResult? {
        let key = gameDetailDatabaseRecordRequestKey(
            rawSupabaseGameID: rawSupabaseGameID,
            providerGameID: providerGameID,
            publicGameID: publicGameID,
            recordType: recordType,
            forceRefresh: forceRefresh
        )
        if forceRefresh == false,
           let rawSupabaseGameID,
           let cached = cachedGameDetailDatabaseReviewsByRawSupabaseID[rawSupabaseGameID] {
            #if DEBUG
            print("[GameDetailDBRecords] fetch skipped reason=alreadyLoaded rawSupabaseGameID=\(rawSupabaseGameID.uuidString) recordType=\(recordType)")
            #endif
            return cached
        }
        if forceRefresh == false,
           let cached = cachedGameDetailDatabaseReviewsByRequestKey[key] {
            #if DEBUG
            print("[GameDetailDBRecords] fetch skipped reason=alreadyLoaded key=\(key)")
            #endif
            return cached
        }
        if let inFlight = inFlightGameDetailDatabaseReviewTasks[key] {
            #if DEBUG
            print("[GameDetailDBRecords] fetch skipped reason=inFlight key=\(key)")
            #endif
            return await inFlight.value
        }

        let stageStartedAt = Date()
        let task = Task { @MainActor () -> GameDetailDatabaseReviewFetchResult? in
            do {
                return try await operation()
            } catch is CancellationError {
                return nil
            } catch {
                #if DEBUG
                print("[GameDetailDBRecords] selectedRecordSource=none reason=fetchFailed key=\(key) error=\(error)")
                #endif
                return nil
            }
        }
        inFlightGameDetailDatabaseReviewTasks[key] = task
        let result = await task.value
        inFlightGameDetailDatabaseReviewTasks[key] = nil
        if let result {
            cachedGameDetailDatabaseReviewsByRequestKey[key] = result
            if let rawSupabaseGameID = rawSupabaseGameID ?? result.rawSupabaseGameID ?? result.resolvedSupabaseGameID {
                cachedGameDetailDatabaseReviewsByRawSupabaseID[rawSupabaseGameID] = result
            }
        }
        #if DEBUG
        print("[GameDetailDBRecords] fetch completed key=\(key) durationMs=\(Int(Date().timeIntervalSince(stageStartedAt) * 1_000)) mappedBatterCount=\(result?.mappedBatterCount ?? 0) mappedPitcherCount=\(result?.mappedPitcherCount ?? 0)")
        #endif
        return result
    }

    // gameDetailDatabaseRecordRequestKey 메서드는 이 타입의 주요 동작을 수행합니다.
    private func gameDetailDatabaseRecordRequestKey(
        rawSupabaseGameID: UUID?,
        providerGameID: String?,
        publicGameID: String?,
        recordType: String,
        forceRefresh: Bool
    ) -> String {
        [
            "raw=\(rawSupabaseGameID?.uuidString ?? "<nil>")",
            "provider=\(providerGameID?.nilIfBlank ?? "<nil>")",
            "public=\(publicGameID?.nilIfBlank ?? "<nil>")",
            "recordType=\(recordType)",
            "forceRefresh=\(forceRefresh)"
        ].joined(separator: "|")
    }

    // fetchGameDetailDatabaseReviewResult 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    func fetchGameDetailDatabaseReviewResult(
        rawSupabaseGameID: UUID,
        providerGameID: String?,
        publicGameID: String?
    ) async -> GameDetailDatabaseReviewFetchResult? {
        guard let recordSource = repository as? any KBOGameDetailDatabaseRecordDiagnosticDataSource else {
            #if DEBUG
            print("[GameDetailDBRecords] selectedRecordSource=none reason=unsupportedRepository rawSupabaseGameId=\(rawSupabaseGameID.uuidString)")
            #endif
            return nil
        }
        return await fetchGameDetailDatabaseReviewResultDeduped(
            rawSupabaseGameID: rawSupabaseGameID,
            providerGameID: providerGameID,
            publicGameID: publicGameID,
            recordType: "supabaseDbRecords",
            forceRefresh: false
        ) {
            try await recordSource.fetchGameDetailDatabaseReview(
                supabaseGameId: rawSupabaseGameID,
                providerGameID: providerGameID,
                publicGameID: publicGameID,
                invokedFrom: "afterFetchGameSingleRawSupabaseId"
            )
        }
    }

    // refreshGameDetail 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    @discardableResult
    func refreshGameDetail(for gameIdentity: String, forceRefresh: Bool = false) async -> GameDetail? {
        await refreshGameDetailResult(for: gameIdentity, forceRefresh: forceRefresh)?.game
    }

    // refreshGameDetailResult 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    @discardableResult
    func refreshGameDetailResult(
        for gameIdentity: String,
        initialGame: GameDetail? = nil,
        forceRefresh: Bool = false
    ) async -> GameDetailRefreshResult? {
        guard let selectedGame = await resolveGameDetailSelection(for: gameIdentity, initialGame: initialGame) else {
            #if DEBUG
            debugLogMissingSelectedGame(gameIdentity)
            #endif
            return nil
        }
        let isAutomaticStarterRefresh = forceRefresh == false && selectedGame.status == .upcoming
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
            if isAutomaticStarterRefresh {
                print("[GameDetailStarterRefresh] skipped reason=freshEnough selectedIdentity=\(gameIdentity) initialAwayStarter=\(selectedGame.awayStartingPitcherName ?? "<nil>") initialHomeStarter=\(selectedGame.homeStartingPitcherName ?? "<nil>")")
            }
            #endif
            return GameDetailRefreshResult(
                game: selectedGame,
                rawSupabaseGameID: rawSupabaseGameDetailIdentity(for: selectedGame)?.supabaseGameID,
                providerGameID: rawSupabaseGameDetailIdentity(for: selectedGame)?.providerGameID ?? selectedGame.providerGameID,
                publicGameID: rawSupabaseGameDetailIdentity(for: selectedGame)?.publicGameID ?? selectedGame.publicGameID
            )
        }

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return Optional(GameDetailRefreshResult(
                    game: selectedGame,
                    rawSupabaseGameID: nil,
                    providerGameID: selectedGame.providerGameID,
                    publicGameID: selectedGame.publicGameID
                ))
            }
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

    // fetchSelectedGameFromRepository 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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
            let upsertResult = upsertScheduleGamesIntoLocalStore([fetchedGame], source: .gameDetailRefresh)
            let cacheUpsertResult = await upsertScheduleGamesIntoRepositoryCache([fetchedGame])
            await refreshLoadedScheduleMonthsFromLocalStore(
                including: scheduleMonthKey(for: fetchedGame.scheduledStart),
                reason: "gameDetailIdentityFallback"
            )
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

    // performRefreshGameDetail 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    private func performRefreshGameDetail(
        selectedGame: GameDetail,
        gameIdentity: String,
        forceRefresh: Bool
    ) async -> GameDetailRefreshResult? {
        AppLog.info(.gameDetail, "[GameDetail] refresh start game=\(operationalGameIdentifier(for: selectedGame)) selectedIdentity=\(gameIdentity) publicGameID=\(selectedGame.publicGameID ?? "<nil>") providerGameID=\(selectedGame.providerGameID ?? selectedGame.officialProviderGameID ?? "<nil>") status=\(selectedGame.status.rawValue) forceRefresh=\(forceRefresh)")
        if forceRefresh == false, selectedGame.status == .upcoming {
            #if DEBUG
            print("[GameDetailStarterRefresh] start selectedIdentity=\(gameIdentity) publicGameID=\(selectedGame.publicGameID ?? "<nil>") providerGameID=\(selectedGame.providerGameID ?? "<nil>") initialAwayStarter=\(selectedGame.awayStartingPitcherName ?? "<nil>") initialHomeStarter=\(selectedGame.homeStartingPitcherName ?? "<nil>")")
            #endif
        }

        guard let detailSource = repository as? any KBOGameDetailSnapshotDataSource else {
            #if DEBUG
            print("[GameDetailFetch] mode=singleGame selectedIdentity=\(gameIdentity) skipped=unsupportedRepository")
            if selectedGame.status == .upcoming && forceRefresh == false {
                print("[GameDetailStarterRefresh] skipped reason=unsupportedRepository selectedIdentity=\(gameIdentity)")
            }
            #endif
            AppLog.warning(.gameDetail, "[GameDetail] refresh skipped game=\(operationalGameIdentifier(for: selectedGame)) reason=unsupportedRepository finalStatus=\(selectedGame.status.rawValue)")
            return GameDetailRefreshResult(
                game: selectedGame,
                rawSupabaseGameID: rawSupabaseGameDetailIdentity(for: selectedGame)?.supabaseGameID,
                providerGameID: selectedGame.providerGameID,
                publicGameID: selectedGame.publicGameID
            )
        }

        #if DEBUG
            print("[GameDetailFetch] mode=singleGame selectedIdentity=\(gameIdentity) stableIdentity=\(selectedGame.stableDetailIdentity) start before=\(debugGameIdentifier(for: selectedGame)) status=\(selectedGame.status.rawValue) score=\(scoreDebugText(selectedGame)) inning=\(selectedGame.inningText ?? "<nil>") force=\(forceRefresh)")
        #endif

        do {
            let previousKnownGames = allKnownGames()
            let snapshotResult: GameDetailSnapshotFetchResult?
            if let resultSource = repository as? any KBOGameDetailSnapshotResultDataSource {
                snapshotResult = try await resultSource.fetchGameDetailSnapshotResult(
                    for: selectedGame,
                    identity: gameIdentity,
                    cachedTeams: teams
                )
            } else if let incomingGame = try await detailSource.fetchGameDetailSnapshot(
                for: selectedGame,
                identity: gameIdentity,
                cachedTeams: teams
            ) {
                snapshotResult = GameDetailSnapshotFetchResult(
                    game: incomingGame,
                    rawSupabaseGameID: nil,
                    providerGameID: incomingGame.providerGameID,
                    publicGameID: incomingGame.publicGameID
                )
            } else {
                snapshotResult = nil
            }

            guard let snapshotResult else {
                #if DEBUG
                print("[GameDetailFetch] mode=singleGame selectedIdentity=\(gameIdentity) fetched count=0 sharedUpdated=false")
                if selectedGame.status == .upcoming && forceRefresh == false {
                    print("[GameDetailStarterRefresh] skipped reason=noRows selectedIdentity=\(gameIdentity) initialAwayStarter=\(selectedGame.awayStartingPitcherName ?? "<nil>") initialHomeStarter=\(selectedGame.homeStartingPitcherName ?? "<nil>")")
                }
                #endif
                AppLog.warning(.gameDetail, "[GameDetail] refresh empty game=\(operationalGameIdentifier(for: selectedGame)) reason=noRows finalStatus=\(selectedGame.status.rawValue)")
                return GameDetailRefreshResult(
                    game: selectedGame,
                    rawSupabaseGameID: rawSupabaseGameDetailIdentity(for: selectedGame)?.supabaseGameID,
                    providerGameID: selectedGame.providerGameID,
                    publicGameID: selectedGame.publicGameID
                )
            }
            let incomingGame = snapshotResult.game
            AppLog.info(.gameDetail, "[GameDetail] snapshot received game=\(operationalGameIdentifier(for: incomingGame)) publicGameID=\(incomingGame.publicGameID ?? "<nil>") providerGameID=\(incomingGame.providerGameID ?? incomingGame.officialProviderGameID ?? "<nil>") inning=\(incomingGame.inningText ?? "<nil>") score=\(scoreDebugText(incomingGame)) count=\(incomingGame.balls.map(String.init) ?? "-")/\(incomingGame.strikes.map(String.init) ?? "-")/\(incomingGame.outs.map(String.init) ?? "-") source=\(snapshotResult.rawSupabaseGameID == nil ? "repository" : "supabase") status=\(incomingGame.status.rawValue)")
            let resolvedIncomingGame = selectedGame.status == .upcoming && forceRefresh == false
                ? GameMergeResolver.preferredGame(existing: selectedGame, candidate: incomingGame)
                : incomingGame

            let upsertResult = upsertScheduleGamesIntoLocalStore([resolvedIncomingGame], source: .gameDetailRefresh)
            let cacheUpsertResult = await upsertScheduleGamesIntoRepositoryCache([resolvedIncomingGame])
            await refreshLoadedScheduleMonthsFromLocalStore(
                including: scheduleMonthKey(for: resolvedIncomingGame.scheduledStart),
                reason: "gameDetailRefresh"
            )
            let resolved = game(withIdentity: resolvedIncomingGame.canonicalGameIdentityValue) ??
                game(withIdentity: gameIdentity) ??
                resolvedIncomingGame
            recordRawSupabaseGameDetailIdentity(snapshotResult, selectedGame: selectedGame, incomingGame: resolvedIncomingGame, resolvedGame: resolved, requestedIdentity: gameIdentity)
            let sharedUpdated = upsertResult.inserted > 0 ||
                upsertResult.updated > 0 ||
                cacheUpsertResult.inserted > 0 ||
                cacheUpsertResult.updated > 0
            #if DEBUG
            print("[GameDetailFetch] mode=singleGame selectedIdentity=\(gameIdentity) stableIdentity=\(selectedGame.stableDetailIdentity) completed changed=\(resolved != selectedGame) before=\(selectedGame.status.rawValue) \(scoreDebugText(selectedGame)) incoming=\(incomingGame.status.rawValue) \(scoreDebugText(incomingGame)) after=\(resolved.status.rawValue) \(scoreDebugText(resolved)) sharedUpdated=\(sharedUpdated) dateWideFetch=false")
            if selectedGame.status == .upcoming && forceRefresh == false {
                let appliedStarterUpdate = selectedGame.awayStartingPitcherName != resolved.awayStartingPitcherName ||
                    selectedGame.homeStartingPitcherName != resolved.homeStartingPitcherName
                print("[GameDetailStarterRefresh] success selectedIdentity=\(gameIdentity) fetchedAwayStarter=\(incomingGame.awayStartingPitcherName ?? "<nil>") fetchedHomeStarter=\(incomingGame.homeStartingPitcherName ?? "<nil>") appliedStarterUpdate=\(appliedStarterUpdate)")
            }
            #endif
            AppLog.info(.gameDetail, "[GameDetail] refresh completed game=\(operationalGameIdentifier(for: resolved)) before=\(selectedGame.status.rawValue) incoming=\(incomingGame.status.rawValue) finalStatus=\(resolved.status.rawValue) sharedUpdated=\(sharedUpdated)")
            await notifyCancellationTransitions(previousGames: previousKnownGames, updatedGames: [resolved])
            await notifyGameContentTransitions(previousGames: previousKnownGames, updatedGames: [resolved])
            await syncFavoriteTeamLiveActivity()
            if shouldSyncFavoriteTeamWidget(afterGameUpdate: resolved) {
                await syncFavoriteTeamWidgetSnapshot(includePrefetch: false, reason: "gameDetailRefresh")
            } else {
                #if DEBUG
                print("[WidgetSnapshot] skipped reason=detailGameOutsideVisibleFavoriteTodaySnapshot gameID=\(resolved.id.uuidString)")
                #endif
            }
            return GameDetailRefreshResult(
                game: resolved,
                rawSupabaseGameID: snapshotResult.rawSupabaseGameID,
                providerGameID: snapshotResult.providerGameID ?? resolved.providerGameID,
                publicGameID: snapshotResult.publicGameID ?? resolved.publicGameID
            )
        } catch is CancellationError {
            #if DEBUG
            print("[GameDetailFetch] mode=singleGame selectedIdentity=\(gameIdentity) cancelled=true")
            if selectedGame.status == .upcoming && forceRefresh == false {
                print("[GameDetailStarterRefresh] skipped reason=cancelled selectedIdentity=\(gameIdentity)")
            }
            #endif
            AppLog.warning(.gameDetail, "[GameDetail] refresh cancelled game=\(operationalGameIdentifier(for: selectedGame)) selectedIdentity=\(gameIdentity)")
            return GameDetailRefreshResult(
                game: selectedGame,
                rawSupabaseGameID: rawSupabaseGameDetailIdentity(for: selectedGame)?.supabaseGameID,
                providerGameID: selectedGame.providerGameID,
                publicGameID: selectedGame.publicGameID
            )
        } catch {
            #if DEBUG
            print("[GameDetailFetch] mode=singleGame selectedIdentity=\(gameIdentity) failed error=\(error)")
            if selectedGame.status == .upcoming && forceRefresh == false {
                print("[GameDetailStarterRefresh] skipped reason=error selectedIdentity=\(gameIdentity)")
            }
            #endif
            AppLog.error(.gameDetail, "[GameDetail] refresh failed game=\(operationalGameIdentifier(for: selectedGame)) selectedIdentity=\(gameIdentity) error=\(error)")
            return GameDetailRefreshResult(
                game: selectedGame,
                rawSupabaseGameID: rawSupabaseGameDetailIdentity(for: selectedGame)?.supabaseGameID,
                providerGameID: selectedGame.providerGameID,
                publicGameID: selectedGame.publicGameID
            )
        }
    }

    // recordRawSupabaseGameDetailIdentity 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    private func recordRawSupabaseGameDetailIdentity(
        _ result: GameDetailSnapshotFetchResult,
        selectedGame: GameDetail,
        incomingGame: GameDetail,
        resolvedGame: GameDetail,
        requestedIdentity: String
    ) {
        guard let rawSupabaseGameID = result.rawSupabaseGameID else { return }
        let identity = RawSupabaseGameDetailIdentity(
            supabaseGameID: rawSupabaseGameID,
            providerGameID: result.providerGameID ?? incomingGame.providerGameID ?? resolvedGame.providerGameID,
            publicGameID: result.publicGameID ?? incomingGame.publicGameID ?? resolvedGame.publicGameID
        )
        let keys = [
            requestedIdentity,
            selectedGame.id.uuidString,
            selectedGame.stableDetailIdentity,
            selectedGame.canonicalGameIdentityValue,
            incomingGame.id.uuidString,
            incomingGame.stableDetailIdentity,
            incomingGame.canonicalGameIdentityValue,
            resolvedGame.id.uuidString,
            resolvedGame.stableDetailIdentity,
            resolvedGame.canonicalGameIdentityValue,
            incomingGame.providerGameID.map { "provider:\($0)" },
            resolvedGame.providerGameID.map { "provider:\($0)" },
            incomingGame.publicGameID.map { "public:\($0)" },
            resolvedGame.publicGameID.map { "public:\($0)" }
        ].compactMap { $0?.nilIfBlank }
        for key in Set(keys) {
            rawSupabaseGameDetailIdentities[key] = identity
        }
        #if DEBUG
        print("[GameDetailDBRecords] rawSupabaseGameId cached localGameId=\(selectedGame.id.uuidString) rawSupabaseGameId=\(rawSupabaseGameID.uuidString) providerGameID=\(identity.providerGameID ?? "<nil>") publicGameID=\(identity.publicGameID ?? "<nil>")")
        #endif
    }

    // rawSupabaseGameDetailIdentity 메서드는 이 타입의 주요 동작을 수행합니다.
    private func rawSupabaseGameDetailIdentity(for game: GameDetail) -> RawSupabaseGameDetailIdentity? {
        let keys = [
            game.id.uuidString,
            game.stableDetailIdentity,
            game.canonicalGameIdentityValue,
            game.providerGameID.map { "provider:\($0)" },
            game.publicGameID.map { "public:\($0)" }
        ].compactMap { $0?.nilIfBlank }
        for key in keys {
            if let identity = rawSupabaseGameDetailIdentities[key] {
                return identity
            }
        }
        return nil
    }

    // gameNavigationIdentity 메서드는 이 타입의 주요 동작을 수행합니다.
    func gameNavigationIdentity(for game: GameDetail) -> String {
        game.canonicalGameIdentityValue
    }

    // gameNavigationIdentity 메서드는 이 타입의 주요 동작을 수행합니다.
    func gameNavigationIdentity(for summary: GameSummary) -> String {
        game(withID: summary.id)?.canonicalGameIdentityValue ?? summary.id.uuidString
    }

    // shouldShowLiveActivityAction 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    func shouldShowLiveActivityAction(for game: GameDetail) -> Bool {
        LiveActivityActionPresentation.shouldShow(
            game: game,
            favoriteTeamID: settings.favoriteTeamID
        )
    }

    // shouldAutoStartLiveActivity 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    func shouldAutoStartLiveActivity(for game: GameDetail) -> Bool {
        game.involves(teamID: settings.favoriteTeamID) &&
            LiveActivityAutoStartEligibility.isEligibleForAutomaticLiveActivityStart(
                game: game,
                now: currentDateProvider()
            )
    }

    // isLiveActivityOn 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    func isLiveActivityOn(for gameID: UUID) -> Bool {
        activeLiveActivityGameID == gameID
    }

    // isLiveActivityActionEnabled 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    func isLiveActivityActionEnabled(for game: GameDetail) -> Bool {
        LiveActivityActionPresentation.isEnabled(
            game: game,
            favoriteTeamID: settings.favoriteTeamID,
            liveActivitiesEnabled: settings.liveActivitiesEnabled,
            liveActivitySupported: liveActivitySupported
        )
    }

    // liveActivityButtonTitle 메서드는 이 타입의 주요 동작을 수행합니다.
    func liveActivityButtonTitle(for game: GameDetail) -> String {
        LiveActivityActionPresentation.buttonTitle(
            game: game,
            favoriteTeamID: settings.favoriteTeamID,
            liveActivitiesEnabled: settings.liveActivitiesEnabled,
            liveActivitySupported: liveActivitySupported,
            isActive: isLiveActivityOn(for: game.id)
        )
    }

    // liveActivityButtonSystemImage 메서드는 이 타입의 주요 동작을 수행합니다.
    func liveActivityButtonSystemImage(for game: GameDetail) -> String {
        LiveActivityActionPresentation.buttonSystemImage(isActive: isLiveActivityOn(for: game.id))
    }

    // toggleLiveActivity 메서드는 이 타입의 주요 동작을 수행합니다.
    func toggleLiveActivity(for game: GameDetail) async {
        guard shouldShowLiveActivityAction(for: game) else { return }

        if isLiveActivityOn(for: game.id) {
            AppLog.info(.liveActivity, "[LiveActivity] end requested source=manual game=\(operationalGameIdentifier(for: game)) status=\(game.status.rawValue)")
            await liveActivityController.endCurrent()
            activeLiveActivityGameID = nil
            return
        }

        guard isLiveActivityActionEnabled(for: game),
              let snapshot = FavoriteTeamLiveActivitySnapshot.make(from: game, favoriteTeamID: settings.favoriteTeamID) else {
            AppLog.info(.liveActivity, "[LiveActivity] start rejected source=manual game=\(operationalGameIdentifier(for: game)) reason=actionDisabledOrSnapshotMissing status=\(game.status.rawValue)")
            return
        }

        do {
            AppLog.info(.liveActivity, "[LiveActivity] start requested source=manual game=\(operationalGameIdentifier(for: game)) status=\(game.status.rawValue)")
            try await liveActivityController.startOrUpdate(using: snapshot)
            activeLiveActivityGameID = game.id
            AppLog.info(.liveActivity, "[LiveActivity] start completed source=manual game=\(operationalGameIdentifier(for: game)) status=\(game.status.rawValue)")
        } catch {
            activeLiveActivityGameID = nil
            AppLog.error(.liveActivity, "[LiveActivity] start failed source=manual game=\(operationalGameIdentifier(for: game)) error=\(error)")
        }
    }

    // startOrUpdateLiveActivityIfNeeded 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    func startOrUpdateLiveActivityIfNeeded(for game: GameDetail) async {
        liveActivitySupported = liveActivityController.isSupported
        let resolvedGame = self.game(withIdentity: game.canonicalGameIdentityValue) ??
            self.game(withIdentity: game.stableDetailIdentity) ??
            game

        guard settings.liveActivitiesEnabled else {
            logLiveActivityAutoStartSkipped(reason: "disabledInSettings", game: resolvedGame)
            return
        }

        guard liveActivitySupported else {
            logLiveActivityAutoStartSkipped(reason: "unsupported", game: resolvedGame)
            return
        }

        guard resolvedGame.involves(teamID: settings.favoriteTeamID) else {
            logLiveActivityAutoStartSkipped(reason: "noFavoriteTeam", game: resolvedGame)
            return
        }

        let eligibilityDecision = LiveActivityAutoStartEligibility.decision(
            for: resolvedGame,
            now: currentDateProvider()
        )
        guard eligibilityDecision == .eligible else {
            logLiveActivityAutoStartSkipped(reason: eligibilityDecision.logReason, game: resolvedGame)
            return
        }

        #if DEBUG
        print("[LiveActivityAutoStart] eligible gameID=\(resolvedGame.id.uuidString) status=\(resolvedGame.status.rawValue) scheduledAt=\(resolvedGame.scheduledStart)")
        #endif
        AppLog.info(.liveActivity, "[LiveActivity] autoStart allowed game=\(operationalGameIdentifier(for: resolvedGame)) status=\(resolvedGame.status.rawValue) scheduledAt=\(resolvedGame.scheduledStart)")

        guard let snapshot = FavoriteTeamLiveActivitySnapshot.make(from: resolvedGame, favoriteTeamID: settings.favoriteTeamID) else {
            logLiveActivityAutoStartSkipped(reason: "snapshotMissing", game: resolvedGame)
            return
        }

        do {
            AppLog.info(.liveActivity, "[LiveActivity] startOrUpdate requested source=auto game=\(operationalGameIdentifier(for: resolvedGame)) status=\(resolvedGame.status.rawValue)")
            try await liveActivityController.startOrUpdate(using: snapshot)
            activeLiveActivityGameID = resolvedGame.id
            AppLog.info(.liveActivity, "[LiveActivity] startOrUpdate completed source=auto game=\(operationalGameIdentifier(for: resolvedGame)) status=\(resolvedGame.status.rawValue)")
        } catch {
            #if DEBUG
            print("[LiveActivityPayload] auto start/update failed gameID=\(resolvedGame.id.uuidString) error=\(error)")
            #endif
            AppLog.error(.liveActivity, "[LiveActivity] startOrUpdate failed source=auto game=\(operationalGameIdentifier(for: resolvedGame)) error=\(error)")
        }
    }

    // logLiveActivityAutoStartSkipped 메서드는 이 타입의 주요 동작을 수행합니다.
    private func logLiveActivityAutoStartSkipped(reason: String, game: GameDetail) {
        AppLog.info(.liveActivity, "[LiveActivity] autoStart rejected game=\(operationalGameIdentifier(for: game)) reason=\(reason) status=\(game.status.rawValue) scheduledAt=\(game.scheduledStart)")
        #if DEBUG
        print("[LiveActivityAutoStart] skipped reason=\(reason) gameID=\(game.id.uuidString) status=\(game.status.rawValue) scheduledAt=\(game.scheduledStart)")
        #endif
    }

    // isGameAlertEnabled 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    func isGameAlertEnabled(for gameID: UUID) -> Bool {
        gameAlertOverrides[gameID, default: true]
    }

    // setGameAlert 메서드는 이 타입의 주요 동작을 수행합니다.
    func setGameAlert(_ isEnabled: Bool, for gameID: UUID) {
        gameAlertOverrides[gameID] = isEnabled
    }

    // isGameAttended 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    func isGameAttended(_ game: GameDetail) -> Bool {
        AttendanceKeyResolver.isAttended(
            game: game,
            equivalentGames: equivalentGames(to: game),
            attendedKeys: attendedGameKeys
        )
    }

    // toggleGameAttendance 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // markNotificationRead 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    func markNotificationRead(_ notificationID: UUID) {
        guard let index = notifications.firstIndex(where: { $0.id == notificationID }) else { return }
        notifications[index].isRead = true
        persistNotificationHistory()
    }

    // notificationGameDetailNavigationIdentity 메서드는 이 타입의 주요 동작을 수행합니다.
    func notificationGameDetailNavigationIdentity(for item: NotificationItem) -> String? {
        let selectedIdentity = item.preferredGameNavigationIdentity
        #if DEBUG
        print("[NotificationNavigation] notificationTap notificationID=\(item.id.uuidString) gamePublicID=\(item.gamePublicID ?? item.publicGameID ?? "<nil>") providerGameID=\(item.gameProviderID ?? "<nil>") selectedIdentity=\(selectedIdentity ?? "<nil>")")
        #endif
        guard let selectedIdentity else {
            #if DEBUG
            print("[NotificationNavigation] notificationTap skipped notificationID=\(item.id.uuidString) reason=missingGameIdentity")
            #endif
            return nil
        }
        if let match = selectedGameMatch(for: selectedIdentity) {
            #if DEBUG
            print("[GameDetailFetch] gameDetailNavigation resolvedBy=local selectedIdentity=\(selectedIdentity) publicGameID=\(match.game.publicGameID ?? "<nil>") providerGameID=\(match.game.providerGameID ?? "<nil>") reason=\(match.reason)")
            #endif
        } else {
            #if DEBUG
            let resolvedBy: String
            if selectedIdentity.hasPrefix("public:") || item.gamePublicID != nil || item.publicGameID != nil {
                resolvedBy = "public"
            } else if selectedIdentity.hasPrefix("provider:") || item.gameProviderID != nil {
                resolvedBy = "provider"
            } else if selectedIdentity.hasPrefix("id:") {
                resolvedBy = "id"
            } else {
                resolvedBy = "fetch"
            }
            print("[GameDetailFetch] gameDetailNavigation resolvedBy=\(resolvedBy) selectedIdentity=\(selectedIdentity) localMatch=false")
            #endif
        }
        return selectedIdentity
    }

    // connectNotificationDelegate 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

    // refreshNotificationAuthorizationStatus 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    func refreshNotificationAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorizationStatus = AppNotificationAuthorizationStatus(settings.authorizationStatus)
        #if DEBUG
        print("[NotificationPipeline] authorizationStatus=\(notificationAuthorizationStatus.rawValue)")
        #endif
        scheduleNotificationRegistrationSync(force: false)
    }

    // syncNotificationRegistrationState 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
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

    // requestNotificationAuthorization 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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
            scheduleNotificationRegistrationSync(force: false)
        } catch {
            await refreshNotificationAuthorizationStatus()
            #if DEBUG
            print("[NotificationPipeline] requestAuthorization failed error=\(error)")
            #endif
        }
    }

    // scheduleDebugNotification 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    func scheduleDebugNotification() async {
        #if DEBUG
        let targetGame = myTeamTodayGame ?? todayGames.first ?? games.first
        let payload = ScoreNotificationPayload(
            gameID: targetGame.map { resolvedRawGameID(for: $0) },
            eventType: .scoreChange,
            title: "테스트 스코어 알림",
            body: targetGame.map { "\($0.awayTeam.displayName) vs \($0.homeTeam.displayName) 상세로 이동합니다." } ?? "게임 상세 이동 경로를 확인합니다.",
            publicGameID: targetGame?.publicGameID,
            providerGameID: targetGame.flatMap { $0.officialGameCenterID ?? $0.providerGameID },
            gameDatabaseID: targetGame?.id.uuidString,
            stableGameIdentity: targetGame?.stableDetailIdentity,
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

    // dismissPresentedGameDetail 메서드는 이 타입의 주요 동작을 수행합니다.
    func dismissPresentedGameDetail() {
        presentedGameIdentity = nil
    }

    // presentNotifications 메서드는 이 타입의 주요 동작을 수행합니다.
    func presentNotifications() {
        isNotificationsPresented = true
    }

    // dismissNotifications 메서드는 이 타입의 주요 동작을 수행합니다.
    func dismissNotifications() {
        isNotificationsPresented = false
    }

    // previewModel 메서드는 이 타입의 주요 동작을 수행합니다.
    static func previewModel() -> AppModel {
        AppModel(bootstrap: MockKBOData.makeBootstrap(), usePersistedSettings: false)
    }

    // loadMyTeamSchedule 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
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

    // performLoadMyTeamSchedule 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

    // loadScheduleMonthFromRepository 메서드는 필요한 데이터를 조회하고 로딩 상태를 갱신합니다.
    private func loadScheduleMonthFromRepository(
        for key: KBOMonthScheduleKey,
        reason: String,
        loadID: String,
        bypassingCache: Bool
    ) async {
        let startedAt = Date()
        do {
            let fetched = try await repository.fetchMonthlySchedule(for: key, bypassingCache: bypassingCache)
            let snapshot = await refreshMonthlyScheduleDebugInfo(for: key)
            let normalized = await reconcileOfficialScheduleStartTimesIfNeeded(
                in: fetched,
                snapshot: snapshot
            )
            monthlyScheduleGames[key] = mergeMonthlyScheduleGames(normalized, for: key)
                .sorted { $0.scheduledStart < $1.scheduledStart }
            failedScheduleMonths.remove(key)
            invalidateScheduleDerivedCaches(for: key)
            await syncFavoriteTeamWidgetSnapshot(
                includePrefetch: false,
                reason: "scheduleMonthLoad:\(reason)",
                monthKey: key
            )
            #if DEBUG
            print("[ScheduleCache] month=\(key.yearMonthText) source=repository reason=\(reason) loadID=\(loadID) gameCount=\(monthlyScheduleGames[key]?.count ?? 0) scheduleMonthLoad skippedGlobalMerge=true durationMs=\(Self.durationMilliseconds(since: startedAt))")
            #endif
        } catch {
            failedScheduleMonths.insert(key)
            #if DEBUG
            print("[ScheduleCache] month=\(key.yearMonthText) source=repository reason=\(reason) failed durationMs=\(Self.durationMilliseconds(since: startedAt)) error=\(error)")
            #endif
            await hydrateScheduleMonthFromLocalStore(for: key, reason: reason, loadID: loadID)
        }
    }

    // hydrateScheduleMonthFromLocalStore 메서드는 이 타입의 주요 동작을 수행합니다.
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
        await syncFavoriteTeamWidgetSnapshot(
            includePrefetch: false,
            reason: "scheduleMonthLocalHydrate:\(reason)",
            monthKey: key
        )
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
    }

    // runStartupScheduleCountCheckIfNeeded 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // performStartupScheduleCountCheck 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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
            let upsertResult = upsertScheduleGamesIntoLocalStore(result.games, source: .startupSync)
            await refreshLoadedScheduleMonthsFromLocalStore(reason: "startupSyncLocalStoreRefresh")
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

    // refreshTodayGamesFromSupabase 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    private func refreshTodayGamesFromSupabase(
        for date: Date,
        monthKey: KBOMonthScheduleKey,
        reason: String
    ) async -> [GameDetail] {
        let dayKey = scheduleDayKey(for: date)
        let todayKey = scheduleDayKey(for: currentDateProvider())
        guard dayKey == todayKey else {
            #if DEBUG
            print("[ScheduleCache] selectedDate=\(dayKey) source=local reason=\(reason) gameCount=\((groupedScheduleGamesByDay(for: date, filter: .all)[dayKey] ?? []).count)")
            #endif
            return []
        }
        let explicitReasons: Set<String> = ["manualTodayRefresh", "manualRefresh", "liveActivity", "notification", "scheduleTodayLiveRefresh"]
        guard explicitReasons.contains(reason) else {
            #if DEBUG
            print("[ScheduleSync] todayLiveRefresh skipped date=\(dayKey) reason=\(reason)")
            #endif
            return []
        }
        if let existingTask = inFlightTodayLiveRefreshTasks[dayKey] {
            #if DEBUG
            print("[ScheduleSync] todayLiveRefresh source=inFlight reason=awaitExistingFetch date=\(dayKey)")
            #endif
            return await existingTask.value
        }
        if reason != "manualTodayRefresh",
           let refreshedAt = lastTodayLiveRefreshAt[dayKey],
           Date().timeIntervalSince(refreshedAt) < 15 {
            #if DEBUG
            print("[ScheduleSync] todayLiveRefresh skipped date=\(dayKey) reason=recent")
            #endif
            return []
        }

        let task = Task<[GameDetail], Never> { @MainActor [weak self] in
            guard let self else { return [GameDetail]() }
            return await self.performRefreshTodayGamesFromSupabase(
                for: date,
                monthKey: monthKey,
                dayKey: dayKey,
                todayKey: todayKey,
                reason: reason
            )
        }
        inFlightTodayLiveRefreshTasks[dayKey] = task
        let refreshedGames = await task.value
        inFlightTodayLiveRefreshTasks[dayKey] = nil
        return refreshedGames
    }

    // performRefreshTodayGamesFromSupabase 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    private func performRefreshTodayGamesFromSupabase(
        for date: Date,
        monthKey: KBOMonthScheduleKey,
        dayKey: String,
        todayKey: String,
        reason: String
    ) async -> [GameDetail] {
        do {
            let previousKnownGames = allKnownGames()
            #if DEBUG
            print("[ScheduleSync] todayLiveRefresh start date=\(dayKey) reason=\(reason)")
            #endif
            let fetched = try await repository.fetchSchedule(for: date, bypassingCache: true)
            #if DEBUG
            print("[ScheduleSync] todayRefresh date=\(dayKey) fetched=\(fetched.count)")
            #endif
            let upsertResult = upsertScheduleGamesIntoLocalStore(fetched, source: .todayLiveRefresh)
            let cacheUpsertResult = await upsertScheduleGamesIntoRepositoryCache(fetched)
            await refreshLoadedScheduleMonthsFromLocalStore(
                including: monthKey,
                reason: "todayLiveRefreshLocalStoreRefresh"
            )
            monthlyScheduleRefreshDayKeys[monthKey] = todayKey
            lastTodayLiveRefreshAt[dayKey] = Date()
            #if DEBUG
            print("[ScheduleSync] todayRefreshUpsert inserted=\(upsertResult.inserted) updated=\(upsertResult.updated) skippedExisting=\(upsertResult.skippedExisting)")
            print("[ScheduleSync] todayRefreshCacheUpsert inserted=\(cacheUpsertResult.inserted) updated=\(cacheUpsertResult.updated) skippedExisting=\(cacheUpsertResult.skippedExisting)")
            #endif
            await notifyCancellationTransitions(previousGames: previousKnownGames, updatedGames: fetched)
            await notifyGameContentTransitions(previousGames: previousKnownGames, updatedGames: fetched)
            await syncFavoriteTeamLiveActivity()
            await syncFavoriteTeamWidgetSnapshot(
                includePrefetch: false,
                reason: "todayLiveRefresh",
                monthKey: monthKey
            )
            return fetched
        } catch is CancellationError {
            #if DEBUG
            print("[ScheduleSync] todayRefresh date=\(dayKey) cancelled=true usingLocalOnly")
            #endif
            return []
        } catch {
            #if DEBUG
            print("[ScheduleSync] todayRefresh date=\(dayKey) failed usingLocalOnly error=\(error)")
            #endif
            return []
        }
    }

    // upsertScheduleGamesIntoRepositoryCache 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    private func upsertScheduleGamesIntoRepositoryCache(_ incomingGames: [GameDetail]) async -> (inserted: Int, updated: Int, skippedExisting: Int) {
        guard let localStore = repository as? any KBOLocalGameCacheUpserting else {
            return (0, 0, incomingGames.count)
        }
        return await localStore.upsertLocalGames(incomingGames)
    }

    // upsertScheduleGamesIntoLocalStore 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    private func upsertScheduleGamesIntoLocalStore(
        _ incomingGames: [GameDetail],
        source: ScheduleGameMergeSource = .unspecified
    ) -> (inserted: Int, updated: Int, skippedExisting: Int) {
        var updatedGames = games
        var inserted = 0
        var updated = 0
        var skippedExisting = 0
        var standingsRelevantChange = false

        for candidate in incomingGames {
            let candidateAliases = candidate.gameIdentityAliases
            if let existingIndex = updatedGames.firstIndex(where: { existing in
                existing.gameIdentityAliases.isDisjoint(with: candidateAliases) == false
            }) {
                let existing = updatedGames[existingIndex]
                let selected = GameMergeResolver.preferredGame(existing: existing, candidate: candidate)
                #if DEBUG
                logPitcherMerge(existing: existing, incoming: candidate, merged: selected)
                #endif
                if selected != existing {
                    if hasStandingsRelevantGameChange(existing: existing, selected: selected) {
                        standingsRelevantChange = true
                    }
                    updatedGames[existingIndex] = selected
                    updated += 1
                } else {
                    skippedExisting += 1
                }
            } else {
                if hasStandingsRelevantGameChange(existing: nil, selected: candidate) {
                    standingsRelevantChange = true
                }
                updatedGames.append(candidate)
                inserted += 1
            }
        }

        let mergedGames = mergeEquivalentGames(updatedGames)
            .sorted { $0.scheduledStart > $1.scheduledStart }
        if mergedGames != games {
            games = mergedGames
            invalidateScheduleDerivedCaches()
            if shouldRepublishStandingsAfterGameMerge(source: source, standingsRelevantChange: standingsRelevantChange) {
                scheduleLocalStandingsProbabilityRefresh()
                refreshPublishedStandingsRowsWithCurrentSource(
                    season: currentStandingsSeason(),
                    reason: source.rawValue
                )
            } else {
                #if DEBUG
                print("[StandingsRankMovement] republish skipped source=\(source.rawValue)")
                #endif
            }
        }
        #if DEBUG
        print("[ScheduleSync] mergeSummary source=\(source.rawValue) fetched=\(incomingGames.count) inserted=\(inserted) updated=\(updated) skipped=\(skippedExisting) standingsRelevantChange=\(standingsRelevantChange)")
        #endif
        return (inserted, updated, skippedExisting)
    }

    // shouldRepublishStandingsAfterGameMerge 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private func shouldRepublishStandingsAfterGameMerge(
        source: ScheduleGameMergeSource,
        standingsRelevantChange: Bool
    ) -> Bool {
        switch source {
        case .scheduleMonthLoad, .homeFavoriteRefresh, .todayLiveRefresh, .gameDetailRefresh, .staleReconciliation:
            return false
        case .unspecified, .standingsRefresh, .startupSync:
            break
        }
        if source == .scheduleMonthLoad, standingsRelevantChange == false {
            return false
        }
        return true
    }

    // hasStandingsRelevantGameChange 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private func hasStandingsRelevantGameChange(existing: GameDetail?, selected: GameDetail) -> Bool {
        guard selected.isRegularSeason || existing?.isRegularSeason == true else { return false }
        guard let existing else {
            return selected.hasCompleteFinalScore
        }
        return existing.seasonClassification != selected.seasonClassification ||
            existing.awayTeam.id != selected.awayTeam.id ||
            existing.homeTeam.id != selected.homeTeam.id ||
            existing.status != selected.status ||
            existing.awayScore != selected.awayScore ||
            existing.homeScore != selected.homeScore
    }

    // overlayScheduleGames 메서드는 이 타입의 주요 동작을 수행합니다.
    private func overlayScheduleGames(
        _ incomingGames: [GameDetail],
        intoMonth monthKey: KBOMonthScheduleKey,
        reason: String
    ) async -> (games: [GameDetail], before: Int, inserted: Int, updated: Int, unchanged: Int, after: Int) {
        var overlaidGames = monthlyScheduleGames[monthKey] ?? fallbackMonthSchedule(for: monthKey)
        let before = overlaidGames.count
        var inserted = 0
        var updated = 0

        for candidate in incomingGames {
            let candidateAliases = candidate.gameIdentityAliases
            if let existingIndex = overlaidGames.firstIndex(where: { existing in
                existing.gameIdentityAliases.isDisjoint(with: candidateAliases) == false
            }) {
                let existing = overlaidGames[existingIndex]
                let selected = GameMergeResolver.preferredGame(existing: existing, candidate: candidate)
                if selected != existing {
                    overlaidGames[existingIndex] = selected
                    updated += 1
                }
            } else {
                overlaidGames.append(candidate)
                inserted += 1
            }
        }

        let mergedGames = mergeEquivalentGames(overlaidGames)
            .sorted { $0.scheduledStart < $1.scheduledStart }
        monthlyScheduleGames[monthKey] = mergedGames
        invalidateScheduleDerivedCaches(for: monthKey)
        await syncFavoriteTeamWidgetSnapshot(
            includePrefetch: false,
            reason: reason,
            monthKey: monthKey
        )

        return (
            games: mergedGames,
            before: before,
            inserted: inserted,
            updated: updated,
            unchanged: max(0, mergedGames.count - inserted - updated),
            after: mergedGames.count
        )
    }

#if DEBUG
    // logPitcherMerge 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // refreshLoadedScheduleMonthsFromLocalStore 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    private func refreshLoadedScheduleMonthsFromLocalStore(
        including key: KBOMonthScheduleKey? = nil,
        reason: String
    ) async {
        var keys = Set(monthlyScheduleGames.keys)
        if let key {
            keys.insert(key)
        }
        for monthKey in keys {
            let existingMonthGames = monthlyScheduleGames[monthKey] ?? fallbackMonthSchedule(for: monthKey)
            monthlyScheduleGames[monthKey] = mergeMonthlyScheduleGames(existingMonthGames, for: monthKey)
                .sorted { $0.scheduledStart < $1.scheduledStart }
        }
        invalidateScheduleDerivedCaches()
        await syncFavoriteTeamWidgetSnapshot(
            includePrefetch: false,
            reason: reason,
            monthKey: key
        )
    }

    // scheduleMonthKey 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    private func scheduleMonthKey(for date: Date) -> KBOMonthScheduleKey {
        var scheduleCalendar = calendar
        scheduleCalendar.timeZone = scheduleTimeZone
        return KBOMonthScheduleKey(date: date, calendar: scheduleCalendar)
    }

    // refreshMonthlyScheduleDebugInfo 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    private func refreshMonthlyScheduleDebugInfo(for key: KBOMonthScheduleKey) async -> RepositoryDebugSnapshot? {
        guard let repositoryRuntimeState else { return nil }
        let snapshot = await repositoryRuntimeState.snapshot()
        monthlyScheduleDebugSnapshots[key] = snapshot
        applyRepositoryDebugSnapshot(snapshot)
        lastUpdatedAt = snapshot.lastRefreshAt ?? lastUpdatedAt
        return snapshot
    }

    // refreshGames 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
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
                logStandingsLocalCalculationSkipped(reason: "remoteRankSource", source: "gamesRefresh")
                if repositoryRuntimeState == nil {
                    markRefreshSuccess(for: .games, at: Date(), isStale: false)
                }
                await refreshRepositoryDebugInfo(dataSets: [.games])
            }
            _ = await refreshTodayGamesFromSupabase(
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

    // refreshNotifications 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
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

    // refreshRepositoryDebugInfo 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
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

    // applyRepositoryDebugSnapshot 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
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
    // debugGameIdentifier 메서드는 화면 표시와 디버그에 사용할 문구를 구성합니다.
    private func debugGameIdentifier(for game: GameDetail) -> String {
        game.publicGameID ??
            game.officialGameCenterID ??
            game.id.uuidString
    }

    private var commonStandingsUnavailableReason: PostseasonProbabilityUnavailableReason? {
        let reasons = Set(standingsSnapshots.compactMap(\.postseasonProbabilityUnavailableReason))
        guard reasons.count == 1 else { return nil }
        return reasons.first
    }

    // logGameDiagnostics 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // shouldReloadBootstrapForLocalData 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private func shouldReloadBootstrapForLocalData() async -> Bool {
        if repository is BundledJSONKBORepository {
            return true
        }

        guard let repositoryRuntimeState else { return false }
        let snapshot = await repositoryRuntimeState.snapshot()
        return snapshot.localBootstrapSource != nil ||
            (snapshot.activeSource == .mock && snapshot.baseURL == nil)
    }

    // reloadBootstrapFromRepository 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // invalidateMonthlyScheduleCache 메서드는 저장된 상태나 캐시 값을 정리합니다.
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

    // isDataSetStale 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private func isDataSetStale(_ dataSet: RefreshDataSet) -> Bool {
        if refreshFailures.contains(dataSet) {
            return true
        }

        guard let lastRefreshAt = lastSuccessfulRefresh[dataSet] else {
            return false
        }

        return Date().timeIntervalSince(lastRefreshAt) > Self.staleThreshold
    }

    // markRefreshSuccess 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
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

    // markRefreshFailure 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
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

    // localBootstrapDocumentsPath 메서드는 이 타입의 주요 동작을 수행합니다.
    private static func localBootstrapDocumentsPath() -> String? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LocalBootstrapData.json", isDirectory: false)
            .path
    }

    // staleStatusMessage 메서드는 이 타입의 주요 동작을 수행합니다.
    private func staleStatusMessage(lastRefreshAt: Date?) -> String {
        guard let lastRefreshAt else {
            return "업데이트가 지연되고 있습니다."
        }
        return "업데이트 지연 · 마지막 갱신 \(lastRefreshAt.formatted(date: .omitted, time: .shortened))"
    }

    // canonicalTeamIdentifier 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private static func canonicalTeamIdentifier(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else {
            return nil
        }

        return Team.canonicalID(for: raw) ?? raw.lowercased()
    }

    // syncFavoriteTeamWidgetSnapshot 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    private func syncFavoriteTeamWidgetSnapshot(
        includePrefetch: Bool,
        reason: String = "unspecified",
        monthKey: KBOMonthScheduleKey? = nil,
        preferredMonthGames: [GameDetail]? = nil,
        incomingSource: FavoriteTeamScheduleWidgetSnapshotSource? = nil
    ) async {
        guard settings.favoriteTeamID != nil else {
            guard lastFavoriteTeamWidgetSemanticKey != "nil" else {
                #if DEBUG
                print("[WidgetSnapshot] skipped reason=unchanged source=\(reason)")
                #endif
                return
            }
            FavoriteTeamScheduleWidgetShared.saveState(favoriteTeamID: nil, snapshot: nil)
            lastFavoriteTeamWidgetSemanticKey = "nil"
            lastFavoriteTeamWidgetSnapshot = nil
            reloadFavoriteTeamWidgetTimelines()
            return
        }

        if includePrefetch {
            await prepareFavoriteTeamWidgetScheduleIfNeeded()
        }

        let resolvedIncomingSource = incomingSource ?? favoriteTeamWidgetSnapshotSource(for: reason)
        let widgetMonthKey = currentWidgetMonthKey()
        if reason.contains("favoriteTeamChanged") == false,
           shouldPreserveFullMonthWidgetSnapshot(
            monthKey: widgetMonthKey,
            incomingSource: resolvedIncomingSource,
            incomingMonthGames: preferredMonthGames
        ) {
            return
        }

        let snapshot = makeFavoriteTeamWidgetSnapshot(
            referenceDate: currentDateProvider(),
            preferredMonthKey: monthKey,
            preferredMonthGames: preferredMonthGames
        )
        let semanticKey = FavoriteTeamWidgetSnapshotBuilder.semanticKey(
            favoriteTeamID: settings.favoriteTeamID,
            snapshot: snapshot
        )
        guard semanticKey != lastFavoriteTeamWidgetSemanticKey else {
            #if DEBUG
            print("[WidgetSnapshot] skipped reason=unchanged source=\(reason)")
            #endif
            return
        }
        logFavoriteTeamScheduleWidgetStoreSave(
            reason: reason,
            monthKey: widgetMonthKey,
            snapshot: snapshot,
            sourceMonthlyGames: preferredMonthGames
        )
        FavoriteTeamScheduleWidgetShared.saveState(favoriteTeamID: settings.favoriteTeamID, snapshot: snapshot)
        lastFavoriteTeamWidgetSemanticKey = semanticKey
        lastFavoriteTeamWidgetSnapshot = snapshot
        reloadFavoriteTeamWidgetTimelines()
    }

    // shouldSyncFavoriteTeamWidget 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private func shouldSyncFavoriteTeamWidget(afterGameUpdate game: GameDetail) -> Bool {
        guard let favoriteTeamID = settings.favoriteTeamID else { return true }
        if game.involves(teamID: favoriteTeamID) {
            return true
        }
        return scheduleDayKey(for: game.scheduledStart) == scheduleDayKey(for: currentDateProvider())
    }

    private func favoriteTeamWidgetSnapshotSource(for reason: String) -> FavoriteTeamScheduleWidgetSnapshotSource {
        if reason.contains("scheduleTab") {
            return .scheduleTabCurrentMonth
        }
        if reason.contains("scheduleMonth") {
            return .appModelMonthly
        }
        if reason.contains("today") || reason.contains("Today") || reason.contains("liveActivity") {
            return .todayLiveRefresh
        }
        if reason.contains("homeFavorite") || reason.contains("home") {
            return .homeFavoriteRefresh
        }
        return .unspecified
    }

    // shouldPreserveFullMonthWidgetSnapshot 메서드는 작은 오늘 데이터가 월간 스냅샷을 덮지 않게 방어합니다.
    private func shouldPreserveFullMonthWidgetSnapshot(
        monthKey: KBOMonthScheduleKey?,
        incomingSource: FavoriteTeamScheduleWidgetSnapshotSource,
        incomingMonthGames: [GameDetail]?
    ) -> Bool {
        guard let monthKey,
              let existingSource = favoriteTeamWidgetMonthSources[monthKey],
              existingSource.source.rawValue > incomingSource.rawValue else {
            return false
        }
        let incomingCount = incomingMonthGames?.count ?? widgetSourceMonthlyGames(for: monthKey).count
        guard incomingCount < existingSource.games.count else { return false }
        #if DEBUG
        print("[WidgetSnapshot] skipped reason=preserveFullMonthSnapshot incomingSource=\(incomingSource.logName) incomingCount=\(incomingCount) existingCount=\(existingSource.games.count) month=\(monthKey.yearMonthText)")
        #endif
        return true
    }

    // prepareFavoriteTeamWidgetScheduleIfNeeded 메서드는 이 타입의 주요 동작을 수행합니다.
    private func prepareFavoriteTeamWidgetScheduleIfNeeded() async {
        guard settings.favoriteTeamID != nil else { return }

        let scheduleCalendar = widgetScheduleCalendar()
        let today = scheduleCalendar.startOfDay(for: currentDateProvider())
        let requestedMonth = startOfMonth(for: today, calendar: scheduleCalendar)

        await loadMyTeamSchedule(for: requestedMonth, forceRefresh: false)

        if let resolvedMonth = nearestScheduleMonth(to: requestedMonth, filter: .myTeam),
           scheduleCalendar.isDate(resolvedMonth, equalTo: requestedMonth, toGranularity: .month) == false {
            await loadMyTeamSchedule(for: resolvedMonth, forceRefresh: false)
        }
    }

    // makeFavoriteTeamWidgetSnapshot 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    private func makeFavoriteTeamWidgetSnapshot(
        referenceDate: Date = Date(),
        preferredMonthKey: KBOMonthScheduleKey? = nil,
        preferredMonthGames: [GameDetail]? = nil
    ) -> FavoriteTeamScheduleWidgetSnapshot? {
        guard let favoriteTeam = favoriteTeamWidgetMetadata() else { return nil }

        let scheduleCalendar = widgetScheduleCalendar()
        let currentMonthKey = currentWidgetMonthKey()
        let requestedMonth = monthStart(for: currentMonthKey, calendar: scheduleCalendar)
        let hasAnyMyTeamGames = knownScheduleGames(filter: .myTeam).isEmpty == false
        let displayedMonthKey = currentMonthKey
        let displayedMonthSourceGames: [GameDetail]?
        if preferredMonthKey == currentMonthKey {
            displayedMonthSourceGames = preferredMonthGames ?? favoriteTeamWidgetMonthSources[displayedMonthKey]?.games
        } else {
            displayedMonthSourceGames = favoriteTeamWidgetMonthSources[displayedMonthKey]?.games
        }
        let calendarDays: [MyTeamCalendarDay]
        if let displayedMonthSourceGames {
            calendarDays = favoriteTeamWidgetCalendarDays(
                monthKey: displayedMonthKey,
                monthGames: displayedMonthSourceGames,
                favoriteTeamID: favoriteTeam.id,
                calendar: scheduleCalendar
            )
        } else {
            calendarDays = scheduleCalendarDays(for: requestedMonth, filter: .myTeam)
        }

        if hasAnyMyTeamGames == false && games.isEmpty && monthlyScheduleGames.isEmpty && displayedMonthSourceGames == nil {
            return nil
        }

        return FavoriteTeamWidgetSnapshotBuilder.makeSnapshot(
            teamID: favoriteTeam.id,
            teamName: favoriteTeam.name,
            teamShortName: favoriteTeam.shortName,
            displayedMonth: monthStart(for: displayedMonthKey, calendar: scheduleCalendar),
            monthTitle: calendarMonthTitle(for: monthStart(for: displayedMonthKey, calendar: scheduleCalendar)),
            days: calendarDays,
            referenceDate: referenceDate,
            calendar: scheduleCalendar
        )
    }

    private func favoriteTeamWidgetCalendarDays(
        monthKey: KBOMonthScheduleKey,
        monthGames: [GameDetail],
        favoriteTeamID: String,
        calendar scheduleCalendar: Calendar
    ) -> [MyTeamCalendarDay] {
        let monthStart = monthStart(for: monthKey, calendar: scheduleCalendar)
        let groupedGames = Dictionary(grouping: monthGames.filter { $0.involves(teamID: favoriteTeamID) }) { game in
            scheduleDayKey(for: game.scheduledStart)
        }
        let todayKey = scheduleDayKey(for: currentDateProvider())
        return ScheduleCalendarDayBuilder.makeDays(
            monthStart: monthStart,
            gamesByDate: groupedGames,
            filter: .myTeam,
            favoriteTeamID: favoriteTeamID,
            calendar: scheduleCalendar,
            dayKey: { [self] date in scheduleDayKey(for: date) },
            isToday: { [self] _, cursorKey in cursorKey == todayKey },
            hasAttendedGame: { [self] games in games.contains(where: isGameAttended) },
            favoriteTeamResult: { [self] games, _ in calendarFavoriteTeamResult(for: games) }
        )
    }

    private func logFavoriteTeamScheduleWidgetStoreSave(
        reason: String,
        monthKey: KBOMonthScheduleKey?,
        snapshot: FavoriteTeamScheduleWidgetSnapshot?,
        sourceMonthlyGames: [GameDetail]? = nil
    ) {
        #if DEBUG
        guard let favoriteTeamID = settings.favoriteTeamID else { return }
        let resolvedMonthKey = monthKey ?? snapshot.map {
            KBOMonthScheduleKey(date: $0.displayedMonth, calendar: widgetScheduleCalendar())
        }
        let sourceGames: [GameDetail]
        if let sourceMonthlyGames {
            sourceGames = sourceMonthlyGames
        } else if let resolvedMonthKey, let widgetMonthSource = favoriteTeamWidgetMonthSources[resolvedMonthKey] {
            sourceGames = widgetMonthSource.games
        } else if let resolvedMonthKey {
            sourceGames = monthlyScheduleGames[resolvedMonthKey] ?? fallbackMonthSchedule(for: resolvedMonthKey)
        } else {
            sourceGames = []
        }
        let myTeamGames = sourceGames
            .filter { $0.involves(teamID: favoriteTeamID) }
            .sorted { $0.scheduledStart < $1.scheduledStart }
        let firstDate = myTeamGames.first.map { scheduleDayKey(for: $0.scheduledStart) } ?? "nil"
        let lastDate = myTeamGames.last.map { scheduleDayKey(for: $0.scheduledStart) } ?? "nil"
        print(
            "[WidgetScheduleStore] save reason=\(reason) " +
            "month=\(resolvedMonthKey?.yearMonthText ?? "nil") " +
            "favoriteTeam=\(favoriteTeamID) " +
            "sourceMonthlyCount=\(sourceGames.count) " +
            "myTeamCount=\(myTeamGames.count) " +
            "first=\(firstDate) last=\(lastDate)"
        )
        #endif
    }

    private func widgetSourceMonthlyGames(for monthKey: KBOMonthScheduleKey) -> [GameDetail] {
        monthlyScheduleGames[monthKey] ?? fallbackMonthSchedule(for: monthKey)
    }

    // currentWidgetMonthKey 메서드는 위젯이 항상 보여야 하는 KST 기준 현재 월을 반환합니다.
    private func currentWidgetMonthKey() -> KBOMonthScheduleKey {
        KBOMonthScheduleKey(date: currentDateProvider(), calendar: widgetScheduleCalendar())
    }

    // favoriteTeamWidgetMetadata 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // widgetScheduleCalendar 메서드는 이 타입의 주요 동작을 수행합니다.
    private func widgetScheduleCalendar() -> Calendar {
        var scheduleCalendar = calendar
        scheduleCalendar.timeZone = scheduleTimeZone
        return scheduleCalendar
    }

    // reloadFavoriteTeamWidgetTimelines 메서드는 이 타입의 주요 동작을 수행합니다.
    private func reloadFavoriteTeamWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: FavoriteTeamScheduleWidgetShared.widgetKind)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    // persistSettings 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    private func persistSettings() {
        FavoriteTeamScheduleWidgetShared.saveState(
            favoriteTeamID: settings.favoriteTeamID,
            snapshot: FavoriteTeamScheduleWidgetShared.loadSnapshot()
        )
        guard usesPersistedSettings else { return }
        AppModelPersistenceStore.saveSettings(settings)
    }

    // updateAPNsDeviceToken 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    private func updateAPNsDeviceToken(_ token: String) {
        #if DEBUG
        print("[NotificationPipeline] APNs token stored tokenPrefix=\(token.prefix(8)) length=\(token.count) environment=\(NotificationRegistrationEnvironment.current) buildConfiguration=\(AppBuildConfiguration.current)")
        #else
        print("[NotificationPipeline] APNs token stored reason=registrationSucceeded environment=\(NotificationRegistrationEnvironment.current)")
        #endif
        AppLog.info(.notification, "[NotificationPipeline] APNs token stored environment=\(NotificationRegistrationEnvironment.current) buildConfiguration=\(AppBuildConfiguration.current)")
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

    // persistNotificationHistory 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    private func persistNotificationHistory() {
        guard usesPersistedSettings else { return }
        AppModelPersistenceStore.saveNotificationHistory(notifications)
    }

    // mergedNotifications 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
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

    // persistAttendedGameKeys 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    private func persistAttendedGameKeys() {
        guard usesPersistedSettings else { return }
        AppModelPersistenceStore.saveAttendedGameKeys(attendedGameKeys)
    }

    // persistCancellationNotificationKeys 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    private func persistCancellationNotificationKeys() {
        guard usesPersistedSettings else { return }
        AppModelPersistenceStore.saveCancellationNotificationKeys(notifiedCancellationKeys)
    }

    // persistOnboardingCompletion 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    private func persistOnboardingCompletion() {
        guard usesPersistedSettings else { return }
        AppModelPersistenceStore.saveOnboardingCompletion(hasCompletedOnboarding)
    }

    // handleNotificationUserInfo 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    func handleNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        guard let payload = ScoreNotificationPayloadExtractor.payload(from: userInfo) else { return }
        recordReceivedNotification(payload)
        routeNotification(payload)
    }

    // recordReceivedNotification 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    private func recordReceivedNotification(_ payload: ScoreNotificationPayload) {
        let receivedAt = currentDateProvider()
        let item = NotificationHistoryBuilder.makeItem(from: payload, receivedAt: receivedAt)
        notifications.insert(item, at: 0)
        notifications = notifications.sorted { $0.sentAt > $1.sentAt }
        persistNotificationHistory()
    }

    // routeNotification 메서드는 이 타입의 주요 동작을 수행합니다.
    private func routeNotification(_ payload: ScoreNotificationPayload) {
        switch ScoreNotificationPayloadExtractor.route(from: payload) {
        case .gameDetail(let gameIdentity):
            isNotificationsPresented = false
            selectedTab = .home
            presentedGameIdentity = gameIdentity
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

    func startLiveActivityPushToStartTokenObservation() {
        #if canImport(ActivityKit)
        guard liveActivityPushToStartTokenObservationTask == nil else { return }
        guard FavoriteTeamLiveActivitySupport.hasWidgetExtension() else {
            print("[LiveActivity] push-to-start observation skipped reason=unsupported_os_or_capability")
            AppLog.info(.liveActivity, "[LiveActivity] push-to-start observation skipped reason=unsupported_os_or_capability")
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivity] push-to-start observation skipped reason=activities_disabled")
            AppLog.info(.liveActivity, "[LiveActivity] push-to-start observation skipped reason=activities_disabled")
            return
        }
        liveActivityPushToStartTokenObservationTask = Task { [weak self] in
            if #available(iOS 17.2, *) {
                for await tokenData in Activity<FavoriteTeamGameActivityAttributes>.pushToStartTokenUpdates {
                    let token = tokenData.map { String(format: "%02x", $0) }.joined()
                    await self?.registerPushToStartToken(token, reason: "tokenUpdate")
                }
            } else {
                #if DEBUG
                print("[LiveActivity] push-to-start observation skipped reason=unsupported_os_or_capability")
                #endif
                AppLog.info(.liveActivity, "[LiveActivity] push-to-start observation skipped reason=unsupported_os_or_capability")
            }
        }
        #else
        #if DEBUG
        print("[LiveActivity] push-to-start observation skipped reason=unsupported_os_or_capability")
        #endif
        AppLog.info(.liveActivity, "[LiveActivity] push-to-start observation skipped reason=unsupported_os_or_capability")
        #endif
    }

    private func registerLastKnownPushToStartTokenIfNeeded(reason: String) async {
        guard let lastLiveActivityPushToStartToken else { return }
        await registerPushToStartToken(lastLiveActivityPushToStartToken, reason: reason)
    }

    private func registerPushToStartToken(_ token: String, reason: String) async {
        guard token.isEmpty == false else { return }
        lastLiveActivityPushToStartToken = token
        let payload = LiveActivityPushToStartTokenRegistrationPayload(
            pushToStartToken: token,
            settings: settings,
            authorizationStatus: notificationAuthorizationStatus
        )
        let key = LiveActivityPushToStartTokenRegistrationKey(
            payload: payload,
            endpointDescription: liveActivityPushToStartTokenRegistrationClient.debugEndpointDescription
        )
        guard registeredPushToStartTokenKeys.insert(key).inserted else {
            #if DEBUG
            print("[LiveActivity] push-to-start registration skipped duplicate reason=\(reason) \(key)")
            #endif
            AppLog.info(.liveActivity, "[LiveActivity] push-to-start registration skipped duplicate reason=\(reason)")
            return
        }

        #if DEBUG
        print("[LiveActivity] push-to-start token received reason=\(reason) tokenPrefix=\(token.prefix(8)) environment=\(payload.environment) autoStart=\(payload.liveActivityAutoStartEnabled) favoriteTeamID=\(payload.favoriteTeamID ?? "nil")")
        #else
        print("[LiveActivity] push-to-start token received reason=\(reason) environment=\(payload.environment)")
        #endif
        AppLog.info(.liveActivity, "[LiveActivity] push-to-start token received reason=\(reason) environment=\(payload.environment) autoStart=\(payload.liveActivityAutoStartEnabled)")
        do {
            _ = try await liveActivityPushToStartTokenRegistrationClient.register(payload)
            #if DEBUG
            print("[LiveActivity] push-to-start registration success reason=\(reason) tokenPrefix=\(token.prefix(8)) environment=\(payload.environment)")
            #else
            print("[LiveActivity] push-to-start registration success reason=\(reason) environment=\(payload.environment)")
            #endif
            AppLog.info(.liveActivity, "[LiveActivity] push-to-start registration success reason=\(reason) environment=\(payload.environment)")
        } catch {
            #if DEBUG
            print("[LiveActivity] push-to-start registration failure reason=\(reason) tokenPrefix=\(token.prefix(8)) endpoint=\(liveActivityPushToStartTokenRegistrationClient.debugEndpointDescription ?? "missing") error=\(error)")
            #else
            print("[LiveActivity] push-to-start registration failure reason=\(reason)")
            #endif
            AppLog.error(.liveActivity, "[LiveActivity] push-to-start registration failure reason=\(reason) error=\(error)")
        }
    }

    // scheduleNotificationRegistrationSyncIfNeeded 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    private func scheduleNotificationRegistrationSyncIfNeeded(oldSettings: AppSettings) {
        guard oldSettings.favoriteTeamID != settings.favoriteTeamID ||
                oldSettings.notificationPreferences != settings.notificationPreferences ||
                oldSettings.quietHours != settings.quietHours ||
                oldSettings.liveActivitiesEnabled != settings.liveActivitiesEnabled ||
                oldSettings.liveActivityAutoStartEnabled != settings.liveActivityAutoStartEnabled else {
            return
        }

        scheduleNotificationRegistrationSync(force: false)
    }

    // scheduleNotificationRegistrationSync 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    private func scheduleNotificationRegistrationSync(force: Bool) {
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
        switch notificationRegistrationDeduplicationState.start(key, force: force) {
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

        notificationRegistrationSyncGeneration += 1
        let generation = notificationRegistrationSyncGeneration
        if let previousKey = notificationRegistrationSyncTaskKey {
            notificationRegistrationDeduplicationState.fail(previousKey)
        }
        notificationRegistrationSyncTask?.cancel()
        notificationRegistrationSyncTaskKey = key
        notificationRegistrationSyncTask = Task { [weak self] in
            await self?.performNotificationRegistrationSync(payload, key: key, generation: generation)
        }
    }

    // performNotificationRegistrationSync 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    private func performNotificationRegistrationSync(
        _ payload: NotificationRegistrationPayload,
        key: NotificationRegistrationKey,
        generation: Int
    ) async {
        notificationRegistrationSyncStatus = .syncing
        notificationRegistrationLastAttemptAt = Date()

        do {
            try Task.checkCancellation()
            #if DEBUG
            print("[NotificationPipeline] registration sync start endpoint=\(notificationRegistrationClient.debugEndpointDescription ?? "missing") tokenPrefix=\(payload.deviceToken.prefix(8)) environment=\(payload.environment) buildConfiguration=\(AppBuildConfiguration.current) \(payload.debugBooleanDescription)")
            #else
            print("[NotificationPipeline] registration sync start reason=deviceRegistration environment=\(payload.environment) buildConfiguration=\(AppBuildConfiguration.current)")
            #endif
            AppLog.info(.notification, "[NotificationPipeline] registration sync start environment=\(payload.environment) buildConfiguration=\(AppBuildConfiguration.current)")
            let status = try await notificationRegistrationClient.syncRegistration(payload)
            guard generation == notificationRegistrationSyncGeneration else {
                notificationRegistrationDeduplicationState.fail(key)
                #if DEBUG
                print("[NotificationPipeline] registration stale result ignored key=\(key)")
                #endif
                return
            }
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
            if notificationRegistrationSyncTaskKey == key {
                notificationRegistrationSyncTaskKey = nil
            }
        } catch {
            guard generation == notificationRegistrationSyncGeneration else {
                notificationRegistrationDeduplicationState.fail(key)
                #if DEBUG
                print("[NotificationPipeline] registration stale failure ignored key=\(key) error=\(error)")
                #endif
                return
            }
            notificationRegistrationSyncStatus = .failed
            notificationRegistrationDeduplicationState.fail(key)
            if notificationRegistrationSyncTaskKey == key {
                notificationRegistrationSyncTaskKey = nil
            }
            #if DEBUG
            print("[NotificationPipeline] backend token registration failure error=\(error)")
            print("[NotificationPipeline] registration failure error=\(error)")
            #endif
        }
    }

    // refreshActiveLiveActivityGameDetailIfNeeded 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    private func refreshActiveLiveActivityGameDetailIfNeeded(reason: String) async {
        guard let activeLiveActivityGameID,
              let activeGame = game(withID: activeLiveActivityGameID) else {
            return
        }

        #if DEBUG
        print("[LiveActivityBackgroundRefresh] activeGameDetailRefresh start reason=\(reason) gameID=\(activeLiveActivityGameID.uuidString)")
        #endif
        _ = await refreshGameDetailResult(
            for: activeGame.canonicalGameIdentityValue,
            forceRefresh: true
        )
    }

    // syncFavoriteTeamLiveActivity 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
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

    // resolvedRawGameID 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    private func resolvedRawGameID(for game: GameDetail) -> String {
        if let officialGame = self.game(withIdentity: game.canonicalGameIdentityValue) {
            return officialGame.canonicalGameIdentityValue
        }
        return game.canonicalGameIdentityValue
    }

    // matchesHomeFilter 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private func matchesHomeFilter(_ summary: GameSummary) -> Bool {
        HomeGameSelector.matches(summary, filter: homeFilter)
    }

    // homeSummaryComparator 메서드는 이 타입의 주요 동작을 수행합니다.
    private func homeSummaryComparator(_ lhs: GameSummary, _ rhs: GameSummary) -> Bool {
        HomeGameSelector.compare(lhs, rhs)
    }

    // todayGameComparator 메서드는 이 타입의 주요 동작을 수행합니다.
    private func todayGameComparator(_ lhs: GameDetail, _ rhs: GameDetail) -> Bool {
        HomeGameSelector.compareTodayGames(lhs, rhs, favoriteTeamID: settings.favoriteTeamID)
    }

    // calendarFavoriteTeamResult 메서드는 이 타입의 주요 동작을 수행합니다.
    private func calendarFavoriteTeamResult(for games: [GameDetail]) -> TeamGameResult? {
        for game in games {
            if let result = game.finalResult(for: settings.favoriteTeamID) {
                return result
            }
        }
        return nil
    }

    // makeStandingsSnapshot 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

    // makeStandingsSnapshot 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

    // refreshLocalStandingsProbabilitySignalsSynchronously 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    private func refreshLocalStandingsProbabilitySignalsSynchronously() {
        localStandingsProbabilityRefreshTask?.cancel()
        localStandingsProbabilitySignalsByTeamID = localPostseasonQualificationCalculator.makeSignals(
            teams: teams,
            games: standingsCalculationGames
        )
    }

    // refreshLocalStandingsProbabilitySignals 메서드는 최신 상태를 다시 가져오고 관련 화면 데이터를 동기화합니다.
    private func refreshLocalStandingsProbabilitySignals(for sourceGames: [GameDetail]) {
        localStandingsProbabilityRefreshTask?.cancel()
        localStandingsProbabilityGeneration += 1
        localStandingsProbabilitySignalsByTeamID = localPostseasonQualificationCalculator.makeSignals(
            teams: teams,
            games: sourceGames
        )
    }

    // scheduleLocalStandingsProbabilityRefresh 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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
                self.refreshPublishedStandingsRowsWithCurrentSource(
                    season: self.currentStandingsSeason(),
                    reason: "probabilitySignals"
                )
            }
        }
    }

    // standingsComparator 메서드는 이 타입의 주요 동작을 수행합니다.
    private func standingsComparator(_ lhs: TeamStandingsSnapshot, _ rhs: TeamStandingsSnapshot) -> Bool {
        StandingsSorter.compare(lhs, rhs, previousRankProvider: previousRegularSeasonRank)
    }

    // previousRegularSeasonRank 메서드는 이 타입의 주요 동작을 수행합니다.
    private func previousRegularSeasonRank(for team: Team) -> Int? {
        if let previousRegularSeasonRank = team.previousRegularSeasonRank {
            return previousRegularSeasonRank
        }
        guard let teamID = Self.canonicalTeamIdentifier(team.id) else {
            return nil
        }
        return Self.previousRegularSeasonRankByTeamID[teamID]
    }

    // notifyGameContentTransitions 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

    // notifyCancellationTransitions 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

    // cancellationNotificationState 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
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

    // cancellationNotificationFingerprint 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
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

    // equivalentGame 메서드는 이 타입의 주요 동작을 수행합니다.
    private func equivalentGame(to game: GameDetail, in candidates: [GameDetail]) -> GameDetail? {
        GameMergeResolver.equivalentGame(to: game, in: candidates)
    }

    // isTodayInKorea 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private func isTodayInKorea(_ game: GameDetail) -> Bool {
        scheduleDayKey(for: game.scheduledStart) == scheduleDayKey(for: currentDateProvider())
    }

    // isWeatherRelatedCancellation 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private func isWeatherRelatedCancellation(_ game: GameDetail) -> Bool {
        let text = ([game.note, game.highlightText, game.inningText].compactMap { $0 } + game.events.map(\.headline))
            .joined(separator: " ")
            .lowercased()
        let weatherTokens = ["우천", "강우", "폭우", "호우", "기상", "rain", "weather"]
        return weatherTokens.contains { text.contains($0) }
    }

    // availableScheduleMonths 메서드는 이 타입의 주요 동작을 수행합니다.
    private func availableScheduleMonths(filter: ScheduleFilter) -> [Date] {
        let monthStarts = knownScheduleGames(filter: filter)
            .map { startOfMonth(for: $0.scheduledStart) }

        return Array(Set(monthStarts)).sorted()
    }

    // knownScheduleGames 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
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

    // mergeMonthlyScheduleGames 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    private func mergeMonthlyScheduleGames(_ monthGames: [GameDetail], for key: KBOMonthScheduleKey) -> [GameDetail] {
        let stateGamesInMonth = games.filter {
            let components = calendar.dateComponents([.year, .month], from: $0.scheduledStart)
            return components.year == key.year && components.month == key.month
        }
        return mergeEquivalentGames(monthGames + stateGamesInMonth)
    }

    // mergeEquivalentGames 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    private func mergeEquivalentGames(_ sourceGames: [GameDetail]) -> [GameDetail] {
        GameMergeResolver.mergeEquivalentGames(sourceGames)
    }

    // scoreDebugText 메서드는 이 타입의 주요 동작을 수행합니다.
    private func scoreDebugText(_ game: GameDetail) -> String {
        "\(game.awayScore.map(String.init) ?? "-"):\(game.homeScore.map(String.init) ?? "-")"
    }

    // operationalGameIdentifier 메서드는 운영 로그용 비민감 경기 식별자를 선택합니다.
    private func operationalGameIdentifier(for game: GameDetail) -> String {
        game.publicGameID ??
            game.providerGameID ??
            game.officialProviderGameID ??
            game.id.uuidString
    }

    // selectedGameMatch 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
    private func selectedGameMatch(for gameIdentity: String) -> SelectedGameResolution? {
        SelectedGameResolver.match(for: gameIdentity, in: allKnownGames())
    }

    #if DEBUG
    // debugLogLocalCandidateMiss 메서드는 화면 표시와 디버그에 사용할 문구를 구성합니다.
    private func debugLogLocalCandidateMiss(_ gameIdentity: String) {
        let rawIdentifier = GameIdentifier.rawIdentifier(from: gameIdentity)
        let candidates = allKnownGames()
        let requestTokens = GameIdentifier.requestedIdentityTokens(from: gameIdentity)
            .sorted()
            .joined(separator: ",")
        print("[GameDetailFetch] selectedGame localMiss selectedIdentity=\(gameIdentity) rawIdentifier=\(rawIdentifier) candidateCount=\(candidates.count) requestedTokens=[\(requestTokens)]")
    }

    // debugLogMissingSelectedGame 메서드는 화면 표시와 디버그에 사용할 문구를 구성합니다.
    private func debugLogMissingSelectedGame(_ gameIdentity: String) {
        let rawIdentifier: String
        rawIdentifier = GameIdentifier.rawIdentifier(from: gameIdentity)
        let candidates = allKnownGames()
        let hasPublicIDs = candidates.contains { GameMergeResolver.nonBlank($0.publicGameID) != nil }
        let hasProviderIDs = candidates.contains { GameMergeResolver.nonBlank($0.providerGameID) != nil }
        let hasOfficialIDs = candidates.contains { GameMergeResolver.nonBlank($0.officialProviderGameID) != nil }
        let requestTokens = GameIdentifier.requestedIdentityTokens(from: gameIdentity)
            .sorted()
            .joined(separator: ",")
        let candidateDescriptions = candidates.map { candidate in
            let tokens = candidate.gameIdentityMatchTokens
                .map { "\($0.priority):\($0.value)" }
                .sorted()
                .joined(separator: "|")
            return "public=\(candidate.publicGameID ?? "<nil>") provider=\(candidate.providerGameID ?? "<nil>") official=\(candidate.officialProviderGameID ?? "<nil>") stable=\(candidate.stableDetailIdentity) tokens=[\(tokens)]"
        }
            .joined(separator: " ; ")
        print("[GameDetailFetch] mode=singleGame selectedIdentity=\(gameIdentity) rawIdentifier=\(rawIdentifier) skipped=noSelectedGame candidateCount=\(candidates.count) hasPublicIDs=\(hasPublicIDs) hasProviderIDs=\(hasProviderIDs) hasOfficialIDs=\(hasOfficialIDs) requestedTokens=[\(requestTokens)] candidates=\(candidateDescriptions)")
    }
    #endif

    // equivalentGames 메서드는 이 타입의 주요 동작을 수행합니다.
    private func equivalentGames(to game: GameDetail) -> [GameDetail] {
        GameMergeResolver.equivalentGames(to: game, in: allKnownGames())
    }

    // allKnownGames 메서드는 이 타입의 주요 동작을 수행합니다.
    private func allKnownGames() -> [GameDetail] {
        games + monthlyScheduleGames.values.flatMap { $0 }
    }

    #if DEBUG
    // debugLogAttendanceToggle 메서드는 화면 표시와 디버그에 사용할 문구를 구성합니다.
    private func debugLogAttendanceToggle(game: GameDetail, storedKey: String, equivalentKeys: Set<String>, isAttended: Bool) {
    }

    // debugLogAttendanceSummaryCandidate 메서드는 화면 표시와 디버그에 사용할 문구를 구성합니다.
    private func debugLogAttendanceSummaryCandidate(
        _ game: GameDetail,
        favoriteTeamID: String,
        result: TeamGameResult?,
        included: Bool
    ) {
    }
    #endif

    // makeScheduleCalendarCacheKey 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    private func makeScheduleCalendarCacheKey(for date: Date, filter: ScheduleFilter) -> ScheduleCalendarCacheKey {
        ScheduleCalendarCacheKey(
            month: KBOMonthScheduleKey(date: date, calendar: calendar),
            filter: filter,
            favoriteTeamID: settings.favoriteTeamID
        )
    }

    // invalidateScheduleDerivedCaches 메서드는 저장된 상태나 캐시 값을 정리합니다.
    private func invalidateScheduleDerivedCaches(for month: KBOMonthScheduleKey? = nil) {
        guard let month else {
            scheduleCalendarDaysCache.removeAll()
            scheduleGamesByDayCache.removeAll()
            return
        }
        scheduleCalendarDaysCache = scheduleCalendarDaysCache.filter { $0.key.month != month }
        scheduleGamesByDayCache = scheduleGamesByDayCache.filter { $0.key.month != month }
    }

    // groupedScheduleGamesByDay 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
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

    // myTeamMonthScheduleSource 메서드는 이 타입의 주요 동작을 수행합니다.
    private func myTeamMonthScheduleSource(for date: Date) -> [GameDetail] {
        let key = KBOMonthScheduleKey(date: date, calendar: calendar)
        return monthlyScheduleGames[key] ?? fallbackMonthSchedule(for: key)
    }

    // filteredScheduleGames 메서드는 입력 데이터를 판별하거나 정렬해 사용할 대상을 결정합니다.
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

    // fallbackMonthSchedule 메서드는 이 타입의 주요 동작을 수행합니다.
    private func fallbackMonthSchedule(for key: KBOMonthScheduleKey) -> [GameDetail] {
        games
            .filter {
                let components = calendar.dateComponents([.year, .month], from: $0.scheduledStart)
                return components.year == key.year && components.month == key.month
            }
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    // reconcileOfficialScheduleStartTimesIfNeeded 메서드는 이 타입의 주요 동작을 수행합니다.
    private func reconcileOfficialScheduleStartTimesIfNeeded(
        in games: [GameDetail],
        snapshot: RepositoryDebugSnapshot?
    ) async -> [GameDetail] {
        guard shouldReconcileOfficialScheduleStartTimes(snapshot: snapshot, games: games) else {
            return games
        }

        return await officialGameCenterClient.reconcileScheduledStartTimes(in: games)
    }

    // reconcileOfficialScheduleStartTimesIfNeeded 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // shouldReconcileOfficialScheduleStartTimes 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
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

    // scheduleDayKey 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    private func scheduleDayKey(for date: Date) -> String {
        ScheduleDateKeyFormatter.dayKey(for: date)
    }

    // scheduleDate 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
    private func scheduleDate(fromDayKey dayKey: String) throws -> Date {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            throw SchedulePostReconciliationRefreshError.invalidDateKey(dayKey)
        }
        var scheduleCalendar = calendar
        scheduleCalendar.timeZone = scheduleTimeZone
        var components = DateComponents()
        components.calendar = scheduleCalendar
        components.timeZone = scheduleTimeZone
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        guard let date = scheduleCalendar.date(from: components) else {
            throw SchedulePostReconciliationRefreshError.invalidDateKey(dayKey)
        }
        return date
    }

    // markScheduleDatesRecentlyReconciled 메서드는 전달된 값을 반영하고 내부 저장 상태를 갱신합니다.
    private func markScheduleDatesRecentlyReconciled(_ dateKeys: [String]) {
        let now = Date()
        for dateKey in dateKeys {
            recentlyReconciledScheduleDates[dateKey] = now
        }
        #if DEBUG
        print("[ScheduleRefresh] recentlyReconciled added dates=\(dateKeys.joined(separator: ","))")
        #endif
    }

    // clearRecentlyReconciledScheduleDates 메서드는 저장된 상태나 캐시 값을 정리합니다.
    private func clearRecentlyReconciledScheduleDates(_ dateKeys: [String]) {
        for dateKey in dateKeys {
            recentlyReconciledScheduleDates.removeValue(forKey: dateKey)
        }
        #if DEBUG
        print("[ScheduleRefresh] recentlyReconciled removed dates=\(dateKeys.joined(separator: ","))")
        #endif
    }

    // pruneExpiredRecentlyReconciledScheduleDates 메서드는 이 타입의 주요 동작을 수행합니다.
    private func pruneExpiredRecentlyReconciledScheduleDates() {
        let now = Date()
        let expiredDateKeys = recentlyReconciledScheduleDates.compactMap { dateKey, markedAt in
            now.timeIntervalSince(markedAt) >= scheduleReconciliationCooldown ? dateKey : nil
        }
        guard expiredDateKeys.isEmpty == false else { return }
        clearRecentlyReconciledScheduleDates(expiredDateKeys)
    }
}

// ScheduleStalePreflightRefreshResult 구조체는 ScheduleStalePreflightRefreshResult 타입의 역할과 값을 정의합니다.
struct ScheduleStalePreflightRefreshResult: Sendable {
    let requestedDateKeys: [String]
    let remainingStaleDateKeys: [String]
    let resolvedDateKeys: [String]
    let failedDateKeys: [String]
}

// SchedulePostReconciliationRefreshResult 구조체는 SchedulePostReconciliationRefreshResult 타입의 역할과 값을 정의합니다.
struct SchedulePostReconciliationRefreshResult: Sendable {
    let dateResults: [SchedulePostReconciliationDateRefreshResult]

    var dateKeys: [String] {
        dateResults.map(\.dateKey)
    }
}

// SchedulePostReconciliationDateRefreshResult 구조체는 SchedulePostReconciliationDateRefreshResult 타입의 역할과 값을 정의합니다.
struct SchedulePostReconciliationDateRefreshResult: Sendable {
    let dateKey: String
    let games: [GameDetail]
    let inserted: Int
    let updated: Int
    let skippedExisting: Int
}

// SchedulePostReconciliationRefreshError 열거형는 실패 상황을 구분하고 호출자에게 전달합니다.
enum SchedulePostReconciliationRefreshError: Error, Sendable {
    case invalidDateKey(String)
}

// ScheduleCalendarCacheKey 구조체는 ScheduleCalendarCacheKey 타입의 역할과 값을 정의합니다.
private struct ScheduleCalendarCacheKey: Hashable {
    let month: KBOMonthScheduleKey
    let filter: ScheduleFilter
    let favoriteTeamID: String?
}

// ScheduleStartupSyncState 열거형는 화면이나 도메인 흐름에서 사용하는 상태 값을 표현합니다.
private enum ScheduleStartupSyncState {
    case notStarted
    case inFlight(Task<Void, Never>)
    case completed
    case failedButDoNotRetryAutomatically
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
