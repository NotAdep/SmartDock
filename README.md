# SmartDock v2

A menu bar app that hides the Dock while a window is **filled** (Window → Fill, `fn ⌃ F`, double-click zoom, or any window manager's "maximise"), then grows that window into the space the Dock leaves behind. Halves and quarters (Window → Move & Resize) count too. It only runs on laptop-sized displays.

## Behaviour

- **Hides** when the focused window of the frontmost app touches all four edges of the usable screen area. There's up to 16 pt of slack per edge, which covers Sequoia's tiling margins and apps that round their size, like Terminal.
- **Tiles:** a focused half or quarter also hides the Dock. Every tiled window on that screen grows together, and the grid lines move proportionally, so side-by-side or stacked layouts stay even. You can turn this off with **Include Halves & Quarters** in the menu.
- **Grows** the window to the new full height in one step, keeping its margins. It grows *just before* the Dock hides. Because the Dock floats above the window, the extra space is revealed by the Dock's own slide animation, so you never see the window stretching.
- **Shows the Dock again** as soon as you drag, resize, un-fill, minimise or close the window, or switch to a window that isn't filled. Switching back to the grown window hides the Dock again.
- **Display rule:** always active on the built-in display. On external displays it's active only if their height is ≤ 1080 pt.
- **Hands-off cases:** native full screen (it already hides the Dock), and setups where you turned on Dock auto-hide yourself.
- **Restores everything** on quit or pause: the Dock comes back and grown windows return to their previous size. If the app crashes, the Dock is restored the next time it launches.

## Build & run

```bash
./build.sh             # builds build/SmartDock.app
./build.sh --install   # also copies it to /Applications and launches it
```

The first time it runs, grant **System Settings → Privacy & Security → Accessibility → SmartDock**. The app is signed with your Apple Development certificate, so the permission survives rebuilds.

## Tuning (optional)

```bash
defaults write com.notadep.SmartDock maxExternalDisplayHeight -float 1200   # allow taller externals
```

## Layout

| File | Role |
| --- | --- |
| `FillController.swift` | State machine: Dock toggling, growing windows, tracking them |
| `Tiling.swift` | Fill/half/quarter detection and remapping between the Dock-visible and Dock-hidden areas |
| `DockController.swift` | Dock auto-hide via CoreDock (instant, native animation), System Events fallback |
| `AX.swift` | Accessibility helpers, AX↔Cocoa coordinate conversion, per-app window observer |
| `AppDelegate.swift` | Menu bar item, permissions, login item, signal-safe shutdown |
