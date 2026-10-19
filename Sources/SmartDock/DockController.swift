import AppKit

/// Toggles Dock auto-hide.
///
/// Prefers the private CoreDock calls the Dock's own context menu uses: they apply
/// instantly with the native slide animation, don't restart the Dock and need no
/// Automation permission. Falls back to System Events if the symbols ever go away.
final class DockController {
    private typealias SetAutoHide = @convention(c) (UInt8) -> Void
    private typealias GetAutoHide = @convention(c) () -> UInt8

    private let setFn: SetAutoHide?
    private let getFn: GetAutoHide?

    init() {
        let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
        setFn = dlsym(handle, "CoreDockSetAutoHideEnabled").map { unsafeBitCast($0, to: SetAutoHide.self) }
        getFn = dlsym(handle, "CoreDockGetAutoHideEnabled").map { unsafeBitCast($0, to: GetAutoHide.self) }
    }

    var isAutoHideOn: Bool {
        if let getFn { return getFn() != 0 }
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        return CFPreferencesCopyAppValue("autohide" as CFString, "com.apple.dock" as CFString) as? Bool ?? false
    }

    func setAutoHide(_ on: Bool) {
        if let setFn {
            setFn(on ? 1 : 0)
            return
        }
        let script = "tell application \"System Events\" to set autohide of dock preferences to \(on)"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error { NSLog("SmartDock: AppleScript fallback failed: \(error)") }
    }
}
