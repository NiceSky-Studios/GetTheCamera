import AVFoundation
import Foundation

enum AutomaticEventType: String, CaseIterable, Identifiable {
	case audioSpike = "Audio spike"
	case clipStart = "Clip start"
	case inactivity = "Inactivity"
	var id: String { rawValue }
}

struct AutomaticEventDetector {
	static func scoreHighlights(in clip: Clip) async -> Int {
		let spikeCount = await detectAudioSpikes(in: clip, threshold: 0.10).count
		let density = clip.duration > 0 ? Double(spikeCount) / (clip.duration / 60.0) : 0
		return min(100, max(1, Int(round(min(1.0, density / 8.0) * 100))))
	}

	static func detectAudioSpikes(in clip: Clip, threshold: Float = 0.12) async -> [TimeInterval] {
		let asset = AVURLAsset(url: clip.url)
		guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
			return []
		}
		let reader: AVAssetReader
		let settings: [String: Any] = [
			AVFormatIDKey: kAudioFormatLinearPCM,
			AVLinearPCMBitDepthKey: 16,
			AVLinearPCMIsFloatKey: false,
			AVLinearPCMIsBigEndianKey: false,
			AVLinearPCMIsNonInterleaved: false,
		]
		do {
			reader = try AVAssetReader(asset: asset)
			let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
			output.alwaysCopiesSampleData = false
			reader.add(output)
			guard reader.startReading() else { return [] }
		} catch {
			return []
		}

		var events: [TimeInterval] = []
		var sampleTime = 0.0
		let sampleRate = 48_000.0
		while reader.status == .reading {
			guard let buffer = reader.outputs.first?.copyNextSampleBuffer() else { break }
			guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
			let length = CMBlockBufferGetDataLength(block)
			var samples = [Int16](repeating: 0, count: length / MemoryLayout<Int16>.size)
			samples.withUnsafeMutableBytes { bytes in
				_ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
			}
			if !samples.isEmpty {
				let rms = sqrt(samples.reduce(Float.zero) { $0 + pow(Float($1) / 32768.0, 2) } / Float(samples.count))
				if rms >= threshold,
				   events.last.map({ sampleTime - $0 > 2.0 }) != false {
					events.append(sampleTime)
				}
				let duration = Double(samples.count) / sampleRate
				sampleTime += duration
			}
		}
		return events
	}
}
