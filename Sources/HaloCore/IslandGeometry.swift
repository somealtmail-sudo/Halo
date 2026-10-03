import Foundation
import CoreGraphics

/// All rectangles use AppKit's screen coordinates, with the origin at the bottom left.
public struct IslandGeometry: Equatable {
    public let screen: CGRect
    public let panel: CGRect
    public let island: CGRect
    public let hardwareNotch: CGRect?

    public init(screen: CGRect, islandSize: CGSize, panelSize: CGSize, notchSize: CGSize = .zero) {
        self.screen = screen
        let panelWidth = max(panelSize.width, islandSize.width)
        let panelHeight = max(panelSize.height, islandSize.height)
        panel = CGRect(x: screen.midX - panelWidth / 2, y: screen.maxY - panelHeight,
                       width: panelWidth, height: panelHeight)
        island = CGRect(x: screen.midX - islandSize.width / 2, y: screen.maxY - islandSize.height,
                        width: islandSize.width, height: islandSize.height)
        hardwareNotch = notchSize.width > 0 && notchSize.height > 0
            ? CGRect(x: screen.midX - notchSize.width / 2, y: screen.maxY - notchSize.height,
                     width: notchSize.width, height: notchSize.height)
            : nil
    }

    /// CGRect.contains excludes maxY, but the physical screen edge is an entry target.
    public func containsPointer(_ point: CGPoint, retainingHover: Bool = false) -> Bool {
        guard containsInclusive(screen, point) else { return false }
        let margin: CGFloat = retainingHover ? 8 : 0
        if containsInclusive(island.insetBy(dx: -margin, dy: -margin), point) { return true }
        return hardwareNotch.map { containsInclusive($0, point) } ?? false
    }

    /// Transparent shadow margins remain click-through, even during exit hysteresis.
    public func acceptsMouse(at point: CGPoint, expanded: Bool = false) -> Bool {
        guard containsInclusive(screen, point), containsInclusive(island, point) else { return false }
        // Match NotchShape's quadratic top shoulders and bottom corners. Hover may retain
        // an 8pt margin, but clicks in the actual transparent contour pass through.
        let shoulder: CGFloat = 8
        let radius = min(expanded ? 22.0 : 12.0, max(0, island.height - shoulder))
        let depth = island.maxY - point.y
        let inset: CGFloat
        if depth < shoulder {
            let progress = sqrt(max(0, depth / shoulder))
            inset = shoulder * (2 * progress - progress * progress)
        } else if radius > 0 && depth > island.height - radius {
            let progress = 1 - sqrt(max(0, (island.height - depth) / radius))
            inset = shoulder + radius * progress * progress
        } else {
            inset = shoulder
        }
        return point.x >= island.minX + inset && point.x <= island.maxX - inset
    }

    private func containsInclusive(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }
}
