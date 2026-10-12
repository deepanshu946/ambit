import Foundation

/// A mode is pure data. Every system lever is optional or empty: nil / empty means "leave the Mac alone".
/// New capabilities are added as new fields with a neutral default, so old saved modes keep decoding.
public struct Mode: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var tagline: String
    public var symbol: String          // SF Symbol name
    public var look: Look
    public var wallpaper: WallpaperSetting
    public var system: SystemSettings
    public var panel: [PanelComponent]
    public var sound: SoundSetting

    public init(
        id: UUID = UUID(), name: String, tagline: String = "", symbol: String = "circle",
        look: Look = Look(), wallpaper: WallpaperSetting = .keep, system: SystemSettings = SystemSettings(),
        panel: [PanelComponent] = [.timer, .priorities], sound: SoundSetting = SoundSetting()
    ) {
        self.id = id; self.name = name; self.tagline = tagline; self.symbol = symbol
        self.look = look; self.wallpaper = wallpaper; self.system = system
        self.panel = panel; self.sound = sound
    }

    // Forgiving decoding: a field missing from an older file falls back to its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        tagline = try c.decodeIfPresent(String.self, forKey: .tagline) ?? ""
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "circle"
        look = try c.decodeIfPresent(Look.self, forKey: .look) ?? Look()
        wallpaper = try c.decodeIfPresent(WallpaperSetting.self, forKey: .wallpaper) ?? .keep
        system = try c.decodeIfPresent(SystemSettings.self, forKey: .system) ?? SystemSettings()
        panel = try c.decodeIfPresent([PanelComponent].self, forKey: .panel) ?? [.timer, .priorities]
        sound = try c.decodeIfPresent(SoundSetting.self, forKey: .sound) ?? SoundSetting()
    }
}

public struct Look: Codable, Hashable, Sendable {
    public enum Appearance: String, Codable, CaseIterable, Sendable { case system, light, dark }
    public var appearance: Appearance = .system
    /// nil = use the system accent colour.
    public var accent: RGB?
    public init(appearance: Appearance = .system, accent: RGB? = nil) {
        self.appearance = appearance; self.accent = accent
    }
}

public struct RGB: Codable, Hashable, Sendable {
    public var red: Double, green: Double, blue: Double
    public init(_ red: Double, _ green: Double, _ blue: Double) { self.red = red; self.green = green; self.blue = blue }
}

public enum WallpaperSetting: Codable, Hashable, Sendable {
    case keep                       // don't touch the desktop
    case bundled(id: String)        // an entry in Wallpapers/manifest.json
    case file(path: String)         // the user's own image
}

public struct SystemSettings: Codable, Hashable, Sendable {
    public var focusShortcut: String?        // name of a Shortcuts-app shortcut that turns a Focus on
    public var focusEndShortcut: String?     // name of one that turns it off again
    public var hideApps: [String] = []       // bundle identifiers, hidden (never quit)
    public var openApps: [String] = []       // bundle identifiers
    public var dockAutoHide: Bool?
    public var outputVolume: Double?         // 0...1
    public var restoreOnExit = true
    public init() {}
}

public enum PanelComponent: String, Codable, CaseIterable, Hashable, Sendable {
    case timer, clock, priorities, sound, quickNote
}

public struct SoundSetting: Codable, Hashable, Sendable {
    public var soundscapeID: String?
    public var volume: Double = 0.5
    public init() {}
}
