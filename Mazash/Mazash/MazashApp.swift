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
