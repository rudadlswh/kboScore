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
    @State private var appModel: AppModel = {
        let bundle = KBORepositoryFactory.makeAppRepositoryBundle()
        let notificationRegistrationClient = NotificationRegistrationClientFactory.makeAppClient()
        return AppModel(
            repository: bundle.repository,
            repositoryRuntimeState: bundle.runtimeState,
            notificationRegistrationClient: notificationRegistrationClient
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
        }
    }
}
