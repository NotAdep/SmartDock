import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = FillController()
    private var statusItem: NSStatusItem!
    private var signalSources: [DispatchSourceSignal] = []
    private var permissionPoll: Timer?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        controller.onStatusChange = { [weak self] _ in self?.updateIcon() }
        updateIcon()

        installSignalHandlers()

        // `open SmartDock.app --args --settings` opens straight into Settings.
        if CommandLine.arguments.contains("--settings") { openSettings() }

        if !AX.isTrusted {
            AX.requestTrust()
            // Pick up the grant as soon as it happens, without a relaunch.
            permissionPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard AX.isTrusted else { return }
                timer.invalidate()
                self?.controller.start()
            }
        } else {
            controller.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }

    /// Restore the Dock if we're killed (logout, `kill`, Ctrl-C).
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.controller.shutdown()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: Menu bar

    private func updateIcon() {
        let symbol: String
        switch controller.status {
        case .hiding: symbol = "dock.arrow.down.rectangle"
        case .disabled, .needsPermission: symbol = "rectangle.dashed"
        default: symbol = "dock.rectangle"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "SmartDock")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = controller.status == .disabled
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if controller.status == .needsPermission {
            menu.addItem(item("Grant Accessibility Access…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }

        let enabled = item("Hide Dock for Filled Windows", #selector(toggleEnabled))
        enabled.state = controller.isEnabled ? .on : .off
        menu.addItem(enabled)

        let tiles = item("Include Halves & Quarters", #selector(toggleTiles))
        tiles.state = controller.includesTiles ? .on : .off
        tiles.isEnabled = controller.isEnabled
        tiles.indentationLevel = 1
        menu.addItem(tiles)

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit SmartDock", #selector(quit), key: "q"))
    }

    private var statusText: String {
        switch controller.status {
        case .needsPermission: return "Needs Accessibility access"
        case .disabled: return "Paused"
        case .userAutoHide: return "Dock auto-hide is already on"
        case .ineligibleDisplay(let size): return "Inactive on this display (\(size))"
        case .watching: return "Watching for filled windows"
        case .hiding(let app): return "Dock hidden for \(app)"
        case .excluded(let app): return "Dock kept for \(app)"
        }
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleEnabled() {
        controller.isEnabled.toggle()
        updateIcon()
        settingsWindow?.model.refresh()
    }

    @objc private func toggleTiles() {
        controller.includesTiles.toggle()
        settingsWindow?.model.refresh()
    }

    @objc private func openSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(controller: controller) }
        settingsWindow?.present()
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
