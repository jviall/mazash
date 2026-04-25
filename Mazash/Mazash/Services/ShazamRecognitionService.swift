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
        guard let pcmBuffer = buffer.asPCMBuffer() else { return }
        try? generator.append(pcmBuffer, at: nil)
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
        let signature = generator.signature()
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

// MARK: - CMSampleBuffer → AVAudioPCMBuffer conversion

private extension CMSampleBuffer {
    /// Converts a `CMSampleBuffer` (as delivered by ScreenCaptureKit) into an
    /// `AVAudioPCMBuffer` suitable for `SHSignatureGenerator.append(_:at:)`.
    func asPCMBuffer() -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(self),
              let streamBasicDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else { return nil }

        guard let avFormat = AVAudioFormat(streamDescription: streamBasicDesc) else { return nil }
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: avFormat, frameCapacity: frameCount) else { return nil }
        pcmBuffer.frameLength = frameCount

        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        ) == noErr else { return nil }

        return pcmBuffer
    }
}
