import Foundation

/// One line of Wallpapers/manifest.json. The image itself is downloaded on demand, never shipped in the app.
public struct WallpaperEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var mode: String            // the preset this image was curated for, e.g. "Deep Work"
    public var tone: String
    public var title: String
    public var author: String
    public var license: String
    public var licenseURL: String
    public var source: URL             // human page for credit
    public var url: URL                // original file
    public var width: Int
    public var height: Int
    public var megabytes: Double
    public var sha256: String?

    public static func decodeManifest(_ data: Data) throws -> [WallpaperEntry] {
        try JSONDecoder().decode([WallpaperEntry].self, from: data)
    }

    /// The credit line CC BY licenses ask for. Shown wherever the image is chosen.
    public var credit: String {
        let by = author.isEmpty ? "" : " by \(author)"
        return "“\(title)”\(by), \(license)"
    }
}
