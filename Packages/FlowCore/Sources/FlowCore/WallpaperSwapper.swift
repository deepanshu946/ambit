import Foundation

/// What one display's desktop looks like. Stored so it can be put back exactly.
public struct DisplayWallpaper: Codable, Equatable, Sendable {
    public var displayID: String       // stable per physical display (a CGDisplay UUID), not a screen index
    public var url: URL
    public var scaling: Int?           // NSImageScaling raw value
    public var allowClipping: Bool?
    public var fillColor: [Double]?    // sRGB r, g, b, a: the letterbox colour

    public init(displayID: String, url: URL, scaling: Int? = nil, allowClipping: Bool? = nil, fillColor: [Double]? = nil) {
        self.displayID = displayID; self.url = url; self.scaling = scaling
        self.allowClipping = allowClipping; self.fillColor = fillColor
    }

    /// NSImageScaling.scaleProportionallyUpOrDown with clipping allowed: macOS's "Fill Screen".
    public static let fillScreenScaling = 3
}

/// The only place that touches the real desktop. The app provides an NSWorkspace version; tests provide a fake.
@MainActor public protocol DesktopBackend {
    func displayIDs() -> [String]
    /// nil when the current wallpaper can't be read back (so it couldn't be restored either).
    func currentWallpaper(on displayID: String) -> DisplayWallpaper?
    /// A check that doesn't change anything: could this wallpaper be set again later? (False for a file Flow can't open.)
    func canRestore(_ wallpaper: DisplayWallpaper) -> Bool
    /// Returns once the change is visible. macOS applies it a moment later, and two sets in quick succession can lose one.
    func setWallpaper(_ wallpaper: DisplayWallpaper, on displayID: String) async throws
}

/// Written to disk before the first change, deleted once everything is back. If Flow dies mid-session,
/// the next launch finds this file and puts the wallpaper back.
public struct RestorePoint: Codable, Equatable, Sendable {
    public var savedAt: Date
    public var originals: [DisplayWallpaper]     // still to put back
    public var applied: [String: String]         // displayID -> path of the picture Flow last set there
}

public enum RestoreResult: Equatable, Sendable {
    case restored
    /// macOS keeps a wallpaper per Space and only exposes the current one. This display isn't showing Flow's picture
    /// right now (another Space, or something else changed it), so the original waits instead of landing on the wrong desktop.
    case pending(displays: Int)
}

public enum WallpaperSwapError: Error, Equatable, LocalizedError {
    case cannotRestoreCurrentWallpaper
    case couldNotChange
    case notOnChangedDesktop
    case couldNotRestore(displays: Int)

    public var errorDescription: String? {
        switch self {
        case .cannotRestoreCurrentWallpaper:
            "Flow couldn’t change your wallpaper because it can’t put your current one back. Wallpapers managed by another app can’t be restored. Choose a photo in System Settings > Wallpaper to use this feature."
        case .couldNotChange:
            "macOS wouldn’t change the wallpaper. Your desktop is unchanged."
        case .notOnChangedDesktop:
            "Flow only changes the desktop where a session started, and you’re on a different one. It will put the first one back when you return to it."
        case .couldNotRestore(let n):
            "Flow couldn’t put your wallpaper back on \(n == 1 ? "a display" : "\(n) displays"). You can set it again in System Settings, and Flow will retry next time it opens."
        }
    }
}

/// Swaps the desktop picture and puts it back. Rules: save before changing, never change what can't be restored
/// (checked first, without changing anything), only restore onto the desktop Flow actually changed, and keep the
/// restore point until a restore has really succeeded.
@MainActor public final class WallpaperSwapper {
    private let backend: DesktopBackend
    private let store: JSONStore<RestorePoint>
    private let now: () -> Date
    public private(set) var restorePoint: RestorePoint?

    public init(backend: DesktopBackend, store: JSONStore<RestorePoint>, now: @escaping () -> Date = Date.init) {
        self.backend = backend; self.store = store; self.now = now
        restorePoint = store.load()
    }

    public var isApplied: Bool { restorePoint != nil }

    private func same(_ url: URL, _ path: String?) -> Bool {
        guard let path else { return false }
        return url.resolvingSymlinksInPath().path == URL(filePath: path).resolvingSymlinksInPath().path
    }

    /// Put `imageURL` on every display Flow can restore. Calling it again (switching modes) keeps the original restore point.
    public func apply(imageURL: URL) async throws {
        if restorePoint == nil { try await applyFirst(imageURL) } else { try await applyAgain(imageURL) }
    }

    private func applyFirst(_ imageURL: URL) async throws {
        // Only displays whose wallpaper Flow has proven it can put back are touched.
        let originals = backend.displayIDs().compactMap { id -> DisplayWallpaper? in
            guard let current = backend.currentWallpaper(on: id), backend.canRestore(current) else { return nil }
            return current
        }
        guard !originals.isEmpty else { throw WallpaperSwapError.cannotRestoreCurrentWallpaper }
        var point = RestorePoint(savedAt: now(), originals: originals, applied: Dictionary(uniqueKeysWithValues: originals.map { ($0.displayID, imageURL.path) }))
        try store.save(point)                                   // before any change, including which picture is about to be set
        restorePoint = point
        var untouched: Set<String> = []
        for original in originals {
            if (try? await backend.setWallpaper(Self.filled(imageURL, like: original), on: original.displayID)) == nil { untouched.insert(original.displayID) }
        }
        if untouched.count == originals.count { forget(); throw WallpaperSwapError.couldNotChange }   // nothing was touched
        if !untouched.isEmpty {
            point.originals.removeAll { untouched.contains($0.displayID) }
            for id in untouched { point.applied[id] = nil }
            restorePoint = point; try? store.save(point)
        }
    }

    /// Switching modes: only change a display that still shows the picture Flow set. Another Space shows something else.
    private func applyAgain(_ imageURL: URL) async throws {
        guard var point = restorePoint else { return }
        let connected = Set(backend.displayIDs())
        var changed = 0
        for original in point.originals where connected.contains(original.displayID) {
            let id = original.displayID
            guard let current = backend.currentWallpaper(on: id), same(current.url, point.applied[id]) else { continue }
            let previous = point.applied[id]
            point.applied[id] = imageURL.path
            restorePoint = point; try? store.save(point)        // intent first
            if (try? await backend.setWallpaper(Self.filled(imageURL, like: original), on: id)) != nil { changed += 1 }
            else { point.applied[id] = previous; restorePoint = point; try? store.save(point) }
        }
        if changed == 0 { throw WallpaperSwapError.notOnChangedDesktop }
    }

    private static func filled(_ imageURL: URL, like original: DisplayWallpaper) -> DisplayWallpaper {
        DisplayWallpaper(displayID: original.displayID, url: imageURL, scaling: DisplayWallpaper.fillScreenScaling,
                         allowClipping: true, fillColor: original.fillColor)
    }

    /// Put each display back, but only where it still shows Flow's picture. Succeeds only if every set call succeeded
    /// (the backend returns once the change is visible). Anything not restored stays in the restore point for later.
    @discardableResult
    public func restore() async throws -> RestoreResult {
        guard var point = restorePoint else { return .restored }
        let connected = Set(backend.displayIDs())
        var remaining: [DisplayWallpaper] = []
        var failed = 0, pending = 0
        for original in point.originals {
            let id = original.displayID
            guard connected.contains(id) else { continue }       // unplugged: can't be restored, doesn't block finishing
            guard let current = backend.currentWallpaper(on: id), same(current.url, point.applied[id]) else {
                remaining.append(original); pending += 1; continue
            }
            do { try await backend.setWallpaper(original, on: id) } catch { remaining.append(original); failed += 1 }
        }
        if remaining.isEmpty { forget() } else { point.originals = remaining; restorePoint = point; try? store.save(point) }
        if failed > 0 { throw WallpaperSwapError.couldNotRestore(displays: failed) }
        return pending > 0 ? .pending(displays: pending) : .restored
    }

    /// Keep whatever is on the desktop now (a mode that opts out of restoring) and drop the restore point.
    public func forget() {
        restorePoint = nil
        store.remove()
    }

    /// At launch and whenever the Space changes: finish a restore that couldn't happen earlier.
    @discardableResult
    public func recoverIfNeeded() async throws -> RestoreResult {
        try await restore()
    }
}
