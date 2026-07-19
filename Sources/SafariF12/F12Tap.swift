import AppKit
import ApplicationServices
import os.log

/// Global CGEvent tap: while Safari is frontmost, swallows F12 and sends
/// ⌥⌘I to toggle the Web Inspector.
final class F12Tap {
    static let shared = F12Tap()
    static let log = Logger(subsystem: "com.rxliuli.safari-f12", category: "tap")

    fileprivate var tap: CFMachPort?
    fileprivate var recentDisables: [Date] = []
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    var isEnabled: Bool {
        tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
    }

    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        // .listenOnly is a hard safety requirement, not an optimization: an
        // ACTIVE tap sits synchronously in the system keyboard pipeline, and
        // when the permission is revoked mid-flight the system
        // can leave it enabled-but-unauthorized, freezing input system-wide
        // until this process dies. A listen-only tap observes asynchronously
        // and can never block delivery, no matter how it fails. The cost:
        // F12 also reaches Safari, which ignores it by default.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
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
        recentDisables = []
        Self.log.notice("Event tap started")
        return true
    }

    /// Tear the tap down completely. Critical when the Input Monitoring permission is
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
        self.recentDisables = []
        Self.log.notice("Event tap stopped")
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
    // re-enabling keeps F12 working afterwards. BUT: after the
    // permission is revoked, the system disables the tap every time we
    // re-enable it, and AXIsProcessTrusted() keeps returning a stale `true`
    // in the running process — so authorization cannot be queried, only
    // observed behaviorally. Repeated disables in a short window mean the
    // system is fighting us; keeping that fight up wedges the system-wide
    // keyboard pipeline. Give up, tear down, and let the app retry slowly.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        let tap = F12Tap.shared
        let now = Date()
        tap.recentDisables = tap.recentDisables.filter { now.timeIntervalSince($0) < 5 }
        tap.recentDisables.append(now)

        if tap.recentDisables.count >= 3 {
            F12Tap.log.error("Event tap disabled 3x within 5s — permission likely revoked, giving up")
            DispatchQueue.main.async {
                F12Tap.shared.stop()
                (NSApp.delegate as? AppDelegate)?.handlePermissionLost()
            }
        } else {
            F12Tap.log.notice("Event tap disabled by system — re-enabling")
            if let port = tap.tap {
                CGEvent.tapEnable(tap: port, enable: true)
            }
        }
        return Unmanaged.passRetained(event)
    }

    guard type == .keyDown else {
        return Unmanaged.passRetained(event)
    }

    // F12 = keycode 111. Listen-only taps cannot swallow the event; Safari
    // also receives the F12 press and ignores it.
    if event.getIntegerValueField(.keyboardEventKeycode) == 111, isSafariFrontmost() {
        sendOptionCommandI()
    }

    return Unmanaged.passRetained(event)
}
