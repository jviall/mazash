import ScreenCaptureKit
import AVFoundation

final class SCKAudioCaptureService: NSObject, AudioCaptureService {
    weak var delegate: AudioCaptureDelegate?
    private var stream: SCStream?

    // Private serial queue ensures SHSignatureGenerator.append calls are never concurrent.
    private let sampleQueue = DispatchQueue(
        label: "com.local.mazash.audioCapture",
        qos: .userInitiated
    )

    func start() async throws {
        guard stream == nil else { return }

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
        // Minimize video overhead — we only care about audio.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        // Capture into a local first so the Task closure sees the live stream,
        // not the nil we're about to assign.
        let streamToStop = stream
        stream = nil
        Task {
            do {
                try await streamToStop?.stopCapture()
            } catch {
                print("[SCKAudioCaptureService] stopCapture error: \(error)")
            }
        }
    }

    enum CaptureError: Error {
        case noDisplayFound
    }
}

extension SCKAudioCaptureService: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer buffer: CMSampleBuffer,
        of type: SCStreamOutputType
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
