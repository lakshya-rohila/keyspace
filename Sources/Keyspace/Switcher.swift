import AppKit

/// Shows one space's apps and hides the rest, using macOS's native app hide/unhide
/// (the same as ⌘H). No Accessibility API, no window moving, no layout math —
/// that's why this stays fast where tiling managers stutter.
final class Switcher {
    let store: SpaceStore
    private var suppressUntil = Date.distantPast

    init(store: SpaceStore) { self.store = store }

    /// While we're switching, the apps we unhide/activate fire "didActivate" notifications.
    /// AppDelegate ignores those during this window so it doesn't chase its own tail.
    var isSuppressingActivation: Bool { Date() < suppressUntil }

    func switchTo(_ space: SpaceKey) {
        suppressUntil = Date().addingTimeInterval(0.8)
        store.state.current = space

        let apps = regularApps()                     // running, user-facing apps (not Keyspace)
        let wanted = Set(store.apps(in: space))      // bundle IDs assigned to `space`
        let focusID = store.state.lastFocused[space]   // may be nil or not running

        let runningIDs = Set(apps.compactMap(\.bundleIdentifier))

        // 1. Show this space's apps (unassigned apps "float" and are never touched).
        for app in apps where wanted.contains(app.bundleIdentifier!) { app.unhide() }

        // 2. Optionally launch assigned apps that aren't running.
        if store.state.launchMissingApps {
            for id in wanted.subtracting(runningIDs) where id != focusID { bringToFront(id) }
        }

        // 3. Pick who gets focus: last-focused here, else any running app of this space.
        let canLaunch = store.state.launchMissingApps
        let focus = [focusID].compactMap { $0 }
            .first { wanted.contains($0) && (runningIDs.contains($0) || canLaunch) }
            ?? wanted.sorted().first { runningIDs.contains($0) || canLaunch }

        // 4. Hide apps that belong to other spaces — only AFTER the focus app is in front,
        //    otherwise macOS hands focus to a random app and the screen flickers.
        let hideOthers = { [store] in
            for app in apps {
                if let s = store.space(of: app.bundleIdentifier!), s != space { app.hide() }
            }
        }
        if let focus {
            store.state.lastFocused[space] = focus
            bringToFront(focus, then: hideOthers)
        } else {
            hideOthers()   // empty space → clean desktop
        }

        store.save()
    }

    func showEverything() {
        regularApps().forEach { $0.unhide() }
    }

    func regularApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0 != .current
        }
    }

    /// Reliable "bring this app forward" across macOS versions. NSRunningApplication.activate()
    /// is subject to cooperative activation (macOS 14+) and can be refused for a background
    /// menu-bar app; asking LaunchServices to open the app is always honored.
    func bringToFront(_ bundleID: String, then done: (() -> Void)? = nil) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            done?(); return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in
            if let done { DispatchQueue.main.async(execute: done) }
        }
    }
}
