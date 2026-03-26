//
//  kboScoreApp.swift
//  kboScore
//
//  Created by 조경민 on 3/25/26.
//

import SwiftUI

@main
struct kboScoreApp: App {
    @State private var appModel: AppModel = {
        let bundle = KBORepositoryFactory.makeAppRepositoryBundle()
        return AppModel(repository: bundle.repository, repositoryRuntimeState: bundle.runtimeState)
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .preferredColorScheme(appModel.settings.appearance.colorScheme)
        }
    }
}
