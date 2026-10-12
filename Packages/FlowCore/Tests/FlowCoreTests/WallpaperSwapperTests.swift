import Foundation
import Testing
@testable import FlowCore

@MainActor private final class FakeDesktop: DesktopBackend {
    struct Refusal: Error {}
    var wallpapers: [String: DisplayWallpaper]
    var connected: [String]
    var unreadable: Set<String> = []
    var refuseSets = false
    var refuseSetsOn: Set<String> = []     // displays whose wallpaper can't be set (e.g. a file in another app's container)
    var sets: [(String, URL)] = []

    init(_ displays: [String: String]) {
        connected = displays.keys.sorted()
        wallpapers = displays.mapValues { _ in DisplayWallpaper(displayID: "", url: URL(filePath: "/x")) }
        for (id, path) in displays { wallpapers[id] = DisplayWallpaper(displayID: id, url: URL(filePath: path), scaling: 3, allowClipping: true) }
    }
    func displayIDs() -> [String] { connected }
    func currentWallpaper(on id: String) -> DisplayWallpaper? { unreadable.contains(id) ? nil : wallpapers[id] }
    func canRestore(_ w: DisplayWallpaper) -> Bool { !refuseSets && !refuseSetsOn.contains(w.displayID) }
    func setWallpaper(_ w: DisplayWallpaper, on id: String) async throws {
        if refuseSets || refuseSetsOn.contains(id) { throw Refusal() }
        wallpapers[id] = w; sets.append((id, w.url))
    }
}

private func tempStore() -> JSONStore<RestorePoint> {
    JSONStore(url: FileManager.default.temporaryDirectory.appending(path: "restore-\(UUID()).json"))
}
private let mine = URL(filePath: "/flow/deep.jpg")
private let theirs = URL(filePath: "/flow/study.jpg")

@MainActor @Suite struct WallpaperSwapperTests {
    @Test func appliesToEveryDisplayAndRestoresExactly() async throws {
        let desktop = FakeDesktop(["A": "/orig/a.jpg", "B": "/orig/b.jpg"])
        let swapper = WallpaperSwapper(backend: desktop, store: tempStore())
        try await swapper.apply(imageURL: mine)
        #expect(desktop.wallpapers["A"]?.url == mine && desktop.wallpapers["B"]?.url == mine)
        try await swapper.restore()
        #expect(desktop.wallpapers["A"]?.url.path == "/orig/a.jpg" && desktop.wallpapers["B"]?.url.path == "/orig/b.jpg")
        #expect(!swapper.isApplied)
    }

    @Test func restorePointIsOnDiskBeforeAnythingChanges() async throws {
        let store = tempStore()
        let desktop = FakeDesktop(["A": "/orig/a.jpg"])
        let swapper = WallpaperSwapper(backend: desktop, store: store)
        try await swapper.apply(imageURL: mine)
        #expect(store.load()?.originals.first?.url.path == "/orig/a.jpg")
    }

    @Test func switchingModesKeepsTheFirstOriginal() async throws {
        let desktop = FakeDesktop(["A": "/orig/a.jpg"])
        let swapper = WallpaperSwapper(backend: desktop, store: tempStore())
        try await swapper.apply(imageURL: mine)
        try await swapper.apply(imageURL: theirs)           // Deep Work → Study
        #expect(desktop.wallpapers["A"]?.url == theirs)
        try await swapper.restore()
        #expect(desktop.wallpapers["A"]?.url.path == "/orig/a.jpg")   // not /flow/deep.jpg
    }

    @Test func aCrashedSessionIsRepairedOnNextLaunch() async throws {
        let store = tempStore()
        let desktop = FakeDesktop(["A": "/orig/a.jpg"])
        try await WallpaperSwapper(backend: desktop, store: store).apply(imageURL: mine)
        // The app dies here. A fresh swapper starts with the same store.
        let relaunched = WallpaperSwapper(backend: desktop, store: store)
        #expect(relaunched.isApplied)
        try await relaunched.recoverIfNeeded()
        #expect(desktop.wallpapers["A"]?.url.path == "/orig/a.jpg")
        #expect(store.load() == nil)
    }

    @Test func aDisplayItCannotReadIsLeftAlone() async throws {
        let desktop = FakeDesktop(["A": "/orig/a.jpg", "B": "/orig/b.jpg"])
        desktop.unreadable = ["B"]
        let swapper = WallpaperSwapper(backend: desktop, store: tempStore())
        try await swapper.apply(imageURL: mine)
        #expect(desktop.wallpapers["A"]?.url == mine)
        #expect(desktop.wallpapers["B"]?.url.path == "/orig/b.jpg")   // untouched: couldn't be put back
    }

    @Test func refusesWhenNothingCanBeRestored() async throws {
        let desktop = FakeDesktop(["A": "/orig/a.jpg"])
        desktop.unreadable = ["A"]
        let store = tempStore()
        let swapper = WallpaperSwapper(backend: desktop, store: store)
        await #expect(throws: WallpaperSwapError.cannotRestoreCurrentWallpaper) { try await swapper.apply(imageURL: mine) }
        #expect(desktop.sets.isEmpty && store.load() == nil)
    }

    @Test func aWallpaperItCannotSetBackIsNeverTouched() async throws {
        // The real case: the current picture is a file inside another app's container, so macOS refuses to set it.
        let desktop = FakeDesktop(["A": "/other-app/container/a.jpg", "B": "/orig/b.jpg"])
        desktop.refuseSetsOn = ["A"]
        let swapper = WallpaperSwapper(backend: desktop, store: tempStore())
        try await swapper.apply(imageURL: mine)
        #expect(desktop.wallpapers["A"]?.url.path == "/other-app/container/a.jpg")   // left alone
        #expect(desktop.wallpapers["B"]?.url == mine)
    }

    @Test func refusesWhenTheOnlyDisplayCannotBeRestored() async throws {
        let desktop = FakeDesktop(["A": "/other-app/container/a.jpg"])
        desktop.refuseSetsOn = ["A"]
        let store = tempStore()
        let swapper = WallpaperSwapper(backend: desktop, store: store)
        await #expect(throws: WallpaperSwapError.cannotRestoreCurrentWallpaper) { try await swapper.apply(imageURL: mine) }
        #expect(desktop.sets.isEmpty && store.load() == nil && !swapper.isApplied)
    }

    @Test func ifMacOSRefusesTheChangeNoRestorePointIsLeftBehind() async throws {
        let desktop = FakeDesktop(["A": "/orig/a.jpg"])
        desktop.refuseSets = true
        let store = tempStore()
        let swapper = WallpaperSwapper(backend: desktop, store: store)
        await #expect(throws: WallpaperSwapError.cannotRestoreCurrentWallpaper) { try await swapper.apply(imageURL: mine) }
        #expect(!swapper.isApplied && store.load() == nil)
    }

    @Test func failedRestoreKeepsTheRestorePointForRetry() async throws {
        let store = tempStore()
        let desktop = FakeDesktop(["A": "/orig/a.jpg"])
        let swapper = WallpaperSwapper(backend: desktop, store: store)
        try await swapper.apply(imageURL: mine)
        desktop.refuseSets = true                       // e.g. the original file was deleted by another app
        await #expect(throws: WallpaperSwapError.couldNotRestore(displays: 1)) { try await swapper.restore() }
        #expect(swapper.isApplied && store.load() != nil)
        desktop.refuseSets = false
        try await swapper.restore()                           // retry works
        #expect(!swapper.isApplied)
    }

    @Test func anUnpluggedDisplayDoesNotBlockRestore() async throws {
        let desktop = FakeDesktop(["A": "/orig/a.jpg", "B": "/orig/b.jpg"])
        let swapper = WallpaperSwapper(backend: desktop, store: tempStore())
        try await swapper.apply(imageURL: mine)
        desktop.connected = ["A"]
        try await swapper.restore()
        #expect(desktop.wallpapers["A"]?.url.path == "/orig/a.jpg")
        #expect(!swapper.isApplied)
    }

    @Test func forgetKeepsTheNewWallpaper() async throws {
        let desktop = FakeDesktop(["A": "/orig/a.jpg"])
        let store = tempStore()
        let swapper = WallpaperSwapper(backend: desktop, store: store)
        try await swapper.apply(imageURL: mine)
        swapper.forget()
        #expect(desktop.wallpapers["A"]?.url == mine && store.load() == nil && !swapper.isApplied)
    }

    @Test func restoreWaitsOnADifferentDesktopThenFinishesWhenYouReturn() async throws {
        // macOS keeps a wallpaper per Space. After switching Space, the display shows some other picture.
        let desktop = FakeDesktop(["A": "/orig/a.jpg"])
        let store = tempStore()
        let swapper = WallpaperSwapper(backend: desktop, store: store)
        try await swapper.apply(imageURL: mine)
        desktop.wallpapers["A"] = DisplayWallpaper(displayID: "A", url: URL(filePath: "/space2/own.jpg"))   // moved to Space 2
        let result = try await swapper.restore()
        #expect(result == .pending(displays: 1))
        #expect(desktop.wallpapers["A"]?.url.path == "/space2/own.jpg")          // Space 2 was NOT overwritten
        #expect(swapper.isApplied && store.load() != nil)
        desktop.wallpapers["A"] = DisplayWallpaper(displayID: "A", url: mine)     // back on Space 1
        #expect(try await swapper.recoverIfNeeded() == .restored)
        #expect(desktop.wallpapers["A"]?.url.path == "/orig/a.jpg")
        #expect(!swapper.isApplied)
    }

    @Test func switchingModesOnADifferentDesktopChangesNothing() async throws {
        let desktop = FakeDesktop(["A": "/orig/a.jpg"])
        let swapper = WallpaperSwapper(backend: desktop, store: tempStore())
        try await swapper.apply(imageURL: mine)
        desktop.wallpapers["A"] = DisplayWallpaper(displayID: "A", url: URL(filePath: "/space2/own.jpg"))
        await #expect(throws: WallpaperSwapError.notOnChangedDesktop) { try await swapper.apply(imageURL: theirs) }
        #expect(desktop.wallpapers["A"]?.url.path == "/space2/own.jpg")
    }

    @Test func theIntendedPictureIsOnDiskBeforeItIsSet() async throws {
        let store = tempStore()
        let desktop = FakeDesktop(["A": "/orig/a.jpg"])
        try await WallpaperSwapper(backend: desktop, store: store).apply(imageURL: mine)
        #expect(store.load()?.applied["A"] == mine.path)   // so a crash right after the set can still be matched and restored
    }
}

