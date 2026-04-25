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
