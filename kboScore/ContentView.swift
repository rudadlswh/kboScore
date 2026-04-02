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
        @Bindable var appModel = appModel

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
                TabView(selection: $appModel.selectedTab) {
                    HomeView()
                        .tag(AppTab.home)
                        .tabItem {
                            Label("홈", systemImage: "house.fill")
                        }

                    StandingsView()
                        .tag(AppTab.standings)
                        .tabItem {
                            Label("순위", systemImage: "list.number")
                        }

                    MyTeamView()
                        .tag(AppTab.myTeam)
                        .tabItem {
                            Label("마이팀", systemImage: "star.fill")
                        }

                    ScheduleView()
                        .tag(AppTab.schedule)
                        .tabItem {
                            Label("일정", systemImage: "calendar")
                        }

                    SettingsView()
                        .tag(AppTab.settings)
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
        .sheet(
            isPresented: Binding(
                get: { appModel.isNotificationsPresented },
                set: { isPresented in
                    if !isPresented {
                        appModel.dismissNotifications()
                    }
                }
            )
        ) {
            NotificationsView()
        }
        .sheet(
            isPresented: Binding(
                get: { appModel.presentedGameID != nil },
                set: { isPresented in
                    if !isPresented {
                        appModel.dismissPresentedGameDetail()
                    }
                }
            )
        ) {
            if let gameID = appModel.presentedGameID {
                NavigationStack {
                    GameDetailView(gameID: gameID)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel.previewModel())
}
