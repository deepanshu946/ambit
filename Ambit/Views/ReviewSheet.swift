import SwiftUI
import AmbitCore

/// Shown before a mode changes the Mac for the first time, and again after its changes are edited.
struct ReviewSheet: View {
    let mode: Mode
    @Environment(AppModel.self) private var model

    var body: some View {
        let lines = mode.effectsSummary { AppInfo(bundleID: $0).name }
        VStack(alignment: .leading, spacing: 18) {
            Label("Start \(mode.name)?", systemImage: mode.symbol)
                .font(.title2.weight(.semibold))
            Text("Ambit will change these things on your Mac:")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(lines) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: line.symbol).foregroundStyle(.tint).frame(width: 22).accessibilityHidden(true)
                        Text(line.text)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10, style: .continuous))
            Text(mode.system.restoreOnExit
                 ? "When the session ends, Ambit puts everything back. If you change something yourself in the meantime, Ambit leaves your change alone."
                 : "These changes stay after the session ends.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Edit mode") { model.editPendingMode() }
                Spacer()
                Button("Cancel", role: .cancel) { model.cancelReview() }.keyboardShortcut(.cancelAction)
                Button("Start") { model.confirmReview() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
