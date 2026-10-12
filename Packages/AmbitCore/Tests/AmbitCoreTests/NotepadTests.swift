import Foundation
import Testing
@testable import AmbitCore

@MainActor private final class FakeNotes: NotesBackend {
    struct Failure: Error, LocalizedError { var errorDescription: String? { "Notes isn’t reachable" } }
    var calls: [(id: String?, folder: String, html: String)] = []
    var failing = false
    var onSave: (() -> Void)?
    func save(noteID: String?, folder: String, html: String) async throws -> String {
        if failing { throw Failure() }
        calls.append((noteID, folder, html))
        onSave?()
        return noteID ?? "note-1"
    }
}

private func draftStore() -> JSONStore<NoteDraft> {
    JSONStore(url: FileManager.default.temporaryDirectory.appending(path: "draft-\(UUID()).json"))
}

@MainActor private func saver(_ notes: FakeNotes, _ store: JSONStore<NoteDraft>) -> NoteSaver {
    // A zero wait makes the typing pause pass instantly, so tests don't depend on the clock.
    NoteSaver(title: "Meeting", folder: "Ambit Meetings", backend: notes, draftStore: store, debounce: .zero, sleep: { _ in })
}

@MainActor @Suite struct NoteSaverTests {
    @Test func theFirstSaveCreatesTheNoteAndLaterOnesUpdateIt() async {
        let notes = FakeNotes(), s = saver(notes, draftStore())
        s.textChanged("agenda")
        await s.finish()
        s.textChanged("agenda\nitem 1")
        await s.finish()
        #expect(notes.calls.count == 2)
        #expect(notes.calls[0].id == nil && notes.calls[1].id == "note-1")      // same note, not a second one
        #expect(notes.calls[0].folder == "Ambit Meetings")
    }

    @Test func anEmptyPadNeverCreatesANote() async {
        let notes = FakeNotes(), s = saver(notes, draftStore())
        s.textChanged("   \n ")
        await s.finish()
        #expect(notes.calls.isEmpty && s.noteID == nil)
    }

    @Test func fastTypingSavesOnceNotOncePerKeystroke() async {
        let notes = FakeNotes(), s = saver(notes, draftStore())
        for text in ["a", "ab", "abc", "abcd"] { s.textChanged(text) }
        await s.finish()
        #expect(notes.calls.count == 1 && notes.calls[0].html.contains("abcd"))
    }

    @Test func finishingFlushesWhatIsUnsaved() async {
        let notes = FakeNotes(), s = saver(notes, draftStore())
        s.textChanged("last words")
        let state = await s.finish()
        #expect(notes.calls.last?.html.contains("last words") == true)
        if case .saved = state {} else { Issue.record("expected saved, got \(state)") }
    }

    @Test func aFailedSaveKeepsTheTextAndRetriesOnFinish() async {
        let notes = FakeNotes(), store = draftStore(), s = saver(notes, store)
        notes.failing = true
        s.textChanged("important")
        let failed = await s.finish()
        #expect(failed == .failed("Notes isn’t reachable"))
        #expect(store.load()?.text == "important")                               // still safe on disk
        notes.failing = false
        let ok = await s.finish()
        if case .saved = ok {} else { Issue.record("expected saved, got \(ok)") }
        #expect(notes.calls.count == 1 && store.load() == nil)                  // saved once the retry worked, draft cleared
    }

    @Test func textTypedWhileASaveIsRunningIsNotLost() async {
        let notes = FakeNotes(), s = saver(notes, draftStore())
        var typedMore = false
        notes.onSave = { if !typedMore { typedMore = true; s.textChanged("first\nsecond") } }   // typing during the first save
        s.textChanged("first")
        await s.finish()
        #expect(notes.calls.last?.html.contains("second") == true)
    }

    @Test func aDraftLeftByACrashIsSavedIntoTheSameNote() async {
        let notes = FakeNotes(), store = draftStore()
        let draft = NoteDraft(title: "Meeting", folder: "Ambit Meetings", noteID: "note-9", text: "kept after crash")
        let recovered = NoteSaver(recovering: draft, backend: notes, draftStore: store)
        await recovered.finish()
        #expect(notes.calls.count == 1 && notes.calls[0].id == "note-9" && notes.calls[0].html.contains("kept after crash"))
    }

    @Test func htmlEscapesTypedTextAndKeepsLineBreaks() {
        let html = NoteHTML.render(title: "A & B", text: "x < y\n\nz")
        #expect(html == "<div><h1>A &amp; B</h1></div><div>x &lt; y</div><div><br></div><div>z</div>")
    }
}

@Suite struct PresetUpgradeTests {
    private func meeting(_ modes: [Mode]) -> Mode { modes.first { $0.name == "Meeting" }! }

    @Test func anExistingMeetingModeGetsTheNotepadOnce() {
        var old = DefaultModes.all
        let i = old.firstIndex { $0.name == "Meeting" }!
        old[i].panel.removeAll { $0 == .notepad }                      // saved before the notepad existed
        let first = PresetUpgrades.apply(to: old, alreadyApplied: [])
        #expect(meeting(first.modes).panel.contains(.notepad) && first.applied.contains("meeting-notepad"))
    }

    @Test func aLaterChoiceToTurnItOffIsNeverUndone() {
        var modes = DefaultModes.all
        let i = modes.firstIndex { $0.name == "Meeting" }!
        modes[i].panel.removeAll { $0 == .notepad }                    // the person turned it off
        let result = PresetUpgrades.apply(to: modes, alreadyApplied: PresetUpgrades.allIDs)
        #expect(!meeting(result.modes).panel.contains(.notepad))
    }

    @Test func aNewInstallAlreadyHasTheNotepad() {
        #expect(meeting(DefaultModes.all).panel.contains(.notepad))
    }
}

@Suite struct NotepadModelTests {
    @Test func aModeSavedBeforeTheNotepadSettingsExistedStillDecodes() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000006","name":"Meeting","panel":["timer"]}"#
        let mode = try JSONDecoder().decode(Mode.self, from: Data(json.utf8))
        #expect(mode.notepad.folder == "Ambit Meetings" && !mode.panel.contains(.notepad))
    }

    @Test func theReviewMentionsTheNotepadAndChangesWhenItsFolderChanges() {
        var m = Mode(name: "Meeting", panel: [.notepad])
        let text = m.effectsSummary().map(\.text).joined()
        #expect(text.contains("notepad") && text.contains("Ambit Meetings"))
        let before = m.effectsFingerprint
        m.notepad.folder = "Standups"
        #expect(m.effectsFingerprint != before)
    }
}
