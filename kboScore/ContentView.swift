//
//  ContentView.swift
//  kboScore
//
//  Created by 조경민 on 3/25/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if appModel.isLoading && appModel.games.isEmpty {
                ProgressView("KBO LIVE 불러오는 중")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(KBOLivePalette.background)
            } else if let loadErrorMessage = appModel.loadErrorMessage, appModel.games.isEmpty {
                ContentUnavailableView(
                    "데이터를 가져오지 못했습니다",
                    systemImage: "wifi.exclamationmark",
                    description: Text(loadErrorMessage)
                )
            } else {
                TabView {
                    HomeView()
                        .tabItem {
                            Label("홈", systemImage: "house.fill")
                        }

                    MyTeamView()
                        .tabItem {
                            Label("마이팀", systemImage: "star.fill")
                        }

                    NotificationsView()
                        .tabItem {
                            Label("알림", systemImage: "bell.fill")
                        }

                    SettingsView()
                        .tabItem {
                            Label("설정", systemImage: "gearshape.fill")
                        }
                }
                .tint(appModel.currentTheme.accent)
                .background(KBOLivePalette.background)
            }
        }
        .task {
            await appModel.loadIfNeeded()
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel.previewModel())
}
