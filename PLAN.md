# Keyspace — plan

Lightweight AeroSpace-style "spaces on keys" for macOS. Menu bar app, no tiling, no polling.

## Principles
- Apps are remembered by **bundle ID** in `~/.config/keyspace/spaces.json`, saved on every change.
  Quit/relaunch/reboot → layout comes back.
- Switching uses native app hide/unhide (⌘H). No Accessibility API in Phase 1.
- Carbon hotkeys (no keystroke tap, no Input Monitoring permission).
- Quitting or pausing always un-hides everything.

## Keys
- ⌥ + key — switch to space (keys 1–9 by default; letters A–Z can be added)
- ⌥⇧ + key — send frontmost app to space (saved immediately)
- ⌥⇧0 — pause / resume

## Phases
1. [x] Menu bar app, hotkeys, persistent store, auto-assign, follow ⌘-Tab, restore on quit
   - [x] `Switcher.switchTo` body
2. [x] Settings window (drag apps onto keys), launch at login (SMAppService), modifier choice, logo, guide
   - [x] Letter keys A–Z (add/remove keys in Settings; v0.2 configs auto-migrate)
   - [ ] Fully custom hotkey recording
3. [ ] Optional per-window mode (AX, only touched on switch) for splitting one app across keys
4. [ ] Optional on-demand layouts (maximize / split halves)
