import Foundation

public struct SessionRecord: Identifiable, Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable { case completed, cancelled }

    public var id: UUID
    public var modeID: UUID
    public var modeName: String        // kept so history still reads after a mode is renamed or deleted
    public var startedAt: Date
    public var endedAt: Date
    public var elapsed: TimeInterval
    public var status: Status

    public init(id: UUID = UUID(), modeID: UUID, modeName: String, startedAt: Date, endedAt: Date,
                elapsed: TimeInterval, status: Status) {
        self.id = id; self.modeID = modeID; self.modeName = modeName
        self.startedAt = startedAt; self.endedAt = endedAt; self.elapsed = elapsed; self.status = status
    }
}

public extension SessionRecord {
    /// Switching modes quickly shouldn't fill History with 0-second sessions.
    static let minimumRecordedDuration: TimeInterval = 5
    static func shouldRecord(elapsed: TimeInterval) -> Bool { elapsed >= minimumRecordedDuration }
}

public extension Sequence where Element == SessionRecord {
    /// Only completed sessions count towards focus time.
    var totalCompletedTime: TimeInterval { filter { $0.status == .completed }.reduce(0) { $0 + $1.elapsed } }
}
