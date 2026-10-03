import XCTest
import CoreGraphics
@testable import HaloCore

final class IslandInteractionTests: XCTestCase {
    func testPanelAndIslandTouchExactScreenEdgeOnOffsetDisplay() {
        let geometry = IslandGeometry(screen: CGRect(x: -1920, y: 340, width: 1920, height: 1080),
                                      islandSize: CGSize(width: 500, height: 260),
                                      panelSize: CGSize(width: 648, height: 400))
        XCTAssertEqual(geometry.panel.maxY, 1420)
        XCTAssertEqual(geometry.island.maxY, 1420)
        XCTAssertEqual(geometry.panel.midX, -960)
        XCTAssertTrue(geometry.containsPointer(CGPoint(x: -960, y: 1420)))
        XCTAssertFalse(geometry.containsPointer(CGPoint(x: -960, y: 1421), retainingHover: true))
    }

    func testHiddenNotchAndHoverHysteresisDoNotCaptureTransparentMargins() {
        let geometry = IslandGeometry(screen: CGRect(x: 0, y: 0, width: 1500, height: 1000),
                                      islandSize: CGSize(width: 160, height: 24),
                                      panelSize: CGSize(width: 648, height: 400),
                                      notchSize: CGSize(width: 210, height: 32))
        XCTAssertTrue(geometry.containsPointer(CGPoint(x: 650, y: 980)))
        let justBelowIsland = CGPoint(x: 750, y: 970)
        XCTAssertTrue(geometry.containsPointer(justBelowIsland)) // hidden notch
        XCTAssertFalse(geometry.acceptsMouse(at: justBelowIsland))
        let besideIsland = CGPoint(x: 835, y: 960)
        XCTAssertFalse(geometry.containsPointer(besideIsland))
        XCTAssertFalse(geometry.containsPointer(besideIsland, retainingHover: true))
        let nearBottom = CGPoint(x: 750, y: 965)
        XCTAssertFalse(geometry.containsPointer(nearBottom))
        XCTAssertFalse(geometry.containsPointer(nearBottom, retainingHover: true))
        let marginPoint = CGPoint(x: 837, y: 974)
        XCTAssertTrue(geometry.containsPointer(marginPoint, retainingHover: true))
        XCTAssertFalse(geometry.acceptsMouse(at: marginPoint))
        let noNotch = IslandGeometry(screen: geometry.screen,
                                    islandSize: CGSize(width: 160, height: 24),
                                    panelSize: CGSize(width: 648, height: 400))
        XCTAssertFalse(noNotch.containsPointer(marginPoint))
        XCTAssertTrue(noNotch.containsPointer(marginPoint, retainingHover: true))
    }

    func testEntryExpandsImmediatelyAndExitWaits180Milliseconds() {
        var hover = IslandHover()
        XCTAssertEqual(hover.update(inside: true, expanded: false, hoverEnabled: true, pinned: false, gestureHeld: false, at: 10), .expand)
        XCTAssertNil(hover.update(inside: false, expanded: true, hoverEnabled: true, pinned: false, gestureHeld: false, at: 11))
        XCTAssertNil(hover.update(inside: false, expanded: true, hoverEnabled: true, pinned: false, gestureHeld: false, at: 11.17))
        XCTAssertEqual(hover.update(inside: false, expanded: true, hoverEnabled: true, pinned: false, gestureHeld: false, at: 11.19), .collapse)
    }

    func testTransparentShouldersAndBottomCornersAreClickThrough() {
        let geometry = IslandGeometry(screen: CGRect(x: 0, y: 0, width: 1500, height: 1000),
                                      islandSize: CGSize(width: 420, height: 240),
                                      panelSize: CGSize(width: 468, height: 280))
        XCTAssertTrue(geometry.acceptsMouse(at: CGPoint(x: 540, y: 1000), expanded: true))
        XCTAssertFalse(geometry.acceptsMouse(at: CGPoint(x: 542, y: 996), expanded: true))
        XCTAssertTrue(geometry.acceptsMouse(at: CGPoint(x: 548, y: 996), expanded: true))
        XCTAssertFalse(geometry.acceptsMouse(at: CGPoint(x: 542, y: 900), expanded: true))
        XCTAssertTrue(geometry.acceptsMouse(at: CGPoint(x: 548, y: 900), expanded: true))
        XCTAssertFalse(geometry.acceptsMouse(at: CGPoint(x: 550, y: 762), expanded: true))
        XCTAssertTrue(geometry.acceptsMouse(at: CGPoint(x: 567, y: 762), expanded: true))
        XCTAssertTrue(geometry.acceptsMouse(at: CGPoint(x: 750, y: 760), expanded: true))
    }

    func testReturnCancelsExitAndManualCloseWaitsForFreshVisit() {
        var hover = IslandHover()
        _ = hover.update(inside: true, expanded: false, hoverEnabled: true, pinned: false, gestureHeld: false, at: 1)
        _ = hover.update(inside: false, expanded: true, hoverEnabled: true, pinned: false, gestureHeld: false, at: 2)
        XCTAssertNil(hover.update(inside: true, expanded: true, hoverEnabled: true, pinned: false, gestureHeld: false, at: 2.1))
        XCTAssertNil(hover.exitDeadline)
        hover.expansionChanged(to: false, at: 2.2)
        XCTAssertNil(hover.update(inside: true, expanded: false, hoverEnabled: true, pinned: false, gestureHeld: false, at: 3))
        _ = hover.update(inside: false, expanded: false, hoverEnabled: true, pinned: false, gestureHeld: false, at: 4)
        XCTAssertEqual(hover.update(inside: true, expanded: false, hoverEnabled: true, pinned: false, gestureHeld: false, at: 5), .expand)
    }

    func testPinAndHeldDragDeferExitThenRetryWithoutPointerCrossing() {
        var hover = IslandHover()
        hover.expansionChanged(to: true, at: 1)
        XCTAssertNil(hover.update(inside: false, expanded: true, hoverEnabled: true, pinned: true, gestureHeld: false, at: 2))
        XCTAssertNil(hover.update(inside: false, expanded: true, hoverEnabled: true, pinned: false, gestureHeld: true, at: 3))
        XCTAssertEqual(hover.update(inside: false, expanded: true, hoverEnabled: true, pinned: false, gestureHeld: false, at: 4), .collapse)
    }

    func testDisabledHoverStillAllowsExitOfExplicitOpening() {
        var hover = IslandHover()
        XCTAssertNil(hover.update(inside: true, expanded: false, hoverEnabled: false, pinned: false, gestureHeld: false, at: 1))
        hover.expansionChanged(to: true, at: 2)
        _ = hover.update(inside: false, expanded: true, hoverEnabled: false, pinned: false, gestureHeld: false, at: 3)
        XCTAssertEqual(hover.update(inside: false, expanded: true, hoverEnabled: false, pinned: false, gestureHeld: false, at: 3.19), .collapse)
    }
}
