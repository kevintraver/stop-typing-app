# Stop Typing App

A macOS menu bar app that notices when you're typing out prose by hand and nudges you to dictate it instead.

It watches for bursts of typing that read like sentences (several words, mostly letters) and shows a small on-screen nudge. Keep typing a whole paragraph and it nudges more firmly. Shortcuts, held keys, Vim motions and code-like text don't count.

## Features

- **Prose detection.** A burst is the typing between pauses. It reads like prose when it has at least 2 word breaks and is at least 60% letters. The first nudge ("You're typing a lot. Use dictation instead.") comes at 25 characters of prose; keep going past 80 characters or a minute and a firm "Still typing?" follows, at most every 30 seconds.
- **Quiet by default.** After a nudge, new bursts wait 2 minutes before the next gentle nudge. A 5 second pause (2.5 s for very short bursts) or Escape ends a burst. All of this is adjustable in Settings → Detection.
- **On-screen nudge** that never takes focus. Drag it anywhere; it remembers the spot. It appears on the screen you're typing on.
- **Notification Center (optional)** gets every nudge too, so you can find them later. The stop window isn't sent there.
- **Stop window (opt-in).** Replaces the firm nudge: keep typing after the first nudge and, once the "time to switch to dictation" (30 s by default) has passed, a centered window takes focus until you click Got It, Snooze 15 Minutes or Ignore <App>. Its buttons have no keyboard shortcuts, so typing can't dismiss it. After Got It it stays quiet for a full "wait between nudges", then starts over. In full-screen apps it shows the on-screen nudge instead (adjustable).
- **Quiet during Focus.** No nudges at all while Do Not Disturb or another Focus is on (adjustable).
- **Ignore list** for terminals, editors and games, with a one-click **Ignore** button for the last app you used.
- **Snooze** for 15 minutes, an hour, or until tomorrow.
- **Today's stats:** nudges and an estimate of words typed.
- **Open at login**, and **automatic updates** through Sparkle in release builds.

## Install

- **Download:** the DMG from the [latest release](https://github.com/kevintraver/stop-typing-app/releases/latest), then drag the app to Applications.
- **Homebrew:** `brew install --cask kevintraver/tap/stop-typing-app`

On first launch a setup window walks through permissions. Only **Input Monitoring** is required (System Settings → Privacy & Security → Input Monitoring); the app starts listening as soon as you allow it, without a relaunch. Notifications and Focus status are optional.

## Privacy

Stop Typing App uses a *listen-only* event tap: it cannot delay, change or block key presses. It briefly classifies input on your Mac as letters, word breaks or other characters. Only counts and timing leave the callback; typed text is not saved to disk, logged or sent anywhere. The input-monitoring code writes no logs and includes no analytics or crash-reporting service.

Preferences contain your settings, ignored app identifiers, and one day's aggregate prose-character and nudge counts. Expired counts are replaced at midnight while running, and on launch, wake, clock/timezone changes and app activation. The app cannot erase data while it is stopped or the Mac is asleep, or remove copies in system backups. Optional Notification Center nudges contain only fixed reminder text, but macOS retains their delivery time.

The keyboard-monitoring process is sandboxed without network access. Automatic update checks are off by default. If you enable them or choose **Check for Updates**, Sparkle contacts GitHub and its download servers. Requests reveal your IP address, app and Sparkle versions, and request language, never typing or app-usage data. System profiling is explicitly disabled. Sparkle's downloader and installer run outside the app sandbox and can retain local diagnostics, update preferences, timestamps and downloaded files. macOS can also produce its own diagnostics; this is not a promise that the operating system writes no logs.

Before decoding characters, the tap checks that an event is addressed to the currently allowed app. Snooze, ignored apps and the stop window close that boundary. Queued counts are invalidated when it changes. If macOS has not yet reported the new app, its input is dropped rather than attributed to the previous app.

macOS suppresses keyboard events while **Secure Event Input** is enabled. Native secure fields normally enable it; custom fields depend on their application's implementation. Secrets entered into an ordinary text field can still be classified, so the app does not promise to recognize every password field.

## Requirements

- macOS 15 or later
- Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Building

```sh
make run      # build, install to ~/Applications, and relaunch
make test     # run the detection tests
make build    # build only (build/Build/Products/Debug)
make install  # build and install to ~/Applications without launching
```

The Xcode project is generated from `project.yml`, so edit that rather than the `.xcodeproj` (which isn't checked in). Run `make project` and open `StopTyping.xcodeproj` to work in Xcode. The version lives only in `project.yml`: bump `MARKETING_VERSION` (what people see) **and** `CURRENT_PROJECT_VERSION` (the build number Sparkle compares) for every release; `make publish` refuses a build number that isn't higher than the published one.

The app runs from `~/Applications`, not `build/`, so `make clean` can't delete it from under you. Debug builds are signed with an Apple Development certificate, so macOS keeps the Input Monitoring permission across rebuilds. To build with a different account, change `DEVELOPMENT_TEAM` in `project.yml`.

## Releasing

```sh
make release  # dist/: signed, notarized DMG, Sparkle zip and appcast; prints the DMG's SHA-256
make publish  # also creates the GitHub release and updates the Homebrew cask
```

Without a Developer ID certificate, `make release` still produces a DMG signed with Apple Development and warns loudly; it won't pass Gatekeeper on other Macs, and `make publish` refuses to use it. One-time setup for real releases:

1. **Developer ID certificate:** Xcode → Settings → Accounts → team → Manage Certificates → + → Developer ID Application.
2. **Notarization:** `xcrun notarytool store-credentials stop-typing --apple-id <apple-id> --team-id 8EDDZ23NT2` with an app-specific password (or set `NOTARY_KEY_ID`/`NOTARY_ISSUER` for an App Store Connect API key).
3. **Sparkle key:** after one `make release`, run `build/release/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys`. It stores the private key in your login keychain; back it up with `generate_keys -x <file>`. Losing it means installed copies can never update again.
4. **Tap:** clone [kevintraver/homebrew-tap](https://github.com/kevintraver/homebrew-tap) to `~/Code/homebrew-tap`. `make publish` writes `Casks/stop-typing-app.rb` there (from `packaging/homebrew/`) and prints the commands to push it.

## Layout

| Path | What's there |
|---|---|
| `StopTypingCore/` | Swift package with the detection logic and daily stats. No system frameworks, fully unit tested. |
| `StopTyping/Input/` | The listen-only event tap (its own thread, delivered as an `AsyncStream`) and Focus status. |
| `StopTyping/App/` | App entry point, `AppModel` (connects everything), `Preferences` and the Sparkle `Updater`. |
| `StopTyping/Nudges/` | The on-screen nudge, the stop window, notifications, and finding the screen you're typing on. |
| `StopTyping/Onboarding/` | The first-run permissions checklist. |
| `StopTyping/Views/` | The menu bar panel and Settings window. |
| `StopTyping/Resources/` | The Icon Composer app icon. |
| `scripts/` | `release.sh` (build, sign, DMG, notarize, appcast, publish) and `update-cask.sh`. |
| `packaging/homebrew/` | The Homebrew cask template. |

## License

[MIT](LICENSE). The keyboard glyph in the app icon is adapted from [Lucide](https://lucide.dev) (ISC license).
