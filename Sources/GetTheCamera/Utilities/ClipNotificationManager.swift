import Foundation
@preconcurrency import UserNotifications

enum ClipNotificationManager {
	static let enabledKey = "clipNotificationsEnabled"

	static var isEnabled: Bool {
		if UserDefaults.standard.object(forKey: enabledKey) == nil {
			return true
		}
		return UserDefaults.standard.bool(forKey: enabledKey)
	}

	static func setEnabled(_ enabled: Bool) {
		UserDefaults.standard.set(enabled, forKey: enabledKey)
		if enabled {
			requestAuthorization()
		}
	}

	static func requestAuthorization() {
		UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
	}

	static func clipSaved(name: String, isHighlightReel: Bool = false) {
		guard isEnabled else { return }
		let content = UNMutableNotificationContent()
		content.title = isHighlightReel ? "Highlight Reel Ready" : "Clip Saved"
		content.body = name
		content.sound = notificationSound
		schedule(content)
	}

	static func showError(_ message: String) {
		guard isEnabled else { return }
		let content = UNMutableNotificationContent()
		content.title = "GetTheCamera"
		content.body = message
		content.sound = notificationSound
		schedule(content)
	}
	private static var notificationSound: UNNotificationSound? {
		let name = UserDefaults.standard.string(forKey: "clipNotificationSoundName") ?? "default"
		if name == "none" { return nil }
		return name == "default" ? .default : UNNotificationSound(named: UNNotificationSoundName(name))
	}

	private static func schedule(_ content: UNMutableNotificationContent) {
		UNUserNotificationCenter.current().getNotificationSettings { settings in
			guard settings.authorizationStatus == .authorized else { return }
			let request = UNNotificationRequest(
				identifier: UUID().uuidString,
				content: content,
				trigger: nil
			)
			UNUserNotificationCenter.current().add(request)
		}
	}
}
