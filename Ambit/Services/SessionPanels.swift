import AppKit
import AmbitCore
import SwiftUI

/// A small window that floats above other windows, follows you across Spaces and over full-screen apps, and doesn't
/// take focus from the app you are using until you click into it.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }       // so you can type into it
    override var canBecomeMain: Bool { false }
}

/// Opens, remembers and closes floating panels. Built once here and reused by every mode's panels.
@MainActor final class PanelHost {
    private var panels: [String: FloatingPanel] = [:]

    func show<Content: View>(id: String, title: String, size: NSSize, @ViewBuilder content: () -> Content) {
        if let existing = panels[id] { existing.orderFrontRegardless(); return }
        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
                                  backing: .buffered, defer: false)
        panel.title = title                                           // VoiceOver and the Window menu still need a name
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 220, height: 200)
        panel.contentView = NSHostingView(rootView: content())
        panel.setFrameAutosaveName("Ambit.\(id)")                      // remembers where it was dragged to
        if !panel.setFrameUsingName("Ambit.\(id)") { dockAtRightEdge(panel, size: size) }
        panels[id] = panel
        panel.orderFrontRegardless()                                   // no key focus: doesn't pull you out of your call
    }

    func bringToFront(id: String) { panels[id]?.orderFrontRegardless() }
    func isOpen(id: String) -> Bool { panels[id]?.isVisible ?? false }

    func close(id: String) {
        panels[id]?.close()
        panels[id] = nil
    }

    private func dockAtRightEdge(_ panel: NSPanel, size: NSSize) {
        guard let area = NSScreen.main?.visibleFrame else { return }
        let height = min(size.height, area.height - 40)
        panel.setFrame(NSRect(x: area.maxX - size.width - 12, y: area.midY - height / 2, width: size.width, height: height), display: false)
    }
}

/// The notepad's state: what is typed, and how saving to Notes is going.
@Observable
final class NotepadModel {
    var text = "" { didSet { saver.textChanged(text) } }
    private(set) var status: NoteSaver.State = .idle
    let title: String
    @ObservationIgnored let saver: NoteSaver

    init(title: String, folder: String, notes: NotesBackend, draftStore: JSONStore<NoteDraft>) {
        self.title = title
        saver = NoteSaver(title: title, folder: folder, backend: notes, draftStore: draftStore)
        saver.onStateChange = { [weak self] in self?.status = $0 }
    }
}

/// What each mode puts on screen while a session runs. Today: the notepad. Music's player joins it later.
@Observable
final class SessionPanels {
    private(set) var hasNotepad = false

    @ObservationIgnored private let host = PanelHost()
    @ObservationIgnored private let notes: NotesBackend
    @ObservationIgnored private let draftStore: JSONStore<NoteDraft>
    @ObservationIgnored private var notepad: NotepadModel?
    private static let notepadID = "notepad"

    init(notes: NotesBackend = AppleScriptNotes(), draftStore: JSONStore<NoteDraft> = .appSupport("notepad-draft")) {
        self.notes = notes
        self.draftStore = draftStore
    }

    /// Open the panels `mode` asks for. Call `leave()` first when switching from another mode.
    func enter(_ mode: Mode) {
        guard mode.panel.contains(.notepad) else { return }
        let title = "\(mode.name) – \(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))"
        let model = NotepadModel(title: title, folder: mode.notepad.folder, notes: notes, draftStore: draftStore)
        notepad = model
        hasNotepad = true
        host.show(id: Self.notepadID, title: "Notepad", size: NSSize(width: 300, height: 520)) { NotepadView(model: model) }
    }

    /// The panels close right away. What is typed finishes saving to Notes in the returned task, which reports any problem.
    func leave() -> Task<[String], Never> {
        host.close(id: Self.notepadID)
        hasNotepad = false
        guard let finished = notepad else { return Task { [] } }
        notepad = nil
        return Task {
            if case .failed(let message) = await finished.saver.finish() {
                return ["Your notes couldn’t be saved to Notes (\(message)). They’re kept safe in Ambit and will be saved the next time it opens."]
            }
            return []
        }
    }

    /// Bring the notepad back if it was closed during the session.
    func showNotepad() {
        guard let notepad else { return }
        host.show(id: Self.notepadID, title: "Notepad", size: NSSize(width: 300, height: 520)) { NotepadView(model: notepad) }
        host.bringToFront(id: Self.notepadID)
    }

    /// At launch: notes typed in a session that never finished are saved now.
    func recoverUnsavedNotes() async -> [String] {
        guard let draft = draftStore.load() else { return [] }
        let saver = NoteSaver(recovering: draft, backend: notes, draftStore: draftStore)
        switch await saver.finish() {
        case .failed(let message): return ["Notes from your last meeting couldn’t be saved yet (\(message)). They’re kept safe in Ambit."]
        default: return ["Notes from a meeting that didn’t finish were saved to Notes."]
        }
    }
}
