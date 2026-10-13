import SwiftUI
import AmbitCore

struct ModeDetailView: View {
    @Binding var mode: Mode

    var body: some View {
        Form {
            Section {
                ModeHero(mode: mode)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                SessionRow(mode: mode)
            }

            Section("General") {
                TextField("Name", text: $mode.name)
                TextField("Tagline", text: $mode.tagline)
                LabeledContent("Symbol") { SymbolGrid(selection: $mode.symbol) }
            }

            WallpaperPicker(mode: $mode)

            Section {
                Picker("Appearance", selection: $mode.look.appearance) {
                    Text("Match system").tag(Look.Appearance.system)
                    Text("Light").tag(Look.Appearance.light)
                    Text("Dark").tag(Look.Appearance.dark)
                }
                .pickerStyle(.segmented)
                Toggle("Custom accent colour", isOn: Binding(
                    get: { mode.look.accent != nil },
                    set: { mode.look.accent = $0 ? (mode.look.accent ?? RGB(0, 0.48, 1)) : nil }))
                if mode.look.accent != nil {
                    ColorPicker("Accent colour", selection: accentBinding, supportsOpacity: false)
                }
            } header: {
                Text("Look")
            } footer: {
                Text("Light or Dark switches macOS itself for the session. If your Mac is set to Auto appearance, Ambit leaves it alone. The accent colour is used inside Ambit.")
            }

            AppListEditor(title: "Hide these apps", footer: "Ambit hides them. It never quits an app.", bundleIDs: $mode.system.hideApps)
            AppListEditor(title: "Open these apps", footer: nil, bundleIDs: $mode.system.openApps)

            Section {
                Picker("Dock", selection: dockChoice) {
                    Text("Don’t change").tag(DockChoice.leave)
                    Text("Hide automatically").tag(DockChoice.hide)
                    Text("Always show").tag(DockChoice.show)
                }
                Toggle("Set the volume", isOn: Binding(
                    get: { mode.system.outputVolume != nil },
                    set: { mode.system.outputVolume = $0 ? (mode.system.outputVolume ?? 0.5) : nil }))
                if mode.system.outputVolume != nil {
                    Slider(value: Binding(get: { mode.system.outputVolume ?? 0.5 }, set: { mode.system.outputVolume = $0 }), in: 0...1) {
                        Text("Volume")
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill").accessibilityHidden(true)
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill").accessibilityHidden(true)
                    }
                }
                Toggle("Restore everything when the session ends", isOn: $mode.system.restoreOnExit)
            } header: {
                Text("System")
            } footer: {
                Text("Ambit changes these when a session starts and puts them back when it ends. If you change one yourself during a session, Ambit leaves your change alone. The first time, macOS asks whether Ambit may control System Events; that is what changes the Dock and appearance.")
            }

            FocusSection(on: $mode.system.focusShortcut, off: $mode.system.focusEndShortcut)

            Section {
                ForEach(PanelComponent.allCases, id: \.self) { component in
                    Toggle(component.title, isOn: Binding(
                        get: { mode.panel.contains(component) },
                        set: { on in
                            if on { if !mode.panel.contains(component) { mode.panel.append(component) } }
                            else { mode.panel.removeAll { $0 == component } }
                        }))
                }
                if mode.panel.contains(.notepad) {
                    TextField("Notes folder", text: $mode.notepad.folder, prompt: Text(NotepadSettings.defaultFolder))
                }
            } header: {
                Text("Session panel")
            } footer: {
                Text("The notepad opens when the mode starts, docked at the right edge, and you can drag it anywhere. What you type is saved as a new note in the chosen folder in Notes, once per session. The first time, macOS asks whether Ambit may control Notes. The other parts are saved with the mode but have no on-screen panel yet.")
            }
        }
        .formStyle(.grouped)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(mode.name)
    }

    private enum DockChoice: Hashable { case leave, hide, show }

    private var dockChoice: Binding<DockChoice> {
        Binding(
            get: { switch mode.system.dockAutoHide { case nil: .leave; case true?: .hide; case false?: .show } },
            set: { mode.system.dockAutoHide = switch $0 { case .leave: nil; case .hide: true; case .show: false } })
    }

    private var accentBinding: Binding<Color> {
        Binding(
            get: { Color(mode.look.accent ?? RGB(0, 0.48, 1)) },
            set: { color in
                if let ns = NSColor(color).usingColorSpace(.sRGB) {
                    mode.look.accent = RGB(ns.redComponent, ns.greenComponent, ns.blueComponent)
                }
            })
    }
}

private struct ModeHero: View {
    let mode: Mode
    @Environment(WallpaperLibrary.self) private var library

    var body: some View {
        let accent = mode.look.accent.map(Color.init) ?? .accentColor
        ZStack(alignment: .bottomLeading) {
            WallpaperThumb(
                url: library.imageURL(for: mode.wallpaper), maxPixel: 1600,
                fallback: AnyShapeStyle(LinearGradient(colors: [accent, accent.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            // Dark scrim keeps white text readable on bright photos.
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: UnitPoint(x: 0.5, y: 0.3), endPoint: .bottom)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: mode.symbol).font(.system(size: 30, weight: .medium)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.name).font(.largeTitle.weight(.bold))
                    if !mode.tagline.isEmpty { Text(mode.tagline).font(.title3).opacity(0.92) }
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
            .padding(22)
        }
        .aspectRatio(2.5, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mode.name). \(mode.tagline)")
    }
}

private struct SessionRow: View {
    @Environment(AppModel.self) private var model
    let mode: Mode

    private var isActive: Bool { model.activeModeID == mode.id }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Duration.seconds(isActive ? Int(model.clock.elapsed(at: context.date)) : 0),
                         format: .time(pattern: .hourMinuteSecond))
                        .font(.system(size: 40, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isActive ? .primary : .tertiary)
                }
                Text(status).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Button(model.clock.isPaused ? "Resume" : "Pause", systemImage: model.clock.isPaused ? "play.fill" : "pause.fill") {
                    model.togglePause()
                }
                Button("End session", systemImage: "stop.fill") { model.end() }
                    .buttonStyle(.borderedProminent)
                Button("Discard", role: .destructive) { model.end(cancel: true) }
            } else {
                Button("Start \(mode.name)", systemImage: "play.fill") { model.start(mode.id) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(.vertical, 4)
    }

    private var status: String {
        guard isActive else { return "No session running" }
        if let working = model.effects.status { return working }
        let base = model.clock.isPaused ? "Paused" : "Session running"
        let changed = model.effects.applied
        return changed.isEmpty ? base : "\(base) · changed: \(changed.formatted(.list(type: .and, width: .narrow)))"
    }
}

private struct SymbolGrid: View {
    @Binding var selection: String
    private static let symbols = [
        "scope", "book", "calendar", "safari", "moon.stars", "video", "paintpalette", "laptopcomputer",
        "pencil.and.outline", "music.note", "figure.mind.and.body", "leaf", "flame", "bolt", "graduationcap", "gamecontroller",
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 30, maximum: 30), spacing: 4)], alignment: .trailing, spacing: 4) {
            ForEach(Self.symbols, id: \.self) { symbol in
                Button { selection = symbol } label: {
                    Image(systemName: symbol)
                        .symbolVariant(selection == symbol ? .fill : .none)
                        .frame(width: 30, height: 30)
                        .background(selection == symbol ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 7))
                        .contentShape(.rect(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                .accessibilityAddTraits(selection == symbol ? .isSelected : [])
            }
        }
        .frame(maxWidth: 260)
    }
}

extension PanelComponent {
    var title: String {
        switch self {
        case .timer: "Timer"
        case .clock: "Clock"
        case .priorities: "Priorities"
        case .sound: "Sound"
        case .quickNote: "Quick note"
        case .notepad: "Notepad (saves to Notes)"
        }
    }
}

extension Color {
    init(_ rgb: RGB) { self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1) }
}

/// macOS has no way for an app to switch a Focus directly; the supported route is a shortcut that contains "Set Focus".
private struct FocusSection: View {
    @Binding var on: String?
    @Binding var off: String?
    @State private var names: [String] = []
    @State private var loaded = false

    var body: some View {
        Section {
            picker("Turn Focus on", selection: $on)
            picker("Turn Focus off", selection: $off)
        } header: {
            Text("Focus")
        } footer: {
            Text("In the Shortcuts app, make one shortcut with the “Set Focus” action that turns a Focus on, and another that turns it off. Pick them here. Without a “turn off” shortcut, Ambit can’t switch the Focus off when the session ends.")
        }
        .task {
            names = await ShortcutsCLI().names()
            loaded = true
        }
    }

    private func picker(_ title: String, selection: Binding<String?>) -> some View {
        let current = selection.wrappedValue ?? ""
        let options = names.contains(current) || current.isEmpty ? names : [current] + names     // keep a saved name even if it's gone
        return Picker(title, selection: Binding(get: { current }, set: { selection.wrappedValue = $0.isEmpty ? nil : $0 })) {
            Text("None").tag("")
            ForEach(options, id: \.self) { name in
                Text(names.contains(name) || !loaded ? name : "\(name) (not found)").tag(name)
            }
        }
    }
}
