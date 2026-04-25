# Mazash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local macOS menu bar app that captures system audio via ScreenCaptureKit, identifies songs using ShazamKit, and appends matches to a text file in Application Support.

**Architecture:** Layered services behind protocols — `AudioCaptureService` (ScreenCaptureKit) feeds `CMSampleBuffer`s to `RecognitionService` (ShazamKit), which publishes `Match` structs to `MatchStore` for persistence. `AppController` wires everything together and is observed by the SwiftUI `MenuBarExtra`.

**Tech Stack:** Swift 5.9+, SwiftUI (`MenuBarExtra`), ScreenCaptureKit, ShazamKit, XCTest, macOS 14.2+

---

## File Structure

```
Mazash/
├── Mazash.xcodeproj/
├── Mazash/
│   ├── MazashApp.swift                    # @main App, MenuBarExtra scene, AppController
│   ├── MenuBarView.swift                  # SwiftUI menu content
│   ├── Models/
│   │   └── Match.swift                    # Match struct (SHMediaItem + Date + formatting)
│   ├── Services/
│   │   ├── AudioCaptureService.swift      # Protocol + delegate protocol
│   │   ├── SCKAudioCaptureService.swift   # ScreenCaptureKit implementation
│   │   ├── RecognitionService.swift       # Protocol + delegate protocol
│   │   └── ShazamRecognitionService.swift # SHSession implementation
│   └── Store/
│       └── MatchStore.swift               # @Observable, [Match] array, append-only file I/O
├── MazashTests/
│   ├── ShazamKitValidationTests.swift
│   ├── MatchTests.swift
│   └── MatchStoreTests.swift
├── Mazash.entitlements                    # app-sandbox = false
└── Info.plist                             # NSScreenCaptureUsageDescription, LSUIElement
```

---

## Task 1: Xcode Project Setup

**Files:**
- Create: `Mazash.xcodeproj` (via Xcode UI)
- Modify: `Mazash/Mazash.entitlements`
- Modify: `Mazash/Info.plist`
- Modify: `Mazash/MazashApp.swift`

- [ ] **Step 1: Create the project in Xcode**

Open Xcode → File → New → Project → macOS → App.

Settings:
- Product Name: `Mazash`
- Team: None
- Organization Identifier: `com.local.mazash`
- Interface: SwiftUI
- Language: Swift
- Uncheck "Include Tests" (we add the test target manually in Task 2)

Save into `/Users/jamesviall/git/github.com/jviall/mazash`.

- [ ] **Step 2: Add ShazamKit framework**

Xcode → select the `Mazash` target → General → Frameworks, Libraries, and Embedded Content → `+` → search "ShazamKit" → Add.

- [ ] **Step 3: Add ScreenCaptureKit framework**

Same location: `+` → search "ScreenCaptureKit" → Add.

- [ ] **Step 4: Disable the app sandbox**

Open `Mazash/Mazash.entitlements`. Set the full file contents to:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

- [ ] **Step 5: Configure Info.plist**

Add two keys to `Mazash/Info.plist`:

```xml
<key>NSScreenCaptureUsageDescription</key>
<string>Mazash needs access to system audio to identify songs playing on your Mac.</string>
<key>LSUIElement</key>
<true/>
```

`LSUIElement = true` hides the app from the Dock and application switcher — menu bar icon only.

- [ ] **Step 6: Configure ad-hoc signing**

Xcode → select `Mazash` target → Signing & Capabilities:
- Uncheck "Automatically manage signing"
- Set Team to "None"
- Set Signing Certificate to "Sign to Run Locally"

- [ ] **Step 7: Replace MazashApp.swift with a minimal stub**

```swift
import SwiftUI

@main
struct MazashApp: App {
    var body: some Scene {
        MenuBarExtra("Mazash", systemImage: "music.note") {
            Text("Mazash")
        }
    }
}
```

- [ ] **Step 8: Build and run**

Cmd+R. Verify: a music note icon appears in the menu bar, menu shows "Mazash", no Dock icon. Fix any build errors before continuing.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: scaffold Mazash Xcode project"
```

---

## Task 2: ShazamKit Validation Checkpoint

**Files:**
- Create: `MazashTests/ShazamKitValidationTests.swift` (requires adding a test target first)

This task validates that `SHSession` works under ad-hoc signing without `com.apple.developer.shazamkit`. If it fails, we know immediately before building on top of it.

- [ ] **Step 1: Add a Unit Test target**

Xcode → File → New → Target → macOS → Unit Testing Bundle.
- Name: `MazashTests`
- Target to be Tested: `Mazash`

- [ ] **Step 2: Write the validation test**

Replace the generated test file at `MazashTests/MazashTests.swift` with `MazashTests/ShazamKitValidationTests.swift`:

```swift
import XCTest
import ShazamKit

final class ShazamKitValidationTests: XCTestCase {
    func testSHSessionInitializes() {
        // If ShazamKit requires a provisioned entitlement and rejects ad-hoc signing,
        // this will crash or produce a recognizable runtime error.
        let session = SHSession()
        XCTAssertNotNil(session)
    }
}
```

- [ ] **Step 3: Run the test**

Cmd+U. Expected: PASS — `testSHSessionInitializes` green.

**If the test crashes or prints an entitlement error:** Add `com.apple.developer.shazamkit` to `Mazash.entitlements` and re-run. If that still fails (requires a provisioning profile you don't have), stop and switch to ACRCloud for the RecognitionService — the protocol boundary in Task 5 makes this a drop-in replacement.

- [ ] **Step 4: Commit**

```bash
git add MazashTests/
git commit -m "test: validate ShazamKit works under ad-hoc signing"
```

---

## Task 3: Match Data Model

**Files:**
- Create: `Mazash/Models/Match.swift`
- Create: `MazashTests/MatchTests.swift`

- [ ] **Step 1: Write the failing test**

Create `MazashTests/MatchTests.swift`:

```swift
import XCTest
import ShazamKit
@testable import Mazash

final class MatchTests: XCTestCase {
    func testFormattedLine() {
        var components = DateComponents()
        components.calendar = .current
        components.year = 2026
        components.month = 4
        components.day = 24
        components.hour = 16
        components.minute = 32
        let date = Calendar.current.date(from: components)!

        // SHMediaItem can't be meaningfully instantiated for formatting tests,
        // so we test the static formatting function directly.
        let line = Match.formatLine(title: "Espresso", artist: "Sabrina Carpenter", date: date)
        XCTAssertEqual(line, "2026-04-24 16:32 | Espresso - Sabrina Carpenter")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Cmd+U. Expected: FAIL — `Match` type not found.

- [ ] **Step 3: Implement Match**

Create `Mazash/Models/Match.swift`:

```swift
import Foundation
import ShazamKit

struct Match {
    let timestamp: Date
    let mediaItem: SHMediaItem

    var title: String { mediaItem.title ?? "Unknown Title" }
    var artist: String { mediaItem.artist ?? "Unknown Artist" }

    var formattedLine: String {
        Match.formatLine(title: title, artist: artist, date: timestamp)
    }

    static func formatLine(title: String, artist: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "\(formatter.string(from: date)) | \(title) - \(artist)"
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Cmd+U. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Mazash/Models/Match.swift MazashTests/MatchTests.swift
git commit -m "feat: add Match data model"
```

---

## Task 4: MatchStore

**Files:**
- Create: `Mazash/Store/MatchStore.swift`
- Create: `MazashTests/MatchStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `MazashTests/MatchStoreTests.swift`:

```swift
import XCTest
import ShazamKit
@testable import Mazash

final class MatchStoreTests: XCTestCase {
    var tempDir: URL!
    var store: MatchStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = MatchStore(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testAddMatchAppendsToMemory() {
        let mediaItem = SHMediaItem(properties: [.title: "Test Song", .artist: "Test Artist"])
        let match = Match(timestamp: Date(), mediaItem: mediaItem)
        store.add(match)
        XCTAssertEqual(store.matches.count, 1)
        XCTAssertEqual(store.matches[0].title, "Test Song")
    }

    func testAddMatchWritesToFile() throws {
        var components = DateComponents()
        components.calendar = .current
        components.year = 2026
        components.month = 4
        components.day = 24
        components.hour = 10
        components.minute = 5
        let date = Calendar.current.date(from: components)!

        let mediaItem = SHMediaItem(properties: [.title: "Test Song", .artist: "Test Artist"])
        let match = Match(timestamp: date, mediaItem: mediaItem)
        store.add(match)

        let fileURL = tempDir.appendingPathComponent("matches.txt")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(
            contents.trimmingCharacters(in: .newlines),
            "2026-04-24 10:05 | Test Song - Test Artist"
        )
    }

    func testMultipleMatchesAppend() throws {
        let item1 = SHMediaItem(properties: [.title: "Song A", .artist: "Artist A"])
        let item2 = SHMediaItem(properties: [.title: "Song B", .artist: "Artist B"])
        let date = Date()
        store.add(Match(timestamp: date, mediaItem: item1))
        store.add(Match(timestamp: date, mediaItem: item2))

        let fileURL = tempDir.appendingPathComponent("matches.txt")
        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2)
    }

    func testLastMatchReturnsNewest() {
        let item1 = SHMediaItem(properties: [.title: "Song A", .artist: "Artist A"])
        let item2 = SHMediaItem(properties: [.title: "Song B", .artist: "Artist B"])
        store.add(Match(timestamp: Date(), mediaItem: item1))
        store.add(Match(timestamp: Date(), mediaItem: item2))
        XCTAssertEqual(store.lastMatch?.title, "Song B")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Cmd+U. Expected: FAIL — `MatchStore` not found.

- [ ] **Step 3: Implement MatchStore**

Create `Mazash/Store/MatchStore.swift`:

```swift
import Foundation
import Observation

@Observable
final class MatchStore {
    private(set) var matches: [Match] = []
    private let fileURL: URL

    init(directory: URL = MatchStore.defaultDirectory) {
        self.fileURL = directory.appendingPathComponent("matches.txt")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func add(_ match: Match) {
        matches.append(match)
        appendToFile(match)
    }

    var lastMatch: Match? { matches.last }

    private func appendToFile(_ match: Match) {
        let line = match.formattedLine + "\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mazash")
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Cmd+U. Expected: all four MatchStore tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Mazash/Store/MatchStore.swift MazashTests/MatchStoreTests.swift
git commit -m "feat: add MatchStore with append-only file persistence"
```

---

## Task 5: AudioCaptureService Protocol and SCKAudioCaptureService

**Files:**
- Create: `Mazash/Services/AudioCaptureService.swift`
- Create: `Mazash/Services/SCKAudioCaptureService.swift`

No unit tests for this task — ScreenCaptureKit requires real hardware and a granted screen recording permission. Correctness is validated during the integration run in Task 8.

- [ ] **Step 1: Create the AudioCaptureService protocol**

Create `Mazash/Services/AudioCaptureService.swift`:

```swift
import AVFoundation

protocol AudioCaptureDelegate: AnyObject {
    func audioCaptureService(_ service: any AudioCaptureService, didCapture buffer: CMSampleBuffer)
    func audioCaptureService(_ service: any AudioCaptureService, didFailWith error: Error)
}

protocol AudioCaptureService: AnyObject {
    var delegate: AudioCaptureDelegate? { get set }
    func start() async throws
    func stop()
}
```

- [ ] **Step 2: Create SCKAudioCaptureService**

Create `Mazash/Services/SCKAudioCaptureService.swift`:

```swift
import ScreenCaptureKit
import AVFoundation

final class SCKAudioCaptureService: NSObject, AudioCaptureService {
    weak var delegate: AudioCaptureDelegate?
    private var stream: SCStream?

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        guard let display = content.displays.first else {
            throw CaptureError.noDisplayFound
        }

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        // Minimize video overhead — we only care about audio
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(
            self,
            type: .audio,
            sampleHandlerQueue: .global(qos: .userInitiated)
        )
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        Task { try? await stream?.stopCapture() }
        stream = nil
    }

    enum CaptureError: Error {
        case noDisplayFound
    }
}

extension SCKAudioCaptureService: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer buffer: CMSampleBuffer,
        ofType type: SCStreamOutputType
    ) {
        guard type == .audio else { return }
        delegate?.audioCaptureService(self, didCapture: buffer)
    }
}

extension SCKAudioCaptureService: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        delegate?.audioCaptureService(self, didFailWith: error)
    }
}
```

- [ ] **Step 3: Build**

Cmd+B. Fix any build errors before continuing.

- [ ] **Step 4: Commit**

```bash
git add Mazash/Services/AudioCaptureService.swift Mazash/Services/SCKAudioCaptureService.swift
git commit -m "feat: add AudioCaptureService protocol and SCKAudioCaptureService"
```

---

## Task 6: RecognitionService Protocol and ShazamRecognitionService

**Files:**
- Create: `Mazash/Services/RecognitionService.swift`
- Create: `Mazash/Services/ShazamRecognitionService.swift`

No unit tests — ShazamKit requires a live network connection to Shazam's servers. Validated in Task 8.

- [ ] **Step 1: Create the RecognitionService protocol**

Create `Mazash/Services/RecognitionService.swift`:

```swift
import AVFoundation
import ShazamKit

protocol RecognitionDelegate: AnyObject {
    func recognitionService(_ service: any RecognitionService, didFind match: Match)
}

protocol RecognitionService: AnyObject {
    var delegate: RecognitionDelegate? { get set }
    func process(buffer: CMSampleBuffer)
    func reset()
}
```

- [ ] **Step 2: Create ShazamRecognitionService**

Create `Mazash/Services/ShazamRecognitionService.swift`:

```swift
import ShazamKit
import AVFoundation

final class ShazamRecognitionService: NSObject, RecognitionService {
    weak var delegate: RecognitionDelegate?

    private let session = SHSession()
    private var generator = SHSignatureGenerator()
    private var lastMatchedShazamID: String?
    private var bufferedDuration: TimeInterval = 0
    private let matchIntervalSeconds: TimeInterval = 10

    override init() {
        super.init()
        session.delegate = self
    }

    func process(buffer: CMSampleBuffer) {
        try? generator.append(buffer, at: nil)
        bufferedDuration += CMSampleBufferGetDuration(buffer).seconds

        if bufferedDuration >= matchIntervalSeconds {
            attemptMatch()
        }
    }

    func reset() {
        generator = SHSignatureGenerator()
        bufferedDuration = 0
        lastMatchedShazamID = nil
    }

    private func attemptMatch() {
        guard let signature = try? generator.generateSignature() else { return }
        generator = SHSignatureGenerator()
        bufferedDuration = 0
        session.match(signature)
    }
}

extension ShazamRecognitionService: SHSessionDelegate {
    func session(_ session: SHSession, didFind match: SHMatch) {
        guard let item = match.mediaItems.first else { return }

        // Suppress duplicate matches for the same song
        guard item.shazamID != lastMatchedShazamID else { return }
        lastMatchedShazamID = item.shazamID

        let result = Match(timestamp: Date(), mediaItem: item)
        delegate?.recognitionService(self, didFind: result)
    }

    func session(
        _ session: SHSession,
        didNotFindMatchFor signature: SHSignature,
        error: (any Error)?
    ) {
        // No match this window — continue accumulating audio
    }
}
```

- [ ] **Step 3: Build**

Cmd+B. Fix any build errors before continuing.

- [ ] **Step 4: Commit**

```bash
git add Mazash/Services/RecognitionService.swift Mazash/Services/ShazamRecognitionService.swift
git commit -m "feat: add RecognitionService protocol and ShazamRecognitionService"
```

---

## Task 7: Wire Up MenuBarApp

**Files:**
- Modify: `Mazash/MazashApp.swift`
- Create: `Mazash/MenuBarView.swift`

- [ ] **Step 1: Create MenuBarView**

Create `Mazash/MenuBarView.swift`:

```swift
import SwiftUI

struct MenuBarView: View {
    @Environment(AppController.self) private var controller

    var body: some View {
        Button(controller.isListening ? "Stop Listening" : "Start Listening") {
            controller.toggle()
        }

        if let last = controller.store.lastMatch {
            Divider()
            Text("Last match:")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("\(last.title) - \(last.artist)")
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 220)
        }

        Divider()
        Button("Quit Mazash") { NSApplication.shared.terminate(nil) }
    }
}
```

- [ ] **Step 2: Replace MazashApp.swift**

Replace the entire contents of `Mazash/MazashApp.swift`:

```swift
import SwiftUI
import AVFoundation

@Observable
final class AppController: AudioCaptureDelegate, RecognitionDelegate {
    private(set) var isListening = false
    let store = MatchStore()
    private let captureService: any AudioCaptureService = SCKAudioCaptureService()
    private let recognitionService: any RecognitionService = ShazamRecognitionService()

    init() {
        captureService.delegate = self
        recognitionService.delegate = self
    }

    func toggle() {
        if isListening {
            stopListening()
        } else {
            Task { await startListening() }
        }
    }

    private func startListening() async {
        do {
            try await captureService.start()
            await MainActor.run { isListening = true }
        } catch {
            print("Failed to start capture: \(error)")
        }
    }

    private func stopListening() {
        captureService.stop()
        recognitionService.reset()
        isListening = false
    }

    // MARK: - AudioCaptureDelegate

    func audioCaptureService(_ service: any AudioCaptureService, didCapture buffer: CMSampleBuffer) {
        recognitionService.process(buffer: buffer)
    }

    func audioCaptureService(_ service: any AudioCaptureService, didFailWith error: Error) {
        print("Capture error: \(error)")
        DispatchQueue.main.async { self.isListening = false }
    }

    // MARK: - RecognitionDelegate

    func recognitionService(_ service: any RecognitionService, didFind match: Match) {
        DispatchQueue.main.async { self.store.add(match) }
    }
}

@main
struct MazashApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra("Mazash", systemImage: controller.isListening ? "waveform" : "music.note") {
            MenuBarView()
                .environment(controller)
        }
    }
}
```

- [ ] **Step 3: Build**

Cmd+B. Fix any build errors before continuing.

- [ ] **Step 4: Commit**

```bash
git add Mazash/MazashApp.swift Mazash/MenuBarView.swift
git commit -m "feat: wire up AppController and menu bar UI"
```

---

## Task 8: Integration Validation

No code changes. This task validates the full running app.

- [ ] **Step 1: Run the app**

Cmd+R. Verify:
- No Dock icon appears
- A music note (♩) icon appears in the menu bar
- The menu shows "Start Listening" and "Quit Mazash"

- [ ] **Step 2: Grant screen recording permission**

Click "Start Listening". macOS will prompt for screen recording access. Grant it via System Settings → Privacy & Security → Screen Recording → enable Mazash. The menu bar icon should switch to a waveform.

If macOS does not prompt (permission was previously denied), open System Settings → Privacy & Security → Screen Recording and manually enable it.

- [ ] **Step 3: Play audio and wait for a match**

Play a recognizable song in any app (Spotify, Apple Music, YouTube, etc.). Wait up to 30 seconds. ShazamKit needs roughly 10 seconds of audio in the first window plus network round-trip time.

- [ ] **Step 4: Verify the match appears in the menu**

The menu should now show:
```
Stop Listening
─────────────
Last match:
<Song Title> - <Artist>
─────────────
Quit Mazash
```

- [ ] **Step 5: Verify the match was written to file**

```bash
cat ~/Library/Application\ Support/mazash/matches.txt
```

Expected output (example):
```
2026-04-24 16:32 | Espresso - Sabrina Carpenter
```

- [ ] **Step 6: Test toggle off**

Click "Stop Listening". Icon reverts to music note. Play more audio — no new matches should appear in the menu or file.

- [ ] **Step 7: Commit**

```bash
git commit --allow-empty -m "chore: integration validated — Mazash v0.1 complete"
```
