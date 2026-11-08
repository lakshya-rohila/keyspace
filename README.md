<p align="center"><img src="docs/icon.png" width="128" alt="Keyspace icon"></p>

<h1 align="center">Keyspace</h1>

<p align="center"><b>Your apps on keys. ⌥1 for the browser, ⌥2 for code, ⌥S for Slack.</b><br>
A tiny macOS menu bar app: press a key, that space's apps appear and everything else hides.<br>
No tiling lag. No permissions. It remembers your setup after every restart.</p>

<p align="center"><a href="docs/keyspace-reel.mp4">▶ Watch the 28-second demo</a></p>

---

## Why

Tiling window managers are great until they make your Mac stutter, and many of them forget which app
lives where as soon as you quit them. Keyspace keeps the part people love, spaces on keys, and drops the rest:

- **Idle at 0% CPU.** It's event-driven: it only wakes up when you press one of its keys or an app launches.
- **No permissions.** No Accessibility, no Input Monitoring. Hotkeys use Carbon `RegisterEventHotKey`;
  switching uses the same hide/unhide as ⌘H.
- **Never forgets.** Assignments are stored by app bundle ID in `~/.config/keyspace/spaces.json`, saved on
  every change. Quit apps, quit Keyspace, shut down: everything comes back on its key.
- **Numbers and letters.** Keys 1–9 by default; add any of A–Z (⌥B = browser, ⌥T = terminal…).

## Install

### One command (recommended)
Paste this into Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/keyspace/main/get.sh | bash
```

It downloads the latest release, installs **Keyspace.app** to `/Applications` and launches it.
Run the same command again any time to update. Your keys are kept (they live in `~/.config/keyspace`).

### Manual download
1. Grab `Keyspace-macOS.zip` from [Releases](../../releases/latest), unzip, and drag **Keyspace.app** to `/Applications`.
2. The app is not notarized, so the first time **right-click → Open → Open**
   (or run `xattr -dr com.apple.quarantine /Applications/Keyspace.app`).

### Build from source (macOS 13+, Xcode command line tools)
```bash
git clone https://github.com/YOUR_GITHUB_USERNAME/keyspace.git && cd keyspace && ./install.sh
```

## Use

| Do this | Press |
|---|---|
| Go to a space | **⌥ + key** (⌥1…⌥9, or a letter you added) |
| Send the front app to a space | **⌥⇧ + key** |
| Pause / resume (shows every app) | **⌥⇧0** |
| Settings | menu bar icon → **Settings…** (⌘,) |

- New apps join the space you're on (toggle in Settings → General).
- ⌘-Tab or a Dock click jumps to the space that app lives on.
- Quitting Keyspace always un-hides every app.
- Modifier can be ⌥, ⌃⌥ or ⌃ if ⌥+key clashes with something you use.

Full walkthrough: [GUIDE.md](GUIDE.md). Roadmap: [PLAN.md](PLAN.md).

## How it works

| File | Job |
|---|---|
| `Sources/Keyspace/HotKeys.swift` | Registers ⌥+key / ⌥⇧+key with Carbon; no keystroke tap |
| `Sources/Keyspace/Switcher.swift` | Shows the target space's apps, focuses the last-used one, then hides the rest |
| `Sources/Keyspace/SpaceStore.swift` | The JSON config: bundle ID → key, migrated automatically between versions |
| `Sources/Keyspace/AppDelegate.swift` | Menu bar, app launch/activation events, pause, restore-on-quit |
| `Sources/Keyspace/SettingsView.swift` | SwiftUI settings: drag-and-drop spaces, add/remove keys, launch at login |

## Contributing

Issues and pull requests are welcome. Ideas on the roadmap: per-window spaces, an on-demand
"arrange now" key (maximize / split halves), custom hotkey recording.

## License

[MIT](LICENSE)
# keyspace
