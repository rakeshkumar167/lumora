import AVFoundation
import Accelerate
import LumoraKit

/// Anything that can supply live audio levels to `ParticleSwarmView`. Lets the
/// view take the real microphone manager in the app and synthetic levels in
/// previews / offscreen checks.
protocol AudioLevelsProviding: AnyObject {
    var currentLevels: AudioLevels { get }
    /// True once the user has denied microphone access (or it is unavailable),
    /// so the effect can fall back to idle motion.
    var isDenied: Bool { get }
    /// Called when an audio-reactive effect appears / disappears so the engine
    /// runs only while needed. Ref-counted.
    func retain()
    func release()
}

/// The project's single microphone tap. A shared singleton so the editor and
/// projector windows react to the same audio without opening two input taps.
/// Taps `AVAudioEngine`'s input, runs an FFT per buffer, and reduces it to
/// smoothed `AudioLevels` via the pure `AudioBandAnalyzer`.
///
/// Microphone access needs `NSMicrophoneUsageDescription` in the packaged app's
/// Info.plist (see `scripts/make_app.sh`); under `swift run` there is no prompt,
/// so this reports `isDenied` and the effect runs idle.
final class AudioInputManager: AudioLevelsProviding {
    static let shared = AudioInputManager()

    private let engine = AVAudioEngine()
    private let analyzer = AudioBandAnalyzer()
    private let lock = NSLock()

    private var _levels = AudioLevels.silent
    private var _denied = false
    private var running = false
    private var refCount = 0

    // FFT
    private let log2n: vDSP_Length = 10          // 1024-point FFT
    private var fftSize: Int { 1 << Int(log2n) }
    private let fftSetup: FFTSetup
    private var window: [Float]

    private init() {
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: 1 << Int(log2n))
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    var currentLevels: AudioLevels {
        lock.lock(); defer { lock.unlock() }; return _levels
    }
    var isDenied: Bool {
        lock.lock(); defer { lock.unlock() }; return _denied
    }

    func retain() {
        DispatchQueue.main.async {
            self.refCount += 1
            if self.refCount == 1 { self.startIfPermitted() }
        }
    }

    func release() {
        DispatchQueue.main.async {
            self.refCount -= 1
            if self.refCount <= 0 { self.refCount = 0; self.stop() }
        }
    }

    // MARK: - Engine lifecycle

    private func startIfPermitted() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted, self.refCount > 0 { self.start() }
                    else { self.setDenied(!granted) }
                }
            }
        default:
            setDenied(true)
        }
    }

    private func start() {
        guard !running else { return }
        setDenied(false)
        analyzer.reset()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { setDenied(true); return }
        let sr = format.sampleRate
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: format) { [weak self] buffer, _ in
            self?.process(buffer: buffer, sampleRate: sr)
        }
        engine.prepare()
        do {
            try engine.start()
            running = true
        } catch {
            input.removeTap(onBus: 0)
            setDenied(true)
        }
    }

    private func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        lock.lock(); _levels = .silent; lock.unlock()
    }

    private func setDenied(_ v: Bool) {
        lock.lock(); _denied = v; lock.unlock()
    }

    // MARK: - FFT

    private func process(buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let available = Int(buffer.frameLength)
        guard available > 0 else { return }

        // Windowed real samples (first fftSize frames; zero-pad if short).
        var samples = [Float](repeating: 0, count: fftSize)
        let n = min(available, fftSize)
        for i in 0..<n { samples[i] = channel[i] }
        vDSP_vmul(samples, 1, window, 1, &samples, 1, vDSP_Length(fftSize))

        let half = fftSize / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                samples.withUnsafeBytes { raw in
                    raw.bindMemory(to: DSPComplex.self).baseAddress.map {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }
        // Power → magnitude, normalized by the transform size.
        let scaled = magnitudes.map { sqrtf(max(0, $0)) / Float(fftSize) }
        let levels = analyzer.process(magnitudes: scaled, sampleRate: sampleRate)
        lock.lock(); _levels = levels; lock.unlock()
    }
}
