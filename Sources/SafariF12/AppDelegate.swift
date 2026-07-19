import AppKit
import ApplicationServices
import ServiceManagement
import os.log

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?
    private let log = Logger(subsystem: "com.rxliuli.safari-f12", category: "app")

    private let hideIconKey = "hideMenuBarIcon"
    private let userDisabledLoginKey = "userDisabledLaunchAtLogin"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        autoRegisterLoginItem()

        if !UserDefaults.standard.bool(forKey: hideIconKey) {
            setUpStatusItem()
        }

        startTapWhenTrusted()
        log.info("Application started")
    }

    // Launching the app again while it is running brings the icon back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if statusItem == nil {
            UserDefaults.standard.set(false, forKey: hideIconKey)
            setUpStatusItem()
        }
        return false
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "safari", accessibilityDescription: "SafariF12")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Register as a login item on behalf of the user — the whole point of the
    /// app is to be always-on. macOS shows a "background items added"
    /// notification and lists it in System Settings, so this is transparent
    /// and revocable. Never re-registers after the user explicitly turned the
    /// menu toggle off.
    private func autoRegisterLoginItem() {
        guard !UserDefaults.standard.bool(forKey: userDisabledLoginKey) else { return }
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

        let hideIcon = NSMenuItem(
            title: "Hide Menu Bar Icon", action: #selector(hideMenuBarIcon), keyEquivalent: "")
        hideIcon.target = self
        menu.addItem(hideIcon)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                UserDefaults.standard.set(true, forKey: userDisabledLoginKey)
            } else {
                try SMAppService.mainApp.register()
                UserDefaults.standard.set(false, forKey: userDisabledLoginKey)
            }
        } catch {
            log.error("Failed to toggle launch at login: \(error)")
        }
    }

    @objc private func hideMenuBarIcon() {
        let alert = NSAlert()
        alert.messageText = "Hide the menu bar icon?"
        alert.informativeText =
            "SafariF12 keeps running in the background. To show the icon again, open SafariF12 from Finder or Launchpad while it is running."
        alert.addButton(withTitle: "Hide Icon")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        UserDefaults.standard.set(true, forKey: hideIconKey)
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }
}
