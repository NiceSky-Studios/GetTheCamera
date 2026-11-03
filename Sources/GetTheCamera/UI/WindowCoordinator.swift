import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator {
	private let onboardingWindowController: OnboardingWindowController
	private let lowStorageWarningWindowController: LowStorageWarningWindowController
	private var homeWindowController: NSWindowController?

	var shouldShowOnboarding: Bool {
		onboardingWindowController.shouldShow
	}

	init() {
		onboardingWindowController = OnboardingWindowController()
		lowStorageWarningWindowController = LowStorageWarningWindowController()
	}

	func showOnboardingIfNeeded(onDismiss: (() -> Void)? = nil) {
		onboardingWindowController.showIfNeeded(onDismiss: onDismiss)
	}

	func showOnboarding(onDismiss: (() -> Void)? = nil) {
		onboardingWindowController.show(onDismiss: onDismiss)
	}

	func showLowStorageWarning(_ warningMessage: String) {
		lowStorageWarningWindowController.show(warningMessage: warningMessage)
	}

	func closeLowStorageWarningIfNeeded() {
		lowStorageWarningWindowController.closeIfNeeded()
	}

	func openHome(appState: AppState, clip: Clip) {
		appState.clipToOpen = clip
		openHome(appState: appState)
	}

	func openHub(appState: AppState, updaterController: UpdaterController) {
		NSApp.activate(ignoringOtherApps: true)
		NSApp.setActivationPolicy(.regular)
		if let existingWindow = NSApp.windows.first(where: { $0.title == "GTC Hub" || $0.identifier?.rawValue == "gtc-hub" }) {
			existingWindow.makeKeyAndOrderFront(nil)
			return
		}
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.title = "GTC Hub"
		window.identifier = NSUserInterfaceItemIdentifier("gtc-hub")
		window.center()
		window.contentViewController = NSHostingController(
			rootView: SettingsView.GTCHubView(appState: appState, updaterController: updaterController)
		)
		window.isReleasedWhenClosed = false
		window.makeKeyAndOrderFront(nil)
	}

	func openHome(appState: AppState) {
		NSApp.activate(ignoringOtherApps: true)
		NSApp.setActivationPolicy(.regular)

		if let existingWindow = NSApp.windows.first(where: { $0.title == "Home" || $0.identifier?.rawValue == "home" }) {
			existingWindow.makeKeyAndOrderFront(nil)
			return
		}

		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.title = "Home"
		window.identifier = NSUserInterfaceItemIdentifier("home")
		window.center()
		window.contentViewController = NSHostingController(rootView: HomeView(appState: appState))
		window.isReleasedWhenClosed = false

		let controller = NSWindowController(window: window)
		homeWindowController = controller
		controller.showWindow(nil)
		window.makeKeyAndOrderFront(nil)
	}
}
