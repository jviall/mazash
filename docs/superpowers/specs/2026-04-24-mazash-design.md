# Mazash — Design Spec
**Date:** 2026-04-24  
**Status:** Approved

---

## Overview

Mazash is a local-only macOS menu bar app that continuously listens to system audio output and identifies songs using ShazamKit. Matches are written to a text file. The app has a single toggle (on/off) and no window UI.

**Non-goals for this version:** App Store distribution, virtual audio device creation, audio device selection, streaming service integrations, preferences UI.

---

## Architecture

Four units with clear single responsibilities. `AudioCaptureService` and `RecognitionService` sit behind protocols to allow future swappability (e.g. swapping audio source to a virtual device, or swapping recognition engine).

```
MenuBarApp (SwiftUI MenuBarExtra)
    └── observes MatchStore
    └── drives toggle → AudioCaptureService

AudioCaptureService (protocol)
    └── SCKAudioCaptureService (ScreenCaptureKit implementation)
    └── publishes CMSampleBuffers

RecognitionService (protocol)
    └── ShazamRecognitionService (SHSession implementation)
    └── consumes CMSampleBuffers, publishes Match on hit

MatchStore (@Observable, concrete)
    └── holds [Match] in memory
    └── appends to file on each new match
```

---

## Data Model

```swift
struct Match {
    let timestamp: Date
    let mediaItem: SHMediaItem  // full ShazamKit metadata preserved
}
```

`SHMediaItem` carries title, artist, album, Apple Music URL, artwork URL, and other metadata. The text file renders a subset; the full struct is available for future integrations (e.g. playlist APIs).

---

## Data Flow

```
[Toggle ON]
    → AudioCaptureService.start()
    → SCStream begins capturing system audio (audio-only, no video frames)
    → CMSampleBuffers delivered continuously
    → RecognitionService.process(buffer:)
    → SHSignatureGenerator accumulates buffers (~5–10s before match attempt)
    → SHSession fires delegate on confident match
    → Match(mediaItem: SHMediaItem, timestamp: Date) created
    → MatchStore.add(match:)
        → appends to in-memory [Match]
        → appends one line to ~/Library/Application Support/mazash/matches.txt

[Toggle OFF]
    → AudioCaptureService.stop()
    → SCStream invalidated
    → SHSession reset, SHSignatureGenerator cleared
```

Duplicate suppression: `RecognitionService` tracks the last matched `shazamID` and ignores subsequent matches for the same song until a different song matches (or silence exceeds a configurable threshold).

---

## Menu Bar UI

Built with SwiftUI `MenuBarExtra`. No separate window.

```
[icon] ← SF Symbol: "music.note" (idle), "waveform" (active)

┌─────────────────────────┐
│ ● Stop Listening        │  ← label toggles; "Start Listening" when idle
│ ─────────────────────── │
│ Last match:             │
│ Espresso - Sabrina C... │  ← most recent match, truncated to fit
│ ─────────────────────── │
│ Quit Mazash             │
└─────────────────────────┘
```

When no match has occurred yet in the current session, the last match section is hidden.

---

## Output File

**Path:** `~/Library/Application Support/mazash/matches.txt`  
**Format:** One line per match, append-only.

```
2026-04-24 16:32 | Espresso - Sabrina Carpenter
2026-04-24 16:38 | Luther - Kendrick Lamar, SZA
```

The directory and file are created on first match if they don't exist. No rotation or size cap in this version.

--

## Permissions & Build Configuration

- **Xcode project** (not SPM) — required for entitlements, Info.plist, app bundle
- **Deployment target:** macOS 14.2+
- **App sandbox:** disabled — local-only, avoids entitlement friction
- **Screen Recording permission:** declared via `NSScreenCaptureUsageDescription` in Info.plist; macOS prompts user on first capture attempt. SCStream is configured audio-only (no video frames captured).
- **ShazamKit entitlement:** not added initially — validate it works under ad-hoc signing first. Add `com.apple.developer.shazamkit` only if the API rejects without it.
- **Code signing:** ad-hoc (`codesign --sign -`). No developer account required.

---

## Future Extension Points

The protocol boundaries are designed to accommodate these without touching existing code:

- **Alternative audio sources:** Implement `AudioCaptureService` for a virtual audio device (e.g. BlackHole) or for a user-selected `AVAudioDevice`. Drop in alongside `SCKAudioCaptureService`.
- **Alternative recognition engines:** Implement `RecognitionService` for ACRCloud or another provider. Useful if ShazamKit requires a paid entitlement for distribution.
- **Output sinks:** `MatchStore` can be extended to push matches to a streaming service playlist API (Spotify, Apple Music) alongside or instead of the text file.
- **Developer ID distribution:** Obtain a paid Apple Developer account, add `com.apple.developer.shazamkit`, sign with Developer ID, and notarize. No architectural changes required.
