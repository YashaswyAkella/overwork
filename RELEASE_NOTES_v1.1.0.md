# 🕳️ Overwork v1.1.0

**Three real black holes. Every break is a different one.**

v1.0.0 gave you one black hole. v1.1.0 gives you three, each modelled on a real object and rendered by the same physics simulator: light paths are ray marched around the hole, so the lensing, the far side of the disk bending over and under the shadow, and the Doppler brightening on the approaching side all come from the maths, not from a texture.

## ✨ What's new

### Three black holes, picked at random
- **TON 618.** A hyperluminous quasar 66 billion times the mass of the Sun. No telescope has resolved it, so this is the simulated view: edge on, an enormous disk, white-blue hot at the core and amber at the rim.
- **M87\*.** The black hole from the first ever photograph of one, the 2019 Event Horizon Telescope image. Viewed 17 degrees from the pole, a thick orange ring, brightest to the south where the gas comes toward you.
- **Sagittarius A\*.** The black hole at the centre of our own galaxy, from the 2022 EHT image. A thinner, yellower ring with three bright knots, and gas that visibly moves, because at this size an orbit takes minutes rather than days.

The preview in the menu bar cycles through all three in order.

### Warmer palette
The disks now lean orange and gold, with the hottest regions pushed toward white.

## 🛠️ Fixes
- Gas near the inner edge of the disk no longer flickers.
- Removed a drawn-on ring that did not line up with the true shadow edge.
- Strongly bent light now shows a mirrored, dimmed copy of your screen instead of a dark blob.
- Removed a seam in the disk texture where the angle wrapped around.
- Settings saved by v1.0.0 carry over.

## 🔒 Privacy
Added [PRIVACY.md](https://github.com/YashaswyAkella/overwork/blob/main/PRIVACY.md). Overwork has no network code, no analytics and no accounts. The screenshot it bends lives in GPU memory for the length of the break and is never written to disk. Call detection reads only a yes/no "is the microphone or camera in use" flag.

## 📥 Install
1. Download `Overwork.dmg` below and drag Overwork into Applications.
2. The build is locally signed but not notarized. If macOS refuses to open it, go to **System Settings → Privacy & Security** and choose **Open Anyway**.
3. Allow **Screen Recording** when asked, then quit and reopen Overwork.

Upgrading from v1.0.0: quit the old copy, replace the app, and reopen. The Screen Recording permission carries over.

Requires macOS 14 Sonoma or later.

**SHA-256 of Overwork.dmg:** `c607e669db0c9387e332b0156cc6ded5883e6241354b8fa756fa6b6a7de10539`
