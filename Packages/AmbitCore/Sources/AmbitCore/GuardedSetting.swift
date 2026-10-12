import Foundation

/// One scalar thing on the Mac that a mode can change: the Dock's auto-hide, light or dark, the output volume.
@MainActor public protocol SettingBackend {
    associatedtype Value: Codable & Equatable & Sendable
    /// Throws when it can't be read (no permission, no such device, not adjustable).
    func current() async throws -> Value
    func set(_ value: Value) async throws
    /// Settings that read back slightly different (volume) override this.
    func matches(_ a: Value, _ b: Value) -> Bool
}

public extension SettingBackend {
    func matches(_ a: Value, _ b: Value) -> Bool { a == b }
}

public struct SettingRestorePoint<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var original: Value
    public var applied: Value
}

public enum SettingRestoreOutcome: Equatable, Sendable {
    case nothingToRestore
    case restored
    /// The person changed it themselves during the session, so Ambit left their choice alone.
    case leftAlone
}

/// Change a setting, remember the original, and give it back later. Rules: save before changing, change nothing that
/// is already as wanted, and only undo a change that is still Ambit's. If the person has moved the setting since,
/// that is their decision and Ambit keeps its hands off.
@MainActor public final class GuardedSetting<Backend: SettingBackend> {
    private let backend: Backend
    private let store: JSONStore<SettingRestorePoint<Backend.Value>>
    public private(set) var point: SettingRestorePoint<Backend.Value>?

    public init(backend: Backend, store: JSONStore<SettingRestorePoint<Backend.Value>>) {
        self.backend = backend; self.store = store
        point = store.load()
    }

    public var isApplied: Bool { point != nil }

    /// Make the setting `target`. nil means this mode doesn't touch it, so anything an earlier mode changed is given back.
    public func apply(_ target: Backend.Value?) async throws {
        guard let target else { _ = try await restore(); return }
        if var existing = point {
            if let now = try? await backend.current(), backend.matches(now, existing.applied) {
                existing.applied = target                                  // still Ambit's: change it again, keep the first original
                try store.save(existing); point = existing
                try await backend.set(target)
                return
            }
            forget()                                                       // the person took over; their value is the new starting point
        }
        let original = try await backend.current()
        if backend.matches(original, target) { return }                    // already as wanted: nothing to remember or undo
        let fresh = SettingRestorePoint(original: original, applied: target)
        try store.save(fresh)                                              // before any change
        point = fresh
        do { try await backend.set(target) } catch { forget(); throw error }
    }

    /// Put the original back, but only if the setting still holds what Ambit set. On failure the restore point is kept.
    @discardableResult
    public func restore() async throws -> SettingRestoreOutcome {
        guard let p = point else { return .nothingToRestore }
        guard let now = try? await backend.current(), backend.matches(now, p.applied) else {
            forget()
            return .leftAlone
        }
        try await backend.set(p.original)
        forget()
        return .restored
    }

    /// Keep whatever the setting is now (a mode that opts out of restoring).
    public func forget() {
        point = nil
        store.remove()
    }
}
