import Foundation

/// Immediate entry, a short cancellable exit, and one expansion per pointer visit.
public struct IslandHover {
    public enum Action: Equatable { case expand, collapse }
    public private(set) var inside = false
    public private(set) var exitDeadline: TimeInterval?
    private var expansionConsumed = false
    public let exitDelay: TimeInterval

    public init(exitDelay: TimeInterval = 0.18) { self.exitDelay = exitDelay }

    public mutating func reset() {
        inside = false
        exitDeadline = nil
        expansionConsumed = false
    }

    /// Also handles openings initiated by the menu or a file drop while the pointer is outside.
    public mutating func expansionChanged(to expanded: Bool, at time: TimeInterval) {
        if inside {
            // Closing explicitly must not re-open until the pointer leaves and returns.
            expansionConsumed = true
        } else {
            exitDeadline = expanded ? time + exitDelay : nil
        }
    }

    public mutating func update(inside isInside: Bool, expanded: Bool, hoverEnabled: Bool,
                                pinned: Bool, gestureHeld: Bool, at time: TimeInterval) -> Action? {
        if isInside != inside {
            inside = isInside
            expansionConsumed = isInside && expanded
            exitDeadline = isInside ? nil : time + exitDelay
        }
        if isInside {
            exitDeadline = nil
            if expanded { expansionConsumed = true }
            if hoverEnabled && !expanded && !expansionConsumed {
                expansionConsumed = true
                return .expand
            }
        } else if expanded {
            if exitDeadline == nil { exitDeadline = time + exitDelay }
            if !pinned && !gestureHeld, let exitDeadline, time >= exitDeadline {
                self.exitDeadline = nil
                return .collapse
            }
        } else {
            exitDeadline = nil
        }
        return nil
    }
}
