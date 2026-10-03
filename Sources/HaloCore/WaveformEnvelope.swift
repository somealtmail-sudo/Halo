import Foundation

/// Fixed 120 ms amplitude history. Stores peaks, never raw audio or recordings.
public struct WaveformEnvelope {
    private var peaks = [Float](repeating: 0, count: 24)
    private var cursor = 0
    private var frames = 0
    private var peak: Float = 0
    private let framesPerPeak: Int

    public init(sampleRate: Double) {
        framesPerPeak = max(1, Int((sampleRate.isFinite ? min(384_000, max(1, sampleRate)) : 48_000) * 0.005))
    }

    public mutating func append(_ amplitude: Float) {
        if amplitude.isFinite { peak = max(peak, min(1, abs(amplitude))) }
        frames += 1
        if frames >= framesPerPeak {
            peaks[cursor] = peak
            cursor = (cursor + 1) % peaks.count
            frames = 0
            peak = 0
        }
    }

    public func levels(count: Int) -> [Float] {
        let count = min(16, max(3, count))
        return (0..<count).map { column in
            let start = column * peaks.count / count
            let end = (column + 1) * peaks.count / count
            var value: Float = 0
            for index in start..<end { value = max(value, peaks[(cursor + index) % peaks.count]) }
            return value
        }
    }
}
