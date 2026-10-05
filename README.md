# Hush

A tiny macOS menu-bar app that pauses your music while your microphone is in use
and resumes it when you're done.

Built for voice modes like Claude's, but it works for anything that records:
calls, dictation, voice memos. With AirPods it waits for them to switch back from
call audio to high-quality playback before resuming, so the music doesn't come
back muffled.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode or the Xcode Command Line Tools (to build)

## Build & install

```bash
git clone https://github.com/rvh70/hush.git
cd hush
./scripts/build.sh --install
```

This builds `Hush.app`, copies it to `~/Applications` and launches it. Turn on
**Launch at Login** from the menu-bar icon to keep it running.

The first time Hush pauses Spotify or Music, macOS asks whether Hush may control
it. Allow this, or Hush can't pause that player. The app is ad-hoc signed, so
macOS may ask again after you rebuild it.

## Menu

Click the menu-bar icon for:

- **Status:** what Hush is doing right now
- **Enable / Disable Hush**
- **Launch at Login**
- **Quit Hush**

| Icon | Meaning |
| --- | --- |
| `music.note` | On, waiting for the mic |
| `mic.fill` | Music paused while the mic is in use |
| `speaker.slash` | Off |

## How it works

- **Mic detection:** CoreAudio's per-process objects
  (`kAudioProcessPropertyIsRunningInput`, macOS 14+) report which apps are
  recording. Hush only listens for CoreAudio change notifications and never
  polls, so it stays idle until something starts or stops recording. Music
  playing through a headset that also has a mic doesn't count as recording.
- **Pausing:** Spotify and Music are paused through AppleScript, only if they're
  running and playing. Hush never launches them. If neither was playing, it
  falls back to the system "now playing" session through the private
  MediaRemote framework, which covers browsers and other players. macOS 15.4+
  limits that framework for third-party apps, so this fallback may not work on
  every system.
- **Resuming:** Hush resumes only what it paused. It waits at least 0.5 s, then
  resumes as soon as the output device is back at music quality (≥ 44.1 kHz),
  or after 4 s at most. AirPods typically take about 2 s to switch back.

### Tip: skip the AirPods quality switch

Using AirPods as the mic forces them into call mode, which lowers quality and
causes the ~2 s wait before resuming. To avoid it, set **System Settings →
Sound → Input** to your Mac's built-in microphone. Your AirPods then stay in
high-quality mode and the music returns in about half a second.

## License

[MIT](LICENSE)
