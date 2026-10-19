# AGENTS.md

Notes for coding agents (and people) working on Stop Typing App. README.md covers what the app does and how to build, install and release it; this file covers how the code is put together and the traps.

## Architecture

- **`StopTypingCore/`** (Swift package, no AppKit): `TypingDetector` decides when typing reads like prose and which nudge to show; `DailyStats` keeps per-day counts. All detection rules live here and are covered by `make test` (Swift Testing). Change behaviour here first, with a test.
- **`StopTyping/Input/KeyboardTap.swift`**: a *listen-only* `CGEventTap` on its own thread, turned into `Keystroke` values (characters are classified, never kept) and delivered as an `AsyncStream`. Listen-only needs Input Monitoring, not Accessibility.
- **`StopTyping/App/AppModel.swift`**: `@MainActor @Observable`; owns the tap, detector, nudges, snooze, ignore list and permission state. `Preferences` persists settings to `UserDefaults` with `didSet`. `Updater` wraps Sparkle.
- **Nudge escalation** (decided with the user, see `TypingDetector.nudge(for:at:)`): gentle → firm "Still typing?" by default; gentle → stop window when "Stop me if I keep typing" is on. After Got It the stop window waits a full cooldown, then starts over. In full-screen apps the stop window becomes the on-screen nudge. During a Focus the detector is `isQuiet` (counts prose, never nudges). Notification Center mirrors gentle and firm nudges, never the stop window.
- **`StopTyping/Nudges/`**: `NudgeHUD` (draggable, click-through margin, remembers its offset), `StopWindow` (focus-stealing panel; buttons deliberately have no keyboard shortcuts), `NotificationNudger`, `FrontmostWindow` (which screen you're typing on, and full-screen detection).
- **`StopTyping/Onboarding/`**: the first-run permissions checklist, hosted in an AppKit window owned by `AppModel`.

## Conventions

- Swift 6 strict concurrency, SwiftUI first, `@Observable`, macOS 15+. Doc comments explain *why*. No speculative defensive checks; never cast to `any`.
- UI copy is short and plain (the app's voice: "You're typing a lot. Use dictation instead."). Settings rows are settings; actions such as Preview or Reset go in `SectionActions` under their section.
- Never log or store typed characters. The `os.Logger` subsystem is `com.kevintraver.StopTyping` and logs decisions and timings only.
- Commit as you go with Conventional Commits (`feat(scope):`, `fix:`, `build:`, `docs:`), one logical, building change per commit. When agents work in parallel worktrees, rebase onto the integration branch before finishing.

## Traps

- **Run the installed app.** `make run` builds, installs to `~/Applications/Stop Typing App.app`, quits the running copy and opens the new one. Don't launch from `build/`.
- **Permissions follow the signature.** Input Monitoring is keyed to the signing identity and bundle ID (`com.kevintraver.StopTyping`). Ad-hoc signing or a new bundle ID silently loses the grant.
- **A tap made before Input Monitoring is granted never receives keys**, and macOS doesn't upgrade it. The app only creates the tap after `CGPreflightListenEventAccess()` is true, so no relaunch is needed; Relaunch is only the fallback when tap creation still fails.
- **Full-screen windows stop below the notch.** Compare against the screen minus `safeAreaInsets.top`, or check that the frontmost app owns every layer-0 window (it has its own Space). Window bounds and owners need no permission; titles need Screen Recording.
- **Focus detection** (`INFocusStatusCenter`) is authorized without the Communication Notifications entitlement here, but has not yet been seen reporting `true` with a Focus on. Verify before relying on it.
- **zsh has a builtin `log`.** Use `/usr/bin/log show --last 5m --predicate 'subsystem == "com.kevintraver.StopTyping"'`.
- **`actool` resolves relative paths through a daemon** with a different working directory. Pass absolute paths when compiling icons by hand.
- **SourceKit shows "No such module 'StopTypingCore'"** in editors that don't load the generated project. Trust `make build`.
- **Sparkle in the sandbox** needs the installer and downloader XPC services and the `-spks`/`-spki` mach-lookup exceptions (all in `project.yml`). Development builds have no `SUPublicEDKey`, so the updater deliberately never starts.
- **`project.yml` is the source of truth.** `Info.plist` and the entitlements file are regenerated from it; the version lives only in `MARKETING_VERSION`.
