import Foundation
import Testing
@testable import FlowCore

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

@Suite struct SessionClockTests {
    @Test func countsUpFromStart() {
        var c = SessionClock()
        c.start(at: at(0))
        #expect(c.elapsed(at: at(90)) == 90)
    }

    @Test func pauseBanksTimeAndResumeContinues() {
        var c = SessionClock()
        c.start(at: at(0))
        c.pause(at: at(60))
        #expect(c.elapsed(at: at(500)) == 60)      // paused: time doesn't move
        c.resume(at: at(500))
        #expect(c.elapsed(at: at(530)) == 90)
    }

    @Test func lateRedrawStaysAccurate() {
        var c = SessionClock()
        c.start(at: at(0))
        #expect(c.elapsed(at: at(3_600)) == 3_600)  // one hour later, no ticks needed
    }

    @Test func finishReturnsOnceSoNoDuplicateRecords() {
        var c = SessionClock()
        c.start(at: at(0))
        #expect(c.finish(at: at(120)) == 120)
        #expect(c.finish(at: at(200)) == nil)
        #expect(c.elapsed(at: at(999)) == 120)
    }

    @Test func invalidTransitionsAreIgnored() {
        var c = SessionClock()
        c.pause(at: at(0)); c.resume(at: at(0))
        #expect(c.finish(at: at(0)) == nil)
        #expect(c.state == .idle)
        c.start(at: at(0)); c.start(at: at(50))    // second start must not reset
        #expect(c.elapsed(at: at(60)) == 60)
    }

    @Test func clockGoingBackwardsNeverGoesNegative() {
        var c = SessionClock()
        c.start(at: at(100))
        #expect(c.elapsed(at: at(50)) == 0)
    }
}

@Suite struct ModelTests {
    @Test func completedTimeIgnoresCancelled() {
        let id = UUID()
        func rec(_ e: TimeInterval, _ s: SessionRecord.Status) -> SessionRecord {
            SessionRecord(modeID: id, modeName: "Deep Work", startedAt: t0, endedAt: at(e), elapsed: e, status: s)
        }
        #expect([rec(600, .completed), rec(300, .cancelled), rec(60, .completed)].totalCompletedTime == 660)
    }

    @Test func veryShortSessionsAreNotRecorded() {
        #expect(!SessionRecord.shouldRecord(elapsed: 0))
        #expect(!SessionRecord.shouldRecord(elapsed: 4.9))
        #expect(SessionRecord.shouldRecord(elapsed: 5))
    }

    @Test func defaultModesAreEightWithUniqueIDs() {
        #expect(DefaultModes.all.count == 8)
        #expect(Set(DefaultModes.all.map(\.id)).count == 8)
    }

    @Test func aSavedListFromBeforeMusicExistedGetsMusicAndKeepsItsEdits() {
        var saved = Array(DefaultModes.all.prefix(7))          // the 7 modes that shipped first
        saved[0].name = "My Deep Work"
        saved[0].system.outputVolume = 0.9
        let merged = DefaultModes.addingMissing(to: saved)
        #expect(merged.count == 8 && merged.last?.name == "Music")
        #expect(merged[0].name == "My Deep Work" && merged[0].system.outputVolume == 0.9)
        #expect(DefaultModes.addingMissing(to: merged) == merged)       // nothing to add the second time
    }

    @Test func oldFileMissingNewFieldsStillDecodes() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","name":"Old"}"#
        let mode = try JSONDecoder().decode(Mode.self, from: Data(json.utf8))
        #expect(mode.name == "Old")
        #expect(mode.wallpaper == .keep)
        #expect(mode.system.restoreOnExit)
    }
}

@Suite struct StoreTests {
    private func tempStore() -> JSONStore<[Mode]> {
        JSONStore(url: FileManager.default.temporaryDirectory.appending(path: "flow-\(UUID()).json"))
    }

    @Test func roundTrips() throws {
        let store = tempStore()
        try store.save(DefaultModes.all)
        #expect(store.load() == DefaultModes.all)
    }

    @Test func missingFileIsNil() {
        #expect(tempStore().load() == nil)
    }

    @Test func corruptFileIsMovedAsideNotDeleted() throws {
        let store = tempStore()
        try Data("not json".utf8).write(to: store.url)
        #expect(store.load() == nil)
        #expect(FileManager.default.fileExists(atPath: store.url.appendingPathExtension("corrupt").path))
    }
}

@Suite struct WallpaperManifestTests {
    private struct Entry: Decodable { let id: String; let mode: String; let width: Int; let height: Int; let license: String; let source: String; let url: String }

    private func entries() throws -> [Entry] {
        // …/Packages/FlowCore/Tests/FlowCoreTests/FlowCoreTests.swift → repo root is 5 levels up
        var root = URL(filePath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try JSONDecoder().decode([Entry].self, from: Data(contentsOf: root.appending(path: "Wallpapers/manifest.json")))
    }

    @Test func everyWallpaperIs4KWithLicenseAndSource() throws {
        let all = try entries()
        #expect(all.count == 35)
        #expect(Set(all.map(\.id)).count == all.count)
        for e in all {
            #expect(e.width >= 3840 && e.height >= 2160, "\(e.id) is \(e.width)x\(e.height)")
            #expect(!e.license.isEmpty && e.source.hasPrefix("https://") && e.url.hasPrefix("https://"))
        }
    }

    @Test func everyDefaultModeWallpaperExistsInManifest() throws {
        let ids = Set(try entries().map(\.id))
        for mode in DefaultModes.all {
            guard case .bundled(let id) = mode.wallpaper else { continue }       // .keep (Music) leaves the desktop alone
            #expect(ids.contains(id), "\(mode.name) → \(id)")
        }
    }
}
