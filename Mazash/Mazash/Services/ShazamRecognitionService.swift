import ShazamKit
import AVFoundation

// process(buffer:) is called on SCKAudioCaptureService.sampleQueue (serial, background).
// SHSessionDelegate callbacks arrive on a ShazamKit-internal queue.
// reset() is called from the main thread via AppController.
// All shared mutable state is protected by `lock`.
final class ShazamRecognitionService: NSObject, RecognitionService {
    weak var delegate: RecognitionDelegate?

    private let session = SHSession()
    private var generator = SHSignatureGenerator()
    private var lastMatchedShazamID: String?
    private var bufferedDuration: TimeInterval = 0
    private var isMatchPending = false
    private let matchIntervalSeconds: TimeInterval = 10
    private let lock = NSLock()

    override init() {
        super.init()
        session.delegate = self
    }

    func process(buffer: CMSampleBuffer) {
        guard let pcmBuffer = buffer.asPCMBuffer() else { return }

        // Derive duration from sample data rather than CMTime, which can return nan.
        let bufferDuration = Double(pcmBuffer.frameLength) / pcmBuffer.format.sampleRate

        lock.lock()
        try? generator.append(pcmBuffer, at: nil)
        bufferedDuration += bufferDuration
        let shouldAttempt = bufferedDuration >= matchIntervalSeconds && !isMatchPending
        lock.unlock()

        if shouldAttempt { attemptMatch() }
    }

    func reset() {
        lock.lock()
        generator = SHSignatureGenerator()
        bufferedDuration = 0
        lastMatchedShazamID = nil
        isMatchPending = false
        lock.unlock()
    }

    private func attemptMatch() {
        lock.lock()
        guard !isMatchPending else { lock.unlock(); return }
        isMatchPending = true
        let signature = generator.signature()
        generator = SHSignatureGenerator()
        bufferedDuration = 0
        lock.unlock()

        session.match(signature)
    }
}

extension ShazamRecognitionService: SHSessionDelegate {
    func session(_ session: SHSession, didFind match: SHMatch) {
        guard let item = match.mediaItems.first,
              let newID = item.shazamID else { return }

        lock.lock()
        isMatchPending = false
        guard newID != lastMatchedShazamID else { lock.unlock(); return }
        lastMatchedShazamID = newID
        lock.unlock()

        let result = Match(timestamp: Date(), mediaItem: item)
        delegate?.recognitionService(self, didFind: result)
    }

    func session(
        _ session: SHSession,
        didNotFindMatchFor signature: SHSignature,
        error: (any Error)?
    ) {
        lock.lock()
        isMatchPending = false
        lock.unlock()

        if let error {
            print("[ShazamRecognitionService] no match: \(error)")
        }
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
