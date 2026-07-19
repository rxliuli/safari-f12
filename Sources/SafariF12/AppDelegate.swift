import AppKit
import ApplicationServices
import IOKit.hid
import ServiceManagement
import SwiftUI
import os.log

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusWindow: NSWindow?
    private var permissionTimer: Timer?
    private var watchdogTimer: Timer?
    private let log = Logger(subsystem: "com.rxliuli.safari-f12", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        registerLoginItemOnce()
        beginSetup()

        // Keepalive: recover if the tap ended up disabled without a callback
        // telling us (sleep/wake, secure input edge cases). Permission state
        // needs no runtime monitoring — Input Monitoring revocation only
        // takes effect on the next launch.
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard F12Tap.shared.isRunning, !F12Tap.shared.isEnabled else { return }
            F12Tap.shared.stop()
            self?.handlePermissionLost()
        }

        // At launch the system permission dialogs own the stage — never show
        // our own window next to them (any ordering call puts it on top of
        // them). It appears only as a fallback, once the dialogs are long
        // gone, if setup still isn't complete.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if !(F12Tap.shared.isRunning && AXIsProcessTrusted()) {
                self?.showStatusWindow(activate: false)
            }
        }

        // A manual launch (Finder/Launchpad) should visibly do something when
        // everything is already healthy — show the window. Login-item
        // launches carry the launched-as-login-item marker and stay silent.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = event?.eventID == AEEventID(kAEOpenApplication)
            && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
                == OSType(keyAELaunchedAsLogInItem)
        if !launchedAtLogin, F12Tap.shared.isRunning, AXIsProcessTrusted() {
            showStatusWindow(activate: true)
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
        beginSetup()
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
        beginSetup()
    }

    /// Permission sequence: Accessibility first (needed to post ⌥⌘I; grants
    /// apply instantly with no dialogs), Input Monitoring last — enabling it
    /// makes macOS show a "Quit & Reopen" dialog, so it doubles as the final
    /// step: after the relaunch everything is already in place. Automatic
    /// system prompts are suppressed while our own window is visible — its
    /// buttons are the guide then.
    private func beginSetup() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        if AXIsProcessTrusted() {
            beginTapSetup()
            return
        }
        if statusWindow == nil {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.permissionTimer = nil
            self?.beginTapSetup()
        }
    }

    private func beginTapSetup() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        // Tap creation is itself the authorization check — trust it, not
        // the query APIs, which can be stale in both directions.
        if F12Tap.shared.start() {
            UserDefaults.standard.set(0, forKey: "autoRelaunchCount")
            return
        }
        if statusWindow == nil {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        var contradictions = 0
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            if F12Tap.shared.start() {
                timer.invalidate()
                self?.permissionTimer = nil
                UserDefaults.standard.set(0, forKey: "autoRelaunchCount")
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
