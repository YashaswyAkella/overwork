import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState?
    private var statusBar: StatusBarController?
    private var settings: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
            RenderTest.run(outputPath: args[i + 1])
            return
        }

        if args.contains("--calls") {
            let r = CallDetector.report()
            let line = "inCall=\(r.inCall) micUsers=\(r.micUsers) cameraRunning=\(r.cameraRunning)\naudioClients=\(r.audioClients)\n"
            print(line, terminator: "")
            if let i = args.firstIndex(of: "--calls"), i + 1 < args.count { try? line.write(toFile: args[i + 1], atomically: true, encoding: .utf8) }
            exit(0)
        }

        let firstLaunch = !Settings.exists
        let state = AppState()
        let settings = SettingsWindowController(state: state)
        self.state = state
        self.settings = settings
        statusBar = StatusBarController(state: state) { [weak self] in self?.settings?.show() }
        state.start()

        // macOS shows the Screen Recording prompt once per app identity; asking again later is silent.
        if !ScreenCapture.hasPermission { ScreenCapture.request() }
        if firstLaunch {
            state.settings.save()
            settings.show()
        }
        if args.contains("--preview") {
            state.onBreakEnded = { NSApp.terminate(nil) }
            state.startBreak(preview: true)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let state, state.phase == .onBreak, !state.isPreview { return .terminateCancel }
        return .terminateNow
    }
}
