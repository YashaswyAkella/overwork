# Privacy

Overwork runs entirely on your Mac. It has no network code, no analytics, no accounts,
and no telemetry. Nothing leaves the machine.

## What it touches, and why

| Data | When | Where it goes |
|---|---|---|
| A screenshot of each display | Once, at the moment a break starts | GPU memory only, for the length of the break, then discarded. Never written to disk. |
| Whether another app is using the microphone or camera | Every few seconds while the work timer is running | Read as a yes/no flag from CoreAudio and CoreMediaIO. No audio or video is accessed. |
| Time since your last mouse or keyboard event | Every second | Read as a number of seconds. Keystrokes and mouse positions are never read. |
| Your code word | When you set it | Stored as a SHA-256 hash in the app's own preferences. The word itself is not stored. |
| Work, break and idle lengths, launch at login | When you change them | The app's own preferences in `~/Library/Preferences`. |

## Permissions

- **Screen Recording** is needed to capture the screenshot that the black hole bends. Without it
  the app still works and shows a starfield instead.
- No Microphone, Camera, Accessibility or Full Disk Access permission is requested.

## Debug flags

`--render file.png` writes one rendered frame, which contains a warped copy of your screen, to the
path you give. `--calls file.txt` writes the bundle identifiers of apps currently using the
microphone. Both run only when you start the app with those flags from a terminal.
