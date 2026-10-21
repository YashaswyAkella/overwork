# Overwork 🕳️

### Your screen pulls you in. Overwork pulls you out.

**Your screen is a black hole. Sometimes, you need to see one to escape it.**

It's easy to lose track of time when a screen keeps pulling you in. **Overwork** turns that feeling into a visual reminder: after **50 minutes of active screen time**, a cinematic black hole takes over your Mac for a **2-minute break**. Step away, reset, and return to the real world.

Overwork is a **macOS menu bar app**, not just another notification you can swipe away.

## Download and try it

**[Download Overwork from GitHub Releases](../../releases)**

1. Open the latest release and download **`Overwork.dmg`** from **Assets**.
2. Open the DMG and drag **Overwork** into **Applications**.
3. Launch Overwork. Because this early build is **locally signed but not Apple-notarized**, macOS may prevent it from opening. If you trust the downloaded app, find it under **System Settings → Privacy & Security** and choose **Open Anyway** if offered.
4. Allow **Screen Recording** when macOS asks, then quit and reopen Overwork. Without this permission, the effect shows a starfield instead of your actual screen.
5. Adjust the work and break lengths in the settings window if you like.

**Requirements:** macOS 14 Sonoma or newer.

> **Early public release:** Overwork is available for testing. Please [report bugs or share ideas](../../issues).

## How it works

- **Work:** The menu bar counts down a 50-minute interval of active screen time.
- **Pause intelligently:** Five minutes without keyboard or mouse input stops idle time from counting as work. Being away for a full break duration resets the clock.
- **Respect calls:** If another app is using the camera or microphone at the end of an interval, Overwork delays the break until the call ends. This can be changed in Settings.
- **Meet the black hole:** Overwork captures your displays and uses a Metal shader to distort them into a dramatic black hole effect, with a thin accretion disk, gravitational lensing and Doppler-inspired lighting.
- **Three real black holes:** Each break picks one at random, rendered by the same simulator from the object's known geometry. **TON 618**, the hyperluminous quasar, seen edge on with a white-hot disk. **M87\***, matching the 2019 Event Horizon Telescope image: 17° from the pole, a thick orange ring brighter to the south. **Sagittarius A\***, matching the 2022 EHT image: a thinner ring with three bright knots and gas that moves in minutes. The preview cycles through them.
- **Take two minutes:** A full-screen break appears across your displays. During the break, the app restricts the Dock, menu bar, app switching, Force Quit and Quit.
- **No early exit:** the break ends when the timer reaches zero. That is the point.

From the menu bar, you can also **take a break now**, **preview the effect for 12 seconds**, **pause**, **reset**, open **Settings**, or **Quit** outside the break experience.

## Why a black hole?

Screens pull at our attention. We keep scrolling, working and clicking, and suddenly an hour has disappeared.

Overwork makes that invisible pull visible. When the black hole appears, it's a cue to break the spell: look away from the screen, move, and return on your own terms.

**Your screen pulls you in. Overwork pulls you out.**

## Privacy

Everything stays on your Mac: no network, no analytics, no stored screenshots. See
[PRIVACY.md](PRIVACY.md) for exactly what the app reads and why.

## Build from source

Requires a Mac with **Xcode Command Line Tools** and the complete project source tree.

```bash
chmod +x build.sh
./build.sh
```

The script produces:

```text
dist/Overwork.app
dist/Overwork.dmg
```

Debug helpers:

```bash
.build/release/Overwork --render frame.png
open dist/Overwork.app --args --preview
.build/release/Overwork --calls
open dist/Overwork.app --env OVERWORK_FPS_LOG=/tmp/fps.txt --args --preview
```

## Project layout

| Path | Purpose |
| --- | --- |
| `Sources/Overwork/AppState.swift` | Timer and idle tracking |
| `Sources/Overwork/BlackHole.swift` | Metal renderer, view and shader |
| `Sources/Overwork/BreakOverlay.swift` | Full-screen windows and break timer |
| `Sources/Overwork/StatusBar.swift` | Menu bar controls |
| `Sources/Overwork/SettingsWindow.swift` | Settings UI |
| `Sources/Overwork/ScreenCapture.swift` | Capture of each display with ScreenCaptureKit |
| `Tools/MakeIcon.swift` | App icon generation |
| `Resources/Info.plist` | Application metadata |

## Feedback

Trying Overwork for the first time? Please [open an issue](../../issues) with any bugs, compatibility problems or suggestions. Include your macOS version and steps to reproduce when reporting an issue.

---

*Escape the screen. Take back your time.*
