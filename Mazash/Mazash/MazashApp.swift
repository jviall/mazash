import SwiftUI
import AVFoundation

// MARK: - AppDelegate

// Thin delegate whose sole job is receiving the mazash:// OAuth callback URL from the OS
// and forwarding it to AppController.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onURL: ((URL) -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { onURL?($0) }
    }
}

// MARK: - AppController

@Observable
@MainActor
final class AppController: AudioCaptureDelegate, RecognitionDelegate {
    private(set) var isListening = false
    private let store = MatchStore()
    private let captureService: any AudioCaptureService = SCKAudioCaptureService()
    // nonisolated(unsafe): let binding never mutated after init; ACRCloudRecognitionService is
    // internally thread-safe via NSLock, so cross-actor access from the audio callback is safe.
    nonisolated(unsafe) private let recognitionService: any RecognitionService = ACRCloudRecognitionService(
        host: ACRCloudConfig.host,
        accessKey: ACRCloudConfig.accessKey,
        accessSecret: ACRCloudConfig.accessSecret
    )

    // nil when Spotify credentials are not configured in Secrets.xcconfig.
    let spotifyService: SpotifyService? = SpotifyConfig.isConfigured
        ? SpotifyService(clientId: SpotifyConfig.clientId, playlistId: SpotifyConfig.playlistId)
        : nil

    var lastMatch: Match? { store.lastMatch }

    init() {
        captureService.delegate = self
        recognitionService.delegate = self
    }

    func toggle() {
        guard !isListening else { stopListening(); return }
        isListening = true
        Task { await startListening() }
    }

    func handleURL(_ url: URL) {
        guard url.scheme == "mazash" else { return }
        spotifyService?.handleCallback(url: url)
    }

    private func startListening() async {
        do {
            try await captureService.start()
            store.writeSessionStart()
        } catch {
            isListening = false
            print("Failed to start capture: \(error)")
        }
    }

    private func stopListening() {
        captureService.stop()
        recognitionService.reset()
        isListening = false
    }

    // MARK: - AudioCaptureDelegate

    nonisolated func audioCaptureService(_ service: any AudioCaptureService, didCapture buffer: CMSampleBuffer) {
        recognitionService.process(buffer: buffer)
    }

    nonisolated func audioCaptureService(_ service: any AudioCaptureService, didFailWith error: Error) {
        print("Capture error: \(error)")
        Task { @MainActor in self.isListening = false }
    }

    // MARK: - RecognitionDelegate

    nonisolated func recognitionService(_ service: any RecognitionService, didFind match: Match) {
        Task { @MainActor in
            self.store.add(match)
            if let id = match.spotifyTrackId {
                await self.spotifyService?.addTrack(spotifyId: id, label: "\(match.title) — \(match.artist)")
            }
        }
    }
}

// MARK: - App

@main
struct MazashApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra("Mazash", systemImage: controller.isListening ? "waveform" : "music.note") {
            MenuBarView()
                .environment(controller)
                .onAppear {
                    appDelegate.onURL = { url in
                        Task { @MainActor in controller.handleURL(url) }
                    }
                }
        }
        .menuBarExtraStyle(.menu)
    }
}
