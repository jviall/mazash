import ShazamKit
import AVFoundation

// process(buffer:) is called on SCKAudioCaptureService.sampleQueue (serial, background).
// SHSessionDelegate callbacks arrive on a ShazamKit-internal queue.
// reset() is called from the main thread via AppController.
// All shared mutable state is protected by `lock`.
//
// NOTE: ShazamKit music recognition requires the ShazamKit App Service to be enabled
// for the app's bundle ID in the Apple Developer portal (paid membership required).
// Use ACRCloudRecognitionService for local/free use.
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

        let result = Match(
            timestamp: Date(),
            title: item.title ?? "Unknown Title",
            artist: item.artist ?? "Unknown Artist"
        )
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
