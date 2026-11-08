import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Things the Settings window asks the app to do (kept as closures so the view stays dumb).
struct SettingsActions {
    var reapply: () -> Void               // re-show/hide apps after assignments change
    var hotkeysChanged: () -> [SpaceKey]  // re-register keys; returns keys taken by other apps
}

enum SettingsTab: Hashable { case spaces, general, guide }

struct SettingsView: View {
    @ObservedObject var store: SpaceStore
    let actions: SettingsActions
    @State var tab: SettingsTab

    var body: some View {
        TabView(selection: $tab) {
            SpacesTab(store: store, actions: actions)
                .tabItem { Label("Spaces", systemImage: "square.grid.3x3") }.tag(SettingsTab.spaces)
            GeneralTab(store: store, actions: actions)
                .tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            GuideTab(store: store)
                .tabItem { Label("Guide", systemImage: "book") }.tag(SettingsTab.guide)
        }
        .frame(width: 640, height: 600)
    }
}

// MARK: - Spaces

private struct SpacesTab: View {
    @ObservedObject var store: SpaceStore
    let actions: SettingsActions
    @State private var running: [String] = []
    @State private var keyWarning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Drag apps between keys. Changes are saved instantly.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Section("Numbers") {
                        ForEach(available.filter { $0.first!.isNumber }, id: \.self) { k in
                            Button("Key \(k)") { addKey(k) }
                        }
                    }
                    Section("Letters") {
                        ForEach(available.filter { $0.first!.isLetter }, id: \.self) { k in
                            Button("Key \(k)") { addKey(k) }
                        }
                    }
                } label: {
                    Label("Add Key", systemImage: "plus.square.on.square")
                }
                .fixedSize()
                .disabled(available.isEmpty)
            }
            if let keyWarning {
                Text(keyWarning).font(.caption).foregroundStyle(.orange)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(store.state.keys, id: \.self) { space in
                        SpaceRow(space: space, store: store, actions: actions, unassigned: unassigned) {
                            removeKey(space)
                        }
                    }
                    FloatingRow(store: store, actions: actions, apps: unassigned)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(20)
        .onAppear(perform: refreshRunning)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in refreshRunning() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in refreshRunning() }
    }

    var available: [SpaceKey] { SpaceStore.allKeys.filter { !store.state.keys.contains($0) } }

    func addKey(_ k: SpaceKey) {
        store.addKey(k)
        let taken = actions.hotkeysChanged()
        keyWarning = taken.contains(k)
            ? "\(store.state.modifier.symbol)\(k) is already used by another app — it won't work until that app releases it."
            : nil
    }

    func removeKey(_ k: SpaceKey) {
        let freed = store.removeKey(k)
        for id in freed {
            NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.unhide() }
        }
        _ = actions.hotkeysChanged()
        actions.reapply()
    }

    /// Running apps that aren't on any key yet.
    var unassigned: [String] {
        running.filter { store.state.assignments[$0] == nil }
    }

    func refreshRunning() {
        running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0 != .current }
            .compactMap(\.bundleIdentifier)
            .sorted { AppInfo.name($0) < AppInfo.name($1) }
    }
}

private struct SpaceRow: View {
    let space: SpaceKey
    @ObservedObject var store: SpaceStore
    let actions: SettingsActions
    let unassigned: [String]
    let onRemoveKey: () -> Void
    @State private var targeted = false

    var isCurrent: Bool { store.state.current == space }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            KeyBadge(text: "\(store.state.modifier.symbol)\(space)", active: isCurrent)
            FlowChips(apps: store.apps(in: space), store: store, actions: actions)
            Spacer(minLength: 0)
            Menu {
                if !unassigned.isEmpty {
                    Section("Running apps") {
                        ForEach(unassigned, id: \.self) { id in
                            Button(AppInfo.name(id)) { assign(id) }
                        }
                    }
                }
                Button("Choose App…") { chooseApp() }
                if store.state.keys.count > 1 {
                    Divider()
                    Button("Remove Key \(space)", role: .destructive, action: onRemoveKey)
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add an app, or remove this key")
        }
        .padding(10)
        .frame(minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(targeted ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(isCurrent ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.5))
        .onDrop(of: [UTType.text], isTargeted: $targeted) { providers in
            AppInfo.receive(providers) { assign($0) }
        }
    }

    func assign(_ id: String) {
        store.assign(id, to: space)
        actions.reapply()
    }

    func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier { store.assign(id, to: space) }
        }
        actions.reapply()
    }
}

private struct FloatingRow: View {
    @ObservedObject var store: SpaceStore
    let actions: SettingsActions
    let apps: [String]
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Not on a key (always visible) — drop here to remove from a key")
                .font(.caption).foregroundStyle(.secondary)
            FlowChips(apps: apps, store: store, actions: actions, removable: false)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
            .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.4)))
        .onDrop(of: [UTType.text], isTargeted: $targeted) { providers in
            AppInfo.receive(providers) { id in
                store.forget(id)
                NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.unhide() }
            }
        }
    }
}

/// Wrapping row of draggable app chips.
private struct FlowChips: View {
    let apps: [String]
    @ObservedObject var store: SpaceStore
    let actions: SettingsActions
    var removable = true

    var body: some View {
        if apps.isEmpty {
            Text("Empty").font(.callout).foregroundStyle(.tertiary)
        } else {
            WrapLayout(spacing: 6) {
                ForEach(apps, id: \.self) { id in
                    AppChip(id: id, removable: removable) {
                        store.forget(id)
                        NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.unhide() }
                    }
                    .onDrag { NSItemProvider(object: id as NSString) }
                }
            }
        }
    }
}

private struct AppChip: View {
    let id: String
    let removable: Bool
    let onRemove: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 5) {
            Image(nsImage: AppInfo.icon(id)).resizable().frame(width: 18, height: 18)
            Text(AppInfo.name(id)).font(.callout).lineLimit(1)
            if removable && hover {
                Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Remove from this key")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(hover ? 0.12 : 0.07)))
        .onHover { hover = $0 }
    }
}

private struct KeyBadge: View {
    let text: String
    let active: Bool
    var body: some View {
        Text(text)
            .font(.system(.body, design: .rounded).weight(.semibold))
            .frame(minWidth: 48, minHeight: 30)
            .padding(.horizontal, 4)
            .foregroundStyle(active ? .white : .primary)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(active ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.31, green: 0.82, blue: 1), Color(red: 0.55, green: 0.36, blue: 0.96)], startPoint: .topLeading, endPoint: .bottomTrailing))
                             : AnyShapeStyle(Color.primary.opacity(0.08))))
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var store: SpaceStore
    let actions: SettingsActions
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var keyWarning: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch Keyspace at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in setLogin(on) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }

            Section("Keys") {
                Picker("Modifier", selection: Binding(
                    get: { store.state.modifier },
                    set: { store.state.modifier = $0; store.save(); checkKeys() })) {
                    ForEach(HotkeyModifier.allCases) { Text($0.label).tag($0) }
                }
                let m = store.state.modifier.symbol
                ShortcutRow(keys: "\(m) + key", what: "Switch to that space (e.g. \(m)1, \(m)B)")
                ShortcutRow(keys: "\(m)⇧ + key", what: "Send the front app to that space")
                ShortcutRow(keys: "\(m)⇧0", what: "Pause / resume Keyspace")
                if let keyWarning { Text(keyWarning).font(.caption).foregroundStyle(.orange) }
            }

            Section("Behavior") {
                Toggle("Auto-assign new apps to the current space", isOn: binding(\.autoAssign))
                Toggle("Launch a space's apps when switching to it", isOn: binding(\.launchMissingApps))
            }

            Section("Data") {
                LabeledContent("Config file") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    func binding(_ kp: WritableKeyPath<KeyspaceState, Bool>) -> Binding<Bool> {
        Binding(get: { store.state[keyPath: kp] },
                set: { store.state[keyPath: kp] = $0; store.save() })
    }

    func checkKeys() {
        let taken = actions.hotkeysChanged()
        keyWarning = taken.isEmpty ? nil
            : "Already used by another app: " + taken.map { store.state.modifier.symbol + $0 }.joined(separator: ", ")
              + ". Try a different modifier, or remove those keys."
    }

    func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change login item: \(error.localizedDescription). Make sure Keyspace is in /Applications."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct ShortcutRow: View {
    let keys: String
    let what: String
    var body: some View {
        LabeledContent(what) {
            Text(keys).font(.system(.body, design: .rounded).weight(.medium)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Guide

private struct GuideTab: View {
    @ObservedObject var store: SpaceStore
    var body: some View {
        let m = store.state.modifier.symbol
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Welcome to Keyspace").font(.title2.weight(.semibold))
                        Text("Your apps on 9 keys. Fast, and it never forgets.").foregroundStyle(.secondary)
                    }
                }
                Step(n: 1, title: "Put apps on keys",
                     text: "Open an app and press \(m)⇧ plus its key, e.g. \(m)⇧2. It moves to key 2 and is saved. Or use the Spaces tab: click + on a row, or drag apps between rows.")
                Step(n: 2, title: "Use letters too",
                     text: "Spaces tab → Add Key → pick a letter, e.g. B for Browser, T for Terminal, S for Slack. Then \(m)B jumps to your browser.")
                Step(n: 3, title: "Switch",
                     text: "Press \(m) + a key. That key's apps appear, everything else hides. The menu bar shows which key you're on.")
                Step(n: 4, title: "Just work normally",
                     text: "New apps you open join the key you're on. ⌘-Tab or clicking a Dock icon jumps to the key that app lives on.")
                Step(n: 5, title: "Start with your Mac",
                     text: "General tab → turn on “Launch Keyspace at login”. After a restart or shutdown, Keyspace starts by itself and every app goes back to its key — no setup again.")
                Step(n: 6, title: "Pause or quit any time",
                     text: "\(m)⇧0 pauses and shows every app. Quitting from the menu bar also shows every app — nothing gets lost.")
                Text("Tip: if a shortcut doesn't work, another app owns it. Quit AeroSpace, or pick a different modifier in General.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct Step: View {
    let n: Int
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.headline).foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Helpers

enum AppInfo {
    static func url(_ id: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }

    static func name(_ id: String) -> String {
        if let n = NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.localizedName { return n }
        return url(id)?.deletingPathExtension().lastPathComponent ?? id
    }

    static func icon(_ id: String) -> NSImage {
        if let u = url(id) { return NSWorkspace.shared.icon(forFile: u.path) }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }

    /// Reads a dragged bundle ID and hands it over on the main thread.
    static func receive(_ providers: [NSItemProvider], _ handle: @escaping (String) -> Void) -> Bool {
        guard let p = providers.first else { return false }
        _ = p.loadObject(ofClass: NSString.self) { obj, _ in
            if let id = obj as? String { DispatchQueue.main.async { handle(id) } }
        }
        return true
    }
}

/// Minimal wrapping (flow) layout for the app chips.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { y += rowH + spacing; x = 0; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxW), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
