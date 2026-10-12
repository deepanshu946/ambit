import SwiftUI
import AmbitCore

/// Quitting mid-session must put the desktop back first, so quit is delayed until the restore has finished.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = Self.model, model.activeModeID != nil || model.effects.needsRestore else { return .terminateNow }
        Task {
            await model.endSession()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct AmbitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel
    @State private var wallpapers: WallpaperLibrary

    init() {
        AppSupportMigration.moveLegacyFolderIfNeeded()      // data from when the app was called Flow, before any store is opened
        let library = WallpaperLibrary()
        let model = AppModel(effects: SystemEffects(library: library))
        _wallpapers = State(initialValue: library)
        _model = State(initialValue: model)
        AppDelegate.model = model
    }

    var body: some Scene {
        WindowGroup("Ambit", id: "main") {
            MainView()
                .environment(model)
                .environment(wallpapers)
                .frame(minWidth: 860, minHeight: 560)
        }
        .defaultSize(width: 1080, height: 740)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands { ModeCommands(model: model) }

        MenuBarExtra {
            MenuBarView().environment(model)
        } label: {
            Image(systemName: model.activeMode?.symbol ?? "wind")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Every command is in the menu bar first; the menu bar extra is a shortcut to these.
struct ModeCommands: Commands {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Mode") {
            ForEach(Array(model.modes.prefix(9).enumerated()), id: \.element.id) { index, mode in
                Button("Start \(mode.name)") {
                    model.start(mode.id)
                    if model.pendingReview != nil {      // the review sheet lives in the window
                        openWindow(id: "main")
                        NSApp.activate()
                    }
                }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .option])
            }
            Divider()
            Button(model.clock.isPaused ? "Resume Session" : "Pause Session") { model.togglePause() }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(!model.clock.isActive)
            Button("Show Notepad") { model.panels.showNotepad() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(!model.panels.hasNotepad)
            Button("End Session") { model.end() }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(!model.clock.isActive)
        }
    }
}
