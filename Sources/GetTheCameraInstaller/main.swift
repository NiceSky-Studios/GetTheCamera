import AppKit

final class InstallerAppDelegate: NSObject, NSApplicationDelegate {
	private var window: NSWindow!
	private let appName = "GetTheCamera"
	private let bundleID = "com.getthecamera.app"

	func applicationDidFinishLaunching(_ notification: Notification) {
		NSApp.setActivationPolicy(.regular)
		NSApp.activate(ignoringOtherApps: true)

		let content = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 330))
		content.wantsLayer = true
		content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

		let iconView = NSImageView(frame: NSRect(x: 210, y: 190, width: 100, height: 100))
		iconView.image = NSImage(contentsOfFile: Bundle.main.path(forResource: "AppIcon", ofType: "icns") ?? "")
			?? NSApplication.shared.applicationIconImage

		let title = NSTextField(labelWithString: "Install GetTheCamera")
		title.font = .systemFont(ofSize: 22, weight: .bold)
		title.frame = NSRect(x: 20, y: 145, width: 480, height: 32)
		title.alignment = .center

		let subtitle = NSTextField(frame: NSRect(x: 55, y: 95, width: 410, height: 42))
		subtitle.stringValue = "The latest version will be installed to your Applications folder."
		subtitle.isEditable = false
		subtitle.isBordered = false
		subtitle.drawsBackground = false
		subtitle.font = .systemFont(ofSize: 13)
		subtitle.textColor = .secondaryLabelColor
		subtitle.alignment = .center

		let progress = NSProgressIndicator(frame: NSRect(x: 70, y: 70, width: 380, height: 8))
		progress.isIndeterminate = true
		progress.style = .bar
		progress.isHidden = true

		let status = NSTextField(labelWithString: "")
		status.font = .systemFont(ofSize: 12)
		status.textColor = .secondaryLabelColor
		status.alignment = .center
		status.frame = NSRect(x: 55, y: 44, width: 410, height: 22)

		let cancel = NSButton(title: "Cancel", target: nil, action: nil)
		cancel.bezelStyle = .rounded
		cancel.frame = NSRect(x: 270, y: 20, width: 100, height: 32)
		cancel.target = self
		cancel.action = #selector(cancelInstaller)

		let install = NSButton(title: "Install GetTheCamera", target: nil, action: nil)
		install.bezelStyle = .rounded
		install.keyEquivalent = "\r"
		install.frame = NSRect(x: 375, y: 20, width: 125, height: 32)
		install.target = self
		install.action = #selector(startInstall)
		install.isEnabled = true

		install.setAccessibilityTitle("Install GetTheCamera")

		content.addSubview(iconView)
		content.addSubview(title)
		content.addSubview(subtitle)
		content.addSubview(progress)
		content.addSubview(status)
		content.addSubview(cancel)
		content.addSubview(install)

		window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 520, height: 330),
			styleMask: [.titled, .closable],
			backing: .buffered,
			defer: false
		)
		window.title = "GetTheCamera Installer"
		window.contentView = content
		window.center()
		window.isReleasedWhenClosed = false
		window.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
	}

	@objc private func cancelInstaller() {
		NSApp.terminate(nil)
	}

	@objc private func startInstall() {
		guard let source = Bundle.main.resourceURL?
			.appendingPathComponent(appName + ".app"),
			FileManager.default.fileExists(atPath: source.path)
		else {
			showError("The app package could not be found inside the installer.")
			return
		}

		let target = URL(fileURLWithPath: "/Applications/\(appName).app")
		let contentView = window.contentView
		contentView?.subviews.compactMap { $0 as? NSProgressIndicator }.forEach {
			$0.isHidden = false
			$0.startAnimation(nil)
		}
		contentView?.subviews.compactMap { $0 as? NSButton }.forEach { $0.isEnabled = false }

		let status = contentView?.subviews.compactMap { $0 as? NSTextField }.last
		status?.stringValue = "Installing..."

		NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
			.forEach { $0.terminate() }

		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			let command = """
			/usr/bin/ditto \(self?.shellQuote(source.path) ?? "") \(self?.shellQuote(target.path) ?? "") && /usr/bin/xattr -cr \(self?.shellQuote(target.path) ?? "") 2>/dev/null || true
			"""
			let script = "do shell script \(self?.shellQuote(command) ?? "") with prompt \"Install GetTheCamera to the Applications folder\" with administrator privileges"
			let task = Process()
			task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
			task.arguments = ["-e", script]
			task.standardOutput = FileHandle.nullDevice
			task.standardError = FileHandle.nullDevice

			do {
				try task.run()
				task.waitUntilExit()
				DispatchQueue.main.async {
					self?.finishInstall(target: target, success: task.terminationStatus == 0)
				}
			} catch {
				DispatchQueue.main.async {
					self?.finishInstall(target: target, success: false)
				}
			}
		}
	}

	private func shellQuote(_ value: String) -> String {
		"\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"") + "\""
	}

	private func finishInstall(target: URL, success: Bool) {
		let alert = NSAlert()
		alert.alertStyle = success ? .informational : .critical
		alert.messageText = success ? "Installation Complete" : "Installation Failed"
		alert.informativeText = success
			? "GetTheCamera has been installed to Applications."
			: "GetTheCamera could not be installed. Please try again."
		if success {
			alert.addButton(withTitle: "Open GetTheCamera")
			alert.addButton(withTitle: "Done")
		} else {
			alert.addButton(withTitle: "OK")
		}

		let response = alert.runModal()
		if success && response == .alertFirstButtonReturn {
			NSWorkspace.shared.open(target)
		}
		NSApp.terminate(nil)
	}

	private func showError(_ message: String) {
		let alert = NSAlert()
		alert.alertStyle = .critical
		alert.messageText = "Installer Error"
		alert.informativeText = message
		alert.runModal()
		NSApp.terminate(nil)
	}
}

let app = NSApplication.shared
let delegate = InstallerAppDelegate()
app.delegate = delegate
app.run()
