import AppKit
import Foundation

private struct GitHubRelease: Decodable {
	let tag_name: String
	let html_url: String
}

@MainActor
final class UpdaterController: ObservableObject {
	func checkForUpdates() {
		Task { await checkGitHubRelease() }
	}

	private var currentVersion: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
	}

	private func checkGitHubRelease() async {
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
			showReleaseResult(latestVersion: latestVersion, releaseURL: release.html_url)
		} catch {
			AppLog.error(.app, "GitHub update check failed", error)
			showAlert(
				title: "Couldn’t Check for Updates",
				message: "Check your internet connection, or visit GitHub Releases.",
				url: URL(string: "https://github.com/NiceSky-Studios/GetTheCamera/releases")!
			)
		}
	}

	private func showReleaseResult(latestVersion: String, releaseURL: String) {
		if compareVersions(latestVersion, currentVersion) > 0 {
			showAlert(
				title: "GetTheCamera \(latestVersion) is available",
				message: "You are running \(currentVersion).",
				url: URL(string: releaseURL) ?? URL(string: "https://github.com/NiceSky-Studios/GetTheCamera/releases")!
			)
		} else {
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
}
