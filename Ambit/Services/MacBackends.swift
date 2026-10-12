import AppKit
import AudioToolbox
import CoreAudio
import AmbitCore

// MARK: - Apps

@MainActor struct WorkspaceApps: AppsBackend {
    var ownBundleID: String? { Bundle.main.bundleIdentifier }

    private func instances(_ id: String) -> [NSRunningApplication] { NSRunningApplication.runningApplications(withBundleIdentifier: id) }
    func isRunning(_ id: String) -> Bool { !instances(id).isEmpty }
    func isHidden(_ id: String) -> Bool { let all = instances(id); return !all.isEmpty && all.allSatisfy(\.isHidden) }
    func hide(_ id: String) { instances(id).forEach { _ = $0.hide() } }       // the result is unreliable (false even on success)
    func unhide(_ id: String) { instances(id).forEach { _ = $0.unhide() } }

    func launch(_ id: String) async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { throw CocoaError(.fileNoSuchFile) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false              // don't steal focus from the mode's first app
        configuration.addsToRecentItems = false
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}

// MARK: - System Events: Dock auto-hide and light/dark

enum AppleScript {
    struct Denied: LocalizedError {
        var errorDescription: String? {
            "macOS didn’t let Ambit control System Events, so the Dock and appearance weren’t changed. Allow it in System Settings > Privacy & Security > Automation."
        }
    }
    struct Failed: LocalizedError {
        let detail: String
        var errorDescription: String? { "macOS couldn’t make that change: \(detail)" }
    }

    /// Runs on a background thread: the first run can sit behind a macOS permission prompt, and the window must not freeze.
    @concurrent static func bool(_ source: String) async throws -> Bool {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw Failed(detail: "the script couldn’t be created") }
        let result = script.executeAndReturnError(&error)
        if let error {
            if (error["NSAppleScriptErrorNumber"] as? Int) == -1743 { throw Denied() }   // errAEEventNotPermitted
            throw Failed(detail: error["NSAppleScriptErrorMessage"] as? String ?? "unknown error")
        }
        return result.booleanValue
    }
}

@MainActor struct SystemEventsSetting: SettingBackend {
    enum Kind { case dockAutohide, darkMode }
    struct AutoAppearance: LocalizedError {
        var errorDescription: String? { "Your Mac’s appearance is set to Auto, so Ambit left it alone. Choose Light or Dark in System Settings > Appearance to let a mode change it." }
    }
    let kind: Kind

    func current() async throws -> Bool {
        if kind == .darkMode, UserDefaults.standard.bool(forKey: "AppleInterfaceStyleSwitchesAutomatically") { throw AutoAppearance() }
        switch kind {
        case .dockAutohide: return try await AppleScript.bool("tell application \"System Events\" to get autohide of dock preferences")
        case .darkMode: return try await AppleScript.bool("tell application \"System Events\" to tell appearance preferences to get dark mode")
        }
    }

    func set(_ value: Bool) async throws {
        switch kind {
        case .dockAutohide: _ = try await AppleScript.bool("tell application \"System Events\" to set autohide of dock preferences to \(value)\nreturn true")
        case .darkMode: _ = try await AppleScript.bool("tell application \"System Events\" to tell appearance preferences to set dark mode to \(value)\nreturn true")
        }
    }
}

// MARK: - Output volume (CoreAudio)

nonisolated struct OutputVolume: Codable, Equatable, Sendable {
    var device: String     // the device's UID, so a restore never lands on a different output
    var level: Double      // 0...1
}

@MainActor struct OutputVolumeSetting: SettingBackend {
    enum Failure: LocalizedError {
        case noDevice, notAdjustable, deviceChanged
        var errorDescription: String? {
            switch self {
            case .noDevice: "There’s no sound output to set the volume on."
            case .notAdjustable: "Your sound output doesn’t let apps change its volume, so Ambit left it alone."
            case .deviceChanged: "The sound output changed, so Ambit left the volume alone."
            }
        }
    }

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

    private func defaultOutput() throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { throw Failure.noDevice }
        return device
    }

    private func uid(of device: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr, let uid else { throw Failure.noDevice }
        return uid.takeRetainedValue() as String
    }

    private func adjustable(_ device: AudioObjectID) -> Bool {
        var address = Self.volumeAddress
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &address)
            && AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    /// The setting to apply for `level`: on whichever output is the default right now.
    func target(level: Double) throws -> OutputVolume { OutputVolume(device: try uid(of: defaultOutput()), level: level) }

    func current() async throws -> OutputVolume {
        let device = try defaultOutput()
        guard adjustable(device) else { throw Failure.notAdjustable }
        var address = Self.volumeAddress
        var level = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &level) == noErr else { throw Failure.notAdjustable }
        return OutputVolume(device: try uid(of: device), level: Double(level))
    }

    func set(_ value: OutputVolume) async throws {
        let device = try defaultOutput()
        guard try uid(of: device) == value.device else { throw Failure.deviceChanged }
        guard adjustable(device) else { throw Failure.notAdjustable }
        var address = Self.volumeAddress
        var level = Float32(min(max(value.level, 0), 1))
        guard AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &level) == noErr else { throw Failure.notAdjustable }
    }

    func matches(_ a: OutputVolume, _ b: OutputVolume) -> Bool { a.device == b.device && abs(a.level - b.level) < 0.02 }
}

// MARK: - Shortcuts app (Focus)

@MainActor struct ShortcutsCLI: ShortcutsBackend {
    struct Failure: LocalizedError {
        let name: String
        let detail: String
        var errorDescription: String? { "The shortcut “\(name)” didn’t run\(detail.isEmpty ? "" : " (\(detail))"). Check it in the Shortcuts app." }
    }

    func run(_ name: String) async throws {
        let result = try await Self.execute(["run", name], timeout: .seconds(30))
        guard result.status == 0 else { throw Failure(name: name, detail: result.error.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    func names() async -> [String] {
        guard let result = try? await Self.execute(["list"], timeout: .seconds(10)), result.status == 0 else { return [] }
        return result.output.split(separator: "\n").map(String.init).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private struct Result: Sendable { var status: Int32; var output: String; var error: String }

    @concurrent private static func execute(_ arguments: [String], timeout: Duration) async throws -> Result {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/shortcuts")
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out; process.standardError = err
        try process.run()
        let deadline = ContinuousClock.now + timeout
        while process.isRunning {
            if ContinuousClock.now > deadline { process.terminate(); throw Failure(name: arguments.last ?? "", detail: "it took too long") }
            try await Task.sleep(for: .milliseconds(100))
        }
        let output = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let error = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return Result(status: process.terminationStatus, output: output, error: error)
    }
}
