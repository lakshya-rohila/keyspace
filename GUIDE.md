# Keyspace — Setup Guide

Keyspace puts your apps on 9 keys. Press a key → that key's apps appear, everything else hides.
It uses no CPU while idle and remembers your setup forever (quit, restart, reboot — it comes back).

---

## 1. First launch (2 minutes)

1. **Quit AeroSpace** if it's running (menu bar icon → Quit). Both apps want the same keys.
2. Open **Keyspace** from `/Applications` (or Spotlight: ⌘Space → "Keyspace").
3. Look for the **grid icon + number** in your menu bar (e.g. `▦ 1`). That's the key you're on.
4. The Settings window opens on the **Guide** tab the first time. Go to **General** and turn on
   **Launch Keyspace at login** so it starts with your Mac.

> No permissions needed. Keyspace doesn't ask for Accessibility or Input Monitoring.

## 2. Put your apps on keys

**Fastest — with the keyboard:**
open the app, then press **⌥⇧ + number**.

| Example | Press |
|---|---|
| Chrome on key 1 | open Chrome → **⌥⇧1** |
| VS Code / Terminal on key 2 | open it → **⌥⇧2** |
| Slack / WhatsApp on key 3 | open it → **⌥⇧3** |
| Spotify on key 9 | open it → **⌥⇧9** |

**Or with the mouse:** menu bar icon → **Settings… → Spaces**
- click **+** on a row to add a running app (or *Choose App…* for one that isn't open)
- **drag** an app chip from one row to another to move it
- drag it to the dashed box at the bottom to take it off a key (it'll always stay visible)

Every change is saved the moment you make it.

### Use letters as keys
Settings → **Spaces** → **Add Key** → pick any letter A–Z (or a number you removed).
Ideas: **B** = Browser, **T** = Terminal, **S** = Slack, **M** = Music.
Then **⌥B** jumps to your browser and **⌥⇧B** sends an app there.
To remove a key: click **+** on its row → **Remove Key**. Its apps simply become always-visible.

> Heads-up: ⌥ + a letter normally types special characters (⌥E = ´, ⌥S = ß).
> Letters you add are taken over by Keyspace. If you type accents a lot, pick the **⌃⌥** modifier in General.

## 3. Daily use

| Do this | Press |
|---|---|
| Go to a space | **⌥ + key** (⌥1 … ⌥9, or ⌥B etc. for letters you added) |
| Send the front app to a space | **⌥⇧ + key** |
| Pause (show all apps) / resume | **⌥⇧0** |
| Open Settings | menu bar icon → **Settings…** (⌘,) |

Things that just happen:
- **New apps join the key you're on.** Turn off in General → *Auto-assign new apps*.
- **⌘-Tab / Dock click follows the app.** Switching to Chrome jumps you to Chrome's key.
- **Quitting Keyspace shows every app again** — nothing is ever lost hidden.

## 4. Settings explained

**General tab**
- **Launch at login** — starts with your Mac.
- **Modifier** — ⌥ (default), ⌃⌥, or ⌃. Pick another if ⌥+number clashes with something
  (e.g. typing special characters, Raycast, AeroSpace). Shift is always added for "send app".
- **Auto-assign new apps** — new apps go to the current key automatically.
- **Launch a space's apps when switching** — pressing ⌥3 opens Slack if it isn't running.
- **Config file** — `~/.config/keyspace/spaces.json`. Safe to back up or copy to another Mac.

## 5. Will I lose my setup?

**No.** Every assignment is saved to `~/.config/keyspace/spaces.json` the moment you make it.

| What happens | Your keys |
|---|---|
| You quit an app (or close its windows) | Stay. Reopen the app → it goes straight back to its key. |
| You quit Keyspace | Stay. Open Keyspace again → everything is back in place. |
| You restart or shut down the Mac | Stay. With *Launch at login* on, Keyspace starts by itself and re-applies them. |
| You update Keyspace (`./install.sh`) | Stay. Older config files are converted automatically. |

## 6. Troubleshooting

| Problem | Fix |
|---|---|
| A shortcut does nothing | Another app owns it. Quit AeroSpace, or change the modifier in General (it warns you if keys are taken). |
| An app won't hide | Some apps (e.g. with a window "always on top") ignore hide. Remove it from its key. |
| Everything disappeared | Press **⌥⇧0** (pause) or quit Keyspace — all apps come back. |
| Want to start fresh | Quit Keyspace, delete `~/.config/keyspace/spaces.json`, reopen. |
| Reinstall / update | `cd ~/Desktop/Keyspace && ./install.sh` |

## 7. Uninstall

1. General → turn off *Launch at login*.
2. Menu bar icon → **Quit Keyspace**.
3. Delete `/Applications/Keyspace.app` and `~/.config/keyspace/`.
