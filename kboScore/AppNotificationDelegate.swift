//
//  AppNotificationDelegate.swift
//  kboScore
//
//  Created by Codex on 3/26/26.
//

import UIKit
import UserNotifications

@MainActor
final class AppNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var onDeviceToken: ((String) -> Void)?
    var onNotificationUserInfo: (([AnyHashable: Any]) -> Void)?
    private var pendingNotificationUserInfos: [[AnyHashable: Any]] = []

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        #if DEBUG
        print("[NotificationPipeline] notification center delegate assigned at launch")
        #endif
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        print("[NotificationPipeline] APNs token received prefix=\(token.prefix(12)) length=\(token.count)")
        #endif
        onDeviceToken?(token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("APNs registration failed:", error.localizedDescription)
        #endif
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        #if DEBUG
        let content = notification.request.content
        print("[NotificationPipeline] willPresent notification id=\(notification.request.identifier) title=\(content.title) body=\(content.body)")
        #endif
        return [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        #if DEBUG
        print("[NotificationPipeline] didReceive notification response id=\(response.notification.request.identifier) action=\(response.actionIdentifier)")
        #endif
        handleNotificationUserInfo(response.notification.request.content.userInfo)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        #if DEBUG
        print("[NotificationPipeline] didReceiveRemoteNotification keys=\(debugSortedKeys(userInfo))")
        #endif
        handleNotificationUserInfo(userInfo)
        completionHandler(.noData)
    }

    func connect(
        onDeviceToken: @escaping (String) -> Void,
        onNotificationUserInfo: @escaping ([AnyHashable: Any]) -> Void
    ) {
        self.onDeviceToken = onDeviceToken
        self.onNotificationUserInfo = onNotificationUserInfo
        UNUserNotificationCenter.current().delegate = self
        #if DEBUG
        print("[NotificationPipeline] notification center delegate connected")
        #endif
        flushPendingNotificationsIfNeeded()
    }

    private func debugSortedKeys(_ userInfo: [AnyHashable: Any]) -> String {
        userInfo.keys
            .map { String(describing: $0) }
            .sorted()
            .joined(separator: ",")
    }

    private func handleNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        guard onNotificationUserInfo != nil else {
            pendingNotificationUserInfos.append(userInfo)
            return
        }

        onNotificationUserInfo?(userInfo)
    }

    private func flushPendingNotificationsIfNeeded() {
        guard onNotificationUserInfo != nil else { return }

        let pending = pendingNotificationUserInfos
        pendingNotificationUserInfos.removeAll()
        for userInfo in pending {
            onNotificationUserInfo?(userInfo)
        }
    }
}
