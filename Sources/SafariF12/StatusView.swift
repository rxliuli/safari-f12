import ApplicationServices
import IOKit.hid
import SwiftUI

struct StatusView: View {
    @State private var imGranted =
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    @State private var axGranted = AXIsProcessTrusted()
    @State private var tapRunning = F12Tap.shared.isRunning

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
                // Hearing F12 needs Input Monitoring; sending ⌥⌘I needs
                // Accessibility. Both are required.
                HStack {
                    Text("Input Monitoring")
                    Spacer()
                    // `imGranted` can be stale, so only show the checkmark
                    // when the tap is actually alive.
                    if imGranted && tapRunning {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") {
                            requestInputMonitoring()
                        }
                    }
                }
                .padding(.vertical, 4)

                Divider()

                HStack {
                    Text("Accessibility")
                    Spacer()
                    if axGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") {
                            requestAccessibility()
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if tapRunning && axGranted {
                Label("Running — you can close this window", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if !tapRunning && imGranted {
                Label(
                    "Permission looks revoked — toggle SafariF12 in System Settings → Input Monitoring",
                    systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else if !tapRunning {
                Label("Waiting for Input Monitoring permission…", systemImage: "hourglass")
                    .foregroundStyle(.orange)
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
            imGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
            axGranted = AXIsProcessTrusted()
            tapRunning = F12Tap.shared.isRunning
        }
    }

    private func requestInputMonitoring() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
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
}
