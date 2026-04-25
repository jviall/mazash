import AVFoundation

protocol AudioCaptureDelegate: AnyObject {
    func audioCaptureService(_ service: any AudioCaptureService, didCapture buffer: CMSampleBuffer)
    func audioCaptureService(_ service: any AudioCaptureService, didFailWith error: Error)
}

protocol AudioCaptureService: AnyObject {
    var delegate: AudioCaptureDelegate? { get set }
    func start() async throws
    func stop()
}
