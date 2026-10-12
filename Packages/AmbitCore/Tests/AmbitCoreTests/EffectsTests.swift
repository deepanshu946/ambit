import Foundation
import Testing
@testable import AmbitCore

private func tempStore<T: Codable & Sendable>(_: T.Type) -> JSONStore<T> {
    JSONStore(url: FileManager.default.temporaryDirectory.appending(path: "fx-\(UUID()).json"))
}

// MARK: - GuardedSetting (Dock, appearance, volume all use this)

@MainActor private final class FakeSetting: SettingBackend {
    struct Failure: Error {}
    var value: Double
    var sets: [Double] = []
    var failReads = false, failSets = false
    init(_ value: Double) { self.value = value }
    func current() async throws -> Double { if failReads { throw Failure() }; return value }
    func set(_ v: Double) async throws { if failSets { throw Failure() }; value = v; sets.append(v) }
    func matches(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.02 }   // like volume: reads back slightly different
}

@MainActor @Suite struct GuardedSettingTests {
    private func make(_ start: Double) -> (FakeSetting, GuardedSetting<FakeSetting>, JSONStore<SettingRestorePoint<Double>>) {
        let backend = FakeSetting(start), store = tempStore(SettingRestorePoint<Double>.self)
        return (backend, GuardedSetting(backend: backend, store: store), store)
    }

    @Test func appliesAndRestores() async throws {
        let (b, s, _) = make(0.8)
        try await s.apply(0.3)
        #expect(b.value == 0.3)
        #expect(try await s.restore() == .restored)
        #expect(b.value == 0.8 && !s.isApplied)
    }

    @Test func savesTheOriginalBeforeChanging() async throws {
        let (_, s, store) = make(0.8)
        try await s.apply(0.3)
        #expect(store.load()?.original == 0.8)
    }

    @Test func switchingModesKeepsTheFirstOriginal() async throws {
        let (b, s, _) = make(0.8)
        try await s.apply(0.3)
        try await s.apply(0.5)
        try await s.restore()
        #expect(b.value == 0.8)
    }

    @Test func aModeThatDoesNotTouchItGivesItBack() async throws {
        let (b, s, _) = make(0.8)
        try await s.apply(0.3)
        try await s.apply(nil)
        #expect(b.value == 0.8 && !s.isApplied)
    }

    @Test func ifThePersonChangedItDuringTheSessionAmbitLeavesItAlone() async throws {
        let (b, s, _) = make(0.8)
        try await s.apply(0.3)
        b.value = 0.6                                  // they turned the volume up themselves
        #expect(try await s.restore() == .leftAlone)
        #expect(b.value == 0.6 && !s.isApplied)
    }

    @Test func aChangeByThePersonBeforeASwitchBecomesTheNewStartingPoint() async throws {
        let (b, s, _) = make(0.8)
        try await s.apply(0.3)
        b.value = 0.6
        try await s.apply(0.2)                         // next mode
        try await s.restore()
        #expect(b.value == 0.6)                        // their value, not the 0.8 from before
    }

    @Test func alreadyAsWantedRemembersNothing() async throws {
        let (b, s, store) = make(0.3)
        try await s.apply(0.3)
        #expect(b.sets.isEmpty && !s.isApplied && store.load() == nil)
    }

    @Test func aCrashedSessionIsRepairedOnNextLaunch() async throws {
        let backend = FakeSetting(0.8), store = tempStore(SettingRestorePoint<Double>.self)
        try await GuardedSetting(backend: backend, store: store).apply(0.3)
        let relaunched = GuardedSetting(backend: backend, store: store)
        #expect(relaunched.isApplied)
        try await relaunched.restore()
        #expect(backend.value == 0.8 && store.load() == nil)
    }

    @Test func aFailedChangeLeavesNothingToRestore() async {
        let (b, s, store) = make(0.8)
        b.failSets = true
        await #expect(throws: FakeSetting.Failure.self) { try await s.apply(0.3) }
        #expect(!s.isApplied && store.load() == nil)
    }

    @Test func aFailedRestoreKeepsTheRestorePointForRetry() async throws {
        let (b, s, _) = make(0.8)
        try await s.apply(0.3)
        b.failSets = true
        await #expect(throws: FakeSetting.Failure.self) { try await s.restore() }
        #expect(s.isApplied)
        b.failSets = false
        #expect(try await s.restore() == .restored)
        #expect(b.value == 0.8)
    }

    @Test func unreadableMeansNoChangeIsMade() async {
        let (b, s, _) = make(0.8)
        b.failReads = true                             // e.g. macOS permission denied
        await #expect(throws: FakeSetting.Failure.self) { try await s.apply(0.3) }
        #expect(b.sets.isEmpty && !s.isApplied)
    }
}

// MARK: - Apps

@MainActor private final class FakeApps: AppsBackend {
    var ownBundleID: String? = "me.ambit"
    var running: Set<String>, hidden: Set<String> = [], launched: [String] = []
    var failLaunch: Set<String> = []
    init(running: Set<String>) { self.running = running }
    func isRunning(_ id: String) -> Bool { running.contains(id) }
    func isHidden(_ id: String) -> Bool {
        reads += 1
        if reads > hideLagsByReads { hidden.formUnion(pendingHide); pendingHide = [] }
        return hidden.contains(id)
    }
    var hideLagsByReads = 0                  // macOS hides a moment after the call
    var pendingHide: Set<String> = []
    var refuseHide: Set<String> = []
    private var reads = 0
    func hide(_ id: String) { if refuseHide.contains(id) { return }; pendingHide.insert(id) }   // reports nothing, like the real API
    func unhide(_ id: String) { hidden.remove(id); pendingHide.remove(id) }
    func launch(_ id: String) async throws { if failLaunch.contains(id) { throw CocoaError(.fileNoSuchFile) }; launched.append(id); running.insert(id) }
}

@MainActor @Suite struct AppsEffectTests {
    @Test func hidesRunningVisibleAppsAndUnhidesOnlyThose() async {
        let apps = FakeApps(running: ["slack", "mail", "notes"])
        apps.hidden = ["mail"]                          // the person had already hidden Mail
        let fx = AppsEffect(backend: apps, store: tempStore(HiddenAppsRecord.self))
        await fx.hide(["slack", "mail", "ghost"])             // ghost isn't running
        #expect(apps.hidden == ["slack", "mail"] && fx.record?.hidden == ["slack"])
        fx.restore()
        #expect(apps.hidden == ["mail"])                // Mail stays hidden, as the person left it
        #expect(!fx.isApplied)
    }

    @Test func neverHidesItself() async {
        let apps = FakeApps(running: ["me.ambit", "slack"])
        let fx = AppsEffect(backend: apps, store: tempStore(HiddenAppsRecord.self))
        await fx.hide(["me.ambit", "slack"])
        #expect(!apps.hidden.contains("me.ambit"))
    }

    @Test func switchingModesGivesBackWhatTheNextDoesNotHide() async {
        let apps = FakeApps(running: ["slack", "mail"])
        let fx = AppsEffect(backend: apps, store: tempStore(HiddenAppsRecord.self))
        await fx.hide(["slack"])
        await fx.hide(["mail"])
        #expect(apps.hidden == ["mail"])
    }

    @Test func anAppTheyQuitIsNotTouchedOnRestore() async {
        let apps = FakeApps(running: ["slack"])
        let fx = AppsEffect(backend: apps, store: tempStore(HiddenAppsRecord.self))
        await fx.hide(["slack"])
        apps.running = []                               // they quit Slack
        fx.restore()
        #expect(!fx.isApplied)
    }

    @Test func aCrashedSessionUnhidesOnNextLaunch() async {
        let apps = FakeApps(running: ["slack"]), store = tempStore(HiddenAppsRecord.self)
        await AppsEffect(backend: apps, store: store).hide(["slack"])
        let relaunched = AppsEffect(backend: apps, store: store)
        relaunched.restore()
        #expect(apps.hidden.isEmpty)
    }

    @Test func aSlowHideIsStillRecordedSoItGetsRestored() async {
        let apps = FakeApps(running: ["slack"])
        apps.hideLagsByReads = 4                         // not hidden yet on the first reads
        let fx = AppsEffect(backend: apps, store: tempStore(HiddenAppsRecord.self))
        await fx.hide(["slack"])
        #expect(fx.record?.hidden == ["slack"])
        fx.restore()
        #expect(apps.hidden.isEmpty)
    }

    @Test func anAppThatNeverHidesIsNotKeptInTheRecord() async {
        let apps = FakeApps(running: ["slack"])
        apps.refuseHide = ["slack"]
        let fx = AppsEffect(backend: apps, store: tempStore(HiddenAppsRecord.self))
        await fx.hide(["slack"])
        #expect(!fx.isApplied)                           // so a later restore can't unhide something it never hid
    }

    @Test func opensOnlyAppsThatAreNotRunning() async {
        let apps = FakeApps(running: ["xcode"])
        apps.failLaunch = ["broken"]
        let fx = AppsEffect(backend: apps, store: tempStore(HiddenAppsRecord.self))
        let failed = await fx.open(["xcode", "notes", "broken"])
        #expect(apps.launched == ["notes"] && failed == ["broken"])
    }
}

// MARK: - Focus

@MainActor private final class FakeShortcuts: ShortcutsBackend {
    struct Failure: Error {}
    var ran: [String] = []
    var failing: Set<String> = []
    func run(_ name: String) async throws { if failing.contains(name) { throw Failure() }; ran.append(name) }
    func names() async -> [String] { [] }
}

@MainActor @Suite struct FocusEffectTests {
    @Test func runsOnThenOff() async throws {
        let sc = FakeShortcuts()
        let fx = FocusEffect(backend: sc, store: tempStore(FocusRecord.self))
        try await fx.apply(on: "Focus On", off: "Focus Off")
        #expect(try await fx.restore() == .turnedOff)
        #expect(sc.ran == ["Focus On", "Focus Off"] && !fx.isApplied)
    }

    @Test func withoutAnOffShortcutItSaysSoInsteadOfPretending() async throws {
        let sc = FakeShortcuts()
        let fx = FocusEffect(backend: sc, store: tempStore(FocusRecord.self))
        try await fx.apply(on: "Focus On", off: nil)
        #expect(try await fx.restore() == .noOffShortcut)
        #expect(sc.ran == ["Focus On"])
    }

    @Test func aFailedOnLeavesNothingToUndo() async {
        let sc = FakeShortcuts(); sc.failing = ["Focus On"]
        let fx = FocusEffect(backend: sc, store: tempStore(FocusRecord.self))
        await #expect(throws: FakeShortcuts.Failure.self) { try await fx.apply(on: "Focus On", off: "Focus Off") }
        #expect(!fx.isApplied)
    }

    @Test func switchingToAModeWithoutFocusTurnsItOff() async throws {
        let sc = FakeShortcuts()
        let fx = FocusEffect(backend: sc, store: tempStore(FocusRecord.self))
        try await fx.apply(on: "Focus On", off: "Focus Off")
        try await fx.apply(on: nil, off: nil)
        #expect(sc.ran == ["Focus On", "Focus Off"] && !fx.isApplied)
    }

    @Test func switchingBetweenTwoFocusModesDoesNotRunItTwice() async throws {
        let sc = FakeShortcuts()
        let fx = FocusEffect(backend: sc, store: tempStore(FocusRecord.self))
        try await fx.apply(on: "Focus On", off: "Focus Off")
        try await fx.apply(on: "Focus On", off: "Focus Off")
        #expect(sc.ran == ["Focus On"])
    }

    @Test func aFailedOffKeepsTheRecordForRetry() async throws {
        let sc = FakeShortcuts()
        let fx = FocusEffect(backend: sc, store: tempStore(FocusRecord.self))
        try await fx.apply(on: "Focus On", off: "Focus Off")
        sc.failing = ["Focus Off"]
        await #expect(throws: FakeShortcuts.Failure.self) { try await fx.restore() }
        #expect(fx.isApplied)
    }
}

// MARK: - Summary and review

@Suite struct SummaryTests {
    @Test func aModeThatChangesNothingHasAnEmptySummary() {
        #expect(Mode(name: "Plain").effectsSummary().isEmpty)
    }

    @Test func summaryNamesEveryChange() {
        var m = Mode(name: "Deep", wallpaper: .bundled(id: "deep-1"))
        m.look.appearance = .dark
        m.system.hideApps = ["a", "b"]; m.system.openApps = ["c"]
        m.system.dockAutoHide = true; m.system.outputVolume = 0.3; m.system.focusShortcut = "Focus On"
        let text = m.effectsSummary { "App-" + $0 }.map(\.text).joined(separator: "|")
        for expected in ["wallpaper", "Dark", "App-a and App-b", "Open App-c", "Dock automatically", "30%", "Focus On"] {
            #expect(text.contains(expected), "missing \(expected) in \(text)")
        }
    }

    @Test func fingerprintChangesWithAnythingThatTouchesTheMacButNotWithTheName() {
        var m = Mode(name: "Deep")
        let base = m.effectsFingerprint
        m.name = "Renamed"; m.tagline = "x"; m.symbol = "bolt"
        #expect(m.effectsFingerprint == base)
        m.system.outputVolume = 0.5
        #expect(m.effectsFingerprint != base)
    }
}
