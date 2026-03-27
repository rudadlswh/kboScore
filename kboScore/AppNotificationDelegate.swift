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
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
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
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        handleNotificationUserInfo(response.notification.request.content.userInfo)
    }

    func connect(
        onDeviceToken: @escaping (String) -> Void,
        onNotificationUserInfo: @escaping ([AnyHashable: Any]) -> Void
    ) {
        self.onDeviceToken = onDeviceToken
        self.onNotificationUserInfo = onNotificationUserInfo
        UNUserNotificationCenter.current().delegate = self
        flushPendingNotificationsIfNeeded()
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
