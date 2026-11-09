import AppKit
import CoreGraphics

/// Shows one space's apps and hides the rest, using macOS's native app hide/unhide
/// (the same as ⌘H). No Accessibility API, no window moving, no layout math.
///
/// Robustness model:
/// - Every switch gets a `generation`. Delayed work from an older switch is dropped, so
///   rapid key presses never fight each other.
/// - After a switch we *verify* the right app is in front and re-assert it if not.
/// - Activations of apps from other spaces only move you there when the USER caused them
///   (click, ⌘-Tab, typing, an app they launched). Activations macOS makes on its own while
///   we hide things are undone instead of followed — that was the "key bounced back" bug.
final class Switcher {
    let store: SpaceStore
    init(store: SpaceStore) { self.store = store }

    private(set) var generation = 0
    private var lastSwitchAt = Date.distantPast
    private var settleUntil = Date.distantPast
    private var focusTarget: String?            // app that should be frontmost after the switch
    private var enforceCount = 0                // re-assertions used in this generation
    private var launchedByUs: [String: Date] = [:]
    private var launchedByUser: [String: Date] = [:]

    /// True for a short window after a switch while macOS shuffles focus around.
    var isSettling: Bool { Date() < settleUntil }

    // MARK: Switching

    func switchTo(_ space: SpaceKey) {
        generation += 1
        let gen = generation
        enforceCount = 0
        lastSwitchAt = Date()
        let previous = store.state.current
        store.state.current = space

        let apps = regularApps()

        // Apps with no key that are on screen belong to the space we're leaving; otherwise
        // they would float over every key.
        if store.state.autoAssign && previous != space {
            for app in apps where !app.isHidden && store.space(of: app.bundleIdentifier!) == nil {
                store.assign(app.bundleIdentifier!, to: previous)
            }
        }

        let wanted = Set(store.apps(in: space))
        let runningIDs = Set(apps.compactMap(\.bundleIdentifier))
        let remembered = store.state.lastFocused[space].flatMap { wanted.contains($0) ? $0 : nil }

        // 1. Show this space's apps.
        for app in apps where wanted.contains(app.bundleIdentifier!) && app.isHidden { app.unhide() }

        // 2. Optionally launch every assigned app that isn't running.
        if store.state.launchMissingApps {
            for id in wanted.subtracting(runningIDs) where id != remembered { open(id) }
        }

        // 3. Focus: last-focused if running, else any running app here, else launch one.
        let focus = remembered.flatMap { runningIDs.contains($0) ? $0 : nil }
            ?? wanted.sorted().first { runningIDs.contains($0) }
            ?? remembered
            ?? wanted.sorted().first
        let launching = focus.map { !runningIDs.contains($0) } ?? false
        focusTarget = focus
        settleUntil = Date().addingTimeInterval(launching ? 6.0 : 1.5)

        if let focus {
            store.state.lastFocused[space] = focus
            open(focus) { [weak self] in self?.hideOthers(gen) }
            // Verify: a moment later the focus app must be in front; re-assert if not.
            let checks: [Double] = launching ? [0.4, 1.0, 2.0, 3.5, 5.0] : [0.3, 0.7, 1.2]
            for t in checks {
                DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in self?.verify(gen) }
            }
        } else {
            // Empty space → clean desktop. Take focus ourselves first (otherwise macOS
            // re-activates — and un-hides — some random app), then "Hide Others".
            open(Bundle.main.bundleURL) { [weak self] in
                guard let self, gen == self.generation else { return }
                NSWorkspace.shared.hideOtherApplications()
                self.hideOthers(gen)
            }
        }
        store.save()
        NSLog("Keyspace: switch #%d -> %@ focus=%@", gen, space, focus ?? "-")
    }

    /// Hide every visible app that belongs to another space (now and once things settle,
    /// because macOS ignores hide() on an app that is mid-activation).
    private func hideOthers(_ gen: Int) {
        hidePass(gen)
        for t in [0.25, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in self?.hidePass(gen) }
        }
    }

    private func hidePass(_ gen: Int) {
        guard gen == generation else { return }          // user already pressed another key
        let space = store.state.current
        for app in regularApps() where !app.isHidden {
            if let s = store.space(of: app.bundleIdentifier!), s != space { app.hide() }
        }
    }

    /// Make sure the switch actually landed. If some other space's app is in front, bring the
    /// focus app back and hide the intruder.
    private func verify(_ gen: Int) {
        guard gen == generation, let focus = focusTarget else { return }
        guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
        if front == focus { hidePass(gen); return }
        let current = store.state.current
        let frontSpace = store.space(of: front)
        // Fine: another app of this space, an unassigned app, or Keyspace itself.
        if frontSpace == current || frontSpace == nil { hidePass(gen); return }
        // Still launching? Wait for it.
        if NSRunningApplication.runningApplications(withBundleIdentifier: focus).isEmpty { return }
        reassert(gen, reason: "verify: \(front) in front")
    }

    private func reassert(_ gen: Int, reason: String) {
        guard gen == generation, let focus = focusTarget, enforceCount < 4 else { return }
        enforceCount += 1
        NSLog("Keyspace: re-assert #%d %@ (%@)", gen, focus, reason)
        open(focus) { [weak self] in self?.hideOthers(gen) }
    }

    // MARK: Activation events

    enum ActivationDecision { case follow(SpaceKey), adopt, remember, ignore }

    /// Decides what an app activation means. Called by AppDelegate for every activation.
    func handleActivation(_ app: NSRunningApplication) -> ActivationDecision {
        guard let id = app.bundleIdentifier else { return .ignore }
        let current = store.state.current
        let space = store.space(of: id)

        if id == focusTarget && isSettling {
            // The app we're waiting for arrived; macOS may still shuffle for a moment.
            settleUntil = min(settleUntil, Date().addingTimeInterval(0.6))
            return .ignore
        }
        if space == current { return isSettling ? .ignore : .remember }

        let intended = userCaused(id)
        if let space {
            if intended { return .follow(space) }
            // Not the user: macOS re-activated something we hid. Undo it, don't follow it.
            if !isSettling { enforceCount = 0 }
            reassert(generation, reason: "stray activation of \(id)")
            return .ignore
        }
        // Unassigned app.
        return (intended || !isSettling) ? .adopt : .ignore
    }

    func noteLaunch(_ id: String) {
        if let t = launchedByUs[id], Date().timeIntervalSince(t) < 15 { return }
        launchedByUser[id] = Date()
    }

    func wasLaunchedByUs(_ id: String) -> Bool {
        launchedByUs[id].map { Date().timeIntervalSince($0) < 15 } ?? false
    }

    /// Did a real person cause this activation? Uses the system's input idle timers
    /// (no Input Monitoring permission needed).
    private func userCaused(_ id: String) -> Bool {
        if let t = launchedByUser[id], Date().timeIntervalSince(t) < 15 {
            launchedByUser[id] = nil
            return true
        }
        func ago(_ type: CGEventType) -> TimeInterval {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
        }
        let sinceSwitch = Date().timeIntervalSince(lastSwitchAt)
        let click = min(ago(.leftMouseDown), ago(.rightMouseDown), ago(.otherMouseDown))
        let key = ago(.keyDown), flags = ago(.flagsChanged)

        // A click after the switch (Dock icon, notification, link) → user.
        if click < sinceSwitch && click < 1.5 { return true }
        // ⌘-Tab: Tab pressed after the switch, then ⌘ released.
        if key < sinceSwitch && flags <= key && flags < 1.0 { return true }
        // Outside the settle window, any recent keypress (Spotlight, Raycast, `open`) counts.
        if !isSettling && key < 1.5 { return true }
        return false
    }

    // MARK: Helpers

    func showEverything() {
        regularApps().forEach { $0.unhide() }
    }

    func regularApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0 != .current
        }
    }

    /// Reliable "bring forward / launch" across macOS versions: asking LaunchServices to open
    /// the app is honored even under cooperative activation (macOS 14+), unlike activate().
    private func open(_ bundleID: String, then done: (() -> Void)? = nil) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            done?(); return
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            launchedByUs[bundleID] = Date()
        }
        open(url, then: done)
    }

    private func open(_ url: URL, then done: (() -> Void)? = nil) {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in
            if let done { DispatchQueue.main.async(execute: done) }
        }
    }
}
