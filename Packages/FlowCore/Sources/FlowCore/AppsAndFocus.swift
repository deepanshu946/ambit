import Foundation

@MainActor public protocol AppsBackend {
    var ownBundleID: String? { get }
    func isRunning(_ bundleID: String) -> Bool
    func isHidden(_ bundleID: String) -> Bool
    /// Asks the app to hide. NSRunningApplication reports `false` even when it works, so callers must check `isHidden` instead.
    func hide(_ bundleID: String)
    func unhide(_ bundleID: String)
    func launch(_ bundleID: String) async throws
}

public struct HiddenAppsRecord: Codable, Equatable, Sendable {
    public var hidden: [String]
}

/// Hides distracting apps and opens the ones a mode wants. It never quits anything. It only unhides apps it hid
/// itself, so an app you hid on purpose stays hidden.
@MainActor public final class AppsEffect {
    private let backend: AppsBackend
    private let store: JSONStore<HiddenAppsRecord>
    public private(set) var record: HiddenAppsRecord?

    public init(backend: AppsBackend, store: JSONStore<HiddenAppsRecord>) {
        self.backend = backend; self.store = store
        record = store.load()
    }

    public var isApplied: Bool { !(record?.hidden.isEmpty ?? true) }
    public var hiddenCount: Int { record?.hidden.count ?? 0 }

    /// Hide `ids` (those that are running and visible) and give back anything an earlier mode hid that this one doesn't.
    /// An app only stays in the record if it really became hidden; the hide call's own result can't be trusted.
    public func hide(_ ids: [String]) async {
        var current = record ?? HiddenAppsRecord(hidden: [])
        for id in current.hidden where !ids.contains(id) {
            if backend.isHidden(id) { backend.unhide(id) }
            current.hidden.removeAll { $0 == id }
        }
        var asked: [String] = []
        for id in ids where id != backend.ownBundleID && !current.hidden.contains(id) && backend.isRunning(id) && !backend.isHidden(id) {
            current.hidden.append(id)
            record = current; try? store.save(current)       // before the change, so a crash can't forget an app it hid
            backend.hide(id)
            asked.append(id)
        }
        for _ in 0..<10 where asked.contains(where: { !backend.isHidden($0) }) {      // macOS hides a moment later
            try? await Task.sleep(for: .milliseconds(100))
        }
        for id in asked where !backend.isHidden(id) { current.hidden.removeAll { $0 == id } }   // didn't hide, so it isn't ours to restore
        commit(current)
    }

    /// Launch the apps that aren't already running. Returns the ones that couldn't be launched.
    public func open(_ ids: [String]) async -> [String] {
        var failed: [String] = []
        for id in ids where !backend.isRunning(id) {
            do { try await backend.launch(id) } catch { failed.append(id) }
        }
        return failed
    }

    /// Unhide what Flow hid, but only apps that are still running and still hidden.
    public func restore() {
        for id in record?.hidden ?? [] where backend.isRunning(id) && backend.isHidden(id) { backend.unhide(id) }
        forget()
    }

    public func forget() {
        record = nil
        store.remove()
    }

    private func commit(_ current: HiddenAppsRecord) {
        if current.hidden.isEmpty { forget() } else { record = current; try? store.save(current) }
    }
}

@MainActor public protocol ShortcutsBackend {
    func run(_ name: String) async throws
    func names() async -> [String]
}

public struct FocusRecord: Codable, Equatable, Sendable {
    public var offShortcut: String?
}

/// macOS has no API to set a Focus. The supported way is a shortcut that contains "Set Focus", so a mode names one
/// shortcut that turns a Focus on and one that turns it off, and Flow runs them.
@MainActor public final class FocusEffect {
    private let backend: ShortcutsBackend
    private let store: JSONStore<FocusRecord>
    public private(set) var record: FocusRecord?

    public init(backend: ShortcutsBackend, store: JSONStore<FocusRecord>) {
        self.backend = backend; self.store = store
        record = store.load()
    }

    public var isApplied: Bool { record != nil }

    /// nil or empty `on` means this mode doesn't use Focus, so one an earlier mode turned on is turned off.
    public func apply(on: String?, off: String?) async throws {
        guard let on, !on.isEmpty else { _ = try await restore(); return }
        if record != nil { return }                             // already on from the previous mode
        let fresh = FocusRecord(offShortcut: off?.isEmpty == false ? off : nil)
        try store.save(fresh); record = fresh                   // before turning it on
        do { try await backend.run(on) } catch { forget(); throw error }
    }

    public enum Outcome: Equatable, Sendable { case nothingToRestore, turnedOff, noOffShortcut }

    @discardableResult
    public func restore() async throws -> Outcome {
        guard let record else { return .nothingToRestore }
        guard let off = record.offShortcut else { forget(); return .noOffShortcut }
        try await backend.run(off)                              // on failure the record stays, so it can be retried
        forget()
        return .turnedOff
    }

    public func forget() {
        record = nil
        store.remove()
    }
}
