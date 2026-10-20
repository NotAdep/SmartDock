import AppKit
import ApplicationServices

/// The core state machine.
///
/// Rule: the Dock is hidden exactly while the focused window of the frontmost app is
/// *filled* (macOS "Fill", zoom, or any tool that sizes a window to the usable screen
/// area) or, optionally, tiled to a half or quarter, on an eligible display. When the
/// Dock hides, every tiled window on that screen is grown into the space the Dock
/// leaves behind. Moving, shrinking, minimising or closing the window, or switching
/// to a window that isn't filled or tiled, brings the Dock back.
final class FillController {
    enum Status: Equatable {
        case needsPermission
        case disabled
        case userAutoHide
        case ineligibleDisplay(String)
        case watching
        case hiding(appName: String)
        case excluded(appName: String)
    }

    private enum Fill {
        /// Fills the area beside the visible Dock; needs growing once the Dock hides.
        case besideDock
        /// Already covers the space the Dock would occupy.
        case overDock
    }

    private struct Target {
        let element: AXUIElement
        let frame: CGRect
        let screen: NSScreen
        let appName: String
        let bundleID: String?
    }

    private struct Expanded {
        let window: AXUIElement
        let original: CGRect
        let frame: CGRect
    }

    private enum Keys {
        static let disabled = "disabled"
        static let hidDock = "dockHiddenBySmartDock"
        static let maxExternalHeight = "maxExternalDisplayHeight"
        static let excludeTiles = "excludeTiles"
        static let excludedApps = "excludedBundleIDs"
    }

    // MARK: Tuning

    private let settleDelay: TimeInterval = 0.06

    // MARK: State

    var onStatusChange: ((Status) -> Void)?
    private(set) var status: Status = .watching {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }

    var isEnabled: Bool {
        get { !defaults.bool(forKey: Keys.disabled) }
        set {
            defaults.set(!newValue, forKey: Keys.disabled)
            if newValue {
                scheduleEvaluate(after: 0)
            } else {
                releaseDock(restoringWindows: true)
                status = .disabled
            }
        }
    }

    /// Whether halves and quarters count, not just Fill.
    var includesTiles: Bool {
        get { !defaults.bool(forKey: Keys.excludeTiles) }
        set {
            defaults.set(!newValue, forKey: Keys.excludeTiles)
            scheduleEvaluate(after: 0, force: true)
        }
    }

    private let dock = DockController()
    private let defaults = UserDefaults.standard
    private var weHidDock = false {
        didSet {
            defaults.set(weHidDock, forKey: Keys.hidDock)
            updateHeartbeat()
        }
    }
    private var appObserver: AppWindowObserver?
    private var pending: DispatchWorkItem?
    private var heartbeat: Timer?
    private var frameWaiter: Timer?
    /// Ignore AX echoes of our own resizes until this moment.
    private var quietUntil = Date.distantPast
    /// Screen frames are in flux right after a Dock toggle; don't learn from them.
    private var transitionUntil = Date.distantPast
    private var shownFrames: [CGDirectDisplayID: CGRect] = [:]
    private var hiddenFrames: [CGDirectDisplayID: CGRect] = [:]
    private var dockDisplay: CGDirectDisplayID?
    private var screenSignature = ""
    private var expanded: [Expanded] = []

    static let defaultMaxExternalHeight: CGFloat = 1080

    /// External displays up to this height (in points) are treated like a laptop screen.
    var maxExternalHeight: CGFloat {
        get {
            let v = defaults.double(forKey: Keys.maxExternalHeight)
            return v > 0 ? v : Self.defaultMaxExternalHeight
        }
        set {
            defaults.set(Double(newValue), forKey: Keys.maxExternalHeight)
            scheduleEvaluate(after: 0, force: true)
        }
    }

    /// Apps that always keep the Dock visible.
    var excludedBundleIDs: [String] {
        get { defaults.stringArray(forKey: Keys.excludedApps) ?? [] }
        set {
            defaults.set(newValue, forKey: Keys.excludedApps)
            scheduleEvaluate(after: 0, force: true)
        }
    }

    // MARK: Lifecycle

    func start() {
        // A previous run may have died while the Dock was hidden.
        if defaults.bool(forKey: Keys.hidDock) {
            dock.setAutoHide(false)
            weHidDock = false
            transitionUntil = Date().addingTimeInterval(1)
        }

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.attachToFrontmostApp()
            self?.scheduleEvaluate(after: 0, force: true)
        }
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.scheduleEvaluate(force: true)
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.screensChanged()
        }

        screenSignature = Self.currentScreenSignature()
        attachToFrontmostApp()
        scheduleEvaluate(after: 0)
    }

    /// Puts everything back the way the user had it.
    func shutdown() {
        pending?.cancel()
        releaseDock(restoringWindows: true)
    }

    // MARK: Events

    /// Safety net for AX notifications an app fails to send. It only runs while we're
    /// hiding the Dock, the one state where a missed event would leave things wrong,
    /// and with generous tolerance so macOS can batch the wakeup with other work.
    private func updateHeartbeat() {
        guard weHidDock else {
            heartbeat?.invalidate()
            heartbeat = nil
            return
        }
        guard heartbeat == nil else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.scheduleEvaluate()
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    private func attachToFrontmostApp() {
        guard AX.isTrusted, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid() else { return }
        guard appObserver?.pid != app.processIdentifier else { return }
        appObserver = AppWindowObserver(pid: app.processIdentifier) { [weak self] in
            self?.scheduleEvaluate()
        }
    }

    private func screensChanged() {
        let signature = Self.currentScreenSignature()
        if signature != screenSignature {
            screenSignature = signature
            shownFrames.removeAll()
            hiddenFrames.removeAll()
            dockDisplay = nil
            expanded.removeAll()
        }
        scheduleEvaluate(force: true)
    }

    private static func currentScreenSignature() -> String {
        NSScreen.screens.map { "\($0.displayID):\($0.frame)" }.joined(separator: "|")
    }

    /// Coalesces bursts of AX notifications. Unless `force`d, an already-scheduled
    /// evaluation is kept, so a continuous drag is still evaluated every few frames.
    private func scheduleEvaluate(after delay: TimeInterval? = nil, force: Bool = false) {
        if pending != nil && !force { return }
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.pending = nil
            self?.evaluate()
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (delay ?? settleDelay), execute: item)
    }

    // MARK: Decision

    private func evaluate() {
        guard isEnabled else { status = .disabled; return }
        guard AX.isTrusted else { status = .needsPermission; return }
        attachToFrontmostApp()
        if !weHidDock && dock.isAutoHideOn { status = .userAutoHide; return }

        let now = Date()
        if now < quietUntil {
            scheduleEvaluate(after: quietUntil.timeIntervalSince(now) + 0.02, force: true)
            return
        }

        learnScreenFrames()
        pruneExpanded()

        guard let target = focusedWindow() else {
            status = .watching
            if weHidDock { showDock() }
            return
        }

        if let id = target.bundleID, excludedBundleIDs.contains(id) {
            status = .excluded(appName: target.appName)
            if weHidDock { showDock() }
            return
        }

        guard isEligible(target.screen) else {
            let size = target.screen.frame.size
            status = .ineligibleDisplay("\(Int(size.width))×\(Int(size.height))")
            if weHidDock { showDock() }
            return
        }

        guard let fill = fillState(of: target) else {
            status = .watching
            if weHidDock { showDock() }
            return
        }

        status = .hiding(appName: target.appName)
        if !weHidDock {
            hideDock(thenExpand: fill == .besideDock ? target : nil)
        } else if fill == .besideDock, frameWaiter == nil {
            growLayout(around: target)
        }
    }

    func isEligible(_ screen: NSScreen) -> Bool {
        screen.isBuiltIn || screen.frame.height <= maxExternalHeight
    }

    private func focusedWindow() -> Target? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.3)
        let window = AX.element(axApp, kAXFocusedWindowAttribute)
        appObserver?.watch(window)

        guard let window else { return nil }
        // Native full screen already hides the Dock in its own Space.
        if AX.bool(window, "AXFullScreen") == true { return nil }
        if AX.bool(window, kAXMinimizedAttribute) == true { return nil }
        if let subrole = AX.string(window, kAXSubroleAttribute), subrole != kAXStandardWindowSubrole { return nil }
        guard let frame = AX.frame(of: window), let screen = NSScreen.screen(containing: frame) else { return nil }
        return Target(element: window, frame: frame, screen: screen, appName: app.localizedName ?? "App",
                      bundleID: app.bundleIdentifier)
    }

    private func fillState(of target: Target) -> Fill? {
        let id = target.screen.displayID
        let dockID = dockDisplay ?? (NSScreen.screens.count == 1 ? id : nil)
        guard id == dockID else { return nil }

        if expanded.contains(where: { CFEqual($0.window, target.element) && $0.frame.isClose(to: target.frame) }) {
            return .overDock
        }
        if let hidden = hiddenFrame(for: target.screen), isLayout(target.frame, in: hidden) {
            return .overDock
        }
        if let shown = shownFrames[id], isLayout(target.frame, in: shown) {
            return .besideDock
        }
        return nil
    }

    private func isLayout(_ frame: CGRect, in area: CGRect) -> Bool {
        guard let (tile, _) = Tiling.match(frame, in: area) else { return false }
        return tile.isFill || includesTiles
    }

    // MARK: Screen geometry

    private func learnScreenFrames() {
        guard Date() >= transitionUntil, !weHidDock, !dock.isAutoHideOn else { return }
        let screens = NSScreen.screens
        for screen in screens {
            shownFrames[screen.displayID] = screen.axVisibleFrame
        }
        if let withDock = screens.first(where: { $0.reservesDockSpace }) {
            dockDisplay = withDock.displayID
        }
    }

    /// The usable area with the Dock hidden: learned once seen, otherwise estimated
    /// by extending the Dock-visible area to the screen edge.
    private func hiddenFrame(for screen: NSScreen) -> CGRect? {
        let id = screen.displayID
        if let known = hiddenFrames[id] { return known }
        guard let shown = shownFrames[id] else { return nil }
        let full = screen.axFrame
        return CGRect(x: full.minX, y: shown.minY, width: full.width, height: full.maxY - shown.minY)
    }

    // MARK: Dock

    private func hideDock(thenExpand target: Target?) {
        let screen = target?.screen ?? NSScreen.screens.first { $0.displayID == dockDisplay }
        let before = screen?.axVisibleFrame

        // Grow the window *before* the Dock leaves. The Dock floats above it, so the
        // new space is revealed by the Dock's own slide animation rather than by the
        // window stretching frame by frame.
        if let target { growLayout(around: target) }

        weHidDock = true
        transitionUntil = Date().addingTimeInterval(1)
        dock.setAutoHide(true)

        guard let screen, let before else { return }
        let id = screen.displayID
        let started = Date()
        frameWaiter?.invalidate()
        frameWaiter = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard self.weHidDock else { timer.invalidate(); self.frameWaiter = nil; return }
            let current = NSScreen.screens.first { $0.displayID == id }
            let now = current?.axVisibleFrame
            let changed = now.map { $0.area > before.area + 1 } ?? false
            guard changed || Date().timeIntervalSince(started) > 0.6 else { return }

            timer.invalidate()
            self.frameWaiter = nil
            guard changed, let now, let current else { return }
            self.hiddenFrames[id] = now
            // Correct the sizes if the estimate we grew to differs from the real area.
            for entry in self.expanded {
                guard let frame = AX.frame(of: entry.window), NSScreen.screen(containing: frame)?.displayID == id else { continue }
                self.grow(entry.window, from: frame, on: current)
            }
            if !self.expanded.isEmpty { self.scheduleEvaluate(after: 0.32, force: true) }
        }
    }

    private func showDock() {
        frameWaiter?.invalidate()
        frameWaiter = nil
        weHidDock = false
        transitionUntil = Date().addingTimeInterval(1)
        dock.setAutoHide(false)
    }

    private func releaseDock(restoringWindows: Bool) {
        if restoringWindows {
            for entry in expanded where AX.frame(of: entry.window)?.isClose(to: entry.frame) == true {
                AX.setFrame(entry.window, entry.original)
            }
        }
        expanded.removeAll()
        if weHidDock { showDock() }
    }

    // MARK: Window growth

    /// Grows the target and, when tiles count, every other tiled window on its screen,
    /// so a side-by-side or quartered layout stays even.
    private func growLayout(around target: Target) {
        grow(target.element, from: target.frame, on: target.screen)
        if includesTiles {
            for (window, frame) in tiledWindows(on: target.screen, excluding: target.element) {
                grow(window, from: frame, on: target.screen)
            }
        }
        scheduleEvaluate(after: 0.32, force: true)
    }

    /// Moves one window from the Dock-visible layout onto the Dock-hidden one in a
    /// single step, keeping its margins and remembering where it came from.
    private func grow(_ window: AXUIElement, from current: CGRect, on screen: NSScreen) {
        let id = screen.displayID
        guard let shown = shownFrames[id], let hidden = hiddenFrame(for: screen) else { return }
        let original = expanded.first { CFEqual($0.window, window) }?.original ?? current
        guard let goal = Tiling.remap(original, from: shown, to: hidden) else { return }

        quietUntil = Date().addingTimeInterval(0.3)
        AX.setFrame(window, goal, current: current)
        let actual = AX.frame(of: window) ?? goal
        expanded.removeAll { CFEqual($0.window, window) }
        expanded.append(Expanded(window: window, original: original, frame: actual))
    }

    /// Other visible windows on `screen` that sit on the Dock-visible tiling grid.
    private func tiledWindows(on screen: NSScreen, excluding focused: AXUIElement) -> [(AXUIElement, CGRect)] {
        guard let shown = shownFrames[screen.displayID],
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }

        let pids = Set(info.compactMap { entry -> pid_t? in
            guard entry[kCGWindowLayer as String] as? Int == 0 else { return nil }
            return entry[kCGWindowOwnerPID as String] as? pid_t
        }).subtracting([getpid()])

        var result: [(AXUIElement, CGRect)] = []
        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.2)
            guard let windows = AX.copy(app, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for window in windows where !CFEqual(window, focused) {
                guard AX.string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole,
                      AX.bool(window, kAXMinimizedAttribute) != true,
                      AX.bool(window, "AXFullScreen") != true,
                      let frame = AX.frame(of: window),
                      NSScreen.screen(containing: frame)?.displayID == screen.displayID,
                      !expanded.contains(where: { CFEqual($0.window, window) && $0.frame.isClose(to: frame) }),
                      Tiling.match(frame, in: shown) != nil else { continue }
                result.append((window, frame))
            }
        }
        return result
    }

    private func pruneExpanded() {
        expanded.removeAll { entry in
            guard let frame = AX.frame(of: entry.window) else { return true }
            return !frame.isClose(to: entry.frame)
        }
    }
}

// MARK: - Geometry helpers

private extension NSScreen {
    /// True while the Dock occupies an edge of this screen.
    var reservesDockSpace: Bool {
        visibleFrame.minY > frame.minY + 1 || visibleFrame.minX > frame.minX + 1 || visibleFrame.maxX < frame.maxX - 1
    }
}

private extension CGRect {
    func isClose(to other: CGRect, tolerance: CGFloat = 3) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
