import Foundation
import Observation
import AppKit
import AmbitCore

@Observable
final class AppModel {
    var modes: [Mode] { didSet { try? modeStore.save(modes) } }
    private(set) var history: [SessionRecord] { didSet { try? historyStore.save(history) } }
    private(set) var activeModeID: Mode.ID?
    private(set) var clock = SessionClock()
    /// Something the person should know about, e.g. a wallpaper that couldn't be restored. Stays until dismissed.
    private(set) var notice: String?
    let effects: SystemEffects
    /// A mode waiting for the person's OK before it changes the Mac for the first time (or after its changes were edited).
    private(set) var pendingReview: Mode?
    /// Set to jump the window to a mode (the review's "Edit mode" button). The window clears it.
    var selectionRequest: Mode.ID?

    @ObservationIgnored private let modeStore: JSONStore<[Mode]>
    @ObservationIgnored private let historyStore: JSONStore<[SessionRecord]>

    @ObservationIgnored private var sessionToken = UUID()
    @ObservationIgnored private let acknowledgementStore: JSONStore<[String: String]>
    @ObservationIgnored private var acknowledged: [String: String]     // mode id -> fingerprint of the changes the person approved

    init(effects: SystemEffects,
         modeStore: JSONStore<[Mode]> = .appSupport("modes"),
         historyStore: JSONStore<[SessionRecord]> = .appSupport("history"),
         acknowledgementStore: JSONStore<[String: String]> = .appSupport("acknowledged")) {
        self.effects = effects
        self.modeStore = modeStore
        self.historyStore = historyStore
        self.acknowledgementStore = acknowledgementStore
        acknowledged = acknowledgementStore.load() ?? [:]
        let saved = modeStore.load()
        let merged = saved.map(DefaultModes.addingMissing(to:)) ?? DefaultModes.all      // new starter modes appear for existing users
        modes = merged
        if let saved, merged.count != saved.count { try? modeStore.save(merged) }
        history = historyStore.load() ?? []
        effects.onNotice = { [weak self] text in
            guard let self else { return }
            if let text { notice = text } else if notice == SystemEffects.pendingNotice { notice = nil }   // the waiting restore finished
        }
        #if DEBUG
        notice = ProcessInfo.processInfo.environment["AMBIT_NOTICE"]      // to see how a banner sits in the layout
        #endif
        Task { [weak self] in
            guard let self else { return }
            post(await effects.recoverFromCrash())
        }
    }

    func dismissNotice() { notice = nil }

    private func post(_ lines: [String]) {
        if !lines.isEmpty { notice = lines.joined(separator: "\n") }
    }

    var activeMode: Mode? { modes.first { $0.id == activeModeID } }

    /// A mode that changes the Mac asks first, once, and again whenever what it changes is edited.
    private func needsReview(_ mode: Mode) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMBIT_SELFTEST"] != nil { return false }
        #endif
        return !mode.effectsSummary().isEmpty && acknowledged[mode.id.uuidString] != mode.effectsFingerprint
    }

    /// Starting a mode while another is running ends the old session (it counts as completed).
    func start(_ id: Mode.ID, reviewed: Bool = false) {
        guard let mode = modes.first(where: { $0.id == id }), activeModeID != id else { return }
        if !reviewed && needsReview(mode) { pendingReview = mode; return }
        if reviewed {
            acknowledged[mode.id.uuidString] = mode.effectsFingerprint
            try? acknowledgementStore.save(acknowledged)
        }
        finishSession(cancel: false)       // the Mac stays as is; the new mode decides what it should look like
        clock = SessionClock()
        clock.start(at: .now)
        activeModeID = id
        let token = UUID()
        sessionToken = token
        Task { [weak self] in
            guard let self else { return }
            let problems = await effects.enter(mode) { [weak self] in self?.sessionToken == token }
            if sessionToken == token { post(problems) }
        }
    }

    func confirmReview() {
        guard let mode = pendingReview else { return }
        pendingReview = nil
        start(mode.id, reviewed: true)
    }

    func cancelReview() { pendingReview = nil }

    func editPendingMode() {
        selectionRequest = pendingReview?.id
        pendingReview = nil
    }

    func togglePause() {
        if clock.isRunning { clock.pause(at: .now) } else { clock.resume(at: .now) }
    }

    /// Completed = the user ended it; cancelled = the user discarded it. Neither can be recorded twice.
    func end(cancel: Bool = false) {
        let leaving = beginEnding(cancel: cancel)       // the session ends right now, so an immediate start() can't be confused with it
        Task { [weak self] in
            guard let self else { return }
            post(await effects.leave(leaving))
        }
    }

    /// Ends the session and waits for the desktop to be put back. Quitting awaits this.
    func endSession(cancel: Bool = false) async {
        let leaving = beginEnding(cancel: cancel)
        post(await effects.leave(leaving))
    }

    private func beginEnding(cancel: Bool) -> Mode? {
        let mode = activeMode
        finishSession(cancel: cancel)
        sessionToken = UUID()                           // a wallpaper download still in flight must not apply after this
        return mode
    }

    private func finishSession(cancel: Bool) {
        guard let mode = activeMode, let startedAt = clock.startedAt,
              let elapsed = clock.finish(at: .now) else { return }
        if SessionRecord.shouldRecord(elapsed: elapsed) {
            history.append(SessionRecord(modeID: mode.id, modeName: mode.name, startedAt: startedAt,
                                         endedAt: .now, elapsed: elapsed, status: cancel ? .cancelled : .completed))
        }
        activeModeID = nil
        clock.reset()
    }
}
