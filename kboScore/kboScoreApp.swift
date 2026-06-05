//
//  kboScoreApp.swift
//  kboScore
//
//  Created by 조경민 on 3/25/26.
//

import SwiftUI
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

private enum LiveActivityBackgroundRefreshScheduler {
    static let taskIdentifier = "com.chogm.kboScore.liveActivityRefresh"

    static func register(refreshHandler: @escaping @MainActor () async -> Bool) {
        #if canImport(BackgroundTasks)
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask, refreshHandler: refreshHandler)
        }
        #if DEBUG
        print("[LiveActivityBackgroundRefresh] register id=\(taskIdentifier) success=\(registered)")
        #endif
        #endif
    }

    static func schedule(earliestBeginDate: Date = Date(timeIntervalSinceNow: 5 * 60)) {
        #if canImport(BackgroundTasks)
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = earliestBeginDate
        do {
            try BGTaskScheduler.shared.submit(request)
            #if DEBUG
            print("[LiveActivityBackgroundRefresh] scheduled id=\(taskIdentifier) earliest=\(earliestBeginDate)")
            #endif
        } catch {
            #if DEBUG
            print("[LiveActivityBackgroundRefresh] schedule failed id=\(taskIdentifier) error=\(error)")
            #endif
        }
        #endif
    }

    #if canImport(BackgroundTasks)
    private static func handle(
        _ task: BGAppRefreshTask,
        refreshHandler: @escaping @MainActor () async -> Bool
    ) {
        schedule()
        let operation = Task { @MainActor in
            await refreshHandler()
        }
        task.expirationHandler = {
            operation.cancel()
            #if DEBUG
            print("[LiveActivityBackgroundRefresh] bgTask expiration id=\(taskIdentifier) limitation=iOSMaySuspendLocalUpdate")
            #endif
        }
        Task {
            let success = await operation.value
            task.setTaskCompleted(success: success)
            #if DEBUG
            print("[LiveActivityBackgroundRefresh] bgTask completed id=\(taskIdentifier) success=\(success) limitation=localUpdatesNotGuaranteedAfterSuspend")
            #endif
        }
    }
    #endif
}

@main
struct kboScoreApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var notificationDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var appModel: AppModel

    @MainActor
    init() {
        let appModel = Self.makeAppModel()
        _appModel = State(initialValue: appModel)
        LiveActivityBackgroundRefreshScheduler.register {
            await appModel.refreshTodayForBackgroundLiveActivity(reason: "backgroundTask")
        }
    }

    @MainActor
    private static func makeAppModel() -> AppModel {
        let bundle = KBORepositoryFactory.makeAppRepositoryBundle()
        let notificationRegistrationClient = NotificationRegistrationClientFactory.makeAppClient()
        let scheduleStaleGameReconciliationClient = ScheduleStaleGameReconciliationClientFactory.makeAppClient()
        return AppModel(
            repository: bundle.repository,
            repositoryRuntimeState: bundle.runtimeState,
            notificationRegistrationClient: notificationRegistrationClient,
            scheduleStaleGameReconciliationClient: scheduleStaleGameReconciliationClient
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .preferredColorScheme(appModel.settings.appearance.colorScheme)
                .task {
                    appModel.connectNotificationDelegate(notificationDelegate)
                    await appModel.syncNotificationRegistrationState()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        Task {
                            await appModel.refreshTodayOnForeground()
                        }
                    case .background:
                        LiveActivityBackgroundRefreshScheduler.schedule()
                        Task {
                            await appModel.refreshTodayForBackgroundLiveActivity(reason: "sceneBackground")
                        }
                    default:
                        break
                    }
                }
        }
    }
}
