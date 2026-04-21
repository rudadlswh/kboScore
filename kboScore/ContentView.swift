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
                    .background(appModel.favoriteStadiumPalette?.background ?? KBOLivePalette.background)
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
                .modifier(
                    AppTabContainerStyleModifier(
                        stadiumPalette: appModel.favoriteStadiumPalette,
                        defaultAccent: appModel.currentTheme.accent,
                        selection: $appModel.selectedTab
                    )
                )
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

private struct AppTabContainerStyleModifier: ViewModifier {
    let stadiumPalette: StadiumPalette?
    let defaultAccent: Color
    @Binding var selection: AppTab

    func body(content: Content) -> some View {
        if let stadiumPalette {
            ZStack(alignment: .bottom) {
                content
                    .tint(stadiumPalette.primary)
                    .toolbar(.hidden, for: .tabBar)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        Color.clear
                            .frame(height: StadiumBottomNavigationBar.reservedContentInset)
                    }
                    .background {
                        LinearGradient(
                            colors: [stadiumPalette.background, stadiumPalette.sectionBackground],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .ignoresSafeArea()
                    }

                StadiumBottomNavigationBar(selection: $selection, palette: stadiumPalette)
            }
            .overlay(alignment: .topTrailing) {
                StadiumNotificationChromeOverlay(palette: stadiumPalette)
            }
        } else {
            content
                .tint(defaultAccent)
                .toolbar(.visible, for: .tabBar)
                .background(KBOLivePalette.background)
        }
    }
}

private struct StadiumBottomNavigationBar: View {
    @Binding var selection: AppTab
    let palette: StadiumPalette

    static let reservedContentInset: CGFloat = 92

    private let items: [StadiumBottomNavigationItem] = [
        StadiumBottomNavigationItem(tab: .home, title: "홈", systemImage: "house.fill"),
        StadiumBottomNavigationItem(tab: .standings, title: "순위", systemImage: "list.number"),
        StadiumBottomNavigationItem(tab: .myTeam, title: "마이팀", systemImage: "star.fill"),
        StadiumBottomNavigationItem(tab: .schedule, title: "일정", systemImage: "calendar"),
        StadiumBottomNavigationItem(tab: .settings, title: "설정", systemImage: "gearshape.fill")
    ]

    private func tabLabelColor(for item: StadiumBottomNavigationItem) -> Color {
        if selection == item.tab {
            return palette.primary
        }
        if palette.usesLightForegroundStyle {
            return palette.textPrimary
        }
        return Color.white.opacity(0.94)
    }

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    palette.background.opacity(0.0),
                    palette.tabBarSurface.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 12)

            HStack(spacing: 7) {
                ForEach(items) { item in
                    Button {
                        selection = item.tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.systemImage)
                                .font(.system(size: 18, weight: .bold))
                                .symbolVariant(selection == item.tab ? .fill : .none)
                            Text(item.title)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(tabLabelColor(for: item))
                        }
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(selection == item.tab ? palette.primary : Color.white.opacity(0.94))
                        .background {
                            if selection == item.tab {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                palette.elevatedCardStrong.opacity(0.98),
                                                palette.elevatedCard.opacity(0.96)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(alignment: .top) {
                                        Capsule()
                                            .fill(palette.primary)
                                            .frame(width: 26, height: 3)
                                            .padding(.top, 5)
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(palette.primary.opacity(0.22), lineWidth: 0.75)
                                    }
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(selection == item.tab ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.recessedSurface,
                                palette.tabBarSurface
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(palette.textPrimary.opacity(0.12), lineWidth: 0.75)
            }
            .shadow(color: palette.ambientShadow.opacity(0.72), radius: 20, y: 8)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background {
            palette.tabBarSurface
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct StadiumNotificationChromeOverlay: View {
    let palette: StadiumPalette

    var body: some View {
        GeometryReader { proxy in
            VStack {
                HStack {
                    Spacer()
                    StadiumNotificationChromeButton(palette: palette)
                        .padding(.trailing, 16)
                }
                Spacer()
            }
            .padding(.top, max(50, proxy.safeAreaInsets.top + 7))
        }
        .ignoresSafeArea()
    }
}

private struct StadiumBottomNavigationItem: Identifiable {
    let tab: AppTab
    let title: String
    let systemImage: String

    var id: AppTab { tab }
}

#Preview {
    ContentView()
        .environment(AppModel.previewModel())
}
