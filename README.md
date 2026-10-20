# SmartDock

A macOS menu bar app that hides the Dock while a window is **filled** (Window → Fill, `fn ⌃ F`, double-click zoom, or any window manager's "maximise"), then grows that window into the space the Dock leaves behind. Halves and quarters (Window → Move & Resize) count too. It only runs on laptop-sized displays.

Requires macOS 13 or later, and is tested on **macOS 15 Sequoia**. The Fill and tile shortcuts it reacts to were added in Sequoia, so on 13–14 only maximised windows (title-bar double-click or tools like Rectangle) trigger it. Newer macOS versions should work but haven't been tested. Released under the [MIT License](LICENSE). See the [Roadmap](ROADMAP.md) for what's next.

## Behaviour

- **Hides** when the focused window of the frontmost app touches all four edges of the usable screen area. There's up to 16 pt of slack per edge, which covers Sequoia's tiling margins and apps that round their size, like Terminal.
- **Tiles:** a focused half or quarter also hides the Dock. Every tiled window on that screen grows together, and the grid lines move proportionally, so side-by-side or stacked layouts stay even. You can turn this off with **Include Halves & Quarters** in the menu.
- **Grows** the window to the new full height in one step, keeping its margins. It grows *just before* the Dock hides. Because the Dock floats above the window, the extra space is revealed by the Dock's own slide animation, so you never see the window stretching.
- **Shows the Dock again** as soon as you drag, resize, un-fill, minimise or close the window, or switch to a window that isn't filled. Switching back to the grown window hides the Dock again.
- **Display rule:** always active on the built-in display. On external displays it's active only if their height is ≤ 1080 pt.
- **Hands-off cases:** native full screen (it already hides the Dock), and setups where you turned on Dock auto-hide yourself.
- **Restores everything** on quit or pause: the Dock comes back and grown windows return to their previous size. If the app crashes, the Dock is restored the next time it launches.

## Install (no Xcode needed)

1. Download `SmartDock-<version>.dmg`, open it, and drag **SmartDock** into **Applications**.
2. Open SmartDock. macOS says it can't verify the app, because it isn't notarised by a paid Apple developer. Click **Done**.
3. Open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to SmartDock, and confirm with your password. On macOS 15, right-click → Open no longer skips this step.
4. Allow SmartDock under **Privacy & Security → Accessibility** when asked. It needs this to read window sizes.

The app runs on both Apple Silicon and Intel Macs. When you install a newer version, macOS treats it as a new app, so you may need to turn its Accessibility switch off and on again.

## Build & run

```bash
./build.sh             # builds build/SmartDock.app
./build.sh --install   # also copies it to /Applications and launches it
```

The first time it runs, grant **System Settings → Privacy & Security → Accessibility → SmartDock**. The app is signed with your Apple Development certificate, so the permission survives rebuilds.

To make a shareable DMG:

```bash
Scripts/package.sh     # → build/release/SmartDock-<version>.dmg
```

It builds for Apple Silicon and Intel, strips debug symbols (they contain your Mac's folder paths) and signs ad-hoc, so your personal certificate isn't embedded. It refuses to package if your username still appears anywhere in the app.

## Settings

Open **Settings…** (⌘,) from the menu bar icon, or launch with `open build/SmartDock.app --args --settings`. It has:

- **Behaviour:** pause SmartDock, include halves & quarters, open at login.
- **Displays:** the height limit for external displays (720–1600 pt; the built-in display is always active), and whether each connected display is active.
- **Excluded Apps:** apps that always keep the Dock visible.

## Troubleshooting

SmartDock logs each time it hides or shows the Dock. To watch it live while you reproduce a problem:

```bash
log stream --level info --predicate 'subsystem == "com.notadep.SmartDock"'
```

## App icon

`Resources/AppIcon.icns` is drawn in code. To change it, edit `Scripts/make-icon.swift` and run `swift Scripts/make-icon.swift`. That also writes a 1024 px preview to `Resources/AppIcon-preview.png`.

## Layout

| File | Role |
| --- | --- |
| `FillController.swift` | State machine: Dock toggling, growing windows, tracking them |
| `Tiling.swift` | Fill/half/quarter detection and remapping between the Dock-visible and Dock-hidden areas |
| `DockController.swift` | Dock auto-hide via CoreDock (instant, native animation), System Events fallback |
| `AX.swift` | Accessibility helpers, AX↔Cocoa coordinate conversion, per-app window observer |
| `Settings.swift` | SwiftUI Settings window and its model |
| `AppDelegate.swift` | Menu bar item, permissions, signal-safe shutdown |
