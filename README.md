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
- **Ignore list** for terminals, editors and games, with a one-click **Ignore** button for the last app you used.
- **Snooze** for 15 minutes, an hour, or until tomorrow.
- **Today's stats:** nudges and an estimate of words typed.
- **Open at login**, and **automatic updates** through Sparkle in release builds.

## Install

- **Download:** the DMG from the [latest release](https://github.com/kevintraver/stop-typing-app/releases/latest), then drag the app to Applications.
- **Homebrew:** `brew install --cask kevintraver/tap/stop-typing-app`

On first launch a setup window walks through permissions. Only **Input Monitoring** is required (System Settings → Privacy & Security → Input Monitoring); the app starts listening as soon as you allow it, without a relaunch. Notifications and Focus status are optional.

## Privacy

Stop Typing App uses a *listen-only* event tap, so it can observe key presses but never delay, change or block them. Each key is turned into a count the moment it arrives; characters are never stored, logged or sent anywhere. The app writes no logs at all. All it keeps, in its own sandboxed preferences, is your settings, your ignore list and today's two counts (nudges and an estimate of words typed). Password fields are invisible to it because macOS hides keystrokes while secure input is on.

The app is sandboxed and has no network access of its own, and by default it makes no network connections at all. If you turn on automatic update checks (off by default, in the setup window or Settings), Sparkle asks this repository's GitHub releases once a day for a newer version. That request carries the app's name and version, your language and, like any web request, your IP address; never anything you typed. Sparkle's downloader and installer helpers run outside the sandbox, as Sparkle ships them; the app that watches the keyboard never does.

While you're snoozed, typing in an ignored app, or looking at the stop window, keys aren't read at all. Otherwise each key is reduced, inside the event tap, to whether it was a letter, a word break or something else; nothing downstream can tell which key it was.

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
