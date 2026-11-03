import AppKit
import AVFoundation
import Carbon
import SwiftUI

struct SettingsView: View {
	@ObservedObject var appState: AppState
	@ObservedObject var updaterController: UpdaterController
	@State private var didApplyWindowSizing = false

	private var settingsLocked: Bool {
		!appState.permissionState.screenRecording
	}

	enum GTCHubSection: String, CaseIterable, Identifiable {
		case library = "Library"
		case activity = "Activity"
		case plugins = "Plugins"
		case general = "General"
		case capture = "Capture"
		case hotkeys = "Hotkeys"
		case feedback = "Feedback"
		case permissions = "Permissions"
		case integrations = "Integrations"
		case about = "About"

		var id: String { rawValue }

		var systemImage: String {
			switch self {
			case .library: return "square.grid.2x2"
			case .activity: return "chart.bar"
			case .plugins: return "puzzlepiece.extension"
			case .general: return "gearshape"
			case .capture: return "record.circle"
			case .hotkeys: return "keyboard"
			case .feedback: return "speaker.wave.2"
			case .permissions: return "lock.shield"
			case .integrations: return "puzzlepiece.extension"
			case .about: return "info.circle"
			}
		}
	}

	struct GTCHubView: View {
		@ObservedObject var appState: AppState
		@ObservedObject var updaterController: UpdaterController
		@State private var selectedSection: GTCHubSection? = .library

		var body: some View {
			NavigationSplitView {
				List(GTCHubSection.allCases, selection: $selectedSection) { section in
					Label(section.rawValue, systemImage: section.systemImage)
						.tag(section)
				}
				.navigationTitle("GTC Hub")
				.frame(minWidth: 180)
			} detail: {
				Group {
					switch selectedSection ?? .library {
					case .library:
						HomeView(appState: appState)
					case .activity:
						GTCActivityView(appState: appState)
					case .plugins:
						GTCPluginsView(appState: appState)
					case .general:
						GeneralSettingsPane(appState: appState, updaterController: updaterController)
					case .capture:
						CaptureSettingsPane(appState: appState, settingsLocked: !appState.permissionState.screenRecording)
					case .hotkeys:
						HotkeysSettingsPane(appState: appState, settingsLocked: !appState.permissionState.screenRecording)
					case .feedback:
						FeedbackSettingsPane(appState: appState, settingsLocked: !appState.permissionState.screenRecording)
					case .permissions:
						PermissionsSettingsPane(appState: appState)
					case .integrations:
						IntegrationsSettingsPane(appState: appState, settingsLocked: !appState.permissionState.screenRecording)
					case .about:
						AboutSettingsPane()
					}
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			.navigationTitle("GTC Hub")
			.frame(minWidth: 760, minHeight: 560)
			.onAppear {
				appState.refreshPermissions()
				if appState.availableResolutions.isEmpty, !appState.isLoadingResolutions {
					appState.refreshResolutions()
				}
				appState.refreshMicrophones()
			}
		}
	}

	var body: some View {
		TabView {
			GeneralSettingsPane(appState: appState, updaterController: updaterController)
				.tabItem { Label("General", systemImage: "gearshape") }

			CaptureSettingsPane(appState: appState, settingsLocked: settingsLocked)
				.tabItem { Label("Capture", systemImage: "record.circle") }

			HotkeysSettingsPane(appState: appState, settingsLocked: settingsLocked)
				.tabItem { Label("Hotkeys", systemImage: "keyboard") }

			FeedbackSettingsPane(appState: appState, settingsLocked: settingsLocked)
				.tabItem { Label("Feedback", systemImage: "speaker.wave.2") }

			PermissionsSettingsPane(appState: appState)
				.tabItem { Label("Permissions", systemImage: "lock.shield") }

			IntegrationsSettingsPane(appState: appState, settingsLocked: settingsLocked)
				.tabItem { Label("Integrations", systemImage: "puzzlepiece.extension") }

			AboutSettingsPane()
				.tabItem { Label("About", systemImage: "info.circle") }
		}
		.frame(minWidth: 440, minHeight: 440)
		.safeAreaInset(edge: .top, spacing: 0) {
			if settingsLocked {
				PermissionCallout(appState: appState)
			}
		}
		.background(
			WindowAccessor { window in
				applyNaturalWindowSizeIfNeeded(window)
			}
		)
		.onAppear {
			appState.refreshPermissions()
			if appState.availableResolutions.isEmpty, !appState.isLoadingResolutions {
				appState.refreshResolutions()
			}
			appState.refreshMicrophones()
		}
	}

	private func applyNaturalWindowSizeIfNeeded(_ window: NSWindow) {
		guard !didApplyWindowSizing else { return }
		didApplyWindowSizing = true

		let naturalSize = NSSize(width: 520, height: 440)
		window.contentMinSize = naturalSize
		window.setContentSize(naturalSize)
	}
}

struct GeneralSettingsPane: View {
	@ObservedObject var appState: AppState
	@ObservedObject var updaterController: UpdaterController
	@State private var showingResetConfirmation = false
	@AppStorage(ClipNotificationManager.enabledKey) private var clipNotificationsEnabled = true
	@AppStorage("clipNotificationSoundName") private var clipNotificationSoundName = "default"

	var body: some View {
		Form {
			Section("Startup") {
				LabeledContent {
					Toggle("", isOn: $appState.launchAtLoginEnabled)
						.labelsHidden()
						.toggleStyle(.switch)
				} label: {
					HelpLabel("Open on login", help: "Automatically launch GetTheCamera when you log in to your Mac.")
				}
			}

			Section("Updates") {
				Button("Check for Updates...") {
					updaterController.checkForUpdates()
				}
				.disabled(updaterController.isChecking || updaterController.isUpdating)
				if updaterController.isUpdating {
					ProgressView(value: updaterController.updateProgress)
				}
				Text(updaterController.statusMessage)
					.foregroundStyle(.secondary)
			}

			Section("Privacy") {
				Toggle(isOn: $appState.analyticsEnabled) {
					HelpLabel(
						"Share anonymous analytics",
						help: "Sends anonymous app-open, recording, and replay-save events to help improve GetTheCamera. Never includes recordings, screenshots, file paths, game names, or error details."
					)
				}
			}

			Section("Notifications") {
				Toggle("Clip notifications", isOn: $clipNotificationsEnabled)
					.help("Show a macOS notification when a clip or highlight reel is ready.")
					.onChange(of: clipNotificationsEnabled) { _, enabled in
						ClipNotificationManager.setEnabled(enabled)
					}
				Picker("Notification sound", selection: $clipNotificationSoundName) {
					Text("System default").tag("default")
					Text("Silent").tag("none")
					Text("Submarine").tag("Submarine")
					Text("Glass").tag("Glass")
					Text("Ping").tag("Ping")
				}
				.disabled(!clipNotificationsEnabled)
			}

			Section("Diagnostics") {
				Toggle(isOn: $appState.fileLoggingEnabled) {
					HelpLabel("Enable verbose file logging", help: "Writes detailed debug logs to disk for troubleshooting.")
				}

				Button("Reveal Log File in Finder") {
					if let url = AppLog.logFileURL {
						NSWorkspace.shared.activateFileViewerSelecting([url])
					}
				}

				Section("Storage and Performance") {
					Toggle("Automatic clip cleanup", isOn: $appState.automaticCleanupEnabled)
					Stepper("Retain up to \(appState.clipRetentionLimit) clips", value: $appState.clipRetentionLimit, in: 25...5000, step: 25)
					Stepper("Storage warning at \(appState.storageWarningLimitGB) GB", value: $appState.storageWarningLimitGB, in: 1...100, step: 1)
					Text("Automatic cleanup removes the oldest unstarred clips when the retention limit is reached.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}

			Section("Advanced") {
				Button("Reset to Defaults...", role: .destructive) {
					showingResetConfirmation = true
				}
			}
		}
		.formStyle(.grouped)
		.confirmationDialog(
			"Reset all settings to their defaults?",
			isPresented: $showingResetConfirmation,
			titleVisibility: .visible
		) {
			Button("Reset to Defaults", role: .destructive) {
				appState.resetToDefaults()
			}
			Button("Cancel", role: .cancel) {}
		}
	}
}

struct CaptureSettingsPane: View {
	@ObservedObject var appState: AppState
	let settingsLocked: Bool

	private var replayDurationRange: ClosedRange<Int> {
		Int(AppSettings.replayDurationRange.lowerBound) ... Int(AppSettings.replayDurationRange.upperBound)
	}

	private var replayDurationStep: Int {
		max(1, Int(AppSettings.replayDurationStep))
	}

	private var replayDurationSecondsBinding: Binding<Int> {
		Binding(
			get: { Int(appState.replayDuration) },
			set: { newValue in
				let clampedValue = min(max(newValue, replayDurationRange.lowerBound), replayDurationRange.upperBound)
				appState.replayDuration = TimeInterval(clampedValue)
			}
		)
	}

	var body: some View {
		Form {
			Section("Recording") {
				LabeledContent {
					Toggle("", isOn: $appState.startRecordingOnLaunchEnabled)
						.labelsHidden()
						.toggleStyle(.switch)
				} label: {
					HelpLabel("Start recording on launch", help: "Automatically begin recording whenever GetTheCamera launches.")
				}

				TextField("Automate when app opens", text: $appState.automationAppName)
					.help("Reserved for app-aware automation, such as a game or streaming app.")
				Toggle("Start recording when this app opens", isOn: Binding(
					get: { appState.automationRules.startRecordingOnNamedApp },
					set: { value in
						appState.automationRules.startRecordingOnNamedApp = value
					}
				))
				Toggle("Stop recording when this app closes", isOn: Binding(
					get: { appState.automationRules.stopRecordingWhenAppCloses },
					set: { value in
						appState.automationRules.stopRecordingWhenAppCloses = value
					}
				))
				Toggle("Create a clip when I mark a moment", isOn: Binding(
					get: { appState.automationRules.createClipOnMarkMoment },
					set: { value in
						appState.automationRules.createClipOnMarkMoment = value
					}
				))

				Toggle("Automatically mark detected events", isOn: $appState.autoEventMarkersEnabled)
					.help("Prepares clips for event-marker workflows and smart reels.")
				Toggle("Detect audio spikes after saving", isOn: $appState.automaticAudioSpikeMarkers)
					.help("Analyzes the saved clip locally and adds markers where audio activity spikes.")
				Toggle("Add a clip-start marker", isOn: $appState.automaticClipStartMarkers)
				Toggle("Offer automatic transcription", isOn: $appState.autoTranscriptEnabled)
					.help("Transcription is still run on demand from each clip's Captions menu.")
				HStack {
					Text(TranscriptManager.shared.isTranscribing
						? "Transcribing background queue..."
						: "\(TranscriptManager.shared.queuedClipCount) clips queued")
					Spacer()
					Button("Queue existing clips") {
						TranscriptManager.shared.enqueue(appState.clipLibrary.clips)
						Task { await TranscriptManager.shared.processQueue() }
					}
				}
				.font(.caption)

				LabeledContent {
					Toggle("", isOn: $appState.captureTargetPromptEnabled)
						.labelsHidden()
						.toggleStyle(.switch)
						.disabled(!AppState.supportsCaptureTargetPrompt)
				} label: {
					HelpLabel(
						"Choose what to record",
						help: AppState.supportsCaptureTargetPrompt
							? "When you start recording manually, macOS asks which display, window or app to capture. Turn off to always record the main display."
							: "Choosing a display, window, or app to capture requires macOS 14 or later."
					)
				}

				LabeledContent {
					Stepper(
						value: replayDurationSecondsBinding,
						in: replayDurationRange,
						step: replayDurationStep
					) {
						Text(Int(appState.replayDuration).formattedDuration)
							.foregroundStyle(.secondary)
					}
					.frame(width: 200, alignment: .trailing)
				} label: {
					HelpLabel("Clip length", help: "Determines how many seconds of video to save when capturing.")
				}

				LabeledContent {
					Toggle("", isOn: $appState.alwaysRecordEnabled)
						.labelsHidden()
						.toggleStyle(.switch)
				} label: {
					HelpLabel("Always record", help: "Automatically saves clips continuously in the background.")
				}
			}
			.disabled(settingsLocked)

			Section("Video") {
				LabeledContent("Resolution") {
					resolutionControl
						.frame(width: 200, alignment: .trailing)
				}

				Picker(selection: $appState.selectedQuality) {
					ForEach(QualityPreset.presets) { preset in
						Text(defaultTaggedLabel(preset.label, isDefault: preset.isDefault)).tag(preset)
					}
				} label: {
					HelpLabel("Quality", help: "Higher quality increases file size but produces clearer video.")
				}
				.pickerStyle(.menu)

				Picker(selection: $appState.selectedFrameRate) {
					ForEach(CaptureFrameRate.options) { option in
						Text(defaultTaggedLabel(option.label, isDefault: option.isDefault)).tag(option)
					}
				} label: {
					HelpLabel("Frame rate", help: "Higher frame rates produce smoother video but use more system resources.")
				}
				.pickerStyle(.menu)
			}
			.disabled(settingsLocked)

			Section("Audio") {
				LabeledContent {
					Toggle("", isOn: $appState.recordDesktopAudioEnabled)
						.labelsHidden()
						.toggleStyle(.switch)
				} label: {
					HelpLabel("Record desktop audio", help: "Captures system/app audio playing on your Mac.")
				}

				LabeledContent {
					Toggle("", isOn: $appState.recordMicrophoneEnabled)
						.labelsHidden()
						.toggleStyle(.switch)
						.disabled(!AppState.supportsMicrophoneCapture)
				} label: {
					HelpLabel(
						"Record Microphone",
						help: AppState.supportsMicrophoneCapture
							? "Captures microphone audio. Requires microphone permissions."
							: "Captures microphone audio. Requires macOS 15 or later."
					)
				}

				if AppState.supportsMicrophoneCapture {
					Picker(selection: $appState.selectedMicrophoneDeviceID) {
						Text("System Default").tag(String?.none)
						ForEach(appState.availableMicrophones) { device in
							Text(device.name).tag(Optional(device.id))
						}
					} label: {
						HelpLabel("Microphone", help: "Which microphone to capture. System Default follows your Mac's input device.")
					}
					.pickerStyle(.menu)
					.disabled(!appState.recordMicrophoneEnabled)
				}
			}
			.disabled(settingsLocked)

			Section("Output") {
				LabeledContent("Save location") {
					HStack(spacing: 8) {
						Text(appState.outputDirectoryPath ?? "Movies/GetTheCamera")
							.lineLimit(1)
							.truncationMode(.middle)
							.foregroundStyle(.secondary)
							.frame(maxWidth: 160, alignment: .trailing)

						Button("Change...") {
							let panel = NSOpenPanel()
							panel.canChooseFiles = false
							panel.canChooseDirectories = true
							panel.canCreateDirectories = true
							if panel.runModal() == .OK, let url = panel.url {
								appState.outputDirectoryPath = url.path
							}
						}
						.controlSize(.small)
					}
				}

				Picker(selection: $appState.selectedContainer) {
					ForEach(CaptureContainer.options) { option in
						Text(defaultTaggedLabel(option.label, isDefault: option.isDefault)).tag(option)
					}
				} label: {
					HelpLabel("Container", help: "Video file format for saved clips (.mp4 or .mov).")
				}
				.pickerStyle(.menu)
			}
			.disabled(settingsLocked)
		}
		.formStyle(.grouped)
	}

	@ViewBuilder
	private var resolutionControl: some View {
		if appState.availableResolutions.isEmpty {
			if appState.isLoadingResolutions {
				ProgressView()
					.controlSize(.small)
			} else {
				HStack(spacing: 8) {
					Text(appState.resolutionLoadingMessage ?? "Resolution unavailable")
						.foregroundStyle(.secondary)
					Button("Reload") {
						appState.refreshResolutions()
					}
					.buttonStyle(.link)
				}
			}
		} else {
			Picker("Resolution", selection: $appState.selectedResolution) {
				ForEach(appState.availableResolutions) { resolution in
					Text(defaultTaggedLabel(resolution.label, isDefault: resolution.isNative))
							.tag(Optional(resolution))
				}
			}
			.labelsHidden()
			.pickerStyle(.menu)
		}
	}
}

struct HotkeysSettingsPane: View {
	@ObservedObject var appState: AppState
	let settingsLocked: Bool

	var body: some View {
		Form {
			Section {
				Toggle("Clip with voice", isOn: $appState.voiceControlEnabled)
					.help("When enabled, say any configured phrase to save the current replay.")
				TextField(
					"Trigger phrases",
					text: Binding(
						get: { appState.voiceControlPhrases.joined(separator: ", ") },
						set: { value in
							appState.voiceControlPhrases = value
								.split(whereSeparator: { $0 == "," || $0.isNewline })
								.map(String.init)
						}
					)
				)
				.disabled(!appState.voiceControlEnabled)
				Toggle("Require wake word", isOn: $appState.voiceWakeWordEnabled)
					.disabled(!appState.voiceControlEnabled)
				TextField("Wake word", text: $appState.voiceWakeWord)
					.disabled(!appState.voiceControlEnabled || !appState.voiceWakeWordEnabled)
				Slider(value: $appState.voiceTriggerConfidence, in: 0.5 ... 1.0, step: 0.05) {
					Text("Confidence")
				} minimumValueLabel: {
					Text("Flexible")
				} maximumValueLabel: {
					Text("Strict")
				}
				.disabled(!appState.voiceControlEnabled)
				Divider()
				Toggle("Speak voice responses", isOn: $appState.voiceResponseEnabled)
					.disabled(!appState.voiceControlEnabled)
				TextField("Response", text: $appState.voiceResponseText)
					.disabled(!appState.voiceControlEnabled || !appState.voiceResponseEnabled)
				TextField("Save clip response", text: Binding(
					get: {
						(UserDefaults.standard.dictionary(forKey: "voiceCommandResponses") as? [String: String])?["saveClip"] ?? ""
					},
					set: { value in
						var responses = UserDefaults.standard.dictionary(forKey: "voiceCommandResponses") as? [String: String] ?? [:]
						responses["saveClip"] = value
						UserDefaults.standard.set(responses, forKey: "voiceCommandResponses")
					}
				))
				.disabled(!appState.voiceControlEnabled || !appState.voiceResponseEnabled)
				TextField("Mark moment response", text: Binding(
					get: {
						(UserDefaults.standard.dictionary(forKey: "voiceCommandResponses") as? [String: String])?["markMoment"] ?? ""
					},
					set: { value in
						var responses = UserDefaults.standard.dictionary(forKey: "voiceCommandResponses") as? [String: String] ?? [:]
						responses["markMoment"] = value
						UserDefaults.standard.set(responses, forKey: "voiceCommandResponses")
					}
				))
				.disabled(!appState.voiceControlEnabled || !appState.voiceResponseEnabled)
				Picker("Voice style", selection: $appState.voiceCharacterPreset) {
					ForEach(VoiceResponseManager.CharacterPreset.allCases) { preset in
						Text(preset.displayName).tag(preset)
					}
				}
				.disabled(!appState.voiceControlEnabled || !appState.voiceResponseEnabled)
				Picker("Voice", selection: Binding(
					get: { appState.voiceResponseVoiceIdentifier ?? "" },
					set: { appState.voiceResponseVoiceIdentifier = $0.isEmpty ? nil : $0 }
				)) {
					Text("System default").tag("")
					ForEach(AVSpeechSynthesisVoice.speechVoices()
						.filter { $0.language.hasPrefix("en") }
						.sorted { $0.name < $1.name }, id: \.identifier) { voice in
						Text(voice.name).tag(voice.identifier)
					}
				}
				.disabled(!appState.voiceControlEnabled || !appState.voiceResponseEnabled)
				Button("Preview response") {
					VoiceResponseManager.shared.speak(
						appState.voiceResponseText,
						voiceIdentifier: appState.voiceResponseVoiceIdentifier,
						preset: appState.voiceCharacterPreset
					)
				}
				.disabled(!appState.voiceControlEnabled || !appState.voiceResponseEnabled)
			} header: {
				Text("Voice Control")
			} footer: {
				Text("Separate custom save phrases with commas. Built-in commands: “Delete the latest clip,” “Open the latest clip,” “Favorite the latest clip,” “Start recording,” “Stop recording,” “Toggle recording,” and “Stop listening.” Uses on-device recognition and requires Microphone and Speech Recognition access.")
			}

			Section {
				HotkeyRecorderRow(title: "Start/Stop recording", hotkey: $appState.startRecordingHotkey)
				HotkeyRecorderRow(title: "Save last clip", hotkey: $appState.hotkey)
				HotkeyRecorderRow(title: "Mark moment", hotkey: $appState.markMomentHotkey)
				HotkeyRecorderRow(title: "Open GTC Hub", hotkey: $appState.openHubHotkey)
			} header: {
				Text("Shortcuts")
			} footer: {
				Text("Press Escape to cancel recording.")
			}
			.disabled(settingsLocked)
		}
		.formStyle(.grouped)
	}
}

private struct FeedbackSection: View {
	let title: String
	let toggleLabel: String
	@Binding var enabled: Bool
	@Binding var sound: FeedbackSound
	@Binding var volume: Double
	let settingsLocked: Bool
	let onPlay: () -> Void

	private var feedbackVolumeRange: ClosedRange<Int> {
		Int(AppSettings.saveFeedbackVolumeRange.lowerBound) ... Int(AppSettings.saveFeedbackVolumeRange.upperBound)
	}

	private var volumeBinding: Binding<Int> {
		Binding(
			get: { Int(volume.rounded()) },
			set: { newValue in
				let clamped = min(max(newValue, feedbackVolumeRange.lowerBound), feedbackVolumeRange.upperBound)
				volume = Double(clamped)
			}
		)
	}

	var body: some View {
		Section(title) {
			Toggle(toggleLabel, isOn: $enabled)

			Picker("Feedback sound", selection: $sound) {
				ForEach(FeedbackSound.options) { soundOption in
					Text(soundOption.label).tag(soundOption)
				}
			}
			.pickerStyle(.menu)
			.disabled(!enabled)

			LabeledContent("Feedback volume") {
				HStack(spacing: 6) {
					TextField("", value: volumeBinding, format: .number.grouping(.never))
						.textFieldStyle(.roundedBorder)
						.multilineTextAlignment(.trailing)
						.frame(width: 64)
						.help("Range: \(feedbackVolumeRange.lowerBound)-\(feedbackVolumeRange.upperBound)")
						.disabled(!enabled)

					Text("%")
						.foregroundStyle(.secondary)

					Button {
						onPlay()
					} label: {
						Image(systemName: "play.circle")
					}
					.buttonStyle(.plain)
					.padding(.leading, 4)
					.disabled(!enabled)
				}
			}
		}
		.disabled(settingsLocked)
	}
}

struct FeedbackSettingsPane: View {
	@ObservedObject var appState: AppState
	let settingsLocked: Bool

	var body: some View {
		Form {
			FeedbackSection(
				title: "Save Feedback",
				toggleLabel: "Enable save feedback",
				enabled: $appState.saveFeedbackEnabled,
				sound: $appState.saveFeedbackSound,
				volume: $appState.saveFeedbackVolume,
				settingsLocked: settingsLocked,
				onPlay: { appState.playReplaySavedFeedback() }
			)

			FeedbackSection(
				title: "Recording Start Feedback",
				toggleLabel: "Enable start feedback",
				enabled: $appState.recordingStartFeedbackEnabled,
				sound: $appState.recordingStartFeedbackSound,
				volume: $appState.recordingStartFeedbackVolume,
				settingsLocked: settingsLocked,
				onPlay: { appState.playRecordingStartFeedback() }
			)

			FeedbackSection(
				title: "Recording End Feedback",
				toggleLabel: "Enable end feedback",
				enabled: $appState.recordingEndFeedbackEnabled,
				sound: $appState.recordingEndFeedbackSound,
				volume: $appState.recordingEndFeedbackVolume,
				settingsLocked: settingsLocked,
				onPlay: { appState.playRecordingEndFeedback() }
			)

			FeedbackSection(
				title: "Error Feedback",
				toggleLabel: "Enable error feedback",
				enabled: $appState.errorFeedbackEnabled,
				sound: $appState.errorFeedbackSound,
				volume: $appState.errorFeedbackVolume,
				settingsLocked: settingsLocked,
				onPlay: { appState.playErrorFeedback() }
			)
		}
		.formStyle(.grouped)
	}
}

private struct WindowAccessor: NSViewRepresentable {
	let onResolve: (NSWindow) -> Void

	func makeNSView(context _: Context) -> NSView {
		let view = NSView()
		DispatchQueue.main.async {
			if let window = view.window {
				onResolve(window)
			}
		}
		return view
	}

	func updateNSView(_ nsView: NSView, context _: Context) {
		DispatchQueue.main.async {
			if let window = nsView.window {
				onResolve(window)
			}
		}
	}
}

struct PermissionsSettingsPane: View {
	@ObservedObject var appState: AppState
	@State private var isRequestingSpeech = false

	var body: some View {
		Form {
			Section("Required for Capture") {
				permissionRow(
					title: "Screen Recording",
					detail: "Required to capture gameplay and create clips.",
					granted: appState.permissionState.screenRecording,
					action: appState.requestScreenRecordingAccess
				)
				permissionRow(
					title: "Microphone",
					detail: "Captures microphone audio with your clips.",
					granted: appState.permissionState.microphone,
					action: {
						Task {
							_ = try? await PermissionManager.ensureMicrophoneAccess()
							appState.refreshPermissions()
						}
						PermissionManager.openMicrophoneSettings()
					}
				)
			}

			Section("Voice & Notifications") {
				permissionRow(
					title: "Speech Recognition",
					detail: "Enables commands such as “Clip that” and “Open the latest clip.”",
					granted: appState.permissionState.speechRecognition,
					action: {
						isRequestingSpeech = true
						Task {
							_ = await PermissionManager.requestSpeechRecognitionAccess()
							appState.refreshPermissions()
							isRequestingSpeech = false
						}
						PermissionManager.openSpeechSettings()
					}
				)
				permissionRow(
					title: "Notifications",
					detail: "Alerts you when clips and highlight reels are ready.",
					granted: appState.permissionState.notifications,
					action: {
						ClipNotificationManager.requestAuthorization()
						PermissionManager.openNotificationsSettings()
					}
				)
			}

			Button("Refresh Permission Status") {
				appState.refreshPermissions()
			}
		}
		.formStyle(.grouped)
		.onAppear {
			appState.refreshPermissions()
		}
	}

	private func permissionRow(
		title: String,
		detail: String,
		granted: Bool,
		action: @escaping () -> Void
	) -> some View {
		HStack {
			VStack(alignment: .leading, spacing: 3) {
				Text(title).font(.body.weight(.medium))
				Text(detail).font(.caption).foregroundStyle(.secondary)
			}
			Spacer()
			Label(granted ? "Allowed" : "Not Allowed",
				  systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
				.foregroundStyle(granted ? .green : .orange)
				.font(.caption)
			Button(granted ? "System Settings" : "Grant Access", action: action)
				.buttonStyle(.bordered)
				.controlSize(.small)
		}
	}
}

struct IntegrationsSettingsPane: View {
	@ObservedObject var appState: AppState
	let settingsLocked: Bool
	@State private var cloudFiles: [GoogleDriveFile] = []
	@State private var cloudLoading = false
	@State private var cloudError: String?

	var body: some View {
		Form {
			Section("Connections") {
				Toggle(isOn: $appState.discordRPCEnabled) {
					HelpLabel("Enable Discord RPC", help: "Shows your recording status on your Discord profile.")
				}
				Toggle(isOn: $appState.shareGamePresenceEnabled) {
					HelpLabel("Show the game you're playing", help: "Adds the game you're playing to your Discord status. Turn this off to show only that you're recording, without naming the game.")
				}
				.disabled(!appState.discordRPCEnabled)
				Toggle(isOn: $appState.shareRobloxExperienceEnabled) {
					HelpLabel("Show your Roblox experience", help: "Shows exactly which Roblox experience you're in, with a button friends can use to join you. Turn this off to show just \"Roblox\".")
				}
				.disabled(!appState.discordRPCEnabled || !appState.shareGamePresenceEnabled)
			}
			.disabled(settingsLocked)

			Section {
				Toggle(isOn: $appState.googleDriveSyncEnabled) {
					HelpLabel(
						"Sync clips to Google Drive",
						help: "Uploads newly saved clips to an app folder in your Google Drive."
					)
				}
			} header: {
				Text("Cloud Sync")
			} footer: {
				Text("Google Drive sync uses the GetTheCamera folder in your Drive. Enable this toggle to sign in.")
			}
			.disabled(settingsLocked)

			if appState.googleDriveSyncEnabled {
				Section("Cloud Library") {
					Picker("Scheduled backup", selection: $appState.cloudBackupIntervalHours) {
						Text("Off").tag(0)
						Text("Every 6 hours").tag(6)
						Text("Daily").tag(24)
						Text("Weekly").tag(168)
					}
					Button("Back up existing clips") {
						Task {
							for clip in appState.clipLibrary.clips {
								do {
									try await GoogleDriveSyncManager.shared.sync(clipAt: clip.url)
								} catch {
									GoogleDriveSyncManager.shared.queueForUpload(clipAt: clip.url)
								}
							}
						}
					}
					Button("Restore cloud clips") {
						Task {
							cloudLoading = true
							cloudError = nil
							do {
								let folder = ClipStorageLocation.folder(outputDirectoryPath: appState.outputDirectoryPath)
								for file in try await GoogleDriveSyncManager.shared.listCloudFiles() {
									let restored = try await GoogleDriveSyncManager.shared.download(file: file, to: folder)
									let asset = AVURLAsset(url: restored)
									let duration = try await asset.load(.duration)
									_ = try await appState.clipLibrary.addClip(url: restored, duration: duration.seconds)
								}
							} catch {
								cloudError = error.localizedDescription
							}
							cloudLoading = false
						}
					}
					.disabled(cloudLoading)
					Button(cloudLoading ? "Refreshing..." : "Refresh Cloud Library") {
						Task {
							cloudLoading = true
							cloudError = nil
							do {
								cloudFiles = try await GoogleDriveSyncManager.shared.listCloudFiles()
							} catch {
								cloudError = error.localizedDescription
							}
							cloudLoading = false
						}
					}
					.disabled(cloudLoading)

					if let cloudError {
						Text(cloudError).font(.caption).foregroundStyle(.red)
					} else if cloudFiles.isEmpty {
						Text("No cloud clips found. Refresh to check Drive.")
							.font(.caption)
							.foregroundStyle(.secondary)
					} else {
						ForEach(cloudFiles.prefix(20)) { file in
							LabeledContent(file.name) {
								Text(file.size.map { ByteCountFormatter.string(fromByteCount: Int64($0) ?? 0, countStyle: .file) } ?? "Cloud file")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
						}
					}
				}
				.disabled(settingsLocked)
			}

			Section {
				ForEach(ClipUploadProvider.providers) { provider in
					Toggle(isOn: uploadProviderBinding(for: provider)) {
						HelpLabel(provider.displayName, help: provider.summary)
					}
				}
			} header: {
				Text("Upload Providers")
			} footer: {
				Text("By enabling a provider, you agree to their respective Terms of Service and Privacy Policy.")
			}
			.disabled(settingsLocked)
		}
		.formStyle(.grouped)
	}

	private func uploadProviderBinding(for provider: ClipUploadProvider) -> Binding<Bool> {
		Binding(
			get: { appState.isUploadProviderEnabled(provider) },
			set: { appState.setUploadProvider(provider, enabled: $0) }
		)
	}
}

struct AboutSettingsPane: View {
	private var appVersion: String {
		let shortVersion = normalizedVersion(
			Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
		) ?? normalizedVersion(ProcessInfo.processInfo.environment["GETTHECAMERA_VERSION"])

		let buildVersion = normalizedVersion(
			Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
		)

		if let shortVersion {
			if let buildVersion, buildVersion != shortVersion {
				return "\(shortVersion) (\(buildVersion))"
			}
			return shortVersion
		}

		if let buildVersion {
			return buildVersion
		}

		return "Dev"
	}

	private func normalizedVersion(_ value: String?) -> String? {
		guard let value else { return nil }
		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : trimmed
	}

	var body: some View {
		Form {
			Section("GetTheCamera") {
				LabeledContent("Version") {
					Text(appVersion)
				}
			}
		}
		.formStyle(.grouped)
	}
}

private func defaultTaggedLabel(_ label: String, isDefault: Bool) -> String {
	isDefault ? "\(label) (Default)" : label
}

private struct HelpLabel: View {
	let title: String
	let help: String
	@State private var isHovering = false
	@State private var hoverTask: Task<Void, Never>?

	init(_ title: String, help: String) {
		self.title = title
		self.help = help
	}

	var body: some View {
		HStack(spacing: 4) {
			Text(title)
			Image(systemName: "questionmark.circle")
				.foregroundStyle(isHovering ? .primary : .secondary)
				.onHover { hovering in
					hoverTask?.cancel()
					if hovering {
						hoverTask = Task {
							try? await Task.sleep(nanoseconds: 500_000_000)
							if !Task.isCancelled {
								isHovering = true
							}
						}
					} else {
						isHovering = false
					}
				}
				.popover(isPresented: $isHovering, arrowEdge: .top) {
					Text(help)
						.lineLimit(nil)
						.frame(width: 220, alignment: .leading)
						.padding(10)
				}
		}
	}
}

private struct PermissionCallout: View {
	@ObservedObject var appState: AppState

	var body: some View {
		HStack(spacing: 12) {
			Image(systemName: "lock.fill")
				.font(.title3)
				.foregroundStyle(.secondary)

			VStack(alignment: .leading, spacing: 2) {
				Text("Screen recording permission required")
					.font(.callout.weight(.medium))
				Text("Grant access to change capture settings.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			Spacer(minLength: 8)

			Button("Open System Settings") {
				appState.requestScreenRecordingAccess()
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.small)
		}
		.padding(12)
		.background(
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.fill(.ultraThinMaterial)
		)
		.overlay(
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
		)
		.padding(.horizontal)
		.padding(.top, 8)
	}
}

private struct HotkeyRecorderRow: View {
	let title: String
	@Binding var hotkey: Hotkey
	@State private var isRecording = false
	@State private var monitor: Any?

	var body: some View {
		LabeledContent(title) {
			HStack(spacing: 10) {
				Text(isRecording ? "Press keys..." : hotkey.displayString)
					.foregroundStyle(.secondary)
					.monospaced()

				Button(isRecording ? "Cancel" : "Record") {
					if isRecording {
						stopRecording()
					} else {
						startRecording()
					}
				}
				.controlSize(.small)
			}
		}
		.onDisappear {
			stopRecording()
		}
	}

	private func startRecording() {
		isRecording = true
		if monitor != nil { return }

		monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
			guard isRecording else { return event }

			if event.keyCode == UInt16(kVK_Escape) {
				stopRecording()
				return nil
			}

			let relevantFlags = event.modifierFlags.intersection([.command, .shift, .option, .control])

			hotkey = Hotkey(keyCode: UInt32(event.keyCode), modifiers: relevantFlags.carbonModifiers)
			stopRecording()
			return nil
		}
	}

	private func stopRecording() {
		isRecording = false
		if let monitor {
			NSEvent.removeMonitor(monitor)
			self.monitor = nil
		}
	}
}

struct GTCActivityView: View {
	@ObservedObject var appState: AppState

	var body: some View {
		Form {
			Section("Library Activity") {
				LabeledContent("Saved clips", value: "\(appState.activityClipCount)")
				LabeledContent("Favorites", value: "\(appState.activityFavoriteCount)")
				LabeledContent("Recorded clip time", value: Int(appState.activityClipDuration).formattedDuration)
				LabeledContent("Library storage") {
					Text(ByteCountFormatter.string(fromByteCount: appState.activityStorageBytes, countStyle: .file))
				}
			}
			Section("Automation") {
				Toggle("Start recording on launch", isOn: $appState.startRecordingOnLaunchEnabled)
				Toggle("Automatic event markers", isOn: $appState.autoEventMarkersEnabled)
				Toggle("Automatic clip cleanup", isOn: $appState.automaticCleanupEnabled)
			}
		}
		.formStyle(.grouped)
		.padding()
	}
}

struct GTCPluginsView: View {
	@ObservedObject var appState: AppState

	var body: some View {
		Form {
			Section("Game and App Integrations") {
				TextField("Automation app name", text: $appState.automationAppName)
				Text("Enter a running app name to use in automation-aware game integrations.")
					.font(.caption)
					.foregroundStyle(.secondary)
				Button("Open Plugin Folder") {
					let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
						.appendingPathComponent("GetTheCamera/Plugins", isDirectory: true)
					try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
					NSWorkspace.shared.open(url)
				}
				Text("Plugins can publish marker events to the GetTheCamera Plugins folder.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Section("Plugin Status") {
				LabeledContent("Folder integration", value: "Ready")
				LabeledContent("Event markers", value: appState.autoEventMarkersEnabled ? "Enabled" : "Disabled")
			}
		}
		.formStyle(.grouped)
		.padding()
	}
}

enum GTCHubSidebarSection: String, CaseIterable, Identifiable {
	case library = "Library"
	case activity = "Activity"
	case plugins = "Plugins"
	case general = "General"
	case capture = "Capture"
	case hotkeys = "Hotkeys"
	case feedback = "Feedback"
	case permissions = "Permissions"
	case integrations = "Integrations"
	case about = "About"

	var id: String { rawValue }

	var systemImage: String {
		switch self {
		case .library: return "square.grid.2x2"
		case .activity: return "chart.bar"
		case .plugins: return "puzzlepiece.extension"
		case .general: return "gearshape"
		case .capture: return "record.circle"
		case .hotkeys: return "keyboard"
		case .feedback: return "speaker.wave.2"
		case .permissions: return "lock.shield"
		case .integrations: return "puzzlepiece.extension"
		case .about: return "info.circle"
		}
	}
}

struct GTCHubView: View {
	@ObservedObject var appState: AppState
	@ObservedObject var updaterController: UpdaterController
	@State private var selectedSection: GTCHubSidebarSection? = .library

	var body: some View {
		NavigationSplitView {
			List(GTCHubSidebarSection.allCases, selection: $selectedSection) { section in
				Label(section.rawValue, systemImage: section.systemImage)
					.tag(section)
			}
			.navigationTitle("GTC Hub")
			.frame(minWidth: 180)
		} detail: {
			Group {
				switch selectedSection ?? .library {
				case .library:
					HomeView(appState: appState)
				case .activity:
					GTCActivityView(appState: appState)
				case .plugins:
					GTCPluginsView(appState: appState)
				case .general:
					GeneralSettingsPane(appState: appState, updaterController: updaterController)
				case .capture:
					CaptureSettingsPane(appState: appState, settingsLocked: !appState.permissionState.screenRecording)
				case .hotkeys:
					HotkeysSettingsPane(appState: appState, settingsLocked: !appState.permissionState.screenRecording)
				case .feedback:
					FeedbackSettingsPane(appState: appState, settingsLocked: !appState.permissionState.screenRecording)
				case .permissions:
					PermissionsSettingsPane(appState: appState)
				case .integrations:
					IntegrationsSettingsPane(appState: appState, settingsLocked: !appState.permissionState.screenRecording)
				case .about:
					AboutSettingsPane()
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.navigationTitle("GTC Hub")
		.frame(minWidth: 760, minHeight: 560)
		.onAppear {
			appState.refreshPermissions()
			if appState.availableResolutions.isEmpty, !appState.isLoadingResolutions {
				appState.refreshResolutions()
			}
			appState.refreshMicrophones()
		}
	}
}
