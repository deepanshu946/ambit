import SwiftUI
import AmbitCore

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            if model.activeMode != nil {
                MenuRow(title: model.clock.isPaused ? "Resume" : "Pause", symbol: model.clock.isPaused ? "play.fill" : "pause.fill") { model.togglePause() }
                if model.panels.hasNotepad { MenuRow(title: "Show notepad", symbol: "note.text") { model.panels.showNotepad() } }
                MenuRow(title: "End session", symbol: "stop.fill") { model.end() }
            }
            Divider().padding(.vertical, 4)

            ForEach(model.modes) { mode in
                MenuRow(title: mode.name, symbol: mode.symbol, tint: mode.look.accent.map(Color.init), checked: model.activeModeID == mode.id) {
                    model.start(mode.id)
                    if model.pendingReview != nil {      // the review sheet lives in the window
                        openWindow(id: "main")
                        NSApp.activate()
                    }
                }
            }

            Divider().padding(.vertical, 4)
            MenuRow(title: "Open Ambit…", symbol: "macwindow") {
                openWindow(id: "main")
                NSApp.activate()
            }
            MenuRow(title: "Quit Ambit", symbol: nil) { NSApp.terminate(nil) }
        }
        .padding(8)
        .frame(width: 270)
    }

    @ViewBuilder private var header: some View {
        if let active = model.activeMode {
            VStack(alignment: .leading, spacing: 0) {
                Label(active.name, systemImage: active.symbol)
                    .font(.callout).foregroundStyle(.secondary)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Duration.seconds(Int(model.clock.elapsed(at: context.date))), format: .time(pattern: .hourMinuteSecond))
                        .font(.system(size: 30, weight: .light, design: .rounded)).monospacedDigit()
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        } else {
            Text("No session running").font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 6)
        }
    }
}

/// A row that highlights on hover like a native menu item.
private struct MenuRow: View {
    let title: String
    let symbol: String?
    var tint: Color?
    var checked = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Group {
                    if let symbol { Image(systemName: symbol).foregroundStyle(hovering ? AnyShapeStyle(.white) : AnyShapeStyle(tint ?? .secondary)) }
                    else { Color.clear }
                }
                .frame(width: 20)
                Text(title)
                Spacer()
                if checked { Image(systemName: "checkmark").foregroundStyle(hovering ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary)) }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
            .foregroundStyle(hovering ? Color.white : Color.primary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
