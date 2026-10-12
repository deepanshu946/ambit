import Foundation

/// The app used to be called Flow. Its data folder moves to Ambit's once, so saved modes, History, downloaded wallpapers
/// and any unfinished restore point carry over (a restore point is what puts a changed Mac back after a crash).
public enum AppSupportMigration {
    /// Returns true if it moved the folder. Does nothing if there is no old folder or the new one already exists.
    @discardableResult
    public static func moveLegacyFolder(in base: URL, from old: String = "Flow", to new: String = "Ambit",
                                        fileManager: FileManager = .default) -> Bool {
        let oldURL = base.appending(path: old, directoryHint: .isDirectory)
        let newURL = base.appending(path: new, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: oldURL.path), !fileManager.fileExists(atPath: newURL.path) else { return false }
        return (try? fileManager.moveItem(at: oldURL, to: newURL)) != nil
    }

    /// Call once at launch, before anything reads or writes the data folder. Skipped when AMBIT_STATE_DIR redirects it.
    @discardableResult
    public static func moveLegacyFolderIfNeeded() -> Bool {
        guard ProcessInfo.processInfo.environment["AMBIT_STATE_DIR"] == nil else { return false }
        return moveLegacyFolder(in: URL.applicationSupportDirectory)
    }
}
