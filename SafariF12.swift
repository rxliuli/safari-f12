import Cocoa
import Carbon

// Headless background app — no Dock icon, no UI
// Listens for F12 globally, sends ⌥⌘I to Safari to toggle Web Inspector

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard acquireAccessibility() else {
            print("❌ Accessibility permission required.")
            print("   Go to: System Settings → Privacy & Security → Accessibility")
            print("   Add this app and enable it, then relaunch.")
            NSApp.terminate(nil)
            return
        }

        print("✅ SafariF12 running. Press F12 in Safari to toggle Web Inspector.")

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventCallback,
            userInfo: nil
        ) else {
            print("❌ Failed to create event tap. Check accessibility permissions.")
            NSApp.terminate(nil)
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

func acquireAccessibility() -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

func isSafariFrontmost() -> Bool {
    guard let app = NSWorkspace.shared.frontmostApplication else { return false }
    return app.bundleIdentifier == "com.apple.Safari"
}

func sendOptionCommandI() {
    let src = CGEventSource(stateID: .hidSystemState)

    // ⌥⌘I  — keycode 34 = "i"
    let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 34, keyDown: true)
    let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: 34, keyDown: false)

    let flags: CGEventFlags = [.maskCommand, .maskAlternate]
    keyDown?.flags = flags
    keyUp?.flags   = flags

    keyDown?.post(tap: .cgSessionEventTap)
    keyUp?.post(tap: .cgSessionEventTap)
}

func eventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Re-enable tap if it gets disabled by the system
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        return Unmanaged.passRetained(event)
    }

    guard type == .keyDown else {
        return Unmanaged.passRetained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    // F12 = keycode 111
    if keyCode == 111 && isSafariFrontmost() {
        sendOptionCommandI()
        return nil // swallow the F12 event
    }

    return Unmanaged.passRetained(event)
}

// --- Main ---
let app = NSApplication.shared
app.setActivationPolicy(.prohibited) // no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
