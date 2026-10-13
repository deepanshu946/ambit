#if DEBUG
import AppKit
import AmbitCore

/// Debug builds only. Lets a script see the UI without screen-recording permission:
///   AMBIT_SNAPSHOT=/path/out.png  render the window to a PNG after 3 s, then quit
///   AMBIT_SELECT=<index|history>  start on that sidebar item
///   AMBIT_SIZE=1100x2200          resize the window first (to see a long form in one shot)
///   AMBIT_SCROLL=<points>         scroll the main form down this far before the snapshot
///   AMBIT_DUMP=/path/out.txt     write the window's view tree (classes, sizes, hidden, table rows, text) and quit
///   AMBIT_APPEARANCE=dark|light   force the appearance
enum DebugHooks {
    /// AMBIT_SELFTEST=wallpaper|apps|events: drives real sessions against the real Mac and checks it after each step.
    /// Logs to stdout. `apps` = hiding apps + volume. `events` = Dock + appearance (macOS asks for permission first).
    @MainActor static func runSelfTestIfRequested(model: AppModel) {
        guard let which = env["AMBIT_SELFTEST"], model.modes.count >= 2 else { return }
        Task { @MainActor in
            let failures: [String]
            switch which {
            case "apps": failures = await appsAndVolumeTest(model)
            case "events": failures = await systemEventsTest(model)
            default: failures = await wallpaperTest(model)
            }
            print("SELFTEST", failures.isEmpty ? "RESULT PASS" : "RESULT FAIL \(failures)"); fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    private struct Reporter {
        var failures: [String] = []
        mutating func check(_ label: String, _ ok: Bool, _ detail: String) {
            print("SELFTEST", "\(ok ? "ok  " : "FAIL") \(label): \(detail)"); fflush(stdout)
            if !ok { failures.append(label) }
        }
        func log(_ s: String) { print("SELFTEST", s); fflush(stdout) }
    }

    private static func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    /// A mode that changes only what the test asks for.
    @MainActor private static func isolate(_ model: AppModel, _ change: (inout Mode) -> Void) -> Mode {
        var mode = model.modes[0]
        mode.wallpaper = .keep; mode.look.appearance = .system
        mode.system = SystemSettings()
        change(&mode)
        model.modes[0] = mode
        return mode
    }

    @MainActor private static func appsAndVolumeTest(_ model: AppModel) async -> [String] {
        var r = Reporter()
        let calc = "com.apple.calculator"
        let volume = OutputVolumeSetting(), apps = WorkspaceApps()
        guard let original = try? await volume.current() else { r.log("volume unavailable on this output"); return ["volume unavailable"] }
        let target = max(0.05, original.level - 0.05)
        r.log("volume before: \(original.level), will use \(target)")

        let launchedByTest = !apps.isRunning(calc)
        if launchedByTest { try? await apps.launch(calc); for _ in 0..<20 where !apps.isRunning(calc) { await wait(0.25) } }
        defer { if launchedByTest { NSRunningApplication.runningApplications(withBundleIdentifier: calc).forEach { $0.terminate() } } }
        guard apps.isRunning(calc) else { return ["couldn't launch Calculator"] }
        apps.unhide(calc); await wait(0.5)

        let mode = isolate(model) { $0.system.hideApps = [calc]; $0.system.outputVolume = target }
        func level() async -> Double { (try? await volume.current())?.level ?? -1 }

        // 1. start hides the app and lowers the volume; end gives both back
        model.start(mode.id); await wait(3)
        r.check("start hides the app", apps.isHidden(calc), "hidden=\(apps.isHidden(calc))")
        r.check("start sets the volume", abs(await level() - target) < 0.02, "now \(await level())")
        await model.endSession(cancel: true); await wait(1.5)
        r.check("end unhides the app", !apps.isHidden(calc), "hidden=\(apps.isHidden(calc))")
        r.check("end restores the volume", abs(await level() - original.level) < 0.02, "now \(await level())")

        // 2. an app the person had already hidden stays hidden afterwards
        apps.hide(calc); await wait(0.5)
        model.start(mode.id); await wait(3)
        await model.endSession(cancel: true); await wait(1.5)
        r.check("an app hidden beforehand stays hidden", apps.isHidden(calc), "hidden=\(apps.isHidden(calc))")
        apps.unhide(calc); await wait(0.5)

        // 3. if the person changes the volume during the session, Ambit leaves their value alone
        model.start(mode.id); await wait(3)
        let theirs = max(0.02, target - 0.1)
        try? await volume.set(OutputVolume(device: original.device, level: theirs)); await wait(0.5)
        await model.endSession(cancel: true); await wait(1.5)
        r.check("a volume the person changed is left alone", abs(await level() - theirs) < 0.02, "now \(await level()), theirs \(theirs)")

        // cleanup: the volume goes back to what it was before the test, whatever happened
        try? await volume.set(original); await wait(0.5)
        r.check("test cleanup left the volume as found", abs(await level() - original.level) < 0.02, "now \(await level())")
        return r.failures
    }

    @MainActor private static func systemEventsTest(_ model: AppModel) async -> [String] {
        var r = Reporter()
        let dock = SystemEventsSetting(kind: .dockAutohide), dark = SystemEventsSetting(kind: .darkMode)
        let dockBefore: Bool
        do { dockBefore = try await dock.current() } catch {
            r.log("Dock read failed: \(error.localizedDescription)  [\(error)]")
            return ["Dock unreadable"]
        }
        r.log("dock autohide before: \(dockBefore)")
        let mode1 = isolate(model) { $0.system.dockAutoHide = !dockBefore }
        model.start(mode1.id); await wait(4)
        r.check("start changes the Dock", ((try? await dock.current()) ?? dockBefore) == !dockBefore, "now \((try? await dock.current()) ?? false) notice=\(model.notice ?? "none")")
        await model.endSession(cancel: true); await wait(3)
        r.check("end restores the Dock", ((try? await dock.current()) ?? !dockBefore) == dockBefore, "now \((try? await dock.current()) ?? false)")

        guard let darkBefore = try? await dark.current() else { r.log("appearance not testable (Auto appearance?)"); return r.failures }
        r.log("dark mode before: \(darkBefore)")
        let mode2 = isolate(model) { $0.look.appearance = darkBefore ? .light : .dark }
        model.start(mode2.id); await wait(4)
        r.check("start changes appearance", ((try? await dark.current()) ?? darkBefore) == !darkBefore, "now \((try? await dark.current()) ?? false) notice=\(model.notice ?? "none")")
        await model.endSession(cancel: true); await wait(4)
        r.check("end restores appearance", ((try? await dark.current()) ?? !darkBefore) == darkBefore, "now \((try? await dark.current()) ?? false)")
        return r.failures
    }

    @MainActor private static func wallpaperTest(_ model: AppModel) async -> [String] {
        var r = Reporter()
        let backend = NSWorkspaceBackend()
        @MainActor func name() -> String { backend.displayIDs().compactMap { backend.currentWallpaper(on: $0)?.url.lastPathComponent }.joined(separator: ",") }
        @MainActor func waitUntilApplied() async { for _ in 0..<60 where !model.effects.wallpaperApplied { await wait(0.5) }; await wait(1.5) }
        let a = isolate(model) { $0.wallpaper = .bundled(id: "deep-1") }
        var b = model.modes[1]
        b.system = SystemSettings(); b.look.appearance = .system; b.wallpaper = .bundled(id: "study-1"); model.modes[1] = b
        let before = name()
        r.log("baseline: \(before)")

        // 1. start, end
        model.start(a.id); await waitUntilApplied()
        r.check("start changes wallpaper", name() != before, name())
        await model.endSession(cancel: true); await wait(1)
        r.check("end restores", name() == before && !model.effects.wallpaperApplied, "\(name()) notice=\(model.notice ?? "none")")

        // 2. switch modes mid-session, then end: must return to the ORIGINAL, not mode A's picture
        model.start(a.id); await waitUntilApplied()
        let first = name()
        model.start(b.id); await waitUntilApplied()
        r.check("switch changes to the other mode", name() != first && name() != before, "\(first) -> \(name())")
        await model.endSession(cancel: true); await wait(1)
        r.check("end after switch restores the original", name() == before, "\(name()) notice=\(model.notice ?? "none")")

        // 3. end immediately followed by start (no waiting in between)
        model.start(a.id); await waitUntilApplied()
        model.end(cancel: true)
        model.start(b.id)
        await waitUntilApplied()
        r.check("quick end-then-start lands on the new mode", name() != before && model.activeModeID == b.id, "\(name()) notice=\(model.notice ?? "none")")
        await model.endSession(cancel: true); await wait(1)
        r.check("and restores the original after", name() == before, "\(name()) notice=\(model.notice ?? "none")")
        return r.failures
    }

    private static let env = ProcessInfo.processInfo.environment

    static var selection: String? { env["AMBIT_SELECT"] }

    @MainActor static func installSnapshotIfRequested() {
        switch env["AMBIT_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        if let dumpPath = env["AMBIT_DUMP"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                var out = ""
                @MainActor func walk(_ v: NSView, _ depth: Int) {
                    var line = String(repeating: "  ", count: depth) + "\(type(of: v)) frame=\(Int(v.frame.minX)),\(Int(v.frame.minY)) \(Int(v.frame.width))x\(Int(v.frame.height))"
                    if v.isHidden { line += " HIDDEN" }
                    if v.alphaValue < 1 { line += " alpha=\(v.alphaValue)" }
                    if let t = v as? NSTableView { line += " rows=\(t.numberOfRows) visibleRect=\(Int(t.visibleRect.width))x\(Int(t.visibleRect.height))" }
                    if let t = v as? NSTextField, !t.stringValue.isEmpty { line += " text=\"\(t.stringValue)\" color=\(t.textColor?.description ?? "nil")" }
                    out += line + "\n"
                    v.subviews.forEach { walk($0, depth + 1) }
                }
                for w in NSApp.windows where w.isVisible && w.styleMask.contains(.titled) {
                    out += "WINDOW \(w.title) frame=\(w.frame) appearance=\(w.effectiveAppearance.name.rawValue)\n"
                    if let root = w.contentView?.superview { walk(root, 0) }
                }
                try? out.write(toFile: dumpPath, atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
            }
            return
        }
        guard let path = env["AMBIT_SNAPSHOT"] else { return }
        if let size = env["AMBIT_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let window = NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) }
                window?.setFrame(NSRect(x: 0, y: 0, width: size[0], height: size[1]), display: true)
            }
        }
        if let points = env["AMBIT_SCROLL"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { MainActor.assumeIsolated {
                let window = NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) }
                var best: NSScrollView?
                @MainActor func walk(_ v: NSView) {
                    if let s = v as? NSScrollView, (s.documentView?.frame.height ?? 0) > (best?.documentView?.frame.height ?? 0) { best = s }
                    v.subviews.forEach(walk)
                }
                if let root = window?.contentView { walk(root) }
                best?.documentView?.scroll(NSPoint(x: 0, y: points))
            } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            let window = NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) }
            if let frame = window?.contentView?.superview {   // the frame view includes the title bar
                if let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) {
                    frame.cacheDisplay(in: frame.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
                }
            }
            NSApp.terminate(nil)
        }
    }
}
#endif
