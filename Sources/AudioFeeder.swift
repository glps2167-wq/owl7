import AVFoundation
import Speech

/// 마이크 버퍼를 음성 인식 모델이 원하는 형식으로 바꿔 넘겨주는 역할.
/// 오디오 스레드에서 호출되므로 메인 액터와 분리해 둔다.
final class AudioFeeder: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outFormat: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation

    init?(from inFormat: AVAudioFormat,
          to outFormat: AVAudioFormat,
          continuation: AsyncStream<AnalyzerInput>.Continuation) {
        guard let conv = AVAudioConverter(from: inFormat, to: outFormat) else { return nil }
        self.converter = conv
        self.outFormat = outFormat
        self.continuation = continuation
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status != .error, out.frameLength > 0 {
            continuation.yield(AnalyzerInput(buffer: out))
        }
    }
}
