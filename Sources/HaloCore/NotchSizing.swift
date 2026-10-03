import Foundation

/// Shared drawing/window dimensions. The physical camera cutout is a hard minimum.
public struct NotchSizing: Equatable, Sendable {
    public let closedWidth: Double
    public let headerHeight: Double
    public let expandedWidth: Double
    public let expandedHeight: Double

    public init(hardwareWidth: Double, hardwareHeight: Double, custom: Bool,
                closedWidth: Double, closedHeight: Double,
                expandedWidth: Double, expandedHeight: Double, hasActivity: Bool) {
        let physicalWidth = Self.finite(hardwareWidth, fallback: 0, range: 0...600)
        let physicalHeight = Self.finite(hardwareHeight, fallback: 0, range: 0...100)
        let requestedWidth = Self.finite(closedWidth, fallback: 220, range: 160...400)
        let requestedHeight = Self.finite(closedHeight, fallback: 38, range: 24...56)
        let automaticWidth = physicalWidth > 0 ? physicalWidth : 180
        let automaticHeight = physicalHeight > 0 ? physicalHeight : 30
        let baseWidth = max(physicalWidth, custom ? requestedWidth : automaticWidth)
        self.headerHeight = max(physicalHeight, custom ? requestedHeight : automaticHeight)
        self.closedWidth = max(baseWidth, hasActivity ? physicalWidth + 112 : 0)
        self.expandedWidth = max(self.closedWidth, Self.finite(expandedWidth, fallback: 420, range: 380...600))
        self.expandedHeight = max(self.headerHeight + 160, Self.finite(expandedHeight, fallback: 240, range: 200...360))
    }

    private static func finite(_ value: Double, fallback: Double, range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}
