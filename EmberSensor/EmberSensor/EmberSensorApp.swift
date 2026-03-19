import SwiftUI
import UserNotifications

@main
struct EmberSensorApp: App {
    
    // ✅ Keep a strong reference
    let notificationDelegate = NotificationDelegate()
    
    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
