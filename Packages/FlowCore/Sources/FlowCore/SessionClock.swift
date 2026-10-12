import Foundation

/// Pure elapsed-time state machine. It never reads the system clock: callers pass `now`,
/// so a UI that redraws late (or a test) can't make it drift. Pausing banks the elapsed time.
public struct SessionClock: Codable, Equatable, Sendable {
    public enum State: Codable, Equatable, Sendable {
        case idle
        case running(since: Date, banked: TimeInterval)
        case paused(banked: TimeInterval)
        case finished(elapsed: TimeInterval)
    }

    public private(set) var state: State = .idle
    public private(set) var startedAt: Date?

    public init() {}

    public var isRunning: Bool { if case .running = state { true } else { false } }
    public var isPaused: Bool { if case .paused = state { true } else { false } }
    public var isActive: Bool { isRunning || isPaused }

    public func elapsed(at now: Date) -> TimeInterval {
        switch state {
        case .idle: 0
        case .running(let since, let banked): banked + max(0, now.timeIntervalSince(since))
        case .paused(let banked): banked
        case .finished(let elapsed): elapsed
        }
    }

    public mutating func start(at now: Date) {
        guard case .idle = state else { return }
        startedAt = now
        state = .running(since: now, banked: 0)
    }

    public mutating func pause(at now: Date) {
        guard case .running = state else { return }
        state = .paused(banked: elapsed(at: now))
    }

    public mutating func resume(at now: Date) {
        guard case .paused(let banked) = state else { return }
        state = .running(since: now, banked: banked)
    }

    /// Returns the final elapsed time exactly once. A second call returns nil,
    /// so a double click can never produce two history records.
    public mutating func finish(at now: Date) -> TimeInterval? {
        guard isActive else { return nil }
        let total = elapsed(at: now)
        state = .finished(elapsed: total)
        return total
    }

    public mutating func reset() {
        state = .idle
        startedAt = nil
    }
}
