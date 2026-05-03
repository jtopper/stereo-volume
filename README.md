# stereo-vol

A macOS menubar utility that maps the keyboard volume keys to a Chromecast-connected audio device.

When the configured audio output is selected as the system default, stereo-vol intercepts the volume up, volume down, and mute keys and sends the corresponding commands to a Chromecast receiver on the local network — instead of adjusting the Mac's own volume. A menubar slider lets you control volume with the mouse, and a live readout reflects changes made from any source.

## Requirements

- macOS 13 or later
- Xcode command-line tools or Xcode (for `swift build`)
- A Chromecast device on the same local network
- An audio output device connected to that Chromecast (e.g. a USB audio interface)

## Building

```bash
git clone <repo-url>
cd stereo-vol
swift build -c release
```

The binary is written to `.build/arm64-apple-macosx/release/stereo-vol`.

## Installing

Copy the binary somewhere permanent and load the included LaunchAgent so it starts automatically at login:

```bash
cp .build/arm64-apple-macosx/release/stereo-vol /usr/local/bin/stereo-vol

cp com.jtopper.stereo-vol.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.jtopper.stereo-vol.plist
```

To start it immediately without logging out:

```bash
launchctl start com.jtopper.stereo-vol
```

Logs are written to `/tmp/stereo-vol.log`.

## First run

On the first launch stereo-vol will open a setup dialog. Select:

- **Audio Output** — the audio device whose volume keys you want to intercept (e.g. `Panasonic USB Audio 2`)
- **Chromecast** — the Chromecast receiver that device is connected to

Click **Save**. The app will discover the Chromecast on the local network and connect. Once connected, the menubar slider will show the current volume.

### Accessibility permission

stereo-vol uses a CGEventTap to intercept system media keys, which requires Accessibility access. On first launch macOS will prompt you, or you can grant it manually:

**System Settings → Privacy & Security → Accessibility → stereo-vol → enable**

After granting permission, restart the app (or restart the LaunchAgent).

## Usage

Click the menubar icon (🔊) to open the menu:

- **Slider** — drag to set volume; updates the Chromecast in real time
- **Mute** — toggle mute; a checkmark indicates the receiver is muted
- **Preferences…** — change the audio device or Chromecast target
- **Quit** — stop the app

The keyboard volume keys work whenever the configured audio output is the system default. Pressing volume up or down while muted will unmute and adjust from the previous volume level.

If a different audio output is selected in System Settings the keys pass through to macOS as normal, so switching outputs temporarily (e.g. to built-in speakers) works without reconfiguring anything.

## Uninstalling

```bash
launchctl unload ~/Library/LaunchAgents/com.jtopper.stereo-vol.plist
rm ~/Library/LaunchAgents/com.jtopper.stereo-vol.plist
rm /usr/local/bin/stereo-vol
rm -rf ~/Library/Application\ Support/stereo-vol
```

## How it works

- **Media key interception** — a `CGEventTap` at the session level intercepts `NX_SYSDEFINED` events (type 14). Keys are only consumed if the current default audio output matches the configured device; otherwise they pass through unmodified.
- **Chromecast communication** — the Cast V2 protocol runs over a TLS connection to port 8009. Messages are length-prefixed protobuf frames, implemented from scratch using `Network.framework`'s `NWProtocolFramer` API and a hand-written proto2 encoder/decoder. No third-party libraries are used.
- **Device discovery** — Chromecast devices are found via mDNS using `NWBrowser` browsing for `_googlecast._tcp`.
- **Configuration** — stored as JSON at `~/Library/Application Support/stereo-vol/config.json`.
