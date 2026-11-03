import AppKit
import Combine

@MainActor
final class AppLifecycleController: NSObject {
	private let appState: AppState
	private let hotkeyManager: GlobalHotkeyManager
	private var windowCoordinator: WindowCoordinator?

	private var appActiveObserver: NSObjectProtocol?
	private var sleepObservers: [NSObjectProtocol] = []
	private var dockRelevantWindows = Set<ObjectIdentifier>()
	private var cancellables = Set<AnyCancellable>()
	private var lowStorageWarningActive = false
	private var hasStarted = false
	private var voiceControlManager: VoiceControlManager?

	init(
		appState: AppState,
		hotkeyManager: GlobalHotkeyManager
	) {
		self.appState = appState
		self.hotkeyManager = hotkeyManager
		super.init()
	}

	func start() {
		guard !hasStarted else { return }
		hasStarted = true

		if ClipNotificationManager.isEnabled {
			ClipNotificationManager.requestAuthorization()
		}

		ensureUIControllers()
		configureHotkeys()
		configureVoiceControl()
		observeApplicationState()
		observeWindowState()

		if windowCoordinator?.shouldShowOnboarding == true {
			windowCoordinator?.showOnboardingIfNeeded(onDismiss: { [weak self] in
				guard let self else { return }
				self.appState.startAlwaysRecording()
				self.windowCoordinator?.openHome(appState: self.appState)
			})
		} else {
			appState.startAlwaysRecording()
			if appState.startRecordingOnLaunchEnabled {
				appState.toggleCapture()
			}
			windowCoordinator?.openHome(appState: appState)
		}
	}

	func showOnboarding() {
		ensureUIControllers()
		windowCoordinator?.showOnboarding()
	}

	func stop() {
		guard hasStarted else { return }
		hasStarted = false

		if let appActiveObserver {
			NotificationCenter.default.removeObserver(appActiveObserver)
			self.appActiveObserver = nil
		}
		for observer in sleepObservers {
			NSWorkspace.shared.notificationCenter.removeObserver(observer)
		}
		sleepObservers.removeAll()
		NotificationCenter.default.removeObserver(
			self,
			name: NSWindow.didBecomeKeyNotification,
			object: nil
		)
		NotificationCenter.default.removeObserver(
			self,
			name: NSWindow.willCloseNotification,
			object: nil
		)

		hotkeyManager.configureActions(onSaveReplay: nil, onRecordToggle: nil)
		hotkeyManager.unregister()
		voiceControlManager?.stop()
		voiceControlManager = nil
		windowCoordinator?.closeLowStorageWarningIfNeeded()
		cancellables.removeAll()
		windowCoordinator = nil
		dockRelevantWindows.removeAll()
		NSApp.setActivationPolicy(.accessory)
	}

	private func ensureUIControllers() {
		guard windowCoordinator == nil else { return }
		windowCoordinator = WindowCoordinator()
	}

	private func configureHotkeys() {
		hotkeyManager.configureActions(
			onSaveReplay: { [weak appState] in
				appState?.saveReplay()
			},
			onRecordToggle: { [weak appState] in
				appState?.toggleCapture()
			},
			onMarkMoment: { [weak appState] in
				appState?.markMoment()
			},
			onOpenHub: { [weak self, weak appState] in
				guard let appState else { return }
				self?.windowCoordinator?.openHub(appState: appState, updaterController: AppCompositionRoot.shared.updaterController)
			}
		)

		hotkeyManager.register(
			saveReplayHotkey: appState.hotkey,
			recordToggleHotkey: appState.startRecordingHotkey,
			markMomentHotkey: appState.markMomentHotkey,
			openHubHotkey: appState.openHubHotkey
		)
	}

	func updateVoiceControl() {
		guard hasStarted else { return }
		if appState.voiceControlEnabled {
			if voiceControlManager == nil {
				voiceControlManager = VoiceControlManager { [weak self, weak appState] command in
					guard let self, let appState else { return }
					appState.respondToVoiceCommand(command)
					switch command {
					case .saveClip: appState.saveReplay()
					case .deleteLatestClip: appState.deleteLatestClip()
					case .openLatestClip:
						if let clip = appState.lastClip ?? appState.clipLibrary.clips.first {
							self.windowCoordinator?.openHome(appState: appState, clip: clip)
							appState.trackClipAction(action: "voice_open")
						}
					case .favoriteLatestClip: appState.favoriteLatestClip()
					case .toggleRecording: appState.toggleCapture()
					case .pauseVoiceControl: appState.voiceControlEnabled = false
					case .markMoment: appState.markMoment()
					}
				}
			}
			voiceControlManager?.setTriggerPhrases(appState.voiceControlPhrases)
			voiceControlManager?.setWakeWord(
				enabled: appState.voiceWakeWordEnabled,
				word: appState.voiceWakeWord,
				confidence: appState.voiceTriggerConfidence
			)
			voiceControlManager?.setEnabled(true)
		} else {
			voiceControlManager?.stop()
		}
	}

	private func configureVoiceControl() {
		voiceControlManager = VoiceControlManager { [weak self, weak appState] command in
			guard let self, let appState else { return }
			appState.respondToVoiceCommand(command)
			switch command {
			case .saveClip: appState.saveReplay()
			case .deleteLatestClip: appState.deleteLatestClip()
			case .openLatestClip:
				if let clip = appState.lastClip ?? appState.clipLibrary.clips.first {
					self.windowCoordinator?.openHome(appState: appState, clip: clip)
					appState.trackClipAction(action: "voice_open")
				}
			case .favoriteLatestClip: appState.favoriteLatestClip()
			case .toggleRecording: appState.toggleCapture()
			case .pauseVoiceControl: appState.voiceControlEnabled = false
			case .markMoment: appState.markMoment()
			}
		}
		updateVoiceControl()
	}

	private func observeApplicationState() {
		appActiveObserver = NotificationCenter.default.addObserver(
			forName: NSApplication.didBecomeActiveNotification,
			object: nil,
			queue: .main
		) { [weak appState] _ in
			Task { @MainActor in
				appState?.refreshPermissions()
			}
		}

		appState.$lowStorageWarningMessage
			.receive(on: DispatchQueue.main)
			.sink { [weak self] warningMessage in
				guard let self else { return }

				if let warningMessage {
					if !lowStorageWarningActive {
						lowStorageWarningActive = true
						windowCoordinator?.showLowStorageWarning(warningMessage)
					}
				} else {
					lowStorageWarningActive = false
					windowCoordinator?.closeLowStorageWarningIfNeeded()
				}
			}
			.store(in: &cancellables)

		let wsCenter = NSWorkspace.shared.notificationCenter

		sleepObservers.append(
			wsCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak appState] notification in
				let activatedName = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName?.lowercased() ?? ""
				Task { @MainActor in
					guard let appState else { return }
					guard appState.automationRules.startRecordingOnNamedApp else { return }
					let name = appState.automationAppName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
					guard !name.isEmpty else { return }
					if activatedName.contains(name), !appState.isCapturing {
						appState.startCapture(isAutomatic: true)
					}
				}
			}
		)
		sleepObservers.append(
			wsCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak appState] notification in
				let terminatedName = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName?.lowercased() ?? ""
				Task { @MainActor in
					guard let appState else { return }
					guard appState.automationRules.stopRecordingWhenAppCloses else { return }
					let name = appState.automationAppName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
					if terminatedName.contains(name), appState.isCapturing {
						appState.stopCapture()
					}
				}
			}
		)

		let sleepNames: [NSNotification.Name] = [
			NSWorkspace.willSleepNotification,
			NSWorkspace.screensDidSleepNotification
		]
		let wakeNames: [NSNotification.Name] = [
			NSWorkspace.didWakeNotification,
			NSWorkspace.screensDidWakeNotification
		]

		for name in sleepNames {
			sleepObservers.append(
				wsCenter.addObserver(forName: name, object: nil, queue: .main) { [weak appState] _ in
					Task { @MainActor in appState?.handleSleep() }
				}
			)
		}
		for name in wakeNames {
			sleepObservers.append(
				wsCenter.addObserver(forName: name, object: nil, queue: .main) { [weak appState] _ in
					Task { @MainActor in appState?.handleWake() }
				}
			)
		}
	}

	private func observeWindowState() {
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleWindowDidBecomeKey(_:)),
			name: NSWindow.didBecomeKeyNotification,
			object: nil
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleWindowWillClose(_:)),
			name: NSWindow.willCloseNotification,
			object: nil
		)
	}

	@objc
	private func handleWindowDidBecomeKey(_ notification: Notification) {
		guard let window = notification.object as? NSWindow else { return }
		guard window.styleMask.contains(.titled) else { return }
		dockRelevantWindows.insert(ObjectIdentifier(window))
		updateActivationPolicyForWindowVisibility()
	}

	@objc
	private func handleWindowWillClose(_ notification: Notification) {
		guard let window = notification.object as? NSWindow else { return }
		dockRelevantWindows.remove(ObjectIdentifier(window))
		updateActivationPolicyForWindowVisibility()
	}

	private func updateActivationPolicyForWindowVisibility() {
		let targetPolicy: NSApplication.ActivationPolicy = dockRelevantWindows.isEmpty ? .accessory : .regular
		guard NSApp.activationPolicy() != targetPolicy else { return }
		NSApp.setActivationPolicy(targetPolicy)
	}
}
