# GetTheCamera

GetTheCamera is a free, open-source macOS app for capturing, organizing, editing, and sharing gameplay highlights. It runs from the menu bar and provides local voice commands, reusable projects, Smart Reels, transcription, and export tools.

**Current release:** 1.8.1
**Minimum macOS:** 14.0 Sonoma  
**Architecture:** Apple Silicon (`arm64`)

## Features

- **Instant Replay Capture:** Save a configurable window of recent gameplay.
- **Always Record Mode:** Record continuously so no highlight is missed.
- **Voice Commands:** Save clips and control recording with local speech recognition.
- **Spoken Responses:** Add custom confirmations and select personality-based speaking styles.
- **GTC Hub:** Manage clips, collections, projects, favorites, playback, trimming, and metadata.
- **Automatic Event Markers:** Detect audio spikes and clip-start moments.
- **Local Transcription and Captions:** Search clip transcripts and export WebVTT captions.
- **Smart Reels:** Rank highlights and build reorderable reels with segment in/out trimming.
- **Export Presets:** Export for source quality, YouTube HD, vertical social, or compact sharing.
- **Automation Rules:** Start or stop recording based on configured apps.
- **Google Drive Integration:** Connect and upload clips from the app.
- **Global Hotkeys and Audio Feedback:** Customize keyboard controls and feedback sounds.
- **Discord Rich Presence:** Display recording activity.
- **In-App Updating:** Download and install confirmed updates, then relaunch on macOS and Windows.

## Requirements

- macOS 14.0 Sonoma or later
- Apple Silicon Mac
- At least 10 GB of free disk space
- Screen Recording permission
- Microphone and Speech Recognition permissions for voice features

## Installation

1. Visit the [GetTheCamera Releases page](https://github.com/NiceSky-Studios/GetTheCamera/releases).
2. Download the latest DMG.
3. Open the DMG and double-click **Install GetTheCamera**.
4. Launch GetTheCamera from Applications or the installer prompt.

To update, open **GTC Hub → Settings → Updates → Check for Updates**. The app opens the new GitHub release page when an update is available; automatic installation is not enabled.

## Permissions

GetTheCamera requests only the permissions needed for enabled features:

- Screen Recording
- Microphone
- Speech Recognition
- Notifications

Permissions can be reviewed in macOS **System Settings → Privacy & Security**.

## Building from Source

GetTheCamera is built with Swift 6 and Swift Package Manager.

```bash
git clone https://github.com/NiceSky-Studios/GetTheCamera.git
cd GetTheCamera
swift build
swift run
```

Create release DMG packages with:

```bash
./scripts/build-package.sh --version 1.8.1
```

Release artifacts are written to `dist/`.

## Release Notes

- [Current release notes](RELEASE_NOTES.md)
- [1.8.1 update log](Update%20Log/1.8.1.md)

## Contact

Discord: molinthenugget  
TikTok: molinthedead  
Email: molinthedead@gmail.com
