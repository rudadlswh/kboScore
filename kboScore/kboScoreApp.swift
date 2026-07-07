//
//  kboScoreApp.swift
//  기능 설명: 앱 전체의 루트 엔트리와 전역 의존성 초기화를 담당합니다.
//  앱 전체의 루트 엔트리와 전역 의존성 초기화를 담당합니다.을 명확히 분리해 변경 범위와 책임을 예측 가능하게 유지합니다.
//  입력 데이터 누락, 비동기 실행 순서, 플랫폼별 동작 차이를 고려해 방어적으로 처리합니다.
//  TODO : 반복되는 정책이나 화면 상태가 늘어나면 전용 모델과 테스트로 분리합니다.
//  kboScore
//
//  Created by 조경민 on 3/25/26.
//

import SwiftUI
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

// LiveActivityBackgroundRefreshScheduler 열거형는 LiveActivityBackgroundRefreshScheduler 타입의 역할과 값을 정의합니다.
private enum LiveActivityBackgroundRefreshScheduler {
    static let taskIdentifier = "com.chogm.kboScore.liveActivityRefresh"

    // register 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

    // schedule 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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
    // handle 메서드는 비동기 작업이나 시스템 연동 흐름을 제어합니다.
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

// kboScoreApp 구조체는 kboScoreApp 타입의 역할과 값을 정의합니다.
@main
struct kboScoreApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var notificationDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var appModel: AppModel

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    @MainActor
    init() {
        let appModel = Self.makeAppModel()
        _appModel = State(initialValue: appModel)
        LiveActivityBackgroundRefreshScheduler.register {
            await appModel.refreshTodayForBackgroundLiveActivity(reason: "backgroundTask")
        }
    }

    // makeAppModel 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
    @MainActor
    private static func makeAppModel() -> AppModel {
        let bundle = KBORepositoryFactory.makeAppRepositoryBundle()
        let notificationRegistrationClient = NotificationRegistrationClientFactory.makeAppClient()
        let liveActivityPushToStartTokenRegistrationClient = LiveActivityPushToStartTokenRegistrationClientFactory.makeAppClient()
        let scheduleStaleGameReconciliationClient = ScheduleStaleGameReconciliationClientFactory.makeAppClient()
        let attendanceClient = AttendanceClientFactory.makeAppClient()
        return AppModel(
            repository: bundle.repository,
            repositoryRuntimeState: bundle.runtimeState,
            notificationRegistrationClient: notificationRegistrationClient,
            liveActivityPushToStartTokenRegistrationClient: liveActivityPushToStartTokenRegistrationClient,
            scheduleStaleGameReconciliationClient: scheduleStaleGameReconciliationClient,
            attendanceClient: attendanceClient
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .preferredColorScheme(appModel.settings.appearance.colorScheme)
                .task {
                    appModel.connectNotificationDelegate(notificationDelegate)
                    appModel.startLiveActivityPushToStartTokenObservation()
                    await appModel.syncNotificationRegistrationState()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        Task {
                            await appModel.resumeLiveGameDetailPollingIfNeeded()
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
