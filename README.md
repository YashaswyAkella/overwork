# Overwork

A menu bar app for macOS that opens a living black hole over your screen every 50 minutes
and keeps it there for a 2 minute break. The only early exit is clicking the timer and typing
your code word. Wrong guesses add 15 seconds.

## Install

1. Open `Overwork.dmg` and drag Overwork to Applications.
2. First launch: right-click the app and choose **Open** (it is signed locally, not notarized).
3. macOS asks for **Screen Recording**. Allow it, then quit and reopen Overwork.
   Without it the hole swallows a starfield instead of your actual screen.
4. In the settings window that opens, set your code word.

## How it works

- The menu bar shows the countdown to the next break.
- Idle time (no mouse or keyboard for 5 minutes) does not count as screen time.
  Being away for a full break length resets the clock.
- Calls are never interrupted. If any other app is capturing the microphone or the camera
  (Zoom, Teams, WhatsApp, FaceTime, Meet) when the work interval ends, the menu bar shows
  "on a call" and the break starts as soon as the call ends. Toggle in Settings.
- When the break starts, every display is captured, then warped by a Metal shader that
  ray marches real Schwarzschild light paths: an Interstellar style thin accretion disk seen
  nearly edge on, its far side lensed over and under the shadow, Doppler beaming on the
  approaching side, and your screen smeared radially as it falls in.
- During the break: Dock, menu bar, Cmd+Tab, Force Quit and Quit are disabled.
  Click the big timer to reveal the code word field.
- Menu: take a break now, 12 second preview, pause, reset, settings, quit.

## Build from source

```bash
./build.sh
```

Produces `dist/Overwork.app` and `dist/Overwork.dmg`. Requires Xcode command line tools.

Debug helpers:

```bash
.build/release/Overwork --render frame.png   # render one frame offscreen
open dist/Overwork.app --args --preview      # 12 second preview, then quit
.build/release/Overwork --calls              # is a call going on right now?
open dist/Overwork.app --env OVERWORK_FPS_LOG=/tmp/fps.txt --args --preview   # also log the frame rate
```

## Layout

- `Sources/Overwork/AppState.swift`: timer state machine, idle handling, code word check
- `Sources/Overwork/BlackHole.swift`: Metal renderer, view and shader source
- `Sources/Overwork/BreakOverlay.swift`: full screen windows, kiosk mode, timer HUD
- `Sources/Overwork/StatusBar.swift`: menu bar item and menu
- `Sources/Overwork/SettingsWindow.swift`: settings UI
- `Sources/Overwork/ScreenCapture.swift`: ScreenCaptureKit screenshot per display
