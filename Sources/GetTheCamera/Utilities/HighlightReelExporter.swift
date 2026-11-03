import AVFoundation
import Foundation

enum HighlightReelExporter {
	enum ExportPreset: String, CaseIterable, Identifiable, Codable {
		case source = "Source Quality"
		case youtubeHD = "YouTube HD"
		case vertical = "Vertical Social"
		case small = "Compact Share"

		var id: String { rawValue }

		var avPreset: String {
			switch self {
			case .source: return AVAssetExportPresetHighestQuality
			case .youtubeHD: return AVAssetExportPreset1920x1080
			case .vertical: return AVAssetExportPreset1280x720
			case .small: return AVAssetExportPresetMediumQuality
			}
		}
	}

	struct Segment {
		let clip: Clip
		let start: CMTime
		let end: CMTime
	}

	static func export(clips: [Clip], to outputDirectory: URL) async throws -> URL {
		try await export(clips: clips, preset: .source, to: outputDirectory)
	}

	static func export(clips: [Clip], preset: ExportPreset, to outputDirectory: URL) async throws -> URL {
		guard !clips.isEmpty else { throw CaptureError.exportFailed }
		let segments = clips.map { clip in
			Segment(clip: clip, start: .zero, end: CMTime(seconds: clip.duration, preferredTimescale: 600))
		}
		return try await export(segments: segments, preset: preset, to: outputDirectory)
	}

	static func export(segments: [Segment], to outputDirectory: URL) async throws -> URL {
		try await export(segments: segments, preset: .source, to: outputDirectory)
	}

	static func export(segments: [Segment], preset: ExportPreset, to outputDirectory: URL) async throws -> URL {
		try await export(segments: segments, preset: preset, profile: nil, to: outputDirectory)
	}

	static func export(segments: [Segment], profile: CustomExportProfile, to outputDirectory: URL) async throws -> URL {
		try await export(segments: segments, preset: profile.preset, profile: profile, to: outputDirectory)
	}

	private static func export(segments: [Segment], preset: ExportPreset, profile: CustomExportProfile?, to outputDirectory: URL) async throws -> URL {
		guard !segments.isEmpty else { throw CaptureError.exportFailed }

		let composition = AVMutableComposition()
		guard let videoTrack = composition.addMutableTrack(
			withMediaType: .video,
			preferredTrackID: kCMPersistentTrackID_Invalid
		) else {
			throw CaptureError.exportFailed
		}
		let audioTrack = composition.addMutableTrack(
			withMediaType: .audio,
			preferredTrackID: kCMPersistentTrackID_Invalid
		)

		var insertionTime = CMTime.zero
		for segment in segments {
			let clip = segment.clip
			let asset = AVURLAsset(url: clip.url)
			let duration = try await asset.load(.duration)
			let start = CMTimeMaximum(segment.start, .zero)
			let end = CMTimeMinimum(segment.end, duration)
			let safeEnd = CMTimeMaximum(end, CMTimeAdd(start, CMTime(seconds: 0.25, preferredTimescale: 600)))
			let timeRange = CMTimeRange(start: start, end: safeEnd - start)

			if let sourceVideo = try await asset.loadTracks(withMediaType: .video).first {
				try videoTrack.insertTimeRange(timeRange, of: sourceVideo, at: insertionTime)
			}
			if let audioTrack, let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
				try audioTrack.insertTimeRange(timeRange, of: sourceAudio, at: insertionTime)
			}
			insertionTime = CMTimeAdd(insertionTime, timeRange.duration)
		}

		try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
		let format = profile?.format ?? .mp4
		let fileExtension = format == .mp4 ? "mp4" : "mov"
		let filename = "Highlight Reel \(HighlightReelExporter.filenameDate()).\(fileExtension)"
		let outputURL = outputDirectory.appendingPathComponent(filename)
		try? FileManager.default.removeItem(at: outputURL)

		guard let exportSession = AVAssetExportSession(
			asset: composition,
			presetName: preset.avPreset
		) else {
			throw CaptureError.exportFailed
		}
		if let profile, let size = profile.resolution.size {
			let videoComposition = AVMutableVideoComposition()
			videoComposition.renderSize = size
			videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, profile.frameRate)))
			let instruction = AVMutableVideoCompositionInstruction()
			instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
			instruction.layerInstructions = composition.tracks
				.filter { $0.mediaType == .video }
				.compactMap { track in
					let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
					return layerInstruction
				}
			videoComposition.instructions = [instruction]
			exportSession.videoComposition = videoComposition
		}
		exportSession.outputURL = outputURL
		exportSession.outputFileType = format == .mp4 ? .mp4 : .mov
		exportSession.shouldOptimizeForNetworkUse = true
		await exportSession.export()

		guard exportSession.status == .completed else {
			throw exportSession.error ?? CaptureError.exportFailed
		}
		return outputURL
	}

	static func filenameDate() -> String {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
		return formatter.string(from: Date())
	}

	static func webVTTTime(_ seconds: Double) -> String {
		let clamped = max(0, seconds)
		let hours = Int(clamped) / 3600
		let minutes = Int(clamped) / 60 % 60
		let secs = Int(clamped) % 60
		let milliseconds = Int((clamped - floor(clamped)) * 1000)
		return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, milliseconds)
	}
}
