import Foundation
import Combine
import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            return false
        }
    }

    func scheduleTestOrder() async throws {
        if authorizationStatus != .authorized {
            _ = await requestAuthorization()
        }

        let content = UNMutableNotificationContent()
        content.title = "New order • $184.20"
        content.subtitle = "Shopify • Northstar Goods"
        content.body = "Maya Chen ordered Linen Overshirt and Canvas Tote."
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Shopify Sales Sound.mp3"))
        content.badge = 1
        content.userInfo = ["orderID": "#OD-10492"]

        let request = UNNotificationRequest(
            identifier: "omnidesk-test-order-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        )
        try await UNUserNotificationCenter.current().add(request)
        AssistantManager.shared.recordNewOrder(
            id: "#OD-10492",
            channel: "Shopify",
            amount: "$184.20",
            customer: "Maya Chen"
        )
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }
}
