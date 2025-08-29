# Keyboard Tracking and Typing Monitor for macOS

A tool inspired by "Vim Hardtime" that detects when you're typing too much text and encourages using keyboard shortcuts instead. This application monitors keyboard activity and warns you when you've typed too many consecutive characters without using shortcuts.

## Features

- Real-time keyboard monitoring using macOS Core Graphics Event Tap
- Warns you when typing too many consecutive characters
- Provides audible and visual warnings through system notifications
- Resets count when using keyboard shortcuts or special keys
- Includes a cooldown timer to reset after periods of inactivity
- Runs in the background with a simple menu bar icon

## How It Works

1. The app counts consecutive character keystrokes as you type
2. When you reach the character threshold (default: 5 characters), it shows a warning
3. Using keyboard shortcuts (Cmd/Ctrl/Alt + any key) or pressing Enter/Escape/etc. resets the counter
4. A pause in typing also resets the counter after the cooldown period

## Technical Details

This application demonstrates how to:

1. **Hook into macOS keyboard events** using Core Graphics Event Tap
2. **Process keyboard events** in real-time
3. **Filter and categorize keys** (characters, modifiers, special keys)
4. **Handle key repeat** properly (counting each key only once while held)
5. **Detect keyboard shortcuts** by checking modifier flags

## Requirements

- macOS 10.10 or later
- Xcode Command Line Tools (for compilation)
- Accessibility permissions (required to monitor keyboard events)

## Building and Running

1. Navigate to the project directory:
    ```
    cd ~/code/macos_keylogger
    ```

2. Compile the application:
    ```
    make
    ```

3. **Run from the app bundle (recommended for full functionality):**
    ```
    make run-app
    ```
    This runs the app from its proper .app bundle, enabling notifications.

4. **Alternative: Run development binary:**
    ```
    make run-dev
    ```
    ⚠️ **Warning:** Running as a standalone executable disables notifications. Use this only for development/testing.

5. Grant accessibility permissions when prompted
6. The app will show a "KM" icon in your menu bar and start monitoring your typing

## Troubleshooting

### Notifications Not Working
- **Problem:** No notifications appear when typing threshold is reached
- **Solution:** Make sure you're running from the .app bundle (`make run-app`), not the dev binary
- **Check:** System Settings → Notifications → Keyboard Monitor should be enabled

### App Won't Start
- **Problem:** App crashes on launch
- **Solution:** Ensure Accessibility permissions are granted in System Settings → Privacy & Security → Accessibility
- **Alternative:** Run `make run-app` to launch from Finder if the terminal method fails

### No Menu Bar Icon
- **Problem:** App runs but no icon appears in menu bar
- **Solution:** Check the console output for error messages, ensure proper permissions are granted

## Configuration

You can modify these in `src/KeyboardMonitor.m` or surface a UI later:

- `maxConsecutiveChars`: The number of consecutive characters before showing a warning (default: 15)
- `typingCooldownMs`: Time in milliseconds of inactivity before resetting the counter (default: 3000)

## Implementation Notes

This project takes inspiration from the keyboard tracking in espanso:

### Architecture Overview

The core architecture consists of:

1. **Event Tap Setup**: Uses Core Graphics Event Tap to hook into system keyboard events
2. **Event Callback**: Processes keyboard events to track consecutive typing
3. **Key Dictionary**: Prevents double-counting keys when held down
4. **Warning System**: Shows a notification when the threshold is reached

### How Events Are Processed

1. **Key Press Detection**: Captures key down, key up, and modifier change events
2. **Character Extraction**: Gets Unicode characters from keyboard events
3. **Modifier Flag Checking**: Detects keyboard shortcuts by checking modifier flags
4. **Tracking Consecutive Characters**: Counts only printable characters, not control keys
5. **Warning Trigger**: Shows a warning when the count exceeds the threshold

### Native Integration

- Uses Core Graphics for event capture
- Uses NSNotification for system notifications
- Uses NSBeep for audible warnings

## Differences from espanso

While this project was inspired by espanso's keyboard tracking, it differs in several ways:

1. **Focused Purpose**: Specifically designed to warn about excessive typing
2. **Simpler Implementation**: Single file implementation instead of a multi-platform structure
3. **Native Notifications**: Uses macOS system notifications
4. **Key Repeat Handling**: Custom tracking of key presses to handle keyboard repeat correctly
5. **No Text Expansion**: Unlike espanso, this app just monitors typing patterns

## Security and Privacy

This application requires Accessibility permissions to monitor keyboard events. It:
- Does not send any data over the network
- Logs only operational status by default; it does not log characters
- Keeps any ephemeral buffers in memory only

## Acknowledgments

- Inspired by Vim Hardtime concept
- Keyboard event tracking approach inspired by espanso's implementation
- Used espanso's source code as reference for macOS keyboard event handling

## Notes

- Uses `UserNotifications` (modern notifications) and ARC.
- Status bar icon currently uses text; consider a template image asset for better dark-mode support.
