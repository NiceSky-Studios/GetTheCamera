import AppKit
import Carbon

@MainActor
final class GlobalHotkeyManager {
	static let shared = GlobalHotkeyManager()

	private let hotKeySignature = OSType(0x5257_4E44) // "RWND"
	private let saveReplayHotKeyId: UInt32 = 1
	private let recordToggleHotKeyId: UInt32 = 2
	private let markMomentHotKeyId: UInt32 = 3
	private let openHubHotKeyId: UInt32 = 4
	private var saveReplayHotKeyRef: EventHotKeyRef?
	private var recordToggleHotKeyRef: EventHotKeyRef?
	private var markMomentHotKeyRef: EventHotKeyRef?
	private var openHubHotKeyRef: EventHotKeyRef?
	private var eventHandler: EventHandlerRef?
	private var saveReplayHotkey: Hotkey = .default
	private var recordToggleHotkey: Hotkey = .startRecordingDefault
	private var onSaveReplay: (() -> Void)?
	private var onRecordToggle: (() -> Void)?
	private var onMarkMoment: (() -> Void)?
	private var onOpenHub: (() -> Void)?

	func configureActions(
		onSaveReplay: (() -> Void)?,
		onRecordToggle: (() -> Void)?,
		onMarkMoment: (() -> Void)? = nil,
		onOpenHub: (() -> Void)? = nil
	) {
		self.onSaveReplay = onSaveReplay
		self.onRecordToggle = onRecordToggle
		self.onMarkMoment = onMarkMoment
		self.onOpenHub = onOpenHub
	}

	func register(
		saveReplayHotkey: Hotkey = .default,
		recordToggleHotkey: Hotkey = .startRecordingDefault,
		markMomentHotkey: Hotkey? = nil,
		openHubHotkey: Hotkey? = nil
	) {
		self.saveReplayHotkey = saveReplayHotkey
		self.recordToggleHotkey = recordToggleHotkey
		unregister()

		var eventType = EventTypeSpec(
			eventClass: OSType(kEventClassKeyboard),
			eventKind: UInt32(kEventHotKeyPressed)
		)

		let installStatus = InstallEventHandler(
			GetEventDispatcherTarget(),
			{ _, event, userData in
				guard let userData else { return noErr }
				let manager = Unmanaged<GlobalHotkeyManager>
					.fromOpaque(userData)
					.takeUnretainedValue()
				Task { @MainActor in
					manager.handleHotKey(event: event)
				}
				return noErr
			},
			1,
			&eventType,
			UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
			&eventHandler
		)
		guard installStatus == noErr else {
			AppLog.error(.app, "Install hotkey event handler error, status:", installStatus)
			eventHandler = nil
			return
		}

		registerHotKey(
			saveReplayHotkey,
			id: saveReplayHotKeyId,
			store: &saveReplayHotKeyRef,
			actionName: "save replay"
		)
		registerHotKey(
			recordToggleHotkey,
			id: recordToggleHotKeyId,
			store: &recordToggleHotKeyRef,
			actionName: "record toggle"
		)
		if let markMomentHotkey {
			registerHotKey(markMomentHotkey, id: markMomentHotKeyId, store: &markMomentHotKeyRef, actionName: "mark moment")
		}
		if let openHubHotkey {
			registerHotKey(openHubHotkey, id: openHubHotKeyId, store: &openHubHotKeyRef, actionName: "open hub")
		}

		if saveReplayHotKeyRef == nil, recordToggleHotKeyRef == nil, let eventHandler {
			RemoveEventHandler(eventHandler)
			self.eventHandler = nil
		}
	}

	func unregister() {
		if let saveReplayHotKeyRef {
			UnregisterEventHotKey(saveReplayHotKeyRef)
			self.saveReplayHotKeyRef = nil
		}

		if let recordToggleHotKeyRef {
			UnregisterEventHotKey(recordToggleHotKeyRef)
			self.recordToggleHotKeyRef = nil
		}
		if let markMomentHotKeyRef {
			UnregisterEventHotKey(markMomentHotKeyRef)
			self.markMomentHotKeyRef = nil
		}
		if let openHubHotKeyRef {
			UnregisterEventHotKey(openHubHotKeyRef)
			self.openHubHotKeyRef = nil
		}

		if let eventHandler {
			RemoveEventHandler(eventHandler)
			self.eventHandler = nil
		}
	}

	func updateHotkeys(saveReplay: Hotkey, recordToggle: Hotkey, markMoment: Hotkey? = nil, openHub: Hotkey? = nil) {
		register(saveReplayHotkey: saveReplay, recordToggleHotkey: recordToggle, markMomentHotkey: markMoment, openHubHotkey: openHub)
	}

	private func registerHotKey(
		_ hotkey: Hotkey,
		id: UInt32,
		store ref: inout EventHotKeyRef?,
		actionName: String
	) {
		let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: id)
		let registerStatus = RegisterEventHotKey(
			hotkey.keyCode,
			hotkey.modifiers,
			hotKeyID,
			GetEventDispatcherTarget(),
			0,
			&ref
		)
		guard registerStatus == noErr else {
			AppLog.error(
				.app,
				"Register global hotkey for",
				actionName,
				"status:",
				registerStatus,
				"keyCode:",
				hotkey.keyCode,
				"modifiers:",
				hotkey.modifiers
			)
			ref = nil
			return
		}
	}

	private func handleHotKey(event: EventRef?) {
		guard let event else { return }

		var hotKeyID = EventHotKeyID()
		let status = GetEventParameter(
			event,
			EventParamName(kEventParamDirectObject),
			EventParamType(typeEventHotKeyID),
			nil,
			MemoryLayout<EventHotKeyID>.size,
			nil,
			&hotKeyID
		)

		guard status == noErr else { return }
		guard hotKeyID.signature == hotKeySignature else { return }

		switch hotKeyID.id {
		case saveReplayHotKeyId:
			onSaveReplay?()
		case recordToggleHotKeyId:
			onRecordToggle?()
		case markMomentHotKeyId:
			onMarkMoment?()
		case openHubHotKeyId:
			onOpenHub?()
		default:
			return
		}
	}
}
