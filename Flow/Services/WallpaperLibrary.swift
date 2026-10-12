import AppKit
import CryptoKit
import FlowCore
import ImageIO

/// Knows which curated wallpapers exist, which are on disk, and downloads the rest on demand.
@Observable
final class WallpaperLibrary {
    enum State: Equatable { case missing, downloading, ready }

    let entries: [WallpaperEntry]
    let directory: URL
    private(set) var states: [String: State] = [:]
    private(set) var errors: [String: String] = [:]
    @ObservationIgnored private var inflight: [String: Task<Void, Never>] = [:]

    init(manifest: Data? = nil, directory: URL? = nil) {
        let data = manifest
            ?? Bundle.main.url(forResource: "manifest", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
            ?? Data()
        entries = (try? WallpaperEntry.decodeManifest(data)) ?? []
        self.directory = directory ?? Self.defaultDirectory()
        refresh()
    }

    private static func defaultDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["FLOW_WALLPAPER_DIR"] {   // dev: point at Wallpapers/images
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        return URL.applicationSupportDirectory.appending(path: "Flow/Wallpapers", directoryHint: .isDirectory)
    }

    func refresh() {
        for entry in entries where states[entry.id] != .downloading {
            states[entry.id] = FileManager.default.fileExists(atPath: fileURL(entry.id).path) ? .ready : .missing
        }
    }

    func fileURL(_ id: String) -> URL { directory.appending(path: "\(id).jpg") }
    func entry(_ id: String) -> WallpaperEntry? { entries.first { $0.id == id } }
    func state(_ id: String) -> State { states[id] ?? .missing }

    /// The image to preview for a mode, or nil if it isn't on disk yet.
    func imageURL(for setting: WallpaperSetting) -> URL? {
        switch setting {
        case .keep: nil
        case .bundled(let id): state(id) == .ready ? fileURL(id) : nil
        case .file(let path): URL(filePath: path)
        }
    }

    /// Two callers asking for the same image (a tile click and a session start) share one download.
    func download(_ id: String) async {
        if let running = inflight[id] { await running.value; return }
        guard state(id) == .missing else { return }
        let task = Task { await self.fetch(id) }
        inflight[id] = task
        await task.value
        inflight[id] = nil
    }

    private func fetch(_ id: String) async {
        guard let entry = entry(id) else { return }
        states[id] = .downloading
        errors[id] = nil
        do {
            var request = URLRequest(url: entry.url)
            request.setValue("Flow/0.1 (macOS; open-source wallpaper download)", forHTTPHeaderField: "User-Agent")
            let (temp, response) = try await URLSession.shared.download(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            if let expected = entry.sha256, try await Self.sha256(of: temp) != expected { throw CocoaError(.fileReadCorruptFile) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: fileURL(id))
            try FileManager.default.moveItem(at: temp, to: fileURL(id))
            states[id] = .ready
        } catch {
            states[id] = .missing
            errors[id] = "Couldn’t download this wallpaper. Check your connection and try again."
        }
    }

    @concurrent private static func sha256(of url: URL) async throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Decodes a small preview of a 4K image off the main thread; a full-size decode per tile would be slow and heavy.
enum Thumbnails {
    private struct Box: @unchecked Sendable { let image: CGImage }
    private static let cache = NSCache<NSString, NSImage>()

    static func image(at url: URL, maxPixel: Int) async -> NSImage? {
        let key = "\(url.path)#\(maxPixel)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let box = await decode(url, maxPixel: maxPixel) else { return nil }
        let image = NSImage(cgImage: box.image, size: NSSize(width: box.image.width, height: box.image.height))
        cache.setObject(image, forKey: key)
        return image
    }

    @concurrent private static func decode(_ url: URL, maxPixel: Int) async -> Box? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return Box(image: image)
    }
}
