# SmartDock Roadmap

Ideas for after v2's Fill behaviour, roughly in priority order.

## Now

- [x] **Version control.** Local git repo at the `SmartDock/` root.
- [x] **Halves & quarters.** Hide the Dock for Sequoia tiles (Window → Move & Resize). Grow every tile on the screen so the layout stays even.
- [ ] **GitHub remote.** Push the local repo to your GitHub account.

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
- [ ] **Unit tests** for the geometry: fill and tile detection, and growing windows into the Dock area.

## Sharing it

Notarisation needs a paid Apple Developer account ($99/year), which you don't have, so for now builds are personal-use only.

- [ ] **Unnotarised zip or DMG** for friends. They'd need to right-click → Open the first time, or allow it in System Settings → Privacy & Security.
- [ ] *(Needs a developer account)* **Notarised DMG,** opens without Gatekeeper warnings.
- [ ] *(Needs a developer account)* **Automatic updates** with Sparkle.
- [ ] *(Only for a public release)* **Stop using the private CoreDock call;** use the System Events fallback, which needs Automation permission.
