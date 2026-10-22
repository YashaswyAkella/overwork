# 🕳️ Overwork v1.1.1

**Sharper black holes, and breaks that simply run their course.**

## 🛠️ Fixes
- **Sharp on Retina displays.** The black hole used to be drawn at half your display's resolution and then stretched to fit, which made it look pixelated. It is now drawn at full native resolution, from a full-resolution capture of your screen.
- **A clean photon ring.** Light paths change sharply at the edge of the shadow, so one ray per pixel left the thin bright ring dotted and jagged. Pixels along that edge now trace 4 to 16 rays each, and the ring is a smooth curve.
- **No more grain.** The stretched, spaghettified screen is now blurred smoothly instead of with random noise.
- **Same physics, fewer steps.** Light paths are traced with a more accurate integration method, which pays for the extra resolution. Checked against a far more finely stepped reference, 99.9% of pixels match to within 3 levels out of 255.
- **Smooth motion.** If your Mac can't keep up at full resolution, for example on a low battery, Overwork lowers the resolution slightly instead of dropping frames.

## 🔄 Changed
- **No code word.** Breaks can no longer be ended early. The timer counts down and the hole closes on its own after 2 minutes. The code word option is gone from Settings, and a code word saved by an earlier version is ignored.
- The 12-second preview from the menu bar can still be closed early by clicking its timer.

## 🔒 Privacy
Unchanged. Overwork has no network code, no analytics and no accounts. The screenshot is now captured at full resolution, but it still lives only in GPU memory for the length of the break and is never written to disk. See [PRIVACY.md](https://github.com/YashaswyAkella/overwork/blob/main/PRIVACY.md).

## 📥 Install
1. Download `Overwork.dmg` below and drag Overwork into Applications.
2. The build is locally signed but not notarized. If macOS refuses to open it, go to **System Settings → Privacy & Security** and choose **Open Anyway**.
3. Allow **Screen Recording** when asked, then quit and reopen Overwork.

Upgrading from v1.0.0 or v1.1.0: quit the old copy, replace the app, and reopen. Your settings and the Screen Recording permission carry over.

Requires macOS 14 Sonoma or later.

**SHA-256 of Overwork.dmg:** `90ef6ebb2326435d69a3039997ef85df68178fd027657d9c9343295b0c98e1e1`
