# Stop Typing App

A macOS menu bar app that notices when you're typing out prose by hand and nudges you to dictate it instead.

It watches for bursts of typing that read like sentences (several words, mostly letters) and shows a small on-screen nudge. Keep typing a whole paragraph and it nudges more firmly. Shortcuts, held keys, Vim motions and code-like text don't count.

## Features

- **Prose detection.** A burst is the typing between pauses. It reads like prose when it has at least 2 word breaks, 5 different letters and is at least 60% letters. The first nudge ("You're typing a lot. Use dictation instead.") comes at 25 characters of prose; keep going past 80 characters or a minute and a firm "Still typing?" follows, at most every 30 seconds.
- **Quiet by default.** After a nudge, new bursts wait 2 minutes before the next gentle nudge. A 5 second pause (2.5 s for very short bursts) or Escape ends a burst. All of this is adjustable in Settings → Detection.
- **On-screen nudge** that never takes focus. Drag it anywhere; it remembers the spot. It appears on the screen you're typing on.
- **Notification Center (optional)** gets every nudge too, so you can find them later. The stop window isn't sent there.
- **Stop window (opt-in).** Replaces the firm nudge: keep typing after the first nudge and, once the "time to switch to dictation" (30 s by default) has passed, a centered window takes focus until you click Got It, Snooze 15 Minutes or Ignore <App>. Its buttons have no keyboard shortcuts, so typing can't dismiss it. After Got It it stays quiet for a full "wait between nudges", then starts over. In full-screen apps it shows the on-screen nudge instead (adjustable).
- **Quiet during Focus.** No nudges at all while Do Not Disturb or another Focus is on (adjustable).
- **Per-app exclusions** for terminals, editors and games, with a one-click toggle for the last app you used.
- **Snooze** for 15 minutes, an hour, or until tomorrow.
- **Today's stats:** nudges and an estimate of words typed.
- **Open at login.**

## Privacy

Stop Typing App uses a *listen-only* event tap, so it can observe key presses but never delay, change or block them. Each key is turned into a count the moment it arrives; characters are never stored, logged or sent anywhere. Password fields are invisible to it because macOS hides keystrokes while secure input is on. The app is sandboxed and makes no network connections.

It needs **Input Monitoring** permission (System Settings → Privacy & Security → Input Monitoring). macOS asks the first time you launch it.

## Requirements

- macOS 15 or later
- Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Building

```sh
make run    # generate the project, build, and launch
make test   # run the detection tests
make build  # build only; the app lands in build/Build/Products/Debug
```

The Xcode project is generated from `project.yml`, so edit that rather than the `.xcodeproj` (which isn't checked in). Run `make project` and open `StopTyping.xcodeproj` to work in Xcode.

Builds are signed with an Apple Development certificate so macOS keeps the Input Monitoring permission between builds. To build with a different account, change `DEVELOPMENT_TEAM` in `project.yml`.

## Layout

| Path | What's there |
|---|---|
| `StopTypingCore/` | Swift package with the detection logic and daily stats. No system frameworks, fully unit tested. |
| `StopTyping/Input/KeyboardTap.swift` | The listen-only event tap, on its own thread, delivered as an `AsyncStream`. |
| `StopTyping/App/` | App entry point, `AppModel` (connects everything) and `Preferences`. |
| `StopTyping/Nudges/` | The on-screen nudge and notifications. |
| `StopTyping/Views/` | The menu bar panel and Settings window. |
| `StopTyping/Resources/` | The Icon Composer app icon and the menu bar asset. |

The keyboard-off glyph is from [Lucide](https://lucide.dev) (ISC license).
