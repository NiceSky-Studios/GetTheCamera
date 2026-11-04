import AppKit
import Foundation

private struct GitHubRelease: Decodable {
	let tag_name: String
	let html_url: String
	let assets: [GitHubAsset]
	struct GitHubAsset: Decodable {
		let name: String
		let browser_download_url: String
	}
}

@MainActor
final class UpdaterController: ObservableObject {
	@Published private(set) var statusMessage = "Updates are ready to check."
	@Published private(set) var isChecking = false
	@Published private(set) var isUpdating = false
	@Published private(set) var updateProgress: Double = 0

	private var releaseAsset: GitHubRelease.GitHubAsset?
	private var releaseURL: URL?

	func checkForUpdates() {
		Task { await checkGitHubRelease(automatic: false) }
	}

	func checkForUpdatesAutomatically() {
		Task { await checkGitHubRelease(automatic: true) }
	}

	private var currentVersion: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
	}

	private func checkGitHubRelease(automatic: Bool = false) async {
		isChecking = true
		statusMessage = "Checking GitHub releases..."
		defer { isChecking = false }
		let url = URL(string: "https://api.github.com/repos/NiceSky-Studios/GetTheCamera/releases/latest")!
		var request = URLRequest(url: url)
		request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
		request.setValue("GetTheCamera/\(currentVersion)", forHTTPHeaderField: "User-Agent")

		do {
			let (data, response) = try await URLSession.shared.data(for: request)
			guard let httpResponse = response as? HTTPURLResponse,
			      (200..<300).contains(httpResponse.statusCode) else {
				throw URLError(.badServerResponse)
			}
			let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
			let latestVersion = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
			releaseURL = URL(string: release.html_url)

			let isWindowsAsset: (String) -> Bool = { name in
				let lower = name.lowercased()
				return lower.contains("windows") || lower.contains("win32") || lower.contains("win64") || lower.contains("-win") || lower.hasSuffix(".exe") || lower.hasSuffix(".msi")
			}
			let macOSAssets = release.assets.filter { !isWindowsAsset($0.name) }

			releaseAsset = macOSAssets.first(where: {
				let lower = $0.name.lowercased()
				return lower.contains(".app.zip") || lower.contains("mac") || lower.contains("darwin") || lower.contains("osx")
			}) ?? macOSAssets.first(where: {
				$0.name.lowercased().hasSuffix(".zip")
			}) ?? macOSAssets.first(where: {
				$0.name.lowercased().hasSuffix(".dmg")
			})
			showReleaseResult(latestVersion: latestVersion, releaseURL: release.html_url, automatic: automatic)
		} catch {
			AppLog.error(.app, "GitHub update check failed", error)
			showAlert(
				title: "Couldn’t Check for Updates",
				message: "Check your internet connection, or visit GitHub Releases.",
				url: URL(string: "https://github.com/NiceSky-Studios/GetTheCamera/releases")!
			)
		}
	}

	private func showReleaseResult(latestVersion: String, releaseURL: String, automatic: Bool = false) {
		if compareVersions(latestVersion, currentVersion) > 0 {
			statusMessage = "Version \(latestVersion) is available."
			if automatic {
				Task { await downloadAndInstallUpdate() }
				return
			}
			let alert = NSAlert()
			alert.messageText = "GetTheCamera \(latestVersion) is available"
			alert.informativeText = "You are running \(currentVersion). Download and replace the app now?"
			alert.addButton(withTitle: "Update and Relaunch")
			alert.addButton(withTitle: "View Release")
			alert.addButton(withTitle: "Not Now")
			let response = alert.runModal()
			if response == .alertFirstButtonReturn {
				Task { await downloadAndInstallUpdate() }
			} else if response == .alertSecondButtonReturn {
				NSWorkspace.shared.open(URL(string: releaseURL) ?? URL(string: "https://github.com/NiceSky-Studios/GetTheCamera/releases")!)
			}
		} else {
			statusMessage = "GetTheCamera \(currentVersion) is up to date."
			let alert = NSAlert()
			alert.messageText = "You’re Up to Date"
			alert.informativeText = "GetTheCamera \(currentVersion) is the latest released version."
			alert.addButton(withTitle: "OK")
			alert.runModal()
		}
	}

	private func showAlert(title: String, message: String, url: URL) {
		let alert = NSAlert()
		alert.messageText = title
		alert.informativeText = message
		alert.addButton(withTitle: "View Release")
		alert.addButton(withTitle: "Not Now")
		if alert.runModal() == .alertFirstButtonReturn {
			NSWorkspace.shared.open(url)
		}
	}

	private func compareVersions(_ lhs: String, _ rhs: String) -> Int {
		let lhsParts = lhs.split(separator: ".", omittingEmptySubsequences: false)
		let rhsParts = rhs.split(separator: ".", omittingEmptySubsequences: false)
		let count = max(lhsParts.count, rhsParts.count)
		for index in 0..<count {
			let lhsNumber = index < lhsParts.count ? Int(lhsParts[index].prefix { $0.isNumber }) ?? 0 : 0
			let rhsNumber = index < rhsParts.count ? Int(rhsParts[index].prefix { $0.isNumber }) ?? 0 : 0
			if lhsNumber != rhsNumber {
				return lhsNumber < rhsNumber ? -1 : 1
			}
		}
		return 0
	}

	private func downloadAndInstallUpdate() async {
		guard let asset = releaseAsset, let url = URL(string: asset.browser_download_url) else {
			statusMessage = "No installable macOS package is available."
			showAlert(
				title: "Installer Not Available",
				message: "Download the latest macOS package from the GitHub release page.",
				url: releaseURL ?? URL(string: "https://github.com/NiceSky-Studios/GetTheCamera/releases")!
			)
			return
		}
		guard asset.name.lowercased().hasSuffix(".zip") else {
			statusMessage = "The release does not contain an installable ZIP."
			showAlert(
				title: "Installer Not Available",
				message: "Download the macOS ZIP package from the GitHub release page and install it.",
				url: releaseURL ?? URL(string: "https://github.com/NiceSky-Studios/GetTheCamera/releases")!
			)
			return
		}

		isUpdating = true
		updateProgress = 0
		statusMessage = "Downloading \(asset.name)..."

		do {
			let session = URLSession(configuration: .default)
			let (downloadedURL, response) = try await session.download(from: url)
			guard let httpResponse = response as? HTTPURLResponse,
			      (200..<300).contains(httpResponse.statusCode) else {
				throw URLError(.badServerResponse)
			}

			updateProgress = 0.5
			statusMessage = "Preparing installation..."
			let temporaryDirectory = FileManager.default.temporaryDirectory
				.appendingPathComponent("GetTheCamera-\(UUID().uuidString)", isDirectory: true)
			try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

			let extractedDirectory = temporaryDirectory.appendingPathComponent("extracted", isDirectory: true)
			try FileManager.default.createDirectory(at: extractedDirectory, withIntermediateDirectories: true)
			let extract = Process()
			extract.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
			extract.arguments = ["-xk", downloadedURL.path, extractedDirectory.path]
			try extract.run()
			extract.waitUntilExit()
			guard extract.terminationStatus == 0 else {
				throw NSError(domain: "GetTheCamera.Updater", code: Int(extract.terminationStatus))
			}

			guard let newApp = findAppBundle(in: extractedDirectory) else {
				throw NSError(domain: "GetTheCamera.Updater", code: 404, userInfo: [
					NSLocalizedDescriptionKey: "The downloaded package did not contain GetTheCamera.app."
				])
			}

			updateProgress = 0.75
			statusMessage = "Installing and relaunching..."
			try installAndRelaunch(sourceApp: newApp, temporaryDirectory: temporaryDirectory)
			updateProgress = 1
		} catch {
			AppLog.error(.app, "macOS update installation failed", error)
			statusMessage = "Update failed: \(error.localizedDescription)"
			showAlert(
				title: "Update Failed",
				message: error.localizedDescription,
				url: releaseURL ?? URL(string: "https://github.com/NiceSky-Studios/GetTheCamera/releases")!
			)
			isUpdating = false
		}
	}

	private func findAppBundle(in directory: URL) -> URL? {
		let enumerator = FileManager.default.enumerator(
			at: directory,
			includingPropertiesForKeys: [.isDirectoryKey],
			options: [.skipsHiddenFiles]
		)
		while let url = enumerator?.nextObject() as? URL {
			if url.pathExtension == "app",
			   url.deletingPathExtension().lastPathComponent == "GetTheCamera" {
				return url
			}
		}
		return nil
	}

	private func installAndRelaunch(sourceApp: URL, temporaryDirectory: URL) throws {
		guard let bundle = Bundle(url: sourceApp),
		      let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
		      !version.isEmpty else {
			throw NSError(domain: "GetTheCamera.Updater", code: 400, userInfo: [
				NSLocalizedDescriptionKey: "Extracted app bundle is invalid or missing version metadata."
			])
		}

		let currentAppURL = Bundle.main.bundleURL
		let targetApp: URL
		if currentAppURL.pathExtension == "app" && !currentAppURL.path.contains("/var/folders") && !currentAppURL.path.contains("/tmp") {
			targetApp = currentAppURL
		} else {
			targetApp = URL(fileURLWithPath: "/Applications/GetTheCamera.app")
		}

		let shellQuote: (String) -> String = { value in
			"'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
		}
		let pid = ProcessInfo.processInfo.processIdentifier
		let shell = """
		while kill -0 \(pid) 2>/dev/null; do kill -TERM \(pid) 2>/dev/null || true; sleep 0.5; done
		rm -rf \(shellQuote(targetApp.path))
		/usr/bin/ditto \(shellQuote(sourceApp.path)) \(shellQuote(targetApp.path))
		/usr/bin/xattr -dr com.apple.quarantine \(shellQuote(targetApp.path)) 2>/dev/null || true
		/bin/chmod -R u+rwX \(shellQuote(targetApp.path))
		/usr/bin/open -n \(shellQuote(targetApp.path))
		rm -rf \(shellQuote(temporaryDirectory.path))
		"""
		let script = "do shell script \(shellQuote(shell)) with administrator privileges"
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
		process.arguments = ["-e", script]
		try process.run()
	}
}
