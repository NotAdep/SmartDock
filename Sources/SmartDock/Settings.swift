import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Model

final class SettingsModel: ObservableObject {
    struct App: Identifiable, Hashable {
        let id: String  // bundle identifier
        let name: String
        let icon: NSImage
    }

    struct Display: Identifiable {
        let id: CGDirectDisplayID
        let name: String
        let size: String
        let isBuiltIn: Bool
        let isActive: Bool
    }

    private let controller: FillController
    private let updater: UpdateChecker
    private var syncing = false

    @Published var isEnabled = true {
        didSet { if !syncing { controller.isEnabled = isEnabled } }
    }
    @Published var includesTiles = true {
        didSet { if !syncing { controller.includesTiles = includesTiles } }
    }
    @Published var maxExternalHeight: Double = 1080 {
        didSet {
            guard !syncing else { return }
            controller.maxExternalHeight = maxExternalHeight
            refreshDisplays()
        }
    }
    @Published var checksForUpdates = true {
        didSet { if !syncing { updater.checksAutomatically = checksForUpdates } }
    }
    @Published var opensAtLogin = false {
        didSet { if !syncing { setLoginItem(opensAtLogin) } }
    }
    @Published private(set) var excludedApps: [App] = []
    @Published private(set) var displays: [Display] = []

    init(controller: FillController, updater: UpdateChecker) {
        self.controller = controller
        self.updater = updater
        refresh()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshDisplays()
        }
    }

    /// Re-reads everything, e.g. after the menu bar changed a setting.
    func refresh() {
        syncing = true
        isEnabled = controller.isEnabled
        includesTiles = controller.includesTiles
        maxExternalHeight = controller.maxExternalHeight
        opensAtLogin = SMAppService.mainApp.status == .enabled
        checksForUpdates = updater.checksAutomatically
        syncing = false
        excludedApps = controller.excludedBundleIDs.map(Self.app(for:))
        refreshDisplays()
    }

    func refreshDisplays() {
        displays = NSScreen.screens.map { screen in
            Display(id: screen.displayID,
                    name: screen.localizedName,
                    size: "\(Int(screen.frame.width)) × \(Int(screen.frame.height)) pt",
                    isBuiltIn: screen.isBuiltIn,
                    isActive: controller.isEligible(screen))
        }
    }

    func addApps() {
        let panel = NSOpenPanel()
        panel.title = "Choose apps that keep the Dock visible"
        panel.prompt = "Exclude"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }

        var ids = controller.excludedBundleIDs
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier, !ids.contains(id) else { continue }
            ids.append(id)
        }
        controller.excludedBundleIDs = ids
        excludedApps = ids.map(Self.app(for:))
    }

    func remove(_ app: App) {
        controller.excludedBundleIDs.removeAll { $0 == app.id }
        excludedApps.removeAll { $0.id == app.id }
    }

    private func setLoginItem(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("SmartDock: login item change failed: \(error)")
            syncing = true
            opensAtLogin = SMAppService.mainApp.status == .enabled
            syncing = false
        }
    }

    private static func app(for bundleID: String) -> App {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            return App(id: bundleID, name: bundleID,
                       icon: NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage())
        }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return App(id: bundleID, name: name, icon: workspace.icon(forFile: url.path))
    }
}

// MARK: - View

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    /// Snaps to 10 pt without the tick marks a stepped slider draws.
    private var roundedHeight: Binding<Double> {
        Binding(get: { model.maxExternalHeight },
                set: { model.maxExternalHeight = ($0 / 10).rounded() * 10 })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Hide Dock for filled windows", isOn: $model.isEnabled)
                Toggle("Include halves & quarters", isOn: $model.includesTiles)
                    .disabled(!model.isEnabled)
                Toggle("Open at login", isOn: $model.opensAtLogin)
                Toggle("Check for updates automatically", isOn: $model.checksForUpdates)
            } footer: {
                Text("The Dock hides while the focused window is filled or tiled, and comes back as soon as it isn't. Update checks only read the latest release on GitHub. You're on version \(UpdateChecker.currentVersion).")
                    .settingsFooter()
            }

            Section {
                LabeledContent("External displays up to") {
                    HStack(spacing: 8) {
                        Slider(value: roundedHeight, in: 720...1600)
                            .frame(width: 150)
                        Text("\(Int(model.maxExternalHeight)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                }
                ForEach(model.displays) { display in
                    HStack(spacing: 10) {
                        Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(display.name)
                            Text(display.size)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label(display.isActive ? "Active" : "Too large",
                              systemImage: display.isActive ? "checkmark.circle.fill" : "minus.circle")
                            .labelStyle(.titleAndIcon)
                            .font(.callout)
                            .foregroundStyle(display.isActive ? Color.green : Color.secondary)
                    }
                }
            } header: {
                Text("Displays")
            } footer: {
                Text("The built-in display is always active. Larger screens have room for the Dock.")
                    .settingsFooter()
            }

            Section {
                if model.excludedApps.isEmpty {
                    Text("No excluded apps")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                }
                ForEach(model.excludedApps) { app in
                    HStack(spacing: 10) {
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 22, height: 22)
                        Text(app.name)
                        Spacer()
                        Button {
                            model.remove(app)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(app.name)")
                    }
                }
                HStack {
                    Spacer()
                    Button("Add App…") { model.addApps() }
                }
            } header: {
                Text("Excluded Apps")
            } footer: {
                Text("The Dock always stays visible for these apps.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension Text {
    func settingsFooter() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Window

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let model: SettingsModel

    init(controller: FillController, updater: UpdateChecker) {
        model = SettingsModel(controller: controller, updater: updater)
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "SmartDock Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func present() {
        model.refresh()
        if window?.isVisible != true { window?.center() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
