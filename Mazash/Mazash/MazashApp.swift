import SwiftUI
import AVFoundation

@Observable
@MainActor
final class AppController: AudioCaptureDelegate, RecognitionDelegate {
    private(set) var isListening = false
    private let store = MatchStore()
    private let captureService: any AudioCaptureService = SCKAudioCaptureService()
    // nonisolated(unsafe): let binding never mutated after init; ShazamRecognitionService is
    // internally thread-safe via NSLock, so cross-actor access from the audio callback is safe.
    nonisolated(unsafe) private let recognitionService: any RecognitionService = ACRCloudRecognitionService(
        host: ACRCloudConfig.host,
        accessKey: ACRCloudConfig.accessKey,
        accessSecret: ACRCloudConfig.accessSecret
    )

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

    private func startListening() async {
        do {
            try await captureService.start()
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
        Task { @MainActor in self.store.add(match) }
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
        .menuBarExtraStyle(.menu)
    }
}
