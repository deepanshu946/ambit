import SwiftUI
import UniformTypeIdentifiers
import AmbitCore

/// A wallpaper preview that fills its frame. Shows `fallback` until the image is decoded.
struct WallpaperThumb: View {
    let url: URL?
    var maxPixel = 800
    var fallback = AnyShapeStyle(.quaternary)
    @State private var image: NSImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image { Image(nsImage: image).resizable().scaledToFill() } else { Rectangle().fill(fallback) }
            }
            .clipped()
            .task(id: url) {
                guard let url else { image = nil; return }
                image = await Thumbnails.image(at: url, maxPixel: maxPixel)
            }
    }
}

/// Lets a mode pick one of the curated wallpapers (downloading it first if needed), keep the current one, or use a file.
struct WallpaperPicker: View {
    @Binding var mode: Mode
    @Environment(WallpaperLibrary.self) private var library
    @State private var importing = false
    @State private var expanded: Set<String> = []

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 12)]

    private var groups: [(name: String, entries: [WallpaperEntry])] {
        var order: [String] = []
        for entry in library.entries where !order.contains(entry.mode) { order.append(entry.mode) }
        return order.map { name in (name, library.entries.filter { $0.mode == name }) }
    }

    var body: some View {
        Section {
            LazyVGrid(columns: columns, spacing: 12) {
                ChoiceTile(title: "Keep my wallpaper", symbol: "rectangle.dashed", selected: mode.wallpaper == .keep) {
                    mode.wallpaper = .keep
                }
                ChoiceTile(title: "Choose an image…", symbol: "photo.badge.plus", selected: isFile) { importing = true }
            }
            ForEach(groups, id: \.name) { group in
                DisclosureGroup(group.name, isExpanded: binding(for: group.name)) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(group.entries) { entry in
                            WallpaperTile(entry: entry, selected: mode.wallpaper == .bundled(id: entry.id)) { choose(entry) }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        } header: {
            Text("Wallpaper")
        } footer: {
            credit
        }
        .onAppear { expandCurrentGroup() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { mode.wallpaper = .file(path: url.path) }
        }
    }

    private var isFile: Bool { if case .file = mode.wallpaper { true } else { false } }

    @ViewBuilder private var credit: some View {
        switch mode.wallpaper {
        case .bundled(let id):
            if let entry = library.entry(id) {
                HStack(spacing: 4) {
                    Text("Photo: \(entry.credit).")
                    Link("Source", destination: entry.source)
                }
            }
        case .file(let path):
            Text(URL(filePath: path).lastPathComponent)
        case .keep:
            Text("Ambit leaves your desktop picture alone.")
        }
    }

    private func choose(_ entry: WallpaperEntry) {
        Task {
            if library.state(entry.id) == .missing { await library.download(entry.id) }
            if library.state(entry.id) == .ready { mode.wallpaper = .bundled(id: entry.id) }
        }
    }

    private func binding(for group: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(group) },
                set: { if $0 { expanded.insert(group) } else { expanded.remove(group) } })
    }

    private func expandCurrentGroup() {
        guard expanded.isEmpty else { return }
        if case .bundled(let id) = mode.wallpaper, let entry = library.entry(id) { expanded = [entry.mode] }
        else if let match = groups.first(where: { $0.name == mode.name }) { expanded = [match.name] }
    }
}

private let tileShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

private struct WallpaperTile: View {
    let entry: WallpaperEntry
    let selected: Bool
    let action: () -> Void
    @Environment(WallpaperLibrary.self) private var library

    var body: some View {
        let state = library.state(entry.id)
        Button(action: action) {
            WallpaperThumb(url: library.thumbnailURL(entry.id) ?? (state == .ready ? library.fileURL(entry.id) : nil), maxPixel: 560)
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) { if state != .ready { badge(state) } }
                .clipShape(tileShape)
                .overlay { tileShape.strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 3) }
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .tint)
                            .font(.title3)
                            .padding(6)
                    }
                }
                .contentShape(tileShape)
        }
        .buttonStyle(.plain)
        .help(library.errors[entry.id] ?? entry.credit)
        .accessibilityLabel("\(entry.title), \(entry.width) by \(entry.height)")
        .accessibilityHint(state == .ready ? "Use this wallpaper" : "Downloads \(Int(entry.megabytes.rounded())) megabytes, then uses it")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The picture is always visible; this small label says a click downloads it first.
    private func badge(_ state: WallpaperLibrary.State) -> some View {
        HStack(spacing: 4) {
            if state == .downloading {
                ProgressView().controlSize(.mini)
                Text("Downloading")
            } else if library.errors[entry.id] != nil {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                Text("Retry")
            } else {
                Image(systemName: "arrow.down.circle.fill")
                Text("\(Int(entry.megabytes.rounded())) MB")
            }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.ultraThinMaterial, in: .capsule)
        .padding(6)
    }
}

private struct ChoiceTile: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: symbol).font(.title2)
                        Text(title).font(.callout).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                    .padding(8)
                }
                .background(.quaternary.opacity(0.5), in: tileShape)
                .overlay { tileShape.strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: selected ? 3 : 1) }
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .tint).font(.title3).padding(6)
                    }
                }
                .contentShape(tileShape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
