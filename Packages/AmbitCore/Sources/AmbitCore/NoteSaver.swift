import Foundation

/// Where notes go. The app's version scripts Apple Notes; tests use a fake.
@MainActor public protocol NotesBackend {
    /// Creates the note when `noteID` is nil, otherwise replaces that note's body. Returns the note's id.
    func save(noteID: String?, folder: String, html: String) async throws -> String
}

/// A safety copy of what was typed, written before each save and removed once everything has reached Notes.
/// If Ambit dies or Notes can't be reached, nothing typed is lost.
public struct NoteDraft: Codable, Equatable, Sendable {
    public var title: String
    public var folder: String
    public var noteID: String?
    public var text: String
    public init(title: String, folder: String, noteID: String?, text: String) {
        self.title = title; self.folder = folder; self.noteID = noteID; self.text = text
    }
}

public enum NoteHTML {
    /// Notes stores HTML. The first line becomes the note's name, so the title goes first. Typed text is escaped.
    public static func render(title: String, text: String) -> String {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.isEmpty ? "<div><br></div>" : "<div>\(escape(String(line)))</div>"
        }
        return "<div><h1>\(escape(title))</h1></div>" + lines.joined()
    }
}

/// Saves a notepad into Notes as it is typed: one note per session, updated after a pause in typing. Nothing is
/// created for an empty pad, a failed save keeps the text and retries, and finishing flushes whatever is unsaved.
@MainActor public final class NoteSaver {
    public enum State: Equatable, Sendable {
        case idle, saving, saved(Date), failed(String)
    }

    public private(set) var state: State = .idle { didSet { onStateChange?(state) } }
    public var onStateChange: (@MainActor (State) -> Void)?
    public private(set) var noteID: String?

    private let title: String
    private let folder: String
    private let backend: NotesBackend
    private let draftStore: JSONStore<NoteDraft>
    private let debounce: Duration
    private let sleep: (Duration) async throws -> Void
    private let now: () -> Date
    private var text = ""
    private var savedText = ""
    private var pending: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?

    public init(title: String, folder: String, backend: NotesBackend, draftStore: JSONStore<NoteDraft>,
                debounce: Duration = .seconds(2),
                sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                now: @escaping () -> Date = Date.init) {
        self.title = title; self.folder = folder; self.backend = backend; self.draftStore = draftStore
        self.debounce = debounce; self.sleep = sleep; self.now = now
    }

    /// Picks up a draft left behind by a session that never finished. `finish()` then saves it.
    public convenience init(recovering draft: NoteDraft, backend: NotesBackend, draftStore: JSONStore<NoteDraft>) {
        self.init(title: draft.title, folder: draft.folder, backend: backend, draftStore: draftStore)
        text = draft.text
        noteID = draft.noteID
    }

    private var needsSave: Bool {
        text != savedText && !(noteID == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)   // no content, no note
    }

    public func textChanged(_ new: String) {
        text = new
        pending?.cancel()
        pending = Task { [weak self] in
            guard let self else { return }
            try? await sleep(debounce)
            guard !Task.isCancelled else { return }
            _ = startSaveIfNeeded()
        }
    }

    private func startSaveIfNeeded() -> Task<Void, Never>? {
        if let inFlight { return inFlight }                    // it will pick up newer text when it finishes
        guard needsSave else { return nil }
        let task = Task { [weak self] in
            guard let self else { return }
            await saveLoop()
            inFlight = nil
        }
        inFlight = task
        return task
    }

    private func saveLoop() async {
        while needsSave {
            let snapshot = text
            state = .saving
            try? draftStore.save(NoteDraft(title: title, folder: folder, noteID: noteID, text: snapshot))      // before touching Notes
            do {
                noteID = try await backend.save(noteID: noteID, folder: folder, html: NoteHTML.render(title: title, text: snapshot))
                savedText = snapshot
                state = .saved(now())
            } catch {
                state = .failed(error.localizedDescription)                                                     // the draft stays on disk
                return
            }
        }
        if text == savedText { draftStore.remove() }
    }

    /// End of the session: save whatever is unsaved now, and report how it went.
    @discardableResult
    public func finish() async -> State {
        pending?.cancel()
        if let task = startSaveIfNeeded() { await task.value }
        return state
    }
}
