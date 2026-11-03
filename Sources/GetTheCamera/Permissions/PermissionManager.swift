import AppKit
import AVFoundation
import CoreGraphics
import Speech
import UserNotifications

struct PermissionState: Equatable {
	var screenRecording: Bool = false
	var microphone: Bool = false
	var speechRecognition: Bool = false
	var notifications: Bool = false
}

enum PermissionError: Error {
	case screenRecordingDenied
	case microphoneDenied
}

enum PermissionManager {
	private static let screenCaptureSettingsURL = URL(
		string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
	)
	
	private static let microphoneSettingsURL = URL(
		string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
	)

	static func currentState() -> PermissionState {
		PermissionState(
			screenRecording: CGPreflightScreenCaptureAccess(),
			microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
			speechRecognition: SFSpeechRecognizer.authorizationStatus() == .authorized,
			notifications: notificationStatus() == .authorized
		)
	}

	private static func notificationStatus() -> UNAuthorizationStatus {
		var result = UNAuthorizationStatus.notDetermined
		let semaphore = DispatchSemaphore(value: 0)
		UNUserNotificationCenter.current().getNotificationSettings { settings in
			result = settings.authorizationStatus
			semaphore.signal()
		}
		_ = semaphore.wait(timeout: .now() + 1)
		return result
	}

	static func ensureScreenAccess() async throws {
		if CGPreflightScreenCaptureAccess() {
			return
		}

		let granted = CGRequestScreenCaptureAccess()
		if !granted {
			throw PermissionError.screenRecordingDenied
		}
	}
	
	static func ensureMicrophoneAccess() async throws {
		if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
			return
		}
		let granted = await AVCaptureDevice.requestAccess(for: .audio)
		if !granted {
			throw PermissionError.microphoneDenied
		}
	}

	static func requestSpeechRecognitionAccess() async -> Bool {
		await withCheckedContinuation { continuation in
			SFSpeechRecognizer.requestAuthorization { status in
				continuation.resume(returning: status == .authorized)
			}
		}
	}

	static func requestNotificationAccess() {
		UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
	}

	static func openNotificationsSettings() {
		if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
			NSWorkspace.shared.open(url)
		}
	}

	static func openSpeechSettings() {
		if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
			NSWorkspace.shared.open(url)
		}
	}

	static func openSystemSettings() {
		guard let url = screenCaptureSettingsURL else { return }
		NSWorkspace.shared.open(url)
	}

	/// Relaunches the app. macOS won't apply a newly granted Screen Recording
	/// permission to an already-running process, so once the user flips the
	/// toggle we restart to pick it up (a helper waits for this process to exit,
	/// then reopens the bundle).
	@MainActor
	static func relaunch() {
		let bundlePath = Bundle.main.bundlePath
		let pid = ProcessInfo.processInfo.processIdentifier
		let helper = Process()
		helper.executableURL = URL(fileURLWithPath: "/bin/sh")
		helper.arguments = [
			"-c",
			"while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"\(bundlePath)\"",
		]
		try? helper.run()
		NSApp.terminate(nil)
	}
	
	static func openMicrophoneSettings() {
		guard let url = microphoneSettingsURL else { return }
		NSWorkspace.shared.open(url)
	}
}
