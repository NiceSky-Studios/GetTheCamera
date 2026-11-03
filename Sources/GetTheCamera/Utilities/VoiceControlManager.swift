import AVFoundation
@preconcurrency import Speech

@MainActor
final class VoiceControlManager {
	enum Command {
		case saveClip
		case deleteLatestClip
		case openLatestClip
		case favoriteLatestClip
		case toggleRecording
		case pauseVoiceControl
		case markMoment
	}

	private let onCommand: (Command) -> Void
	private let audioEngine = AVAudioEngine()
	private var recognizer: SFSpeechRecognizer?
	private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
	private var recognitionTask: SFSpeechRecognitionTask?
	private var isListening = false
	private var shouldListen = false
	private var authorizationGeneration = 0
	private var lastTriggerDate: Date?
	private var triggerPhrases: [String] = ["clip that"]
	private var wakeWordEnabled = false
	private var wakeWord = "jarvis"
	private var triggerConfidence = 0.75

	init(onCommand: @escaping (Command) -> Void) {
		self.onCommand = onCommand
	}

	func setEnabled(_ enabled: Bool) {
		if enabled {
			shouldListen = true
			start()
		} else {
			stop()
		}
	}

	func setTriggerPhrases(_ phrases: [String]) {
		let normalized = AppSettings.normalizedPhrases(phrases)
			.map { $0.lowercased() }
			.map { phrase in
				phrase
					.replacingOccurrences(of: "[^a-z ]", with: " ", options: .regularExpression)
					.replacingOccurrences(of: "  ", with: " ")
					.trimmingCharacters(in: .whitespacesAndNewlines)
			}
		guard normalized != triggerPhrases else { return }
		triggerPhrases = normalized
		if shouldListen {
			stop()
			start()
		}
	}

	func setWakeWord(enabled: Bool, word: String, confidence: Double) {
		wakeWordEnabled = enabled
		wakeWord = word
			.lowercased()
			.trimmingCharacters(in: .whitespacesAndNewlines)
		triggerConfidence = min(max(confidence, 0.5), 1.0)
	}

	func stop() {
		shouldListen = false
		authorizationGeneration &+= 1
		stopListeningResources()
	}

	private func stopListeningResources() {
		isListening = false
		recognitionTask?.cancel()
		recognitionTask = nil
		recognitionRequest?.endAudio()
		recognitionRequest = nil
		if audioEngine.isRunning {
			audioEngine.stop()
		}
		audioEngine.inputNode.removeTap(onBus: 0)
	}

	private func start() {
		guard !isListening else { return }
		let generation = authorizationGeneration
		let authorizationHandler: @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void = { status in
			guard status == .authorized else {
				Task { @MainActor [weak self] in
					guard let self, self.shouldListen, self.authorizationGeneration == generation else { return }
					self.speechPermissionDenied()
				}
				return
			}

			let permissionHandler: @Sendable (Bool) -> Void = { granted in
				Task { @MainActor [weak self] in
					guard let self, self.shouldListen, self.authorizationGeneration == generation else { return }
					granted ? self.beginListening() : AppLog.error(.app, "Voice control microphone permission denied")
				}
			}
			AVAudioApplication.requestRecordPermission(completionHandler: permissionHandler)
		}
		SFSpeechRecognizer.requestAuthorization(authorizationHandler)
	}

	private func speechPermissionDenied() {
		AppLog.error(.app, "Voice control speech recognition permission denied")
	}

	private func beginListening() {
		guard shouldListen else { return }
		stopListeningResources()
		guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US")),
		      recognizer.isAvailable else {
			AppLog.error(.app, "Voice control speech recognizer is unavailable")
			return
		}
		self.recognizer = recognizer

		let request = SFSpeechAudioBufferRecognitionRequest()
		request.shouldReportPartialResults = true
		request.requiresOnDeviceRecognition = true
		recognitionRequest = request

		let inputNode = audioEngine.inputNode
		let recordingFormat = inputNode.outputFormat(forBus: 0)
		inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { @Sendable buffer, _ in
			request.append(buffer)
		}

		do {
			audioEngine.prepare()
			try audioEngine.start()
			isListening = true
		} catch {
			stop()
			AppLog.error(.app, "Voice control could not start audio:", error.localizedDescription)
			return
		}

		let triggerPhrases = triggerPhrases.map { phrase in
			phrase
				.replacingOccurrences(of: "[^a-z ]", with: " ", options: .regularExpression)
				.replacingOccurrences(of: "  ", with: " ")
				.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		let wakeWordEnabled = wakeWordEnabled
		let wakeWord = wakeWord.lowercased()
			.replacingOccurrences(of: "[^a-z ]", with: " ", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		let triggerConfidence = triggerConfidence
		recognitionTask = recognizer.recognitionTask(with: request) { @Sendable result, error in
			if let result {
				let text = result.bestTranscription.formattedString
					.lowercased()
					.replacingOccurrences(of: "[^a-z ]", with: " ", options: .regularExpression)
					.replacingOccurrences(of: "  ", with: " ")
					.trimmingCharacters(in: .whitespacesAndNewlines)
				let confidence = result.bestTranscription.segments.reduce(0.0) { sum, segment in
					sum + Double(segment.confidence)
				} / Double(max(result.bestTranscription.segments.count, 1))
				let shouldTrigger = triggerPhrases.contains { phrase in
					text.contains(phrase.lowercased())
				} && confidence >= triggerConfidence
					&& (!wakeWordEnabled || text.contains(wakeWord))
				let command = VoiceControlManager.recognizeCommand(
					text,
					confidence: confidence,
					triggerConfidence: triggerConfidence,
					wakeWordEnabled: wakeWordEnabled,
					wakeWord: wakeWord
				)
				let shouldRestart = error != nil || result.isFinal

				Task { @MainActor [weak self] in
					guard let self, self.shouldListen else { return }
					if let command {
						self.trigger(command: command)
					} else if shouldTrigger {
						self.trigger(command: .saveClip)
					}
					if shouldRestart && self.isListening {
						self.restartRecognition()
					}
				}
			} else if error != nil {
				Task { @MainActor [weak self] in
					guard let self, self.shouldListen, self.isListening else { return }
					self.restartRecognition()
				}
			}
		}
	}

	private nonisolated static func recognizeCommand(
		_ text: String,
		confidence: Double,
		triggerConfidence: Double,
		wakeWordEnabled: Bool,
		wakeWord: String
	) -> Command? {
		guard confidence >= triggerConfidence else { return nil }
		if wakeWordEnabled && !text.contains(wakeWord) { return nil }

		let commandMatches: [(Command, [String])] = [
			(.pauseVoiceControl, ["stop listening", "disable voice control", "voice control off"]),
			(.deleteLatestClip, ["delete the latest clip", "delete latest clip", "remove the latest clip"]),
			(.openLatestClip, ["open the latest clip", "open latest clip", "show the latest clip"]),
			(.favoriteLatestClip, ["favorite the latest clip", "favourite the latest clip", "bookmark the latest clip"]),
			(.toggleRecording, ["start recording", "stop recording", "toggle recording"]),
			(.markMoment, ["mark this moment", "mark that", "event marker", "bookmark this moment"])
		]
		return commandMatches.first(where: { _, phrases in
			phrases.contains { text.contains($0) }
		})?.0
	}

	private func trigger(command: Command) {
		if let lastTriggerDate, Date().timeIntervalSince(lastTriggerDate) < 2 {
			return
		}
		lastTriggerDate = Date()
		onCommand(command)
	}

	private func restartRecognition() {
		stop()
		start()
	}
}
