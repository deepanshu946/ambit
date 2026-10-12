import SwiftUI
import AmbitCore

private enum SidebarItem: Hashable {
    case mode(Mode.ID)
    case history
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem?

    var body: some View {
        #if DEBUG
        if DebugHooks.selection == "menubar" {   // preview the menu bar popover inside the window (it can't be snapshotted otherwise)
            MenuBarView().environment(model).onAppear { DebugHooks.installSnapshotIfRequested() }
        } else if DebugHooks.selection == "review", let mode = model.modes.first {   // preview the first-start review sheet
            ReviewSheet(mode: mode).environment(model).onAppear { DebugHooks.installSnapshotIfRequested() }
        } else { split }
        #else
        split
        #endif
    }

    private var split: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Modes") {
                    ForEach(model.modes) { mode in
                        HStack {
                            Label {
                                Text(mode.name)
                            } icon: {
                                Image(systemName: mode.symbol).foregroundStyle(mode.look.accent.map(Color.init) ?? Color.secondary)
                            }
                            Spacer()
                            if model.activeModeID == mode.id {
                                Image(systemName: model.clock.isPaused ? "pause.circle.fill" : "waveform")
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel(model.clock.isPaused ? "Paused" : "Session running")
                            }
                        }
                        .tag(SidebarItem.mode(mode.id))
                    }
                }
                Section("Library") {
                    Label("History", systemImage: "clock").tag(SidebarItem.history)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            detail
                .safeAreaInset(edge: .top, spacing: 0) { NoticeBanner() }
        }
        .sheet(item: Binding(get: { model.pendingReview }, set: { if $0 == nil { model.cancelReview() } })) { mode in
            ReviewSheet(mode: mode)
        }
        .onChange(of: model.selectionRequest) { _, id in
            if let id { selection = .mode(id); model.selectionRequest = nil }     // the review's "Edit mode"
        }
        .onAppear {
            if selection == nil { selection = initialSelection() }
            #if DEBUG
            DebugHooks.installSnapshotIfRequested()
            DebugHooks.runSelfTestIfRequested(model: model)
            #endif
        }
    }

    @ViewBuilder private var detail: some View {
            switch selection {
            case .mode(let id):
                if let index = model.modes.firstIndex(where: { $0.id == id }) {
                    @Bindable var model = model
                    ModeDetailView(mode: $model.modes[index])
                }
            case .history:
                HistoryView()
            case nil:
                ContentUnavailableView("Choose a mode", systemImage: "wind")
            }
    }

    private func initialSelection() -> SidebarItem? {
        #if DEBUG
        if let choice = DebugHooks.selection {
            if choice == "history" { return .history }
            if let index = Int(choice), model.modes.indices.contains(index) { return .mode(model.modes[index].id) }
        }
        #endif
        return model.modes.first.map { .mode($0.id) }
    }
}

private struct NoticeBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let notice = model.notice {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow).accessibilityHidden(true)
                Text(notice).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button("Dismiss") { model.dismissNotice() }
            }
            .padding(12)
            .background(.thinMaterial, in: .rect(cornerRadius: 12, style: .continuous))
            .padding([.horizontal, .top], 12)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isStaticText)
        }
    }
}
