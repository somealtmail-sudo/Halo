import Foundation

public struct FocusClock: Equatable, Sendable {
    public private(set) var duration: TimeInterval = 25 * 60
    public private(set) var deadline: Date?
    public private(set) var pausedRemaining: TimeInterval?
    public private(set) var completed = false
    public init() {}
    public var isRunning: Bool { deadline != nil }
    public var isPaused: Bool { pausedRemaining != nil }
    public var isActive: Bool { isRunning || isPaused }
    public func remaining(at now: Date) -> TimeInterval {
        if let deadline { return max(0, deadline.timeIntervalSince(now)) }
        return pausedRemaining ?? (completed ? 0 : duration)
    }
    public mutating func start(minutes: Int, now: Date) {
        duration = Double(max(1, minutes)) * 60
        deadline = now.addingTimeInterval(duration)
        pausedRemaining = nil
        completed = false
    }
    public mutating func pause(now: Date) {
        guard isRunning else { return }
        if remaining(at: now) <= 0 { _ = tick(now: now); return }
        pausedRemaining = remaining(at: now)
        deadline = nil
    }
    public mutating func resume(now: Date) {
        guard let pausedRemaining else { return }
        deadline = now.addingTimeInterval(pausedRemaining)
        self.pausedRemaining = nil
    }
    @discardableResult public mutating func tick(now: Date) -> Bool {
        guard let deadline, now >= deadline else { return false }
        self.deadline = nil
        pausedRemaining = nil
        completed = true
        return true
    }
    public mutating func reset() { deadline = nil; pausedRemaining = nil; completed = false }
}

public func clockText(_ seconds: TimeInterval) -> String {
    let value = Int(max(0, seconds.isFinite ? seconds : 0).rounded(.up))
    if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60) }
    return String(format: "%d:%02d", value / 60, value % 60)
}
