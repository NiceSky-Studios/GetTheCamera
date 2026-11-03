import Foundation

struct AutomationRules: Codable, Equatable {
	var startRecordingOnNamedApp: Bool
	var stopRecordingWhenAppCloses: Bool
	var createClipOnMarkMoment: Bool

	static let defaults = AutomationRules(
		startRecordingOnNamedApp: false,
		stopRecordingWhenAppCloses: false,
		createClipOnMarkMoment: false
	)

	static let storageKey = "automationRulesV1"

	static func load() -> AutomationRules {
		guard let data = UserDefaults.standard.data(forKey: storageKey),
		      let rules = try? JSONDecoder().decode(AutomationRules.self, from: data) else {
			return defaults
		}
		return rules
	}

	func save() {
		guard let data = try? JSONEncoder().encode(self) else { return }
		UserDefaults.standard.set(data, forKey: Self.storageKey)
	}
}
