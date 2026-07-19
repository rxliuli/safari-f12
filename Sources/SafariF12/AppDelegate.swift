import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI
import os.log

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let userDisabledLoginKey = "userDisabledLaunchAtLogin"
    private let hasLaunchedKey = "hasLaunchedBefore"

    private var statusWindow: NSWindow?
    private var permissionTimer: Timer?
    private var watchdogTimer: Timer?
    private let log = Logger(subsystem: "com.rxliuli.safari-f12", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        autoRegisterLoginItem()
        startTapWhenTrusted()

        // Watchdog: notice when the tap died behind our back. Deleting the
        // permission entry can leave the tap "enabled" with stale trust
        // values, so the probe (a fresh tap creation) is the authority. The
        // tap is listen-only, so this is about restoring F12, not safety.
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard F12Tap.shared.isRunning else { return }
            if !F12Tap.shared.isEnabled || !F12Tap.probeAuthorization() {
                F12Tap.shared.stop()
                self?.handlePermissionLost()
            }
        }

        // Show the status window on first launch, or whenever the permission
        // is missing (e.g. revoked or invalidated by an update). Otherwise
        // stay fully in the background.
        let firstLaunch = !UserDefaults.standard.bool(forKey: hasLaunchedKey)
        UserDefaults.standard.set(true, forKey: hasLaunchedKey)
        if firstLaunch || !AXIsProcessTrusted() {
            showStatusWindow()
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
        showStatusWindow()
        return false
    }

    private func showStatusWindow() {
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
        NSApp.activate(ignoringOtherApps: true)
        statusWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        statusWindow = nil
    }

    /// Register as a login item on behalf of the user — the whole point of the
    /// app is to be always-on. macOS shows a "background items added"
    /// notification and lists it in System Settings, so this is transparent
    /// and revocable. Never re-registers after the user explicitly turned the
    /// toggle off.
    private func autoRegisterLoginItem() {
        guard !UserDefaults.standard.bool(forKey: Self.userDisabledLoginKey) else { return }
        if SMAppService.mainApp.status != .enabled {
            do {
                try SMAppService.mainApp.register()
            } catch {
                log.error("Failed to register login item: \(error)")
            }
        }
    }

    func handlePermissionLost() {
        log.error("Accessibility permission lost — event tap stopped")
        showStatusWindow()
        startTapWhenTrusted()
    }

    private func startTapWhenTrusted() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        // Tap creation is itself the authorization check — trust it, not
        // AXIsProcessTrusted(), which can be stale in both directions.
        if F12Tap.shared.start() {
            return
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        var contradictions = 0
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            if F12Tap.shared.start() {
                timer.invalidate()
                self?.permissionTimer = nil
                UserDefaults.standard.set(0, forKey: "autoRelaunchCount")
                return
            }
            // Deleting the TCC entry poisons the running process: after a
            // re-grant, tap creation keeps failing here forever while
            // AXIsProcessTrusted reports true. That contradiction is only
            // resolvable by a fresh process — relaunch ourselves.
            if AXIsProcessTrusted() {
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
