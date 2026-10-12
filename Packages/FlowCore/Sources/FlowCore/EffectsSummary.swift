import CryptoKit
import Foundation

/// What starting a mode does to the Mac, in plain words, so the person can review it before it happens.
public struct EffectLine: Equatable, Sendable, Identifiable {
    public var id: String { text }
    public var symbol: String
    public var text: String
}

public extension Mode {
    /// Empty means the mode changes nothing on the Mac. `appName` turns a bundle identifier into a name.
    func effectsSummary(appName: (String) -> String = { $0 }) -> [EffectLine] {
        var lines: [EffectLine] = []
        func names(_ ids: [String]) -> String { ids.map(appName).formatted(.list(type: .and)) }
        if wallpaper != .keep { lines.append(EffectLine(symbol: "photo", text: "Change the desktop wallpaper")) }
        switch look.appearance {
        case .dark: lines.append(EffectLine(symbol: "moon", text: "Switch macOS to Dark appearance"))
        case .light: lines.append(EffectLine(symbol: "sun.max", text: "Switch macOS to Light appearance"))
        case .system: break
        }
        if !system.hideApps.isEmpty { lines.append(EffectLine(symbol: "eye.slash", text: "Hide \(names(system.hideApps)) (never quits them)")) }
        if !system.openApps.isEmpty { lines.append(EffectLine(symbol: "arrow.up.forward.app", text: "Open \(names(system.openApps))")) }
        if let dock = system.dockAutoHide { lines.append(EffectLine(symbol: "dock.rectangle", text: dock ? "Hide the Dock automatically" : "Always show the Dock")) }
        if let volume = system.outputVolume { lines.append(EffectLine(symbol: "speaker.wave.2", text: "Set the volume to \(Int((volume * 100).rounded()))%")) }
        if let focus = system.focusShortcut, !focus.isEmpty { lines.append(EffectLine(symbol: "moon.circle", text: "Run the shortcut “\(focus)” to turn on a Focus")) }
        return lines
    }

    /// Changes whenever anything that touches the Mac changes, so the review is shown again after an edit.
    var effectsFingerprint: String {
        struct Basis: Codable {
            var wallpaper: WallpaperSetting; var appearance: Look.Appearance; var hide: [String]; var open: [String]
            var dock: Bool?; var volume: Double?; var focusOn: String?; var focusOff: String?; var restore: Bool
        }
        let basis = Basis(wallpaper: wallpaper, appearance: look.appearance, hide: system.hideApps.sorted(), open: system.openApps.sorted(),
                          dock: system.dockAutoHide, volume: system.outputVolume, focusOn: system.focusShortcut, focusOff: system.focusEndShortcut,
                          restore: system.restoreOnExit)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(basis)) ?? Data()
        return SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
