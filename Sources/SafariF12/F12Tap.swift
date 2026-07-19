import AppKit
import os.log

/// Global CGEvent tap: while Safari is frontmost, swallows F12 and sends
/// ⌥⌘I to toggle the Web Inspector.
final class F12Tap {
    static let shared = F12Tap()
    private static let log = Logger(subsystem: "com.rxliuli.safari-f12", category: "tap")

    fileprivate var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            Self.log.error("Failed to create event tap")
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Self.log.info("Event tap started")
        return true
    }

    /// Tear the tap down completely. Critical when Accessibility permission is
    /// revoked: an active tap kept alive without authorization blocks the
    /// system-wide keyboard event pipeline.
    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        self.runLoopSource = nil
        Self.log.info("Event tap stopped")
    }
}

private func isSafariFrontmost() -> Bool {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Safari"
}

private func sendOptionCommandI() {
    let src = CGEventSource(stateID: .hidSystemState)
    // ⌥⌘I — keycode 34 = "i"
    let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 34, keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 34, keyDown: false)
    let flags: CGEventFlags = [.maskCommand, .maskAlternate]
    keyDown?.flags = flags
    keyUp?.flags = flags
    keyDown?.post(tap: .cgSessionEventTap)
    keyUp?.post(tap: .cgSessionEventTap)
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // The system disables taps that are slow or when secure input kicks in;
    // re-enable so F12 keeps working afterwards — but ONLY while we are still
    // authorized. Re-enabling after the permission was revoked wedges the
    // system-wide keyboard pipeline (system disables, we re-enable, repeat)
    // until the process dies. In that case tear down and wait instead.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if AXIsProcessTrusted() {
            if let tap = F12Tap.shared.tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        } else {
            DispatchQueue.main.async {
                F12Tap.shared.stop()
                (NSApp.delegate as? AppDelegate)?.handlePermissionLost()
            }
        }
        return Unmanaged.passRetained(event)
    }

    guard type == .keyDown else {
        return Unmanaged.passRetained(event)
    }

    // F12 = keycode 111
    if event.getIntegerValueField(.keyboardEventKeycode) == 111, isSafariFrontmost() {
        sendOptionCommandI()
        return nil // swallow the F12 event
    }

    return Unmanaged.passRetained(event)
}
