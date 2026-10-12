import Foundation

/// A feature added to a starter mode in a later release reaches people who already have that mode saved, once.
/// After that the person's own choice (for example turning it off) is never undone.
public struct PresetUpgrade: Sendable {
    public let id: String
    public let modeID: UUID
    let change: @Sendable (inout Mode) -> Void
}

public enum PresetUpgrades {
    private static let meeting = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!

    public static let all: [PresetUpgrade] = [
        PresetUpgrade(id: "meeting-notepad", modeID: meeting) { mode in
            if !mode.panel.contains(.notepad) { mode.panel.append(.notepad) }
        },
    ]

    /// Applies each upgrade that hasn't been applied yet. Returns the updated modes and the ids now applied.
    public static func apply(to modes: [Mode], alreadyApplied: Set<String>) -> (modes: [Mode], applied: Set<String>) {
        var modes = modes
        var applied = alreadyApplied
        for upgrade in all where !applied.contains(upgrade.id) {
            if let index = modes.firstIndex(where: { $0.id == upgrade.modeID }) { upgrade.change(&modes[index]) }
            applied.insert(upgrade.id)
        }
        return (modes, applied)
    }

    /// A brand-new install already has the feature in its starter modes, so nothing needs upgrading.
    public static var allIDs: Set<String> { Set(all.map(\.id)) }
}
