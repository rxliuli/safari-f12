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
    private let log = Logger(subsystem: "com.rxliuli.safari-f12", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        autoRegisterLoginItem()
        startTapWhenTrusted()

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
            window.contentViewController = NSHostingController(rootView: StatusView())
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

    private func startTapWhenTrusted() {
        if AXIsProcessTrusted(), F12Tap.shared.start() {
            return
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        // Keep polling until the tap is actually running — permission can be
        // granted while tap creation still fails transiently right after.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted(), F12Tap.shared.start() else { return }
            timer.invalidate()
            self?.permissionTimer = nil
        }
    }
}
