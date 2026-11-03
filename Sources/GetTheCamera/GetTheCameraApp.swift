import SwiftUI

@main
struct GetTheCameraApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
	@ObservedObject private var appState: AppState
	@ObservedObject private var updaterController: UpdaterController
	@Environment(\.openWindow) private var openWindow

	init() {
		_appState = ObservedObject(initialValue: AppCompositionRoot.shared.appState)
		_updaterController = ObservedObject(initialValue: AppCompositionRoot.shared.updaterController)
		AppLog.startFileLogging()
		AppLog.installFallbackCrashHandlers()
	}

	var body: some Scene {
		MenuBarExtra {
			MenuBarView(appState: appState)
		} label: {
			Image(systemName: appState.voiceControlEnabled ? "waveform.circle.fill" : "backward.end.fill")
		}

		Window("Home", id: "home") {
			HomeView(appState: appState)
		}
		.defaultSize(width: 800, height: 600)

		Window("GTC Hub", id: "gtc-hub") {
			GTCHubView(appState: appState, updaterController: updaterController)
		}
		.defaultSize(width: 960, height: 640)
		.commands {
			CommandGroup(replacing: .appSettings) {
				Button("GTC Hub...") {
					NSApp.activate(ignoringOtherApps: true)
					openWindow(id: "gtc-hub")
				}
				.keyboardShortcut(",", modifiers: .command)
			}
		}
	}
}
