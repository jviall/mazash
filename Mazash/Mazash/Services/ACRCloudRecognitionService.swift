import Foundation
import AVFoundation
import CommonCrypto

// process(buffer:) is called on SCKAudioCaptureService.sampleQueue (serial, background).
// reset() and attemptMatch() may be called from different queues; all shared state protected by lock.
final class ACRCloudRecognitionService: RecognitionService {
    weak var delegate: RecognitionDelegate?

    private let host: String
    private let accessKey: String
    private let accessSecret: String

    // Accumulated interleaved Int16 PCM samples.
    // Collects up to windowSeconds of audio, then submits and resets regardless of result.
    // Each attempt is a clean 10-second window — the size ACRCloud recommends for raw audio.
    //
    // At 320 kbps AAC, 10 seconds encodes to ~40 KB — well under ACRCloud's 5 MB limit.
    private var pcmData = Data()
    private var sampleRate: Double = 48000
    private var channelCount: Int = 2
    private var totalDuration: TimeInterval = 0
    private var isMatchPending = false
    private let windowSeconds: TimeInterval = 10
    private let lock = NSLock()

    init(host: String, accessKey: String, accessSecret: String) {
        self.host = host
        self.accessKey = accessKey
        self.accessSecret = accessSecret
    }

    func process(buffer: CMSampleBuffer) {
        guard let pcmBuffer = buffer.asPCMBuffer() else { return }
        guard let int16Data = pcmBuffer.toInt16Data() else { return }

        let bufferDuration = Double(pcmBuffer.frameLength) / pcmBuffer.format.sampleRate

        lock.lock()
        sampleRate = pcmBuffer.format.sampleRate
        channelCount = Int(pcmBuffer.format.channelCount)
        if totalDuration < windowSeconds {
            pcmData.append(int16Data)
        }
        totalDuration += bufferDuration
        let shouldAttempt = totalDuration >= windowSeconds && !isMatchPending
        lock.unlock()

        if shouldAttempt { attemptMatch() }
    }

    // Called by AppController when the user stops listening.
    func reset() {
        lock.lock()
        resetBuffer()
        isMatchPending = false
        lock.unlock()
    }

    // MARK: - Private

    // Must be called with lock held.
    private func resetBuffer() {
        pcmData = Data()
        totalDuration = 0
    }

    private func attemptMatch() {
        lock.lock()
        guard !isMatchPending else { lock.unlock(); return }
        isMatchPending = true
        let capturedPCM = pcmData
        let rate = sampleRate
        let channels = channelCount
        resetBuffer()
        lock.unlock()

        print("[ACRCloud] submitting \(String(format: "%.1f", windowSeconds))s window")
        Task { await identify(pcmData: capturedPCM, sampleRate: rate, channels: channels) }
    }

    private func clearPending() {
        lock.lock()
        isMatchPending = false
        lock.unlock()
    }

    private func identify(pcmData: Data, sampleRate: Double, channels: Int) async {
        let audioData: Data
        do {
            audioData = try encodeAsAAC(pcmData: pcmData, sampleRate: sampleRate, channels: channels)
        } catch {
            print("[ACRCloud] AAC encoding failed: \(error)")
            clearPending()
            return
        }

        let timestamp = String(Int(Date().timeIntervalSince1970))
        let sigString = "POST\n/v1/identify\n\(accessKey)\naudio\n1\n\(timestamp)"
        let signature = hmacSHA1(key: accessSecret, message: sigString)

        guard let url = URL(string: "https://\(host)/v1/identify") else { clearPending(); return }

        let boundary = UUID().uuidString
        var body = Data()

        func field(_ name: String, _ value: String) {
            body += "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
                .data(using: .utf8)!
        }

        field("access_key", accessKey)
        field("sample_bytes", "\(audioData.count)")
        field("timestamp", timestamp)
        field("signature", signature)
        field("data_type", "audio")
        field("signature_version", "1")

        body += "--\(boundary)\r\nContent-Disposition: form-data; name=\"sample\"; filename=\"sample.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n"
            .data(using: .utf8)!
        body += audioData
        body += "\r\n--\(boundary)--\r\n".data(using: .utf8)!

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            handleResponse(data: data)
            clearPending()
        } catch {
            print("[ACRCloud] request failed: \(error)")
            clearPending()
        }
    }

    // MARK: - AAC encoding

    private enum EncodingError: Error {
        case emptyInput
        case bufferAllocationFailed
    }

    /// Encodes accumulated Int16 interleaved PCM into a 320 kbps AAC M4A file in memory.
    private func encodeAsAAC(pcmData: Data, sampleRate: Double, channels: Int) throws -> Data {
        let ch = Int(channels)
        let frameCount = pcmData.count / (ch * MemoryLayout<Int16>.size)
        guard frameCount > 0 else { throw EncodingError.emptyInput }

        // Build a Float32 non-interleaved PCM buffer from our Int16 interleaved data.
        let pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: false
        )!
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: pcmFormat,
                                               frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw EncodingError.bufferAllocationFailed
        }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        pcmData.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: Int16.self)
            for c in 0..<ch {
                guard let dst = pcmBuffer.floatChannelData?[c] else { return }
                for f in 0..<frameCount {
                    dst[f] = Float(src[f * ch + c]) / 32768.0
                }
            }
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let aacSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 320_000
        ]

        // AVAudioFile is closed (and the AAC stream flushed) when it goes out of scope.
        do {
            let file = try AVAudioFile(forWriting: tempURL, settings: aacSettings)
            try file.write(from: pcmBuffer)
        }

        return try Data(contentsOf: tempURL)
    }

    // MARK: - Response parsing

    private func handleResponse(data: Data) {
        struct Artist: Decodable { let name: String }
        struct SpotifyTrack: Decodable { let id: String }
        struct SpotifyMeta: Decodable { let track: SpotifyTrack? }
        struct YouTubeMeta: Decodable { let vid: String }
        struct ExternalMetadata: Decodable {
            let spotify: SpotifyMeta?
            let youtube: YouTubeMeta?
        }
        struct MusicItem: Decodable {
            let title: String
            let artists: [Artist]?
            let externalMetadata: ExternalMetadata?
            enum CodingKeys: String, CodingKey {
                case title, artists
                case externalMetadata = "external_metadata"
            }
        }
        struct Metadata: Decodable { let music: [MusicItem]? }
        struct Status: Decodable { let code: Int; let msg: String }
        struct Response: Decodable { let status: Status; let metadata: Metadata? }

        do {
            let response = try JSONDecoder().decode(Response.self, from: data)
            guard response.status.code == 0,
                  let item = response.metadata?.music?.first else {
                print("[ACRCloud] no match (code \(response.status.code)): \(response.status.msg)")
                return
            }
            let artist = item.artists?.first?.name ?? "Unknown Artist"
            let match = Match(
                timestamp: Date(),
                title: item.title,
                artist: artist,
                spotifyTrackId: item.externalMetadata?.spotify?.track?.id,
                youtubeVideoId: item.externalMetadata?.youtube?.vid
            )
            delegate?.recognitionService(self, didFind: match)
        } catch {
            print("[ACRCloud] JSON parse error: \(error)")
        }
    }

    // MARK: - HMAC-SHA1

    private func hmacSHA1(key: String, message: String) -> String {
        let keyBytes = Array(key.utf8)
        let msgBytes = Array(message.utf8)
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1),
               keyBytes, keyBytes.count,
               msgBytes, msgBytes.count,
               &hmac)
        return Data(hmac).base64EncodedString()
    }
}
