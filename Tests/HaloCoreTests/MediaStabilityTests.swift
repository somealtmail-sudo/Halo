import XCTest
@testable import HaloCore

final class MediaStabilityTests: XCTestCase {
    func testOversizedWholeFrameIsDiscardedAndFollowingFramesSurvive() {
        var buffer = LineBuffer(maximumLineBytes: 4)
        let lines = buffer.append(Data("12345\nok\n1234\n".utf8))
        XCTAssertEqual(lines.map { String(decoding: $0, as: UTF8.self) }, ["ok", "1234"])
    }

    func testOversizedFragmentCannotBecomeAValidSuffixFrame() {
        var buffer = LineBuffer(maximumLineBytes: 4)
        XCTAssertTrue(buffer.append(Data("12345".utf8)).isEmpty)
        XCTAssertTrue(buffer.append(Data("{}".utf8)).isEmpty)
        let lines = buffer.append(Data("\n{}\n".utf8))
        XCTAssertEqual(lines.map { String(decoding: $0, as: UTF8.self) }, ["{}"])
    }

    func testLimitCountsAllFragmentsAndRetainsTheNextPartialFrame() {
        var buffer = LineBuffer(maximumLineBytes: 4)
        XCTAssertTrue(buffer.append(Data("123".utf8)).isEmpty)
        XCTAssertEqual(buffer.append(Data("4\nabc".utf8)), [Data("1234".utf8)])
        XCTAssertEqual(buffer.append(Data("de\nx".utf8)), [])
        XCTAssertEqual(buffer.append(Data("y\n".utf8)), [Data("xy".utf8)])
    }

    func testNonFiniteTimingFieldsDoNotProduceInvalidProgress() {
        let now = Date(timeIntervalSince1970: 1000)
        var snapshot = MediaSnapshot(bundleIdentifier: "com.spotify.client", playing: true,
                                     duration: 300, elapsed: 90, timestamp: now)
        snapshot.timestampEpochMicros = .nan
        snapshot.playbackRate = .infinity
        XCTAssertEqual(snapshot.position(at: now.addingTimeInterval(20)), 90)
        snapshot.timestampEpochMicros = now.timeIntervalSince1970 * 1_000_000
        XCTAssertEqual(snapshot.position(at: now.addingTimeInterval(20)), 110)
        snapshot.playbackRate = .greatestFiniteMagnitude
        XCTAssertEqual(snapshot.position(at: now.addingTimeInterval(20)), 300)
        snapshot.durationMicros = nil
        XCTAssertEqual(snapshot.position(at: now.addingTimeInterval(20)), 90)
    }
}
