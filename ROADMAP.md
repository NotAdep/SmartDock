# SmartDock Roadmap

Ideas for after v2's Fill behaviour, roughly in priority order.

## Now

- [x] **Version control.** Local git repo at the `SmartDock/` root.
- [ ] **Halves & quarters.** Hide the Dock for Sequoia tiles (Window → Move & Resize). Grow every tile on the screen so the layout stays even.
- [ ] **GitHub remote.** Push the local repo to your GitHub account.

## Edge cases to check

- [ ] **Restoring size after a drag.** Sequoia puts a filled window back to its old size when you drag it off. Check whether that still happens after SmartDock grows the window. If not, restore the remembered original frame ourselves.
- [ ] **Stage Manager.** The strip of recent apps changes the usable area; check that detection still works.
- [ ] **Laptop + external display,** with the Dock on the other screen.
- [ ] **Apps with unusual sizing:** Terminal (character grid), Finder, Electron apps (VS Code, Slack), fixed-size windows.
- [ ] **Dock on the left or right** instead of the bottom.
- [ ] **Changing Dock auto-hide in System Settings while SmartDock is running.**

## Polish

- [ ] **Settings window** (SwiftUI) instead of `defaults write`:
  - display-size limit for external displays
  - per-app exclusions, for apps where you always want the Dock
  - turn halves & quarters on or off
- [ ] **App icon,** plus a short transition on the menu bar icon when the Dock hides or shows.
- [ ] **Auto-hide the menu bar too (opt-in).** Gains about 37 pt on notched MacBooks. It's a bigger system change, so it should be off by default.
- [ ] **Unit tests** for the geometry: fill and tile detection, and growing windows into the Dock area.

## Sharing it

- [ ] **Notarised build in a DMG,** for installing on other Macs.
- [ ] **Automatic updates,** e.g. with Sparkle.
- [ ] **Stop using the private CoreDock call** in public builds; use the System Events fallback, which needs Automation permission.
