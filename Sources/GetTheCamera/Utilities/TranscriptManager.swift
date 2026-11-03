import AVFoundation
import Foundation
import Speech

@MainActor
final class TranscriptManager: ObservableObject {
	@Published private(set) var transcripts: [UUID: String] = [:]
	@Published private(set) var isTranscribing = false

	init() {
		if let saved = UserDefaults.standard.dictionary(forKey: "clipTranscripts") as? [String: String] {
			transcripts = saved.reduce(into: [:]) { result, item in
				if let id = UUID(uuidString: item.key) {
					result[id] = item.value
				}
			}
		}
	}

	func cachedTranscript(for clipID: UUID) -> String? {
		transcripts[clipID]
	}

	func transcribe(_ clip: Clip) async {
		guard !isTranscribing else { return }
		isTranscribing = true
		defer { isTranscribing = false }

		let status = await withCheckedContinuation { continuation in
			SFSpeechRecognizer.requestAuthorization { status in
				continuation.resume(returning: status)
			}
		}
		guard status == .authorized else {
			transcripts[clip.id] = "Speech recognition access is required."
			return
		}

		guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US")),
		      recognizer.isAvailable else {
			transcripts[clip.id] = "On-device speech recognition is unavailable."
			return
		}

		let request = SFSpeechURLRecognitionRequest(url: clip.url)
		request.requiresOnDeviceRecognition = true
		request.shouldReportPartialResults = false

		transcripts[clip.id] = await withCheckedContinuation { continuation in
			var resultText = ""
			recognizer.recognitionTask(with: request) { result, error in
				if let result {
					resultText = result.bestTranscription.formattedString
				}
				if let error {
					resultText = error.localizedDescription
					continuation.resume(returning: resultText)
					return
				}
				if result?.isFinal == true {
					continuation.resume(returning: resultText)
				}
			}
		}
		persist()
	}

	private func persist() {
		let saved = transcripts.reduce(into: [String: String]()) { result, item in
			result[item.key.uuidString] = item.value
		}
		UserDefaults.standard.set(saved, forKey: "clipTranscripts")
	}
}
