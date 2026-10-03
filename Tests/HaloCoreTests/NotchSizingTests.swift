import XCTest
@testable import HaloCore

final class NotchSizingTests: XCTestCase {
    func testIdleMatchesPhysicalCutoutAndActivityLeavesCameraClear() {
        let idle = sizing(activity: false)
        XCTAssertEqual(idle.closedWidth, 220)
        XCTAssertEqual(idle.headerHeight, 38)
        XCTAssertEqual(sizing(activity: true).closedWidth, 332)
    }

    func testCustomDimensionsNeverShrinkBelowCamera() {
        let value = sizing(custom: true, width: 160, height: 24)
        XCTAssertEqual(value.closedWidth, 220)
        XCTAssertEqual(value.headerHeight, 38)
    }

    func testExpandedPanelContainsCustomClosedSizeAndContent() {
        let value = NotchSizing(hardwareWidth: 220, hardwareHeight: 38, custom: true,
                                closedWidth: 400, closedHeight: 56, expandedWidth: 380,
                                expandedHeight: 200, hasActivity: false)
        XCTAssertEqual(value.expandedWidth, 400)
        XCTAssertEqual(value.expandedHeight, 216)
    }

    func testUnnotchedScreenAndMalformedPreferencesRemainFinite() {
        let value = NotchSizing(hardwareWidth: 0, hardwareHeight: 0, custom: false,
                                closedWidth: .nan, closedHeight: .infinity, expandedWidth: .nan,
                                expandedHeight: .infinity, hasActivity: false)
        XCTAssertEqual(value.closedWidth, 180)
        XCTAssertEqual(value.headerHeight, 30)
        XCTAssertEqual(value.expandedWidth, 420)
        XCTAssertEqual(value.expandedHeight, 240)
    }

    private func sizing(custom: Bool = false, width: Double = 220, height: Double = 38, activity: Bool = false) -> NotchSizing {
        NotchSizing(hardwareWidth: 220, hardwareHeight: 38, custom: custom, closedWidth: width,
                    closedHeight: height, expandedWidth: 420, expandedHeight: 240, hasActivity: activity)
    }
}
