import AppKit
import ApplicationServices

/// The core state machine.
///
/// Rule: the Dock is hidden exactly while the focused window of the frontmost app is
/// *filled* (macOS "Fill", zoom, or any tool that sizes a window to the usable screen
/// area) on an eligible display. When the Dock hides, the window is grown into the
/// space the Dock leaves behind. Moving, shrinking, minimising or closing the window,
/// or switching to a window that isn't filled, brings the Dock back.
final class FillController {
    enum Status: Equatable {
        case needsPermission
        case disabled
        case userAutoHide
        case ineligibleDisplay(String)
        case watching
        case hiding(appName: String)
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
    }

    // MARK: Tuning

    /// How far each window edge may sit inside the usable area and still count as
    /// touching it. Covers Sequoia's "Tiled windows have margins" and apps that round
    /// their size (e.g. Terminal's character grid).
    private let edgeSlack: ClosedRange<CGFloat> = -3...16
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

    private let dock = DockController()
    private let defaults = UserDefaults.standard
    private var weHidDock = false {
        didSet { defaults.set(weHidDock, forKey: Keys.hidDock) }
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

    private var maxExternalHeight: CGFloat {
        let v = defaults.double(forKey: Keys.maxExternalHeight)
        return v > 0 ? v : 1080
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

        // Safety net for anything the AX notifications miss.
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.scheduleEvaluate()
        }

        screenSignature = Self.currentScreenSignature()
        attachToFrontmostApp()
        scheduleEvaluate(after: 0)
    }

    /// Puts everything back the way the user had it.
    func shutdown() {
        heartbeat?.invalidate()
        pending?.cancel()
        releaseDock(restoringWindows: true)
    }

    // MARK: Events

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
            expand(target)
        }
    }

    private func isEligible(_ screen: NSScreen) -> Bool {
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
        return Target(element: window, frame: frame, screen: screen, appName: app.localizedName ?? "App")
    }

    private func fillState(of target: Target) -> Fill? {
        let id = target.screen.displayID
        let dockID = dockDisplay ?? (NSScreen.screens.count == 1 ? id : nil)
        guard id == dockID else { return nil }

        if expanded.contains(where: { CFEqual($0.window, target.element) && $0.frame.isClose(to: target.frame) }) {
            return .overDock
        }
        if let hidden = hiddenFrame(for: target.screen), touchesAllEdges(target.frame, of: hidden) {
            return .overDock
        }
        if let shown = shownFrames[id], touchesAllEdges(target.frame, of: shown) {
            return .besideDock
        }
        return nil
    }

    private func touchesAllEdges(_ window: CGRect, of area: CGRect) -> Bool {
        let insets = window.insets(within: area)
        return [insets.left, insets.top, insets.right, insets.bottom].allSatisfy(edgeSlack.contains)
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
        if let target { expand(target) }

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
            // Correct the size if the estimate we grew to differs from the real area.
            if let target, let frame = AX.frame(of: target.element) {
                self.expand(Target(element: target.element, frame: frame, screen: current, appName: target.appName))
            }
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

    /// Grows a window that fills the Dock-visible area into the Dock-hidden area in
    /// one step, keeping whatever margins it had.
    private func expand(_ target: Target) {
        let id = target.screen.displayID
        guard let shown = shownFrames[id], let hidden = hiddenFrame(for: target.screen) else { return }
        let original = expanded.first { CFEqual($0.window, target.element) }?.original ?? target.frame

        let i = original.insets(within: shown)
        let margin = max(0, min(i.left, i.top, i.right))
        let dockLeft = hidden.minX < shown.minX - 1
        let dockRight = hidden.maxX > shown.maxX + 1
        let dockBottom = hidden.maxY > shown.maxY + 1

        let left = hidden.minX + (dockLeft ? margin : max(0, i.left))
        let right = hidden.maxX - (dockRight ? margin : max(0, i.right))
        let top = hidden.minY + max(0, i.top)
        let bottom = hidden.maxY - (dockBottom ? margin : max(0, i.bottom))
        let goal = CGRect(x: left, y: top, width: right - left, height: bottom - top).integral

        quietUntil = Date().addingTimeInterval(0.3)
        AX.setFrame(target.element, goal, current: target.frame)
        let actual = AX.frame(of: target.element) ?? goal
        expanded.removeAll { CFEqual($0.window, target.element) }
        expanded.append(Expanded(window: target.element, original: original, frame: actual))
        scheduleEvaluate(after: 0.32, force: true)
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
    /// Distance of each edge inside `area` (negative = beyond it). AX coordinates.
    func insets(within area: CGRect) -> (left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) {
        (minX - area.minX, minY - area.minY, area.maxX - maxX, area.maxY - maxY)
    }

    func isClose(to other: CGRect, tolerance: CGFloat = 3) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
