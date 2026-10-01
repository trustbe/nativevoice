import AVFoundation
import NativeVoiceCore

/// Records audio and reports the input level.
///
/// The engine starts on key press, before the hold threshold, and writing
/// begins only once the threshold passes. Opening an audio device takes real
/// time — measured at over a second with an `ffmpeg` subprocess, which ate the
/// first word of every sentence. Starting early puts that cost outside the
/// recording.
///
/// Recording happens in-process for the same reason: a subprocess was both
/// slower to start and harder to reason about.
final class Recorder {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private let lock = NSLock()
    private var running = false
    private var writing = false
    private var peak: Float = -200

    /// Input level in dB, reported continuously. Raw, not normalized — the
    /// scaling belongs to `LevelHistory`, where it is tested.
    var onLevel: ((Float) -> Void)?

    /// Loudest point since writing began, in dB. When a transcript comes back
    /// empty this is the only thing that tells silence on the input apart from
    /// speech the model did not recognize.
    var peakDecibels: Float { lock.lock(); defer { lock.unlock() }; return peak }

    func warmUp() {
        guard !running else { return }
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            appLog("audio input unavailable: \(format)")
            return
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }

            self.lock.lock()
            let target = self.writing ? self.file : nil
            try? target?.write(from: buffer)
            let isWriting = self.writing
            self.lock.unlock()

            guard let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for i in 0..<count { sum += channel[i] * channel[i] }
            let rms = (sum / Float(count)).squareRoot()
            let db = 20 * log10(max(rms, 1e-7))

            if isWriting {
                self.lock.lock()
                if db > self.peak { self.peak = db }
                self.lock.unlock()
            }

            DispatchQueue.main.async { self.onLevel?(db) }
        }

        do {
            engine.prepare()
            try engine.start()
            running = true
        } catch {
            input.removeTap(onBus: 0)
            appLog("audio engine failed to start: \(error.localizedDescription)")
        }
    }

    func startWriting(to url: URL) -> Bool {
        guard running else { return false }
        let format = engine.inputNode.inputFormat(forBus: 0)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings)
            lock.lock(); self.file = file; writing = true; peak = -200; lock.unlock()
            let device = AVCaptureDevice.default(for: .audio)?.localizedName ?? "unknown"
            appLog(String(format: "recording from %@ at %.0f Hz, %d ch",
                       device, format.sampleRate, format.channelCount))
            return true
        } catch {
            appLog("could not open the recording file: \(error.localizedDescription)")
            return false
        }
    }

    func stop() {
        lock.lock(); writing = false; file = nil; lock.unlock()
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }
}
