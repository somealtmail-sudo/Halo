import XCTest
@testable import HaloCore

final class HaloCoreTests: XCTestCase {
    func testFragmentedStreamAndMultipleFrames() throws {
        var buffer = LineBuffer()
        XCTAssertTrue(buffer.append(Data("{\"a\":".utf8)).isEmpty)
        XCTAssertEqual(buffer.append(Data("1}\n{}\nrest".utf8)).map { String(decoding: $0, as: UTF8.self) }, ["{\"a\":1}", "{}"])
        XCTAssertEqual(buffer.append(Data("\n".utf8)).count, 1)
    }
    func testMediaProgressPauseClampAndBrowserParent() throws {
        let json = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari","playing":true,"title":"Video","durationMicros":120000000,"elapsedTimeMicros":30000000,"timestampEpochMicros":1000000000,"playbackRate":2}}"#
        let snapshot = try JSONDecoder().decode(MediaEnvelope.self, from: Data(json.utf8)).payload
        XCTAssertEqual(snapshot.sourceID, "com.apple.Safari")
        XCTAssertEqual(snapshot.position(at: Date(timeIntervalSince1970: 1010)), 50)
        XCTAssertEqual(snapshot.position(at: Date(timeIntervalSince1970: 2000)), 120)
        var paused = snapshot
        paused.playing = false
        XCTAssertEqual(paused.position(at: Date(timeIntervalSince1970: 2000)), 30)
    }
    func testEmptySnapshotClearsSessionAndMissingFields() throws {
        let envelope = try JSONDecoder().decode(MediaEnvelope.self, from: Data(#"{"type":"data","diff":false,"payload":{}}"#.utf8))
        XCTAssertFalse(envelope.payload.hasSession)
        XCTAssertFalse(envelope.payload.isPlaying)
        XCTAssertEqual(envelope.payload.duration, 0)
    }
    func testPauseFlagBeforeTimingUpdateDoesNotJumpBack() {
        let now = Date(timeIntervalSince1970: 1000)
        let playing = MediaSnapshot(bundleIdentifier: "com.spotify.client", playing: true, title: "Track", duration: 300, elapsed: 90, timestamp: now)
        var paused = playing
        paused.playing = false
        let reconciled = paused.reconciled(after: playing, at: now.addingTimeInterval(20))
        XCTAssertEqual(reconciled.position(at: now.addingTimeInterval(30)), 110)
        paused.elapsedTimeMicros = 112_000_000
        XCTAssertEqual(paused.reconciled(after: reconciled, at: now.addingTimeInterval(30)).position(at: now), 112)
    }
    func testPausedMusicDoesNotHideOtherAudio() {
        var snapshot = MediaSnapshot(bundleIdentifier: "com.apple.Music", playing: false, title: "Paused song")
        XCTAssertTrue(snapshot.shouldShowMetadata(activeAudioSources: []))
        XCTAssertTrue(snapshot.shouldShowMetadata(activeAudioSources: ["com.apple.Music"]))
        XCTAssertFalse(snapshot.shouldShowMetadata(activeAudioSources: ["com.apple.Safari"]))
        snapshot.playing = true
        XCTAssertTrue(snapshot.shouldShowMetadata(activeAudioSources: ["com.apple.Safari"]))
    }
    func testRepeatedStalePauseSnapshotsKeepReconciledPosition() {
        let now = Date(timeIntervalSince1970: 1000)
        let playing = MediaSnapshot(bundleIdentifier: "com.spotify.client", playing: true, title: "Track", duration: 300, elapsed: 90, timestamp: now)
        var rawPause = playing
        rawPause.playing = false
        let firstPause = rawPause.reconciled(after: playing, at: now.addingTimeInterval(20))
        var artworkUpdate = rawPause
        artworkUpdate.artworkData = "updated-artwork"
        let secondPause = artworkUpdate.reconciled(after: rawPause, displayed: firstPause, at: now.addingTimeInterval(25))
        XCTAssertEqual(secondPause.position(at: now.addingTimeInterval(50)), 110)
        XCTAssertEqual(secondPause.artworkData, "updated-artwork")
        var seekUpdate = rawPause
        seekUpdate.elapsedTimeMicros = 40_000_000
        seekUpdate.timestampEpochMicros = now.addingTimeInterval(30).timeIntervalSince1970 * 1_000_000
        XCTAssertEqual(seekUpdate.reconciled(after: artworkUpdate, displayed: secondPause, at: now.addingTimeInterval(30)).position(at: now), 40)
    }
    func testTimerSurvivesSleepAndCompletesOnce() {
        var timer = FocusClock()
        let now = Date(timeIntervalSince1970: 100)
        timer.start(minutes: 5, now: now)
        XCTAssertEqual(timer.remaining(at: now.addingTimeInterval(60)), 240)
        XCTAssertTrue(timer.tick(now: now.addingTimeInterval(400)))
        XCTAssertFalse(timer.tick(now: now.addingTimeInterval(401)))
        XCTAssertTrue(timer.completed)
    }
    func testTimerPauseResumeDoesNotCountPausedTime() {
        var timer = FocusClock()
        let now = Date(timeIntervalSince1970: 100)
        timer.start(minutes: 25, now: now)
        timer.pause(now: now.addingTimeInterval(90))
        XCTAssertEqual(timer.remaining(at: now.addingTimeInterval(900)), 1410)
        timer.resume(now: now.addingTimeInterval(900))
        XCTAssertEqual(timer.remaining(at: now.addingTimeInterval(910)), 1400)
        timer.reset()
        XCTAssertFalse(timer.isActive)
    }
}
