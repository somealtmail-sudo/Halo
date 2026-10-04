import AppKit
import CoreAudio
import Combine
import HaloCore

/// Only the small waveform views observe this publisher; audio never redraws AppModel.
@MainActor
final class AudioWaveform: ObservableObject {
    @Published private(set) var levels = [Float](repeating: 0, count: 8)
    @Published private(set) var status = "Enable live waveform to allow system audio access."
    private var tap: AudioObjectID = 0
    private var device: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private var timer: Timer?
    private var samples: WaveformSamples?
    private var failed = false
    private var count = 8

    func reconcile(active: Bool, enabled: Bool, count: Int, reduced: Bool) {
        self.count = count
        if !enabled { failed = false }
        guard enabled && active && !reduced else {
            stop()
            if !enabled { status = "Enable live waveform to allow system audio access." }
            else { status = reduced ? "Waveform paused by Reduce motion." : "Waiting for visible audio playback." }
            return
        }
        guard device == 0, !failed else { return }
        start()
    }

    func retry() { stop(); failed = false }

    private func start() {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "Halo live waveform"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        do {
            try check(AudioHardwareCreateProcessTap(description, &tap))
            var format = AudioStreamBasicDescription()
            var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var size = UInt32(MemoryLayout.size(ofValue: format))
            try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format))
            guard format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mBitsPerChannel == 32 else { throw CaptureError.unsupportedFormat }
            let configuration: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Halo waveform",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                                  kAudioSubTapDriftCompensationKey: true]]
            ]
            try check(AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &device))
            let samples = WaveformSamples(sampleRate: format.mSampleRate)
            self.samples = samples
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, device, nil) { _, input, _, _, _ in
                samples.consume(input)
            })
            try check(AudioDeviceStart(device, ioProc))
            status = "Live system audio · nothing recorded or saved."
            let timer = Timer(timeInterval: 1.0 / 24, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let samples = self.samples else { return }
                    let next = samples.read(count: self.count)
                    if next != self.levels { self.levels = next }
                }
            }
            timer.tolerance = 0.005
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        } catch {
            stop()
            failed = true
            status = "Audio capture unavailable (\(error.localizedDescription)). Allow Halo in System Settings → Privacy & Security → Screen & System Audio Recording, then retry."
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if device != 0 {
            if let ioProc {
                AudioDeviceStop(device, ioProc)
                AudioDeviceDestroyIOProcID(device, ioProc)
            }
            AudioHardwareDestroyAggregateDevice(device)
        }
        ioProc = nil; device = 0
        if tap != 0 { AudioHardwareDestroyProcessTap(tap) }
        tap = 0; samples = nil
        let flat = [Float](repeating: 0, count: count)
        if levels != flat { levels = flat }
    }

    private func check(_ status: OSStatus) throws {
        if status != noErr { throw CaptureError.system(status) }
    }
    private enum CaptureError: LocalizedError {
        case system(OSStatus), unsupportedFormat
        var errorDescription: String? {
            switch self {
            case .system(let code): return "Core Audio \(code)"
            case .unsupportedFormat: return "unsupported audio format"
            }
        }
    }
}

/// The callback does no heap allocation or dispatch, and never waits for the UI.
private final class WaveformSamples: @unchecked Sendable {
    private let lock = NSLock()
    private var envelope: WaveformEnvelope
    private var lastInput = CFAbsoluteTimeGetCurrent()
    init(sampleRate: Double) { envelope = WaveformEnvelope(sampleRate: sampleRate) }

    func consume(_ input: UnsafePointer<AudioBufferList>) {
        guard lock.try() else { return }
        defer { lock.unlock() }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let frameCount = buffers.mapFrameCount
        for frame in 0..<frameCount {
            var peak: Float = 0
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let channels = Int(buffer.mNumberChannels)
                let values = data.assumingMemoryBound(to: Float.self)
                for channel in 0..<channels {
                    let value = values[frame * channels + channel]
                    if value.isFinite { peak = max(peak, abs(value)) }
                }
            }
            envelope.append(peak)
        }
        lastInput = CFAbsoluteTimeGetCurrent()
    }

    func read(count: Int) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        // A device can stop delivering callbacks during silence or a route change.
        if CFAbsoluteTimeGetCurrent() - lastInput > 0.15 { return .init(repeating: 0, count: count) }
        return envelope.levels(count: count)
    }
}

private extension UnsafeMutableAudioBufferListPointer {
    var mapFrameCount: Int {
        var frames = Int.max
        for buffer in self where buffer.mData != nil && buffer.mNumberChannels > 0 {
            frames = Swift.min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * Int(buffer.mNumberChannels)))
        }
        return frames == Int.max ? 0 : frames
    }
}
