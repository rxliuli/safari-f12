import AppKit
import ApplicationServices
import ServiceManagement
import os.log

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?
    private let log = Logger(subsystem: "com.rxliuli.safari-f12", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "safari", accessibilityDescription: "SafariF12")

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        startTapWhenTrusted()
        log.info("Application started")
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(
            title: F12Tap.shared.isRunning
                ? "F12 toggles Web Inspector in Safari"
                : "Waiting for Accessibility permission…",
            action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        menu.addItem(.separator())

        let launchAtLogin = NSMenuItem(
            title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLogin.target = self
        launchAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLogin)

        let quit = NSMenuItem(
            title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            log.error("Failed to toggle launch at login: \(error)")
        }
    }
}
