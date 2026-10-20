# SmartDock Roadmap

Ideas for after v2's Fill behaviour, roughly in priority order.

## Now

- [x] **Version control.** Git repo in `SmartDock v2/`.
- [x] **Halves & quarters.** Hide the Dock for Sequoia tiles (Window → Move & Resize). Grow every tile on the screen so the layout stays even.
- [x] **GitHub.** Public at github.com/NotAdep/SmartDock.

## Edge cases to check

- [x] **Restoring size after a drag.** Sequoia puts a filled window back to its old size when you drag it off. Check whether that still happens after SmartDock grows the window. If not, restore the remembered original frame ourselves.
- [x] **Stage Manager.** The strip of recent apps changes the usable area; check that detection still works.
- [ ] **Laptop + external display,** with the Dock on the other screen.
- [x] **Apps with unusual sizing:** Terminal (character grid), Finder, Electron apps (VS Code, Slack), fixed-size windows.
- [x] **Dock on the left or right** instead of the bottom.
- [ ] **Changing Dock auto-hide in System Settings while SmartDock is running.**

## Polish

- [x] **Settings window** (SwiftUI) instead of `defaults write`:
  - display-size limit for external displays
  - per-app exclusions, for apps where you always want the Dock
- [x] **App icon.** The menu bar icon stays monochrome.
- [-] ~~**Auto-hide the menu bar too.**~~ Decided against it: the menu bar stays.
- [ ] *(Later)* **Unit tests** for the geometry: fill and tile detection, and growing windows into the Dock area.

## Sharing it

Notarisation needs a paid Apple Developer account ($99/year), which you don't have, so for now builds are personal-use only.

- [x] **Unnotarised DMG** for friends (`Scripts/package.sh`). They allow it once via System Settings → Privacy & Security → Open Anyway.
- [x] **Stable self-signed certificate** so updates keep Accessibility access.
- [x] **Update check:** "Download SmartDock x.y.z…" in the menu when a newer release exists.
- [ ] *(Needs a developer account)* **Notarised DMG,** opens without Gatekeeper warnings.
- [ ] *(Needs a developer account)* **Automatic updates** with Sparkle.
- [ ] *(Only for a public release)* **Stop using the private CoreDock call;** use the System Events fallback, which needs Automation permission.
