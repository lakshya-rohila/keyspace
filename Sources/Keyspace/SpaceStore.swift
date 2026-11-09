import Combine
import Foundation

/// A space is named by the key that opens it: "1"…"9" or "A"…"Z".
typealias SpaceKey = String

/// Everything Keyspace remembers. Apps are stored by bundle ID (e.g. "com.google.Chrome"),
/// never by window ID, so the setup survives quitting Keyspace, quitting apps, and reboots.
struct KeyspaceState: Codable {
    var keys: [SpaceKey] = []                          // keys in use (have apps, or were just added)
    var assignments: [String: SpaceKey] = [:]          // bundle ID -> space key
    var lastFocused: [SpaceKey: String] = [:]          // space key -> bundle ID focused there last
    var current: SpaceKey = "1"
    var autoAssign: Bool = true               // unassigned apps join the current space when used
    var launchMissingApps: Bool = false       // switching to a space launches its apps if not running
    var modifier: HotkeyModifier = .option    // ⌥N switches; add ⇧ to move
    var onboarded: Bool = false               // shown the welcome/guide once

    init() {}

    // Tolerant decoding: missing keys fall back to defaults, and v0.1/v0.2 files
    // (where spaces were numbers 1…9) are converted to key strings automatically.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let a = try? c.decode([String: SpaceKey].self, forKey: .assignments) {
            assignments = a
        } else if let old = try? c.decode([String: Int].self, forKey: .assignments) {
            assignments = old.mapValues(String.init)
        }
        lastFocused = (try? c.decode([SpaceKey: String].self, forKey: .lastFocused)) ?? [:]
        if let cur = try? c.decode(SpaceKey.self, forKey: .current) {
            current = cur
        } else if let old = try? c.decode(Int.self, forKey: .current) {
            current = String(old)
        }
        keys = (try? c.decode([SpaceKey].self, forKey: .keys)) ?? []
        autoAssign = (try? c.decode(Bool.self, forKey: .autoAssign)) ?? true
        launchMissingApps = (try? c.decode(Bool.self, forKey: .launchMissingApps)) ?? false
        modifier = (try? c.decode(HotkeyModifier.self, forKey: .modifier)) ?? .option
        onboarded = (try? c.decode(Bool.self, forKey: .onboarded)) ?? false
    }
}

/// Which modifier the space keys use. Moving an app always adds ⇧ on top.
enum HotkeyModifier: String, Codable, CaseIterable, Identifiable {
    case option, controlOption, control
    var id: String { rawValue }
    var symbol: String {
        switch self { case .option: "⌥"; case .controlOption: "⌃⌥"; case .control: "⌃" }
    }
    var label: String {
        switch self { case .option: "Option  ⌥"; case .controlOption: "Control + Option  ⌃⌥"; case .control: "Control  ⌃" }
    }
}

/// ObservableObject so the Settings window updates live when hotkeys/auto-assign change things.
final class SpaceStore: ObservableObject {
    /// ⌥⇧1…9 always work so any app can start a new key; letters are added in Settings.
    static let alwaysMoveKeys: [SpaceKey] = (1...9).map(String.init)
    /// Called when the set of keys in use changes (AppDelegate re-registers hotkeys).
    var onKeysChanged: (() -> Void)?
    /// Every key a space can use. "0" is reserved for pause.
    static let allKeys: [SpaceKey] = (1...9).map(String.init) + "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)

    @Published var state = KeyspaceState()
    let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/keyspace", isDirectory: true)
    var fileURL: URL { folder.appendingPathComponent("spaces.json") }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            state = try JSONDecoder().decode(KeyspaceState.self, from: data)
            sanitize()
        } catch {
            NSLog("Keyspace: could not read \(fileURL.path): \(error). Keeping defaults.")
        }
    }

    /// Keep the file self-consistent after hand edits or migration.
    private func sanitize() {
        state.keys = state.keys.map { $0.uppercased() }.filter(Self.allKeys.contains)
        state.lastFocused = state.lastFocused.filter { state.assignments[$0.value] != nil }
        state.assignments = state.assignments.mapValues { $0.uppercased() }
        state.lastFocused = Dictionary(state.lastFocused.map { ($0.key.uppercased(), $0.value) },
                                       uniquingKeysWith: { a, _ in a })
        // Any key an app is assigned to must be active, so nothing becomes unreachable.
        state.keys += state.assignments.values.filter(Self.allKeys.contains)
        // Only keys that hold apps are kept; empty ones disappear.
        let used = Set(state.assignments.values)
        state.keys = Self.sorted(state.keys.filter(used.contains))
        state.lastFocused = state.lastFocused.filter { state.keys.contains($0.key) && state.assignments[$0.value] == $0.key }
        state.current = state.current.uppercased()
        if !state.keys.contains(state.current) { state.current = state.keys.first ?? "1" }
    }

    /// Unique, numbers first, then letters A–Z.
    static func sorted(_ keys: [SpaceKey]) -> [SpaceKey] {
        Array(Set(keys)).sorted { (allKeys.firstIndex(of: $0) ?? 99) < (allKeys.firstIndex(of: $1) ?? 99) }
    }

    /// Written on every change (atomically), so a crash or force-quit never loses assignments.
    func save() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(state).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Keyspace: save failed: \(error)")
        }
    }

    func space(of bundleID: String) -> SpaceKey? { state.assignments[bundleID] }

    func apps(in space: SpaceKey) -> [String] {
        state.assignments.filter { $0.value == space }.map(\.key).sorted()
    }

    func assign(_ bundleID: String, to space: SpaceKey) {
        let old = state.assignments[bundleID]
        state.assignments[bundleID] = space
        var changed = false
        if !state.keys.contains(space) { state.keys = Self.sorted(state.keys + [space]); changed = true }
        if let old, old != space, pruneIfEmpty(old) { changed = true }
        save()
        if changed { onKeysChanged?() }
    }

    /// Drops a key that no longer holds any app. Returns true if it was removed.
    @discardableResult
    private func pruneIfEmpty(_ key: SpaceKey) -> Bool {
        guard apps(in: key).isEmpty, state.keys.contains(key) else { return false }
        state.keys.removeAll { $0 == key }
        state.lastFocused[key] = nil
        return true
    }

    func forget(_ bundleID: String) {
        let old = state.assignments[bundleID]
        state.assignments[bundleID] = nil
        state.lastFocused = state.lastFocused.filter { $0.value != bundleID }
        let changed = old.map { pruneIfEmpty($0) } ?? false
        save()
        if changed { onKeysChanged?() }
    }

    // MARK: Keys

    func addKey(_ key: SpaceKey) {
        guard Self.allKeys.contains(key), !state.keys.contains(key) else { return }
        state.keys = Self.sorted(state.keys + [key])   // stays (empty) so apps can be dropped in
        save()
        onKeysChanged?()
    }

    /// Removing a key un-assigns its apps (they become "always visible"); returns those apps.
    @discardableResult
    func removeKey(_ key: SpaceKey) -> [String] {
        let freed = apps(in: key)
        freed.forEach { state.assignments[$0] = nil }
        state.lastFocused[key] = nil
        state.keys.removeAll { $0 == key }
        if state.current == key { state.current = state.keys.first ?? "1" }
        save()
        onKeysChanged?()
        return freed
    }
}
