import AVFoundation
import AppKit
import CoreGraphics

enum TimelineEditorExporter {
	struct Edit: Sendable {
		let start: CMTime
		let end: CMTime
		let playbackRate: Double
		let volume: Float
	}

	static func export(clip: Clip, edit: Edit, to outputURL: URL) async throws {
		let asset = AVURLAsset(url: clip.url)
		let duration = try await asset.load(.duration)
		let start = CMTimeMaximum(edit.start, .zero)
		let end = CMTimeMinimum(edit.end, duration)
		guard end > start else { throw CaptureError.exportFailed }

		let composition = AVMutableComposition()
		var audioMix: AVAudioMix?
		guard let videoTrack = composition.addMutableTrack(
			withMediaType: .video,
			preferredTrackID: kCMPersistentTrackID_Invalid
		) else { throw CaptureError.exportFailed }
		let audioTrack = composition.addMutableTrack(
			withMediaType: .audio,
			preferredTrackID: kCMPersistentTrackID_Invalid
		)

		let sourceRange = CMTimeRange(start: start, end: CMTimeSubtract(end, start))
		if let sourceVideo = try await asset.loadTracks(withMediaType: .video).first {
			try videoTrack.insertTimeRange(sourceRange, of: sourceVideo, at: .zero)
			videoTrack.scaleTimeRange(
				CMTimeRange(start: .zero, duration: sourceRange.duration),
				toDuration: CMTimeMultiplyByFloat64(sourceRange.duration, multiplier: 1.0 / edit.playbackRate)
			)
		}
		if let audioTrack, let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
			try audioTrack.insertTimeRange(sourceRange, of: sourceAudio, at: .zero)
			audioTrack.scaleTimeRange(
				CMTimeRange(start: .zero, duration: sourceRange.duration),
				toDuration: CMTimeMultiplyByFloat64(sourceRange.duration, multiplier: 1.0 / edit.playbackRate)
			)
			let parameters = AVMutableAudioMixInputParameters(track: audioTrack)
			parameters.setVolume(edit.volume, at: .zero)
			let mix = AVMutableAudioMix()
			mix.inputParameters = [parameters]
			audioMix = mix
		}

		try? FileManager.default.removeItem(at: outputURL)
		guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
			throw CaptureError.exportFailed
		}
		exportSession.outputURL = outputURL
		exportSession.outputFileType = .mp4
		exportSession.shouldOptimizeForNetworkUse = true
		exportSession.audioMix = audioMix
		await exportSession.export()
		guard exportSession.status == .completed else {
			throw exportSession.error ?? CaptureError.exportFailed
		}
	}
}
