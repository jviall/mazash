import AVFoundation
import ShazamKit

protocol RecognitionDelegate: AnyObject {
    func recognitionService(_ service: any RecognitionService, didFind match: Match)
}

protocol RecognitionService: AnyObject {
    var delegate: RecognitionDelegate? { get set }
    func process(buffer: CMSampleBuffer)
    func reset()
}
