import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let state: AppState

    init(state: AppState) { self.state = state }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Overwork"
            w.contentViewController = NSHostingController(rootView: SettingsView(state: state))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var loginMessage = ""

    var body: some View {
        Form {
            Section("Rhythm") {
                Stepper("Work for \(state.settings.workMinutes) minutes", value: $state.settings.workMinutes, in: 5...180, step: 5)
                Stepper("Break for \(state.settings.breakMinutes) minutes", value: $state.settings.breakMinutes, in: 1...30)
                Stepper("Count as away after \(state.settings.idleMinutes) minutes idle", value: $state.settings.idleMinutes, in: 1...30)
                Text("Idle time doesn't count as screen time. Being away for a full break length resets the clock.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Wait for calls to end", isOn: $state.settings.respectCalls)
                Text("While another app is using the microphone or camera (Zoom, Teams, WhatsApp, FaceTime, Meet), the break is held until the call ends.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("System") {
                Toggle("Launch at login", isOn: Binding(
                    get: { state.settings.launchAtLogin },
                    set: { loginMessage = state.setLaunchAtLogin($0) ?? "" }
                ))
                if !loginMessage.isEmpty {
                    Text(loginMessage).font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Text(ScreenCapture.hasPermission
                         ? "Screen Recording: allowed. The hole will swallow your actual screen."
                         : "Screen Recording: not allowed. The hole will swallow a starfield instead of your screen.")
                        .font(.caption)
                    Spacer()
                    Button("Privacy Settings") {
                        ScreenCapture.request()
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                Text("After allowing Screen Recording, quit and reopen Overwork.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Preview the black hole (12 s)") { state.startBreak(preview: true) }
                    Button("Take a break now") { state.startBreak() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}
