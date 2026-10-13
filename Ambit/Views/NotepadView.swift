import SwiftUI
import AmbitCore

/// The notepad that floats beside a call. What is typed saves into Apple Notes as you go.
struct NotepadView: View {
    @Bindable var model: NotepadModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.title, systemImage: "note.text")
                .font(.headline)
                .lineLimit(1)
            TextEditor(text: $model.text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .padding(6)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if model.text.isEmpty {
                        Text("Type your meeting notes here.")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11).padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Meeting notes")
            statusLine
        }
        .padding(.horizontal, 14)
        .padding(.top, 34)                                   // clears the hidden title bar
        .padding(.bottom, 12)
        .background(.regularMaterial)
        .ignoresSafeArea()
    }

    @ViewBuilder private var statusLine: some View {
        switch model.status {
        case .idle:
            Text("Saved to Notes as you type.").foregroundStyle(.secondary)
        case .saving:
            Label("Saving to Notes…", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
        case .saved(let date):
            Label("Saved to Notes at \(date.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle").foregroundStyle(.secondary)
        case .failed(let message):
            Label("Not saved yet: \(message) Your text is safe here.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
