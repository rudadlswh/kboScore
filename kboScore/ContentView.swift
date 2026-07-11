//
//  ContentView.swift
//  kboScore
//  기능 설명: 탭 기반 메인 화면 구성과 최상위 화면 전환을 담당합니다.
//  사용자가 경기 상태와 설정을 빠르게 이해하도록 도메인 상태를 화면 구조에 직접 매핑합니다.
//  SwiftUI 상태 갱신, 접근성, 작은 화면 레이아웃에서 정보가 겹치지 않도록 표시 조건을 제한합니다.
//  TODO : 반복되는 화면 조각은 재사용 가능한 컴포넌트로 분리하고 미리보기 케이스를 보강합니다.
//
//  Created by 조경민 on 3/25/26.
//

import SwiftUI

// ContentView 구조체는 화면에 표시되는 SwiftUI 뷰 구성을 담당합니다.
struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        Group {
            if appModel.shouldShowFavoriteTeamOnboarding {
                FavoriteTeamOnboardingView()
            } else if appModel.isLoading && appModel.games.isEmpty {
                ProgressView("불러오는 중")
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

                    ScheduleView()
                        .tag(AppTab.schedule)
                        .tabItem {
                            Label("일정", systemImage: "calendar")
                        }

                    AttendanceView()
                        .tag(AppTab.attendance)
                        .tabItem {
                            Label("직관", systemImage: "checkmark.circle.fill")
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
            await appModel.refreshAttendanceRecordsFromServer()
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
                get: { appModel.presentedGameIdentity != nil },
                set: { isPresented in
                    if !isPresented {
                        appModel.dismissPresentedGameDetail()
                    }
                }
            )
        ) {
            if let gameIdentity = appModel.presentedGameIdentity {
                NavigationStack {
                    GameDetailView(gameIdentity: gameIdentity)
                }
            }
        }
    }
}

// AppTabContainerStyleModifier 구조체는 SwiftUI 뷰 스타일과 동작을 재사용 가능한 형태로 적용합니다.
private struct AppTabContainerStyleModifier: ViewModifier {
    let stadiumPalette: StadiumPalette?
    let defaultAccent: Color
    @Binding var selection: AppTab

    // body 메서드는 SwiftUI 화면의 본문 구성을 반환합니다.
    func body(content: Content) -> some View {
        if let stadiumPalette {
            ZStack(alignment: .bottom) {
                content
                    .tint(stadiumPalette.primary)
                    .toolbar(.visible, for: .tabBar)
                    .background {
                        LinearGradient(
                            colors: [stadiumPalette.background, stadiumPalette.sectionBackground],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .ignoresSafeArea()
                    }

                // Temporarily disabled so stadium mode falls back to the system TabView tab bar.
                // StadiumBottomNavigationBar(selection: $selection, palette: stadiumPalette)
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

// StadiumBottomNavigationBar 구조체는 StadiumBottomNavigationBar 타입의 역할과 값을 정의합니다.
private struct StadiumBottomNavigationBar: View {
    @Binding var selection: AppTab
    let palette: StadiumPalette

    static let reservedContentInset: CGFloat = 92

    private let items: [StadiumBottomNavigationItem] = [
        StadiumBottomNavigationItem(tab: .home, title: "홈", systemImage: "house.fill"),
        StadiumBottomNavigationItem(tab: .standings, title: "순위", systemImage: "list.number"),
        StadiumBottomNavigationItem(tab: .schedule, title: "일정", systemImage: "calendar"),
        StadiumBottomNavigationItem(tab: .attendance, title: "직관", systemImage: "checkmark.circle.fill"),
        StadiumBottomNavigationItem(tab: .settings, title: "설정", systemImage: "gearshape.fill")
    ]

    // tabForegroundColor 메서드는 이 타입의 주요 동작을 수행합니다.
    private func tabForegroundColor(for item: StadiumBottomNavigationItem) -> Color {
        palette.tabBarForeground(isSelected: selection == item.tab)
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
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
                        }
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(tabForegroundColor(for: item))
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
    }
}

// StadiumNotificationChromeOverlay 구조체는 StadiumNotificationChromeOverlay 타입의 역할과 값을 정의합니다.
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

// StadiumBottomNavigationItem 구조체는 StadiumBottomNavigationItem 타입의 역할과 값을 정의합니다.
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
