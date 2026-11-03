import AppKit
import AVKit
import SwiftUI

enum ReelTransition: String, CaseIterable, Identifiable {
	case none = "None"
	case crossfade = "Crossfade"
	case dissolve = "Dissolve"
	var id: String { rawValue }
}

enum ReelCaptionStyle: String, CaseIterable, Identifiable {
	case none = "None"
	case title = "Clip titles"
	case timestamp = "Titles + timestamps"
	var id: String { rawValue }
}

struct HomeView: View {
	@ObservedObject var appState: AppState
	@StateObject private var transcriptManager = TranscriptManager.shared
	@State private var selectedClip: Clip?
	@State private var selectedCategory: String? = "all"
	@State private var searchText = ""
	@State private var showingReelEditor = false
	@State private var reelClips: [Clip] = []
	@State private var reelTransition: ReelTransition = .none
	@State private var reelCaptionStyle: ReelCaptionStyle = .none
	@State private var reelMaxDuration = 60
	@State private var collectionName = ""
	@State private var projectName = ""
	@State private var reelStarts: [UUID: Double] = [:]
	@State private var reelEnds: [UUID: Double] = [:]
	@State private var newProfileName = ""
	@State private var newProfileResolution: CustomExportProfile.Resolution = .hd1080
	@State private var newProfileFrameRate = 30
	@State private var newProfileFormat: CustomExportProfile.Format = .mp4

	let columns = [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)]

	var filteredClips: [Clip] {
		let clips: [Clip]
		switch selectedCategory {
		case "favorites":
			clips = appState.clipLibrary.clips.filter { $0.isFavorite }
		case "today":
			let start = Calendar.current.startOfDay(for: Date())
			clips = appState.clipLibrary.clips.filter { $0.createdAt >= start }
		case "week":
			let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
			clips = appState.clipLibrary.clips.filter { $0.createdAt >= start }
		case "marked":
			clips = appState.clipLibrary.clips.filter {
				$0.tags.contains("event-markers")
			}
		case "highlights":
			clips = appState.clipLibrary.clips.filter {
				$0.tags.contains("ai-highlight")
					|| $0.tags.contains(where: { $0.hasPrefix("highlight-score:") && (Int($0.split(separator: ":").last ?? "0") ?? 0) >= 70 })
			}
		default:
			if let selectedCategory, selectedCategory.hasPrefix("collection:") {
				let name = String(selectedCategory.dropFirst("collection:".count))
				clips = appState.clipLibrary.clips.filter { $0.tags.contains("collection:\(name)") }
			} else if let selectedCategory, selectedCategory.hasPrefix("project:") {
				let name = String(selectedCategory.dropFirst("project:".count))
				clips = appState.clipLibrary.clips.filter { $0.tags.contains("project:\(name)") }
			} else {
				clips = appState.clipLibrary.clips
			}
		}
		let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		guard !query.isEmpty else { return clips }
		return clips.filter { clip in
			clip.url.lastPathComponent.lowercased().contains(query)
				|| clip.tags.contains(where: { $0.lowercased().contains(query) })
				|| (transcriptManager.cachedTranscript(for: clip.id)?.lowercased().contains(query) == true)
				|| clip.createdAt.formatted(date: .abbreviated, time: .omitted).lowercased().contains(query)
		}
	}

	var body: some View {
		NavigationSplitView {
			List(selection: $selectedCategory) {
				NavigationLink(value: "all") {
					Label("All Clips", systemImage: "square.grid.2x2")
				}
				NavigationLink(value: "favorites") {
					Label("Favorites", systemImage: "heart")
				}
				NavigationLink(value: "today") {
					Label("Today", systemImage: "calendar")
				}
				NavigationLink(value: "week") {
					Label("Last 7 Days", systemImage: "calendar.badge.clock")
				}
				NavigationLink(value: "marked") {
					Label("Marked Moments", systemImage: "bookmark")
				}
				NavigationLink(value: "highlights") {
					Label("AI Highlights", systemImage: "sparkles")
				}
				Section("Collections") {
					ForEach(appState.clipCollections, id: \.self) { collection in
						NavigationLink(value: "collection:\(collection)") {
							Label(collection, systemImage: "folder")
						}
					}
				}
				Section("Projects") {
					ForEach(appState.clipProjects, id: \.self) { project in
						NavigationLink(value: "project:\(project)") {
							Label(project, systemImage: "rectangle.stack")
						}
					}
				}
			}
			.navigationTitle("Library")
			.frame(minWidth: 150)
		} content: {
			VStack(spacing: 0) {
				HStack {
					TextField("Search clips", text: $searchText)
						.textFieldStyle(.roundedBorder)
					Button {
						appState.createSmartHighlightReel()
					} label: {
						Label("Smart Reel", systemImage: "sparkles")
					}
					.disabled(appState.isCreatingHighlightReel || filteredClips.count < 2)
					Button {
						reelClips = Array(filteredClips.prefix(10))
						showingReelEditor = true
					} label: {
						if appState.isCreatingHighlightReel {
							ProgressView()
								.controlSize(.small)
						} else {
							Label("Highlight Reel", systemImage: "film.stack")
						}
					}
					.disabled(appState.isCreatingHighlightReel || filteredClips.count < 2)
					.help("Combine up to 10 currently visible clips into one reel")
					Menu("Collection") {
						TextField("Collection name", text: $collectionName)
						Button("Create Collection") {
							appState.addClipCollection(collectionName)
							collectionName = ""
						}
						if let selectedClip {
							ForEach(appState.clipCollections, id: \.self) { collection in
								Button("Add selected to \(collection)") {
									appState.addSelectedClip(selectedClip, toCollection: collection)
								}
							}
						}
					}
					Menu("Project") {
						TextField("Project name", text: $projectName)
						Button("Create Project") {
							appState.addClipProject(projectName)
							projectName = ""
						}
						if let selectedClip {
							ForEach(appState.clipProjects, id: \.self) { project in
								Button("Add selected to \(project)") {
									appState.addSelectedClip(selectedClip, toProject: project)
								}
							}
						}
					}
				}
				.padding(.horizontal)
				.padding(.top, 8)
				if let reelURL = appState.highlightReelURL {
					Button {
						NSWorkspace.shared.activateFileViewerSelecting([reelURL])
					} label: {
						Label("Highlight reel ready — Show in Finder", systemImage: "checkmark.circle.fill")
					}
					.buttonStyle(.link)
					.padding(.horizontal)
				} else if let reelError = appState.highlightReelError {
					Text(reelError)
						.font(.caption)
						.foregroundStyle(.red)
						.padding(.horizontal)
				}
				ScrollView {
				if filteredClips.isEmpty {
					Text(selectedCategory == "favorites" ? "No favorites yet." : "No clips yet.")
						.foregroundStyle(.secondary)
						.padding()
				} else {
					LazyVGrid(columns: columns, spacing: 16) {
						ForEach(filteredClips) { clip in
							Button {
								selectedClip = clip
								appState.trackClipAction(action: "open")
							} label: {
								ClipCard(clip: clip, onFavorite: {
									appState.trackClipAction(
										action: "favorite",
										result: clip.isFavorite ? "disabled" : "enabled"
									)
									appState.clipLibrary.toggleFavorite(clip: clip)
								}, onDelete: {
									if selectedClip?.id == clip.id {
										selectedClip = nil
									}
									Task { await appState.clipLibrary.deleteClip(clip) }
									appState.clipWasDeleted(clip)
									appState.trackClipAction(action: "delete", result: "requested")
								})
								.overlay(
									RoundedRectangle(cornerRadius: 8)
										.stroke(selectedClip?.id == clip.id ? Color.accentColor : Color.clear, lineWidth: 3)
								)
							}
							.buttonStyle(.plain)
						}
					}
					.padding()
				}
			}
			}
			.navigationTitle(selectedCategory == "favorites" ? "Favorites" : "All Clips")
			.frame(minWidth: 300)
		} detail: {
			if let clip = selectedClip {
				TrimEditorView(clip: clip, appState: appState)
					.id(clip.id)
			} else {
				Text("Select a clip to view and edit.")
					.foregroundStyle(.secondary)
			}
		}
		.sheet(isPresented: $showingReelEditor) {
			VStack(alignment: .leading, spacing: 16) {
				Text("Reel Editor")
					.font(.title2.weight(.semibold))
				Picker("Transition", selection: $reelTransition) {
					ForEach(ReelTransition.allCases) { Text($0.rawValue).tag($0) }
				}
				Picker("Captions", selection: $reelCaptionStyle) {
					ForEach(ReelCaptionStyle.allCases) { Text($0.rawValue).tag($0) }
				}
				Picker("Export preset", selection: $appState.reelExportPreset) {
					ForEach(HighlightReelExporter.ExportPreset.allCases) { preset in
						Text(preset.rawValue).tag(preset)
					}
				}
				Picker("Custom profile", selection: $appState.selectedCustomExportProfileID) {
					Text("None (built-in preset)").tag(nil as UUID?)
					ForEach(appState.customExportProfiles) { profile in
						Text(profile.name).tag(profile.id as UUID?)
					}
				}
				if !appState.customExportProfiles.isEmpty {
					ForEach(appState.customExportProfiles) { profile in
						if profile.id == appState.selectedCustomExportProfileID {
							LabeledContent("Resolution", value: profile.resolution.rawValue)
							LabeledContent("Frame rate", value: "\(profile.frameRate) fps")
							LabeledContent("Format", value: profile.format.rawValue)
							Button("Delete profile", role: .destructive) {
								appState.customExportProfiles.removeAll { $0.id == profile.id }
								appState.selectedCustomExportProfileID = nil
							}
						}
					}
				}
				HStack {
					TextField("New profile name", text: $newProfileName)
					Picker("Resolution", selection: $newProfileResolution) {
						ForEach(CustomExportProfile.Resolution.allCases) { Text($0.rawValue).tag($0) }
					}
					Picker("FPS", selection: $newProfileFrameRate) {
						Text("30 fps").tag(30)
						Text("60 fps").tag(60)
					}
					Picker("Format", selection: $newProfileFormat) {
						ForEach(CustomExportProfile.Format.allCases) { Text($0.rawValue).tag($0) }
					}
					Button("Save profile") {
						let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
						guard !name.isEmpty else { return }
						let profile = CustomExportProfile(
							name: name,
							preset: appState.reelExportPreset,
							resolution: newProfileResolution,
							frameRate: newProfileFrameRate,
							format: newProfileFormat
						)
						appState.customExportProfiles.append(profile)
						appState.selectedCustomExportProfileID = profile.id
						newProfileName = ""
					}
					.disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				}
				Stepper("Maximum length: \(reelMaxDuration)s", value: $reelMaxDuration, in: 15...300, step: 15)
				Text("Clip order")
					.font(.headline)
				ForEach(Array(reelClips.enumerated()), id: \.element.id) { index, clip in
					HStack {
						Text("\(index + 1)")
							.frame(width: 24)
						Text(clip.url.lastPathComponent)
							.lineLimit(1)
						Spacer()
						Stepper("In \(Int(reelStarts[clip.id] ?? 0))s", value: Binding(
							get: { reelStarts[clip.id] ?? 0 },
							set: { reelStarts[clip.id] = min($0, reelEnds[clip.id] ?? clip.duration) }
						), in: 0...max(0, clip.duration - 0.25), step: 1)
						.frame(width: 120)
						Stepper("Out \(Int(reelEnds[clip.id] ?? clip.duration))s", value: Binding(
							get: { reelEnds[clip.id] ?? clip.duration },
							set: { reelEnds[clip.id] = max(reelStarts[clip.id] ?? 0, min($0, clip.duration)) }
						), in: 0.25...max(0.25, clip.duration), step: 1)
						.frame(width: 140)
						Button("Up") {
							guard index > 0 else { return }
							reelClips.swapAt(index, index - 1)
						}.disabled(index == 0)
						Button("Down") {
							guard index < reelClips.count - 1 else { return }
							reelClips.swapAt(index, index + 1)
						}.disabled(index == reelClips.count - 1)
					}
				}
				HStack {
					Spacer()
					Button("Cancel") { showingReelEditor = false }
					Button("Create Reel") {
						appState.trackClipAction(
							action: "reel_editor",
							result: "\(reelTransition.rawValue.lowercased()),\(reelCaptionStyle.rawValue.lowercased()),\(reelMaxDuration)s"
						)
						appState.createHighlightReel(
							from: reelClips,
							starts: reelStarts,
							ends: reelEnds,
							captionStyle: reelCaptionStyle
						)
						showingReelEditor = false
					}
					.buttonStyle(.borderedProminent)
					.disabled(reelClips.count < 2)
				}
			}
			.padding(20)
			.frame(width: 620, height: 440)
		}
		.onChange(of: appState.clipToOpen?.id) {
			openRequestedClip()
		}
		.onAppear {
			openRequestedClip()
		}
	}

	private func openRequestedClip() {
		guard let clip = appState.clipToOpen else { return }
		selectedCategory = "all"
		selectedClip = clip
		appState.clipToOpen = nil
	}
}

struct ClipCard: View {
	let clip: Clip
	let onFavorite: () -> Void
	let onDelete: () -> Void
	@State private var thumbnail: NSImage?
	@State private var showDeleteConfirmation = false

	var body: some View {
		VStack {
			ZStack(alignment: .bottomTrailing) {
				if let thumbnail = thumbnail {
					Image(nsImage: thumbnail)
						.resizable()
						.aspectRatio(contentMode: .fill)
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.clipped()
				} else {
					Color.black.opacity(0.1)
					Image(systemName: "video")
						.font(.largeTitle)
						.foregroundStyle(.secondary)
				}

				HStack(spacing: 6) {
					Button(action: onFavorite) {
						Image(systemName: clip.isFavorite ? "heart.fill" : "heart")
							.foregroundStyle(clip.isFavorite ? .red : .white)
							.padding(6)
							.background(Color.black.opacity(0.5))
							.clipShape(Circle())
					}
					.buttonStyle(.plain)

					Button {
						showDeleteConfirmation = true
					} label: {
						Image(systemName: "trash")
							.foregroundStyle(.white)
							.padding(6)
							.background(Color.black.opacity(0.5))
							.clipShape(Circle())
					}
					.buttonStyle(.plain)
				}
				.padding(8)
			}
			.aspectRatio(16 / 9, contentMode: .fit)
			.cornerRadius(8)

			Text(clip.createdAt, style: .date)
				.font(.caption)
		}
		.confirmationDialog("Delete this clip?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
			Button("Delete", role: .destructive, action: onDelete)
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("This permanently deletes the clip file from disk.")
		}
		.task(id: clip.id) {
			if thumbnail == nil {
				thumbnail = await ClipThumbnailCache.shared.thumbnail(for: clip)
			}
		}
	}
}

struct TrimEditorView: View {
	let clip: Clip
	@ObservedObject var appState: AppState
	@StateObject private var transcriptManager = TranscriptManager.shared
	@State private var playerView = AVPlayerView()
	@State private var isUploading = false
	@State private var uploadSuccess = false
	@State private var uploadFailed = false
	@State private var isTrimming = false
	/// Key kept from when Litterbox was the only host with an expiry choice.
	@AppStorage("litterboxExpiration") private var uploadExpiration = "72h"
	@State private var uploadTask: Task<Void, Never>?
	@State private var uploadProgress: Double = 0.0
	@State private var uploadErrorMessage: String?
	@State private var showProgressPopover = false

	var body: some View {
		VStack {
			NativeVideoPlayerWrapper(playerView: playerView)
		}
		.toolbar {
			ToolbarItem {
				Button("Trim") {
					if playerView.canBeginTrimming {
						playerView.beginTrimming { result in
							if result == .okButton {
								Task { @MainActor in
									saveTrimmedClip()
								}
							}
						}
					}
				}
				.disabled(isTrimming)
			}
			ToolbarItem {
				Menu("Captions") {
					Button("Transcribe locally") {
						Task { await transcriptManager.transcribe(clip) }
					}
					.disabled(transcriptManager.isTranscribing)
					if let text = transcriptManager.cachedTranscript(for: clip.id) {
						Text(text.prefix(500))
						Button("Copy transcript") {
							NSPasteboard.general.clearContents()
							NSPasteboard.general.setString(text, forType: .string)
						}
					}
				}
			}
			ToolbarItem {
				HStack {
					Menu {
						Button("Copy to clipboard") {
							copyClipToPasteboard(clip.url)
						}
						Button("AirDrop...") {
							shareClip(clip.url, serviceName: .sendViaAirDrop)
						}
						Button("Mail...") {
							shareClip(clip.url, serviceName: .composeEmail)
						}
						Button("Messages...") {
							shareClip(clip.url, serviceName: .composeMessage)
						}
						Button("Reveal in Finder") {
							NSWorkspace.shared.activateFileViewerSelecting([clip.url])
						}

						ForEach(appState.enabledUploadProviders) { provider in
							if provider.supportsExpiration {
								Menu("Upload to \(provider.displayName)") {
									Picker("Expiration", selection: $uploadExpiration) {
										ForEach(provider.expirationOptions) { option in
											Text(option.label).tag(option.id)
										}
									}
									Button("Upload") {
										uploadClip(clip.url, provider: provider)
									}
								}
							} else {
								Button("Upload to \(provider.displayName)") {
									uploadClip(clip.url, provider: provider)
								}
							}
						}
					} label: {
						Label("Share", systemImage: "square.and.arrow.up")
					}
					.disabled(isUploading)
					.popover(isPresented: $showProgressPopover, arrowEdge: .bottom) {
						VStack(spacing: 16) {
							if uploadSuccess {
								Image(systemName: "checkmark.circle.fill")
									.resizable()
									.frame(width: 32, height: 32)
									.foregroundStyle(.green)
								Text("Upload Successful!")
									.font(.headline)
								Text("Link copied to clipboard.")
									.font(.subheadline)
									.foregroundStyle(.secondary)
							} else if uploadFailed {
								Image(systemName: "exclamationmark.triangle.fill")
									.resizable()
									.frame(width: 32, height: 32)
									.foregroundStyle(.orange)
								Text("Oops! Upload failed.")
									.font(.headline)
								Text(uploadErrorMessage ?? "The clip couldn't be uploaded.")
									.font(.subheadline)
									.foregroundStyle(.secondary)
									.multilineTextAlignment(.center)
							} else {
								Text("Uploading...")
									.font(.headline)
								ProgressView(value: uploadProgress)
									.progressViewStyle(.linear)
								HStack {
									Text("\(Int(uploadProgress * 100))%")
										.font(.caption)
										.foregroundStyle(.secondary)
									Spacer()
									Button("Cancel") {
										uploadTask?.cancel()
									}
								}
							}
						}
						.padding()
						.frame(width: 250)
					}
				}
			}
		}
		.onAppear {
			playerView.player = AVPlayer(url: clip.url)
			playerView.showsSharingServiceButton = true
			playerView.showsFullScreenToggleButton = true
		}
	}

	private func saveTrimmedClip() {
		guard let currentItem = playerView.player?.currentItem else { return }
		let asset = currentItem.asset

		var start = currentItem.reversePlaybackEndTime
		var end = currentItem.forwardPlaybackEndTime

		isTrimming = true
		Task {
			if !start.isValid { start = .zero }
			if !end.isValid {
				end = (try? await asset.load(.duration)) ?? .zero
			}

			let timeRange = CMTimeRange(start: start, end: end)

			guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
				isTrimming = false
				return
			}

			let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(clip.url.pathExtension)

			exportSession.outputURL = tempURL
			exportSession.outputFileType = clip.url.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
			exportSession.timeRange = timeRange

			await exportSession.export()
			if exportSession.status == .completed {
				do {
					try? FileManager.default.removeItem(at: clip.url)
					try FileManager.default.moveItem(at: tempURL, to: clip.url)
					// The clip was rewritten in place, so its cached first frame
					// is no longer the frame it starts on.
					ClipThumbnailCache.shared.invalidate(clipID: clip.id)
					appState.trackClipAction(action: "trim")
				} catch {
					print("Error saving trimmed clip: \(error)")
					appState.trackClipAction(action: "trim", result: "failed")
				}
			} else {
				appState.trackClipAction(action: "trim", result: "failed")
			}
			isTrimming = false
		}
	}

	private func copyClipToPasteboard(_ url: URL) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.writeObjects([url as NSURL])
		appState.trackClipAction(action: "copy")
	}

	private func shareClip(_ url: URL, serviceName: NSSharingService.Name) {
		guard let service = NSSharingService(named: serviceName) else { return }
		service.perform(withItems: [url])
		appState.trackClipAction(action: "native_share", result: serviceName.rawValue)
	}

	private func showUploadFailure(_ error: Error, provider: ClipUploadProvider) {
		isUploading = false
		uploadSuccess = false
		uploadErrorMessage = (error as? LocalizedError)?.errorDescription
		uploadFailed = true
		appState.trackClipAction(action: "upload", result: "failed", provider: provider.id)
		Task {
			try? await Task.sleep(nanoseconds: 5_000_000_000)
			uploadFailed = false
			uploadErrorMessage = nil
			showProgressPopover = false
		}
	}

	private func uploadClip(_ url: URL, provider: ClipUploadProvider) {
		isUploading = true
		uploadSuccess = false
		uploadFailed = false
		uploadErrorMessage = nil
		showProgressPopover = true
		uploadProgress = 0.0
		appState.trackClipAction(action: "upload", result: "started", provider: provider.id)

		uploadTask = Task { @MainActor in
			do {
				let link = try await ClipUploader.shared.upload(
					clipAt: url,
					provider: provider,
					expirationID: provider.supportsExpiration ? uploadExpiration : nil
				) { fraction in
					Task { @MainActor in uploadProgress = fraction }
				}

				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(link.absoluteString, forType: .string)
				uploadSuccess = true
				appState.trackClipAction(action: "upload", provider: provider.id)
				try? await Task.sleep(nanoseconds: 2_500_000_000)
				uploadSuccess = false
				isUploading = false
				showProgressPopover = false
			} catch is CancellationError {
				isUploading = false
				showProgressPopover = false
				appState.trackClipAction(action: "upload", result: "cancelled", provider: provider.id)
			} catch {
				AppLog.error(.library, "Upload to \(provider.id) failed:", error)
				showUploadFailure(error, provider: provider)
			}
		}
	}
}

struct NativeVideoPlayerWrapper: NSViewRepresentable {
	let playerView: AVPlayerView

	func makeNSView(context _: Context) -> AVPlayerView {
		playerView
	}

	func updateNSView(_: AVPlayerView, context _: Context) {}
}
