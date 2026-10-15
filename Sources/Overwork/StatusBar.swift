import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let state: AppState
    private let openSettings: () -> Void
    private let menu = NSMenu()

    init(state: AppState, openSettings: @escaping () -> Void) {
        self.state = state
        self.openSettings = openSettings
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        if let b = item.button {
            b.image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "Overwork")
            b.imagePosition = .imageLeading
            b.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        }
        state.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    func refresh() {
        switch state.phase {
        case .working: item.button?.title = state.waitingForCall ? " on a call" : " " + state.timeString
        case .paused: item.button?.title = " ❚❚ " + state.timeString
        case .onBreak: item.button?.title = " ● " + state.timeString
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status: String
        switch state.phase {
        case .working: status = state.waitingForCall ? "Break is waiting for your call to end" : "Next break in \(state.timeString)"
        case .paused: status = "Paused at \(state.timeString)"
        case .onBreak: status = "On break, \(state.timeString) left"
        }
        let s = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        s.isEnabled = false
        menu.addItem(s)
        menu.addItem(.separator())

        add("Take a break now", #selector(breakNow), enabled: state.phase != .onBreak)
        add("Preview the black hole (12 s)", #selector(preview), enabled: state.phase != .onBreak)
        add(state.phase == .paused ? "Resume timer" : "Pause timer", #selector(togglePause), enabled: state.phase != .onBreak)
        add("Reset timer", #selector(reset), enabled: state.phase != .onBreak)
        menu.addItem(.separator())
        add("Settings…", #selector(settings), key: ",")
        add("Quit Overwork", #selector(quit), key: "q", enabled: state.phase != .onBreak)
    }

    private func add(_ title: String, _ action: Selector, key: String = "", enabled: Bool = true) {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        i.isEnabled = enabled
        menu.addItem(i)
    }

    @objc private func breakNow() { state.startBreak() }
    @objc private func preview() { state.startBreak(preview: true) }
    @objc private func togglePause() { state.togglePause() }
    @objc private func reset() { state.resetWorkTimer() }
    @objc private func settings() { openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
