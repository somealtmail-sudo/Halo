import XCTest
@testable import HaloCore

final class WaveformEnvelopeTests: XCTestCase {
    func testSilenceRemainsFlat() {
        var waveform = WaveformEnvelope(sampleRate: 48_000)
        for _ in 0..<48_000 { waveform.append(0) }
        XCTAssertEqual(waveform.levels(count: 8), Array(repeating: 0, count: 8))
    }

    func testRealAmplitudeAndPolarityArePreserved() {
        var waveform = WaveformEnvelope(sampleRate: 48_000)
        for _ in 0..<5_760 { waveform.append(-0.25) }
        XCTAssertEqual(waveform.levels(count: 8), Array(repeating: 0.25, count: 8))
    }

    func testImpulseMovesThroughHistoryAndExpires() {
        var waveform = WaveformEnvelope(sampleRate: 1_000)
        waveform.append(0.75)
        for _ in 0..<4 { waveform.append(0) }
        XCTAssertEqual(waveform.levels(count: 8).last, 0.75)
        for _ in 0..<105 { waveform.append(0) }
        XCTAssertEqual(waveform.levels(count: 8).first, 0.75)
        for _ in 0..<15 { waveform.append(0) }
        XCTAssertTrue(waveform.levels(count: 8).allSatisfy { $0 == 0 })
    }

    func testChangingLineCountRetainsPeaksAndBoundsOutput() {
        var waveform = WaveformEnvelope(sampleRate: 1_000)
        for index in 0..<120 { waveform.append(index == 60 ? 0.9 : 0) }
        for count in 3...16 {
            XCTAssertEqual(waveform.levels(count: count).count, count)
            XCTAssertEqual(waveform.levels(count: count).max(), 0.9)
        }
        XCTAssertEqual(waveform.levels(count: Int.max).count, 16)
        XCTAssertEqual(waveform.levels(count: Int.min).count, 3)
    }

    func testNonFiniteSamplesAndClipping() {
        var waveform = WaveformEnvelope(sampleRate: .nan)
        for _ in 0..<240 { waveform.append(.infinity); waveform.append(.nan) }
        XCTAssertTrue(waveform.levels(count: 8).allSatisfy { $0 == 0 })
        for _ in 0..<240 { waveform.append(-4) }
        XCTAssertEqual(waveform.levels(count: 8).last, 1)
        _ = WaveformEnvelope(sampleRate: .greatestFiniteMagnitude)
    }
}
