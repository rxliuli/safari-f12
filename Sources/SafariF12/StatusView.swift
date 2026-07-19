import ApplicationServices
import ServiceManagement
import SwiftUI

struct StatusView: View {
    @State private var trusted = AXIsProcessTrusted()
    @State private var tapRunning = F12Tap.shared.isRunning
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 72, height: 72)

            VStack(spacing: 4) {
                Text("SafariF12")
                    .font(.title2.bold())
                Text("Press F12 in Safari to toggle the Web Inspector")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                HStack {
                    Text("Accessibility permission")
                    Spacer()
                    if trusted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") {
                            requestAccessibility()
                        }
                    }
                }
                .padding(.vertical, 4)

                Divider()

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .padding(.vertical, 4)
                    .onChange(of: launchAtLogin) { enabled in
                        setLaunchAtLogin(enabled)
                    }
            }

            if tapRunning {
                Label("Running — you can close this window", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Waiting for Accessibility permission…", systemImage: "hourglass")
                    .foregroundStyle(.orange)
            }

            Button("Quit SafariF12") {
                NSApp.terminate(nil)
            }
            .controlSize(.small)
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 400)
        .onReceive(timer) { _ in
            trusted = AXIsProcessTrusted()
            tapRunning = F12Tap.shared.isRunning
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let current = SMAppService.mainApp.status == .enabled
        guard enabled != current else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            UserDefaults.standard.set(!enabled, forKey: AppDelegate.userDisabledLoginKey)
        } catch {
            launchAtLogin = current
        }
    }
}
