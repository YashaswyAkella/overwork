import AppKit
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    enum Phase { case working, paused, onBreak }

    @Published private(set) var phase: Phase = .working
    @Published private(set) var remaining: TimeInterval
    @Published private(set) var isPreview = false
    /// True when the work interval is over but a call is keeping the break from starting.
    @Published private(set) var waitingForCall = false
    @Published private(set) var variant: HoleVariant = .random()
    private var previewIndex = 0
    @Published var settings: Settings {
        didSet { settings.save(); onChange?() }
    }

    /// Called after every state change so the menu bar can refresh.
    var onChange: (() -> Void)?
    /// Called when a break ends (used by --preview to quit afterwards).
    var onBreakEnded: (() -> Void)?

    let overlay = BreakOverlayController()
    private var timer: Timer?
    private var lastTick = Date()
    private var lastCallCheck = Date.distantPast
    private var cachedInCall = false

    init() {
        let s = Settings.load()
        settings = s
        remaining = s.workInterval
    }


    var timeString: String {
        let t = max(Int(remaining.rounded(.up)), 0)
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    func start() {
        lastTick = Date()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        defer { onChange?() }

        switch phase {
        case .working:
            // Machine slept or was locked long enough to count as a break.
            if dt > settings.breakLength { remaining = settings.workInterval; return }
            let idle = Idle.seconds()
            if idle >= settings.idleThreshold {
                if idle >= settings.breakLength { remaining = settings.workInterval }
                return // away from the keyboard: don't count this second
            }
            remaining -= dt
            if remaining <= 0 {
                remaining = 0
                if inCall() {
                    waitingForCall = true   // the hole waits for the call to end
                } else {
                    waitingForCall = false
                    startBreak()
                }
            }
        case .onBreak:
            remaining -= dt
            if remaining <= 0 { endBreak() }
        case .paused:
            break
        }
    }

    /// Checked at most every 5 seconds; querying CoreAudio and CoreMediaIO is cheap but not free.
    private func inCall() -> Bool {
        guard settings.respectCalls else { return false }
        if Date().timeIntervalSince(lastCallCheck) > 5 {
            cachedInCall = CallDetector.inCall()
            lastCallCheck = Date()
        }
        return cachedInCall
    }

    func startBreak(preview: Bool = false) {
        guard phase != .onBreak else { return }
        waitingForCall = false
        if preview {
            variant = HoleVariant.all[previewIndex % HoleVariant.all.count]   // previews cycle through every look
            previewIndex += 1
        } else {
            variant = .random()
        }
        phase = .onBreak
        isPreview = preview
        remaining = preview ? 12 : settings.breakLength
        onChange?()
        Task { await overlay.show(state: self) }
    }

    func endBreak() {
        guard phase == .onBreak else { return }
        overlay.hide()
        phase = .working
        isPreview = false
        remaining = settings.workInterval
        lastTick = Date()
        onChange?()
        onBreakEnded?()
    }

    /// Previews can be dismissed by clicking the timer; a real break runs its course.
    func closePreview() {
        if phase == .onBreak && isPreview { endBreak() }
    }

    func togglePause() {
        switch phase {
        case .working: phase = .paused
        case .paused: phase = .working; lastTick = Date()
        case .onBreak: return
        }
        onChange?()
    }

    func resetWorkTimer() {
        guard phase != .onBreak else { return }
        remaining = settings.workInterval
        onChange?()
    }

    /// Returns an error message, or nil on success.
    func setLaunchAtLogin(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            settings.launchAtLogin = on
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
