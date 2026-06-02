//
//  kboScoreApp.swift
//  kboScore
//
//  Created by 조경민 on 3/25/26.
//

import SwiftUI

@main
struct kboScoreApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var notificationDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var appModel: AppModel = {
        let bundle = KBORepositoryFactory.makeAppRepositoryBundle()
        let notificationRegistrationClient = NotificationRegistrationClientFactory.makeAppClient()
        let scheduleStaleGameReconciliationClient = ScheduleStaleGameReconciliationClientFactory.makeAppClient()
        return AppModel(
            repository: bundle.repository,
            repositoryRuntimeState: bundle.runtimeState,
            notificationRegistrationClient: notificationRegistrationClient,
            scheduleStaleGameReconciliationClient: scheduleStaleGameReconciliationClient
        )
    }()

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
                    guard newPhase == .active else { return }
                    Task {
                        await appModel.refreshTodayOnForeground()
                    }
                }
        }
    }
}
