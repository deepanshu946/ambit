import SwiftUI
import UniformTypeIdentifiers

/// An editable list of apps, stored as bundle identifiers so it survives the app moving or being renamed.
struct AppListEditor: View {
    let title: String
    let footer: String?
    @Binding var bundleIDs: [String]
    @State private var importing = false

    var body: some View {
        Section {
            ForEach(bundleIDs, id: \.self) { id in
                let app = AppInfo(bundleID: id)
                HStack(spacing: 10) {
                    Group {
                        if let icon = app.icon { Image(nsImage: icon).resizable() }
                        else { Image(systemName: "app.dashed").resizable().scaledToFit().padding(3).foregroundStyle(.secondary) }
                    }
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(app.name)
                        if app.icon == nil { Text("Not installed on this Mac").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button("Remove \(app.name)", systemImage: "minus.circle") { bundleIDs.removeAll { $0 == id } }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 28, minHeight: 28)
                        .contentShape(.rect)
                }
            }
            Button("Add app…", systemImage: "plus") { importing = true }
        } header: {
            Text(title)
        } footer: {
            if let footer { Text(footer) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.application], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                if let id = Bundle(url: url)?.bundleIdentifier, !bundleIDs.contains(id) { bundleIDs.append(id) }
            }
        }
    }
}

struct AppInfo {
    private static let knownNames = ["com.tinyspeck.slackmacgap": "Slack", "com.apple.MobileSMS": "Messages", "com.apple.mail": "Mail"]
    let name: String
    let icon: NSImage?     // nil = not installed here

    init(bundleID: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            // Not installed here. Well-known apps keep their real name; anything else shows the last part of its identifier.
            name = Self.knownNames[bundleID] ?? bundleID.split(separator: ".").last.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? bundleID
            icon = nil   // kept in the list so the mode still works on a Mac that has it
        }
    }
}
