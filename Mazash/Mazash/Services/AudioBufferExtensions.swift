import AVFoundation

// MARK: - CMSampleBuffer → AVAudioPCMBuffer

extension CMSampleBuffer {
    /// Converts a CMSampleBuffer (as delivered by ScreenCaptureKit) into an AVAudioPCMBuffer.
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

// MARK: - AVAudioPCMBuffer → interleaved Int16

extension AVAudioPCMBuffer {
    /// Converts a non-interleaved Float32 buffer (SCKit's native format) to
    /// interleaved Int16 PCM suitable for submission to ACRCloud.
    func toInt16Data() -> Data? {
        guard let floatChannelData else { return nil }
        let channels = Int(format.channelCount)
        let frames = Int(frameLength)
        var result = Data(count: frames * channels * 2)
        result.withUnsafeMutableBytes { raw in
            let ptr = raw.bindMemory(to: Int16.self)
            for frame in 0..<frames {
                for ch in 0..<channels {
                    let sample = floatChannelData[ch][frame]
                    let clamped = max(-1.0, min(1.0, sample))
                    ptr[frame * channels + ch] = Int16(clamped * 32767)
                }
            }
        }
        return result
    }
}
