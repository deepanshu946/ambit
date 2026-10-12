import AppKit
import AmbitCore

/// Saves notes into Apple Notes. Notes has no direct API, so this scripts it. The text is passed to the script as a
/// parameter, never spliced into its source, so what is typed can't break or alter the script.
@MainActor struct AppleScriptNotes: NotesBackend {
    struct Denied: LocalizedError {
        var errorDescription: String? {
            "macOS didn’t let Ambit control Notes, so the notepad couldn’t save. Allow it in System Settings > Privacy & Security > Automation. What you typed is kept safe in Ambit."
        }
    }
    struct Failed: LocalizedError {
        let detail: String
        var errorDescription: String? { "Notes couldn’t save the note: \(detail)" }
    }

    func save(noteID: String?, folder: String, html: String) async throws -> String {
        try await Self.run(noteID: noteID ?? "", folder: folder, html: html)
    }

    private nonisolated static let source = """
    on saveNote(noteID, folderName, noteBody)
        tell application "Notes"
            if noteID is "" then
                if not (exists folder folderName) then make new folder with properties {name:folderName}
                set theNote to make new note at folder folderName with properties {body:noteBody}
                return id of theNote
            else
                set body of note id noteID to noteBody
                return noteID
            end if
        end tell
    end saveNote
    """

    private nonisolated static func fourCC(_ s: String) -> FourCharCode { s.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) } }

    /// Background thread: the first call can sit behind a macOS permission prompt, and the window must not freeze.
    @concurrent private static func run(noteID: String, folder: String, html: String) async throws -> String {
        guard let script = NSAppleScript(source: source) else { throw Failed(detail: "the script couldn’t be created") }
        var error: NSDictionary?
        script.compileAndReturnError(&error)
        if let error { throw Failed(detail: error["NSAppleScriptErrorMessage"] as? String ?? "the script didn’t compile") }

        // A call to the script's own handler: event 'ascr'/'psbr' with the handler name and a list of parameters.
        let event = NSAppleEventDescriptor(eventClass: fourCC("ascr"), eventID: fourCC("psbr"),
                                           targetDescriptor: NSAppleEventDescriptor.null(), returnID: -1, transactionID: 0)
        event.setDescriptor(NSAppleEventDescriptor(string: "saveNote"), forKeyword: fourCC("snam"))
        let parameters = NSAppleEventDescriptor.list()
        parameters.insert(NSAppleEventDescriptor(string: noteID), at: 1)
        parameters.insert(NSAppleEventDescriptor(string: folder), at: 2)
        parameters.insert(NSAppleEventDescriptor(string: html), at: 3)
        event.setDescriptor(parameters, forKeyword: fourCC("----"))

        let result = script.executeAppleEvent(event, error: &error)
        if let error {
            if (error["NSAppleScriptErrorNumber"] as? Int) == -1743 { throw Denied() }       // errAEEventNotPermitted
            throw Failed(detail: error["NSAppleScriptErrorMessage"] as? String ?? "unknown error")
        }
        guard let id = result.stringValue, !id.isEmpty else { throw Failed(detail: "Notes didn’t return the note") }
        return id
    }
}
