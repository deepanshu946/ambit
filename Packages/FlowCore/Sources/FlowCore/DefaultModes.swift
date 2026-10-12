import Foundation

public enum DefaultModes {
    private static let chat = ["com.tinyspeck.slackmacgap", "com.apple.MobileSMS", "com.apple.mail"]

    /// Starting presets. Stable ids so a reset or an app update can match them up later.
    private static let presets: [Mode] = [
        mode("00000000-0000-0000-0000-000000000001", "Deep Work", "Intense. Everything unrelated gets out of the way.",
             "scope", .dark, RGB(0.43, 0.66, 1.00), [.timer, .priorities, .sound, .quickNote], hide: chat, dock: true, volume: 0.3),
        mode("00000000-0000-0000-0000-000000000002", "Study", "Calm. One document, warm light, no hurry.",
             "book", .light, RGB(0.72, 0.40, 0.11), [.timer, .priorities, .sound, .quickNote], hide: chat, dock: true),
        mode("00000000-0000-0000-0000-000000000003", "Plan", "Open. Space to arrange the day and the week.",
             "calendar", .light, RGB(0.08, 0.64, 0.50), [.timer, .priorities, .quickNote]),
        mode("00000000-0000-0000-0000-000000000004", "Browse", "Loose. No rules, just a tidy desk.",
             "safari", .system, nil, [.clock]),
        mode("00000000-0000-0000-0000-000000000005", "Chill", "Low. Work disappears, music takes over.",
             "moon.stars", .dark, RGB(1.00, 0.54, 0.40), [.sound], hide: chat, dock: true),
        mode("00000000-0000-0000-0000-000000000006", "Meeting", "Reactive. Only what the call needs.",
             "video", .light, RGB(0.18, 0.71, 0.34), [.timer, .priorities, .quickNote], hide: ["com.tinyspeck.slackmacgap"]),
        mode("00000000-0000-0000-0000-000000000007", "Creative", "Energetic. Big canvas, tools in reach.",
             "paintpalette", .dark, RGB(1.00, 0.31, 0.64), [.timer, .priorities, .sound, .quickNote], dock: true),
        mode("00000000-0000-0000-0000-000000000008", "Music", "Your music, always one glance away.",
             "music.note", .system, RGB(0.62, 0.40, 0.98), [.sound]),
    ]

    /// First wallpaper of each mode in Wallpapers/manifest.json, in the same order as `presets`. nil leaves the desktop alone
    /// (Music is about the player, not the desktop).
    private static let firstWallpaper: [String?] = ["deep-1", "study-1", "plan-1", "browse-1", "chill-1", "meeting-1", "creative-1", nil]

    public static let all: [Mode] = zip(presets, firstWallpaper).map { mode, id in
        var mode = mode
        if let id { mode.wallpaper = .bundled(id: id) }
        return mode
    }

    /// A saved list from before a starter mode existed gets that mode appended; everything already saved, including
    /// the person's edits, is left exactly as it is. (Revisit when modes can be deleted, or a deleted one would return.)
    public static func addingMissing(to saved: [Mode]) -> [Mode] {
        let known = Set(saved.map(\.id))
        return saved + all.filter { !known.contains($0.id) }
    }

    private static func mode(
        _ id: String, _ name: String, _ tagline: String, _ symbol: String,
        _ appearance: Look.Appearance, _ accent: RGB?, _ panel: [PanelComponent],
        hide: [String] = [], dock: Bool? = nil, volume: Double? = nil
    ) -> Mode {
        var system = SystemSettings()
        system.hideApps = hide
        system.dockAutoHide = dock
        system.outputVolume = volume
        return Mode(id: UUID(uuidString: id)!, name: name, tagline: tagline, symbol: symbol,
                    look: Look(appearance: appearance, accent: accent), system: system, panel: panel)
    }
}
