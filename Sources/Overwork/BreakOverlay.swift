import AppKit
import SwiftUI

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Puts a black hole window over every display and keeps it on top until hidden.
@MainActor
final class BreakOverlayController {
    private struct Screen { let window: OverlayWindow; let hole: BlackHoleView; let hud: NSView }
    private var screens: [Screen] = []
    private var raiseTimer: Timer?
    private var generation = 0

    func show(state: AppState) async {
        generation += 1
        let gen = generation

        // Capture every display before any of our windows appear.
        var shots: [(NSScreen, CGImage?)] = []
        for screen in NSScreen.screens {
            var img: CGImage? = nil
            if let id = ScreenCapture.displayID(of: screen) {
                img = await ScreenCapture.capture(displayID: id, size: screen.frame.size)
            }
            shots.append((screen, img))
        }
        guard gen == generation, state.phase == .onBreak else { return }
        closeAll()

        for (screen, img) in shots {
            let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.setFrame(screen.frame, display: false)
            w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.isOpaque = true
            w.backgroundColor = .black
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.acceptsMouseMovedEvents = true

            let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            let hole = BlackHoleView(frame: container.bounds, image: img)
            hole.autoresizingMask = [.width, .height]
            let hud = NSHostingView(rootView: BreakHUD(state: state))
            hud.frame = container.bounds
            hud.autoresizingMask = [.width, .height]
            container.addSubview(hole)
            container.addSubview(hud)
            w.contentView = container
            w.orderFrontRegardless()
            screens.append(Screen(window: w, hole: hole, hud: hud))
        }

        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableForceQuit,
                                     .disableSessionTermination, .disableHideApplication, .disableAppleMenu]
        activate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.raise() }
        }
        RunLoop.main.add(t, forMode: .common)
        raiseTimer = t
    }

    private func activate() {
        NSApp.activate()
        screens.first?.window.makeKeyAndOrderFront(nil)
    }

    private func raise() {
        for s in screens { s.window.orderFrontRegardless() }
        if !NSApp.isActive { activate() }
    }

    func hide() {
        generation += 1
        raiseTimer?.invalidate()
        raiseTimer = nil
        NSApp.presentationOptions = []
        let closing = screens
        screens = []
        for s in closing {
            s.hud.isHidden = true
            s.hole.targetIntensity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            for s in closing { s.window.orderOut(nil); s.window.close() }
        }
    }

    private func closeAll() {
        for s in screens { s.window.close() }
        screens = []
    }
}

struct BreakHUD: View {
    @ObservedObject var state: AppState
    @State private var showEntry = false
    @State private var code = ""
    @State private var message = ""
    @State private var shakes: CGFloat = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Text(state.isPreview ? "Preview" : "Look away from the screen")
                .font(.system(size: 24, weight: .light, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .shadow(color: .black, radius: 14)

            Button {
                if state.isPreview { _ = state.attemptUnlock(""); return }
                withAnimation(.easeOut(duration: 0.2)) { showEntry.toggle() }
                focused = showEntry
            } label: {
                Text(state.timeString)
                    .font(.system(size: 104, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 18)
                    .shadow(color: .black.opacity(0.8), radius: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to enter your code word")

            Text(state.isPreview ? "Click the timer to close." : "Find something 20 feet away. Blink. Breathe.")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .shadow(color: .black, radius: 12)

            if showEntry && !state.isPreview {
                if !state.hasCodeWord {
                    Text("No code word is set. Wait it out.")
                        .foregroundStyle(.orange)
                        .padding(.top, 8)
                } else {
                    HStack(spacing: 10) {
                        SecureField("code word", text: $code)
                            .textFieldStyle(.plain)
                            .font(.system(size: 18, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(10)
                            .frame(width: 240)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            .focused($focused)
                            .onSubmit(attempt)
                        Button("Unlock", action: attempt).buttonStyle(.bordered)
                    }
                    .padding(.top, 8)
                    if !message.isEmpty {
                        Text(message).foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(40)
        .modifier(Shake(animatableData: shakes))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .offset(y: -0.07 * (NSScreen.main?.frame.height ?? 900)) // sit in the dark upper half of the shadow
    }

    private func attempt() {
        if state.attemptUnlock(code) { return }
        code = ""
        message = ["Nope. +15 s", "Wrong. +15 s", "Still no. +15 s", "The hole disagrees. +15 s"].randomElement()!
        withAnimation(.default) { shakes += 1 }
    }
}

struct Shake: GeometryEffect {
    var amount: CGFloat = 12
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * shakesPerUnit), y: 0))
    }
}
