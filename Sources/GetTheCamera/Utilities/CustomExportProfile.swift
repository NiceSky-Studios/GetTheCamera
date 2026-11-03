import CoreGraphics
import Foundation

struct CustomExportProfile: Codable, Identifiable, Hashable {
	enum Resolution: String, CaseIterable, Codable, Identifiable {
		case source = "Source"
		case hd1080 = "1080p"
		case hd720 = "720p"
		case vertical1080 = "1080x1920"
		case compact = "480p"

		var id: String { rawValue }
		var size: CGSize? {
			switch self {
			case .source: return nil
			case .hd1080: return CGSize(width: 1920, height: 1080)
			case .hd720: return CGSize(width: 1280, height: 720)
			case .vertical1080: return CGSize(width: 1080, height: 1920)
			case .compact: return CGSize(width: 854, height: 480)
			}
		}
	}

	enum Format: String, CaseIterable, Codable, Identifiable {
		case mp4 = "MP4"
		case mov = "MOV"
		var id: String { rawValue }
	}

	var id = UUID()
	var name: String
	var preset: HighlightReelExporter.ExportPreset
	var resolution: Resolution
	var frameRate: Int
	var format: Format
}

enum CustomExportProfileStore {
	private static let key = "customExportProfiles"

	static func load() -> [CustomExportProfile] {
		guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
		return (try? JSONDecoder().decode([CustomExportProfile].self, from: data)) ?? []
	}

	static func save(_ profiles: [CustomExportProfile]) {
		guard let data = try? JSONEncoder().encode(profiles) else { return }
		UserDefaults.standard.set(data, forKey: key)
	}
}
