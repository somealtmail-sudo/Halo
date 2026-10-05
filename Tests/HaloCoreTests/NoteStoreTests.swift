import XCTest
@testable import HaloCore

final class NoteStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        suite = "HaloNoteTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    func testNewScratchpadIsEmpty() {
        XCTAssertEqual(NoteStore(defaults: defaults).text, "")
    }

    func testLatestEditSurvivesRecreatingStore() {
        let notes = NoteStore(defaults: defaults)
        notes.text = "First draft"
        notes.text = "Remember this\n日本語 🎵\n  keep spacing  "
        XCTAssertEqual(NoteStore(defaults: UserDefaults(suiteName: suite)!).text, notes.text)
    }

    func testClearPersistsWithoutChangingOtherPreferences() {
        defaults.set(true, forKey: "showIsland")
        let notes = NoteStore(defaults: defaults)
        notes.text = "Temporary note"
        notes.text = ""
        XCTAssertEqual(NoteStore(defaults: defaults).text, "")
        XCTAssertTrue(defaults.bool(forKey: "showIsland"))
    }
}
