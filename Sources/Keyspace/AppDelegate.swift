import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = SpaceStore()
    lazy var switcher = Switcher(store: store)
    let hotKeys = HotKeys()
    var statusItem: NSStatusItem!
    var paused = false
    var settingsWindow: NSWindow?

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.load()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self            // rebuilt fresh each time it opens
        statusItem.menu = menu

        HotKeys.onPress = { [weak self] action in self?.handleHotKey(action) }
        store.onKeysChanged = { [weak self] in
            self?.registerHotkeys()
            self?.refreshTitle()
        }
        hotKeys.installHandler()
        registerHotkeys()

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(appLaunched(_:)),
                       name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appActivated(_:)),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)

        // Scriptable trigger (also used for testing):
        //   swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("local.keyspace.switch"), object: "G", userInfo: nil, deliverImmediately: true)'
        DistributedNotificationCenter.default().addObserver(
            forName: .init("local.keyspace.switch"), object: nil, queue: .main) { [weak self] note in
            guard let self, !self.paused, let key = (note.object as? String)?.uppercased(),
                  self.store.state.keys.contains(key) else { return }
            self.switcher.switchTo(key)
            self.refreshTitle()
        }

        // Re-apply the saved layout: this is the "remembers everything after restart" part.
        switcher.switchTo(store.state.current)
        refreshTitle()

        if !store.state.onboarded {
            store.state.onboarded = true
            store.save()
            showSettings(tab: .guide)
        }
    }

    /// Returns keys whose shortcuts are taken by another app.
    @discardableResult
    func registerHotkeys() -> [SpaceKey] {
        hotKeys.registerPauseKey(store.state.modifier)
        guard !paused else { return [] }
        let move = SpaceStore.sorted(store.state.keys + SpaceStore.alwaysMoveKeys)
        return hotKeys.registerSpaceKeys(switchKeys: store.state.keys, moveKeys: move, store.state.modifier)
    }

    // MARK: Settings window

    func showSettings(tab: SettingsTab = .spaces) {
        let actions = SettingsActions(
            reapply: { [weak self] in
                guard let self, !self.paused else { return }
                self.switcher.switchTo(self.store.state.current)
                self.refreshTitle()
            },
            hotkeysChanged: { [weak self] in
                guard let self else { return [] }
                defer { self.refreshTitle() }
                return self.registerHotkeys()
            })
        let root = SettingsView(store: store, actions: actions, tab: tab)
        if let w = settingsWindow {
            w.contentViewController = NSHostingController(rootView: root)
        } else {
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = "Keyspace"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Never leave apps stranded in a hidden state when Keyspace goes away.
    func applicationWillTerminate(_ notification: Notification) {
        switcher.showEverything()
        store.save()
    }

    // MARK: Hotkeys

    func handleHotKey(_ action: HotKeyAction) {
        switch action {
        case .pause: togglePause()
        case .switchTo(let key) where !paused: switcher.switchTo(key)
        case .move(let key) where !paused: moveFrontmostApp(to: key)
        default: break
        }
        refreshTitle()
    }

    func moveFrontmostApp(to space: SpaceKey) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app != .current, let id = app.bundleIdentifier else { return }
        store.assign(id, to: space)
        // Stay on the current space; re-applying it hides the app we just sent away.
        switcher.switchTo(store.state.current)
    }

    func togglePause() {
        paused.toggle()
        if paused {
            hotKeys.unregisterSpaceKeys()
            switcher.showEverything()
        } else {
            registerHotkeys()
            switcher.switchTo(store.state.current)
        }
        refreshTitle()
    }

    // MARK: Workspace events (push-based, zero cost while idle)

    @objc func appLaunched(_ note: Notification) {
        guard !paused, let app = runningApp(note), let id = app.bundleIdentifier else { return }
        if switcher.wasLaunchedByUs(id) {
            // We launched it (e.g. "Launch Missing Apps"); keep it out of other spaces.
            if let space = store.space(of: id), space != store.state.current {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { app.hide() }
            }
            return
        }
        // You launched it (Spotlight, Dock, Finder…): its activation will be followed.
        switcher.noteLaunch(id)
        if store.space(of: id) == nil && store.state.autoAssign {
            store.assign(id, to: store.state.current)
        }
    }

    @objc func appActivated(_ note: Notification) {
        guard !paused, let app = runningApp(note), let id = app.bundleIdentifier else { return }
        let current = store.state.current
        switch switcher.handleActivation(app) {
        case .follow(let space):
            // ⌘-Tab / Dock click / link / launch opened an app that lives elsewhere: follow it.
            NSLog("Keyspace: follow %@ -> space %@ (was %@)", id, space, current)
            store.state.lastFocused[space] = id
            switcher.switchTo(space)
            refreshTitle()
        case .adopt:
            guard store.state.autoAssign else { return }
            store.assign(id, to: current)
            store.state.lastFocused[current] = id
        case .remember:
            store.state.lastFocused[current] = id   // saved on next switch
        case .ignore:
            break
        }
    }

    private func runningApp(_ note: Notification) -> NSRunningApplication? {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular, app != .current else { return nil }
        return app
    }

    // MARK: Menu bar

    func refreshTitle() {
        guard let button = statusItem.button else { return }
        let symbol = paused ? "pause.circle" : "square.grid.3x3.fill"
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Keyspace")
        img?.isTemplate = true
        button.image = img
        button.imagePosition = .imageLeading
        button.title = paused ? "" : " \(store.state.current)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem(title: paused ? "Keyspace — Paused" : "Keyspace — Space \(store.state.current)",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if store.state.keys.isEmpty {
            let hint = NSMenuItem(title: "No keys yet — press \(store.state.modifier.symbol)⇧1 on any app",
                                  action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }
        for space in store.state.keys {
            let names = store.apps(in: space).map(displayName)
            let item = NSMenuItem(title: "\(store.state.modifier.symbol)\(space)   " + (names.isEmpty ? "—" : names.joined(separator: ", ")),
                                  action: #selector(menuSwitch(_:)), keyEquivalent: "")
            item.representedObject = space
            item.target = self
            item.state = space == store.state.current ? .on : .off
            item.isEnabled = !paused
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let forget = NSMenuItem(title: "Forget App", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for id in store.state.assignments.keys.sorted(by: { displayName($0) < displayName($1) }) {
            let i = NSMenuItem(title: "\(displayName(id))  (\(store.state.modifier.symbol)\(store.state.assignments[id]!))",
                               action: #selector(menuForget(_:)), keyEquivalent: "")
            i.representedObject = id
            i.target = self
            sub.addItem(i)
        }
        if sub.items.isEmpty { sub.addItem(withTitle: "No apps assigned", action: nil, keyEquivalent: "") }
        forget.submenu = sub
        menu.addItem(forget)

        addToggle(menu, "Auto-assign New Apps", store.state.autoAssign, #selector(toggleAutoAssign))
        addToggle(menu, "Launch Missing Apps on Switch", store.state.launchMissingApps, #selector(toggleLaunchMissing))
        menu.addItem(.separator())

        let m = store.state.modifier.symbol
        addAction(menu, paused ? "Resume  (\(m)⇧0)" : "Pause  (\(m)⇧0)", #selector(menuTogglePause))
        addAction(menu, "Settings…", #selector(openSettings), key: ",")
        addAction(menu, "Setup Guide", #selector(openGuide))
        addAction(menu, "Open Config Folder", #selector(openConfig))
        addAction(menu, "Reload Config", #selector(reloadConfig))
        menu.addItem(.separator())
        addAction(menu, "Quit Keyspace (shows all apps)", #selector(quit), key: "q")
    }

    private func addAction(_ menu: NSMenu, _ title: String, _ sel: Selector, key: String = "") {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        menu.addItem(i)
    }

    private func addToggle(_ menu: NSMenu, _ title: String, _ on: Bool, _ sel: Selector) {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        i.state = on ? .on : .off
        menu.addItem(i)
    }

    func displayName(_ bundleID: String) -> String { AppInfo.name(bundleID) }

    @objc func menuSwitch(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? SpaceKey else { return }
        switcher.switchTo(key)
        refreshTitle()
    }
    @objc func menuForget(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        store.forget(id)
        NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.unhide() }
    }
    @objc func toggleAutoAssign() { store.state.autoAssign.toggle(); store.save() }
    @objc func toggleLaunchMissing() { store.state.launchMissingApps.toggle(); store.save() }
    @objc func menuTogglePause() { togglePause() }
    @objc func openConfig() {
        store.save()
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }
    @objc func reloadConfig() {
        store.load()
        registerHotkeys()
        if !paused { switcher.switchTo(store.state.current) }
        refreshTitle()
    }
    @objc func openSettings() { showSettings(tab: .spaces) }
    @objc func openGuide() { showSettings(tab: .guide) }
    @objc func quit() { NSApp.terminate(nil) }
}
