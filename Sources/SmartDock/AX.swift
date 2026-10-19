import AppKit
import ApplicationServices

/// Thin helpers over the Accessibility C API.
/// All rects here are in AX ("global display") coordinates: origin at the top-left
/// of the primary display, y growing downward.
enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        copy(element, attribute) as? Bool
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let p = copy(window, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = copy(window, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &origin)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    /// Sets position/size, skipping whichever part is unchanged from `current`.
    static func setFrame(_ window: AXUIElement, _ rect: CGRect, current: CGRect? = nil) {
        var origin = rect.origin
        var size = rect.size
        let moveNeeded = current.map { $0.origin != rect.origin } ?? true
        let resizeNeeded = current.map { $0.size != rect.size } ?? true
        if moveNeeded, let v = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
        }
        if resizeNeeded, let v = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var isBuiltIn: Bool { CGDisplayIsBuiltin(displayID) != 0 }

    /// Converts a Cocoa rect (bottom-left origin) to AX coordinates.
    static func axRect(_ rect: NSRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? rect.maxY
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    var axFrame: CGRect { NSScreen.axRect(frame) }
    var axVisibleFrame: CGRect { NSScreen.axRect(visibleFrame) }

    /// The screen holding most of an AX-space rect.
    static func screen(containing rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if let hit = screens.first(where: { $0.axFrame.contains(center) }) { return hit }
        return screens.max { $0.axFrame.intersection(rect).area < $1.axFrame.intersection(rect).area }
    }
}

extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

/// Watches one application's windows and forwards every relevant AX notification.
final class AppWindowObserver {
    let pid: pid_t
    private let app: AXUIElement
    private var observer: AXObserver?
    private var watchedWindow: AXUIElement?
    private let handler: () -> Void

    private static let appNotifications = [
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXWindowCreatedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
    ]
    private static let windowNotifications = [
        kAXMovedNotification,
        kAXResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXUIElementDestroyedNotification,
    ]

    init?(pid: pid_t, handler: @escaping () -> Void) {
        self.pid = pid
        self.app = AXUIElementCreateApplication(pid)
        self.handler = handler
        AXUIElementSetMessagingTimeout(app, 0.3)

        var obs: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<AppWindowObserver>.fromOpaque(refcon).takeUnretainedValue().handler()
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return nil }
        observer = obs
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.appNotifications {
            AXObserverAddNotification(obs, app, n as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
    }

    /// Moves the per-window subscriptions (move/resize/close…) onto `window`.
    func watch(_ window: AXUIElement?) {
        guard let observer else { return }
        if let old = watchedWindow, let window, CFEqual(old, window) { return }
        if let old = watchedWindow {
            for n in Self.windowNotifications { AXObserverRemoveNotification(observer, old, n as CFString) }
        }
        watchedWindow = window
        guard let window else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.windowNotifications {
            AXObserverAddNotification(observer, window, n as CFString, refcon)
        }
    }

    deinit {
        guard let observer else { return }
        watch(nil)
        for n in Self.appNotifications { AXObserverRemoveNotification(observer, app, n as CFString) }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
}
