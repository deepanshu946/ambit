import AppKit
import FlowCore

/// The real desktop, through NSWorkspace. Everything with a rule in it lives in FlowCore's WallpaperSwapper.
@MainActor struct NSWorkspaceBackend: DesktopBackend {
    private func displayID(of screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private func screen(for id: String) -> NSScreen? { NSScreen.screens.first { displayID(of: $0) == id } }

    func displayIDs() -> [String] { NSScreen.screens.compactMap(displayID(of:)) }

    func currentWallpaper(on id: String) -> DisplayWallpaper? {
        guard let screen = screen(for: id), let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        let options = NSWorkspace.shared.desktopImageOptions(for: screen)
        var fill: [Double]?
        if let color = (options?[.fillColor] as? NSColor)?.usingColorSpace(.sRGB) {
            fill = [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
        }
        return DisplayWallpaper(displayID: id, url: url,
                                scaling: (options?[.imageScaling] as? NSNumber)?.intValue,
                                allowClipping: (options?[.allowClipping] as? NSNumber)?.boolValue,
                                fillColor: fill)
    }

    /// The same check macOS itself makes before setting a picture. A file inside another app's container fails it.
    func canRestore(_ wallpaper: DisplayWallpaper) -> Bool {
        FileManager.default.isReadableFile(atPath: wallpaper.url.path)
    }

    func setWallpaper(_ wallpaper: DisplayWallpaper, on id: String) async throws {
        for _ in 0..<2 {                                  // one retry: a set can be lost if another lands just before it
            try issue(wallpaper, on: id)
            if await settled(wallpaper, on: id) { return }
        }
        throw DesktopError.didNotSettle
    }

    private func issue(_ wallpaper: DisplayWallpaper, on id: String) throws {
        guard let screen = screen(for: id) else { throw CocoaError(.fileNoSuchFile) }
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        if let scaling = wallpaper.scaling { options[.imageScaling] = NSNumber(value: scaling) }
        if let clipping = wallpaper.allowClipping { options[.allowClipping] = NSNumber(value: clipping) }
        if let c = wallpaper.fillColor, c.count == 4 { options[.fillColor] = NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: c[3]) }
        try NSWorkspace.shared.setDesktopImageURL(wallpaper.url, for: screen, options: options)
    }

    /// macOS applies the change a moment after the call returns, so wait until the desktop reads back as the new image.
    private func settled(_ wallpaper: DisplayWallpaper, on id: String) async -> Bool {
        func matches() -> Bool {
            currentWallpaper(on: id)?.url.resolvingSymlinksInPath().path == wallpaper.url.resolvingSymlinksInPath().path
        }
        for _ in 0..<20 {
            if matches() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return matches()
    }
}

enum DesktopError: LocalizedError {
    case didNotSettle
    var errorDescription: String? { "macOS didn’t apply the wallpaper change." }
}

/// Applies a mode to the Mac and undoes it, one operation at a time. Every effect follows the same rules: save what was
/// there before changing it, change only what it can put back, and undo only what is still its own change.
/// Returns user-facing text for anything that went wrong; never throws into the UI.
@Observable
final class SystemEffects {
    /// Shown in the session row while something is in progress, e.g. "Downloading wallpaper…".
    private(set) var status: String?
    /// What Flow has changed right now, e.g. ["wallpaper", "Dock", "volume"].
    private(set) var applied: [String] = []
    private(set) var wallpaperApplied = false
    /// Told about problems (and when a waiting restore finishes) that happen outside a button press, e.g. after a Space change.
    @ObservationIgnored var onNotice: (@MainActor (String?) -> Void)?
    static let pendingNotice = "Flow will put your wallpaper back when you return to the desktop where this session started."
    @ObservationIgnored private var sessionActive = false
    @ObservationIgnored private var spaceObserver: NSObjectProtocol?
    @ObservationIgnored private var lastOperation: Task<Void, Never>?

    @ObservationIgnored private let library: WallpaperLibrary
    @ObservationIgnored private let swapper: WallpaperSwapper
    @ObservationIgnored private let dock = GuardedSetting(backend: SystemEventsSetting(kind: .dockAutohide), store: .appSupport("restore-dock"))
    @ObservationIgnored private let appearance = GuardedSetting(backend: SystemEventsSetting(kind: .darkMode), store: .appSupport("restore-appearance"))
    @ObservationIgnored private let volumeBackend = OutputVolumeSetting()
    @ObservationIgnored private let volume = GuardedSetting(backend: OutputVolumeSetting(), store: .appSupport("restore-volume"))
    @ObservationIgnored private let apps = AppsEffect(backend: WorkspaceApps(), store: .appSupport("restore-apps"))
    @ObservationIgnored private let focus = FocusEffect(backend: ShortcutsCLI(), store: .appSupport("restore-focus"))

    init(library: WallpaperLibrary, swapper: WallpaperSwapper? = nil) {
        self.library = library
        self.swapper = swapper ?? WallpaperSwapper(backend: NSWorkspaceBackend(), store: .appSupport("restore-point"))
        refresh()
        // macOS keeps a wallpaper per Space, so a restore that had to wait is retried when the Space changes.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.spaceChanged() }
        }
    }

    private func refresh() {
        wallpaperApplied = swapper.isApplied
        var items: [String] = []
        if swapper.isApplied { items.append("wallpaper") }
        if appearance.isApplied { items.append("appearance") }
        if dock.isApplied { items.append("Dock") }
        if volume.isApplied { items.append("volume") }
        if apps.isApplied { items.append(apps.hiddenCount == 1 ? "1 app hidden" : "\(apps.hiddenCount) apps hidden") }
        if focus.isApplied { items.append("Focus") }
        applied = items
    }

    /// True while there is something to put back (used when quitting).
    var needsRestore: Bool { swapper.isApplied || dock.isApplied || appearance.isApplied || volume.isApplied || apps.isApplied || focus.isApplied }

    private func spaceChanged() {
        guard swapper.isApplied, !sessionActive else { return }   // never restore under a running session
        Task {
            let problem = await serialized { [self] in
                defer { refresh() }
                guard !sessionActive, swapper.isApplied else { return nil as String? }
                return await restoreWallpaper()
            }
            if !swapper.isApplied { onNotice?(nil) } else if let problem, problem != Self.pendingNotice { onNotice?(problem) }
        }
    }

    /// Runs one operation at a time, in order, so an end followed straight away by a start can't interleave.
    private func serialized<T: Sendable>(_ operation: @escaping @MainActor () async -> T) async -> T {
        let previous = lastOperation
        let task = Task { @MainActor () -> T in
            await previous?.value
            return await operation()
        }
        lastOperation = Task { _ = await task.value }
        return await task.value
    }

    // MARK: Launch

    /// At launch: a leftover restore point means a session never finished (crash, force quit).
    func recoverFromCrash() async -> [String] {
        await serialized { [self] in
            guard needsRestore else { return [] }
            defer { refresh() }
            let notices = await restoreAll()
            return notices.isEmpty ? ["Flow didn’t close cleanly last time, so it put your Mac back the way it was."] : notices
        }
    }

    // MARK: Start of a session

    /// Apply `mode`. `stillCurrent` lets a slow download notice the session already ended.
    func enter(_ mode: Mode, stillCurrent: @escaping @MainActor () -> Bool) async -> [String] {
        await serialized { [self] in await performEnter(mode, stillCurrent: stillCurrent) }
    }

    private func performEnter(_ mode: Mode, stillCurrent: @MainActor () -> Bool) async -> [String] {
        guard stillCurrent() else { return [] }          // the session ended while this was queued
        sessionActive = true
        defer { status = nil; refresh() }
        var notices: [String] = []
        func attempt(_ work: () async throws -> Void) async {
            do { try await work() } catch { notices.append(error.localizedDescription) }
        }

        // Quick things first; the wallpaper may need a download, so it goes last.
        let dark: Bool? = mode.look.appearance == .system ? nil : (mode.look.appearance == .dark)
        await attempt { try await appearance.apply(dark) }
        await attempt { try await dock.apply(mode.system.dockAutoHide) }
        await attempt { try await volume.apply(try mode.system.outputVolume.map { try volumeBackend.target(level: $0) }) }
        await apps.hide(mode.system.hideApps)
        let notOpened = await apps.open(mode.system.openApps)
        if !notOpened.isEmpty { notices.append("Couldn’t open \(notOpened.map { AppInfo(bundleID: $0).name }.formatted(.list(type: .and))).") }
        await attempt { try await focus.apply(on: mode.system.focusShortcut, off: mode.system.focusEndShortcut) }
        if let problem = await enterWallpaper(mode, stillCurrent: stillCurrent) { notices.append(problem) }
        return notices
    }

    private func enterWallpaper(_ mode: Mode, stillCurrent: @MainActor () -> Bool) async -> String? {
        let image: URL
        switch mode.wallpaper {
        case .keep:
            return await restoreWallpaper()                // switching from a mode that had changed it
        case .file(let path):
            image = URL(filePath: path)
            guard FileManager.default.fileExists(atPath: path) else { return "The wallpaper image for \(mode.name) is missing, so your desktop wasn’t changed." }
        case .bundled(let id):
            if library.state(id) != .ready {
                status = "Downloading wallpaper…"
                await library.download(id)
            }
            guard stillCurrent() else { return nil }
            guard library.state(id) == .ready else { return "Couldn’t download the wallpaper for \(mode.name), so your desktop wasn’t changed." }
            image = library.fileURL(id)
        }
        do {
            try await swapper.apply(imageURL: image)
            return nil
        } catch {
            if swapper.isApplied { _ = await restoreWallpaper() }   // don't leave the previous mode's picture behind
            return error.localizedDescription
        }
    }

    // MARK: End of a session

    /// Put things back, or keep the changes if the mode says so.
    func leave(_ mode: Mode?) async -> [String] {
        sessionActive = false
        return await serialized { [self] in
            defer { refresh() }
            if mode?.system.restoreOnExit == false { forgetAll(); return [] }
            return await restoreAll()
        }
    }

    private func restoreAll() async -> [String] {
        var notices: [String] = []
        func attempt(_ work: () async throws -> Void) async {
            do { try await work() } catch { notices.append(error.localizedDescription) }
        }
        await attempt { try await appearance.restore() }
        await attempt { try await dock.restore() }
        await attempt { try await volume.restore() }
        apps.restore()
        do {
            if try await focus.restore() == .noOffShortcut {
                notices.append("Flow couldn’t turn Focus off because this mode has no “turn off” shortcut. Turn it off in Control Centre.")
            }
        } catch { notices.append(error.localizedDescription) }
        if let problem = await restoreWallpaper() { notices.append(problem) }
        return notices
    }

    private func forgetAll() {
        swapper.forget(); dock.forget(); appearance.forget(); volume.forget(); apps.forget(); focus.forget()
    }

    private func restoreWallpaper() async -> String? {
        do {
            switch try await swapper.restore() {
            case .restored: return nil
            case .pending: return Self.pendingNotice
            }
        } catch { return error.localizedDescription }
    }
}
