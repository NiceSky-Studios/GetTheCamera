import AVFoundation

@MainActor
final class VoiceResponseManager {
	enum CharacterPreset: String, CaseIterable, Identifiable {
		case system = "System Default"
		case jarvis = "British AI Butler"
		case calmAI = "Calm AI Assistant"
		case commander = "Mission Commander"
		case companion = "Friendly Companion"
		case cinematic = "Cinematic Voice"

		var id: String { rawValue }

		var displayName: String {
			switch self {
			case .system: return "System Default"
			case .jarvis: return "British AI Butler (Jarvis-inspired)"
			case .calmAI: return "Calm AI Assistant"
			case .commander: return "Mission Commander"
			case .companion: return "Friendly Companion"
			case .cinematic: return "Cinematic Voice"
			}
		}

		var rate: Float {
			switch self {
			case .system: return AVSpeechUtteranceDefaultSpeechRate
			case .jarvis: return AVSpeechUtteranceDefaultSpeechRate * 0.92
			case .calmAI: return AVSpeechUtteranceDefaultSpeechRate * 0.82
			case .commander: return AVSpeechUtteranceDefaultSpeechRate * 1.08
			case .companion: return AVSpeechUtteranceDefaultSpeechRate * 1.04
			case .cinematic: return AVSpeechUtteranceDefaultSpeechRate * 0.88
			}
		}

		var pitch: Float {
			switch self {
			case .system: return 1.0
			case .jarvis: return 1.04
			case .calmAI: return 0.95
			case .commander: return 0.88
			case .companion: return 1.08
			case .cinematic: return 0.82
			}
		}

		var preferredLanguage: String {
			switch self {
			case .jarvis: return "en-GB"
			default: return "en-US"
			}
		}
	}

	static let shared = VoiceResponseManager()

	private let synthesizer = AVSpeechSynthesizer()

	private init() {}

	func speak(
		_ text: String,
		voiceIdentifier: String?,
		preset: CharacterPreset = .system
	) {
		let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !cleaned.isEmpty else { return }
		synthesizer.stopSpeaking(at: .immediate)

		let utterance = AVSpeechUtterance(string: cleaned)
		utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier ?? "")
			?? bestVoice(for: preset)
		utterance.rate = preset.rate
		utterance.pitchMultiplier = preset.pitch
		utterance.volume = 1.0
		synthesizer.speak(utterance)
	}

	private func bestVoice(for preset: CharacterPreset) -> AVSpeechSynthesisVoice? {
		let voices = AVSpeechSynthesisVoice.speechVoices()
		if preset == .jarvis {
			if let british = voices.first(where: { $0.language.hasPrefix("en-GB") && $0.name.localizedCaseInsensitiveContains("Daniel") }) {
				return british
			}
			if let british = voices.first(where: { $0.language.hasPrefix("en-GB") }) {
				return british
			}
		}
		return AVSpeechSynthesisVoice(language: preset.preferredLanguage)
			?? AVSpeechSynthesisVoice(language: "en-US")
	}
}
