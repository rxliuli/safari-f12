import AppKit
import ApplicationServices
import IOKit.hid
import ServiceManagement
import SwiftUI
import os.log

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let hasLaunchedKey = "hasLaunchedBefore"

    private var statusWindow: NSWindow?
    private var permissionTimer: Timer?
    private var watchdogTimer: Timer?
    private let log = Logger(subsystem: "com.rxliuli.safari-f12", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        registerLoginItemOnce()
        startTapWhenTrusted()

        // Keepalive: recover if the tap ended up disabled without a callback
        // telling us (sleep/wake, secure input edge cases). Permission state
        // needs no runtime monitoring — Input Monitoring revocation only
        // takes effect on the next launch.
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard F12Tap.shared.isRunning, !F12Tap.shared.isEnabled else { return }
            F12Tap.shared.stop()
            self?.handlePermissionLost()
        }

        // Show the status window on first launch, or whenever something is
        // missing (tap not running / Accessibility revoked). Otherwise stay
        // fully in the background. Launch-time shows must not steal focus —
        // the system permission dialogs need to stay on top.
        let firstLaunch = !UserDefaults.standard.bool(forKey: hasLaunchedKey)
        UserDefaults.standard.set(true, forKey: hasLaunchedKey)
        if firstLaunch || !F12Tap.shared.isRunning || !AXIsProcessTrusted() {
            showStatusWindow(activate: false)
        }

        log.info("Application started")
    }

    // Opening the app again while it is running brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Recreate the tap so the window reports the truth — creation runs a
        // fresh TCC check, unlike AXIsProcessTrusted() which can be stale.
        if F12Tap.shared.isRunning {
            F12Tap.shared.stop()
        }
        startTapWhenTrusted()
        showStatusWindow(activate: true)
        return false
    }

    private func showStatusWindow(activate: Bool) {
        if statusWindow == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "SafariF12"
            let hosting = NSHostingController(rootView: StatusView())
            window.contentViewController = hosting
            // Force SwiftUI layout to the final size before centering —
            // centering a zero-sized window puts it in a wrong spot.
            window.setContentSize(hosting.view.fittingSize)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            statusWindow = window
        }
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            statusWindow?.makeKeyAndOrderFront(nil)
        } else {
            statusWindow?.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        statusWindow = nil
    }

    /// Register as a login item once, on first launch — the whole point of
    /// the app is to be always-on. macOS notifies the user and lists it under
    /// System Settings → General → Login Items, which is the canonical place
    /// to turn it off; we never touch the registration again, so a choice
    /// made there is always respected.
    private func registerLoginItemOnce() {
        let key = "didRegisterLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        do {
            try SMAppService.mainApp.register()
        } catch {
            log.error("Failed to register login item: \(error)")
        }
    }

    func handlePermissionLost() {
        log.error("Event tap lost — attempting recovery")
        showStatusWindow(activate: false)
        startTapWhenTrusted()
    }

    /// Posting the synthetic ⌥⌘I needs Accessibility (separate from Input
    /// Monitoring, which only covers listening). Requested after the tap is
    /// up so the two system prompts don't stack on top of each other.
    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func startTapWhenTrusted() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        // Tap creation is itself the authorization check — trust it, not
        // the query APIs, which can be stale in both directions.
        if F12Tap.shared.start() {
            requestAccessibilityIfNeeded()
            return
        }
        // Listen-only keyboard taps are governed by Input Monitoring
        // (kTCCServiceListenEvent), not Accessibility.
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        var contradictions = 0
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            if F12Tap.shared.start() {
                timer.invalidate()
                self?.permissionTimer = nil
                UserDefaults.standard.set(0, forKey: "autoRelaunchCount")
                self?.requestAccessibilityIfNeeded()
                return
            }
            // If TCC claims we are granted but tap creation still fails, the
            // process's TCC state is stale — only a fresh process resolves it.
            if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted {
                contradictions += 1
                if contradictions >= 2 {
                    self?.relaunchIfAllowed()
                }
            } else {
                contradictions = 0
            }
        }
    }

    private func relaunchIfAllowed() {
        // If a fresh process didn't resolve the contradiction, relaunching
        // again won't either (the TCC db itself is inconsistent) — give up
        // after two attempts and leave the status window as guidance. The
        // counter resets whenever the tap starts successfully.
        let countKey = "autoRelaunchCount"
        let count = UserDefaults.standard.integer(forKey: countKey)
        guard count < 2 else { return }
        let key = "lastAutoRelaunch"
        let now = Date().timeIntervalSince1970
        guard now - UserDefaults.standard.double(forKey: key) > 60 else { return }
        UserDefaults.standard.set(now, forKey: key)
        UserDefaults.standard.set(count + 1, forKey: countKey)
        log.notice("TCC state contradictory (trusted, but tap creation fails) — relaunching")
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }
}
