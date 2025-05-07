# Implementation Notes: Keyboard Monitoring in macOS

This document covers the implementation details of keyboard monitoring in macOS, with specific reference to how it's done in both our application and the espanso project that inspired it.

## Core Concepts

### 1. Event Taps

In macOS, keyboard monitoring is primarily done using **CGEventTap**. This is a system-level mechanism that lets applications intercept and modify events before they reach other applications. For global keyboard monitoring:

```objc
CFMachPortRef eventTap = CGEventTapCreate(
    kCGSessionEventTap,        // Tap at session level (global)
    kCGHeadInsertEventTap,     // Insert at start of event chain
    kCGEventTapOptionDefault,  // Default options
    CGEventMaskBit(kCGEventKeyDown) | 
    CGEventMaskBit(kCGEventKeyUp) | 
    CGEventMaskBit(kCGEventFlagsChanged),  // Events to monitor
    eventCallback,             // Callback function
    NULL                       // User data
);
```

### 2. Event Callback Structure

The event callback function is called whenever a monitored event occurs:

```objc
CGEventRef eventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    // Process the event
    
    // Return the event (potentially modified)
    return event;
}
```

### 3. Key Event Types

Three main types of keyboard events are monitored:

- **kCGEventKeyDown**: Triggered when a key is pressed
- **kCGEventKeyUp**: Triggered when a key is released
- **kCGEventFlagsChanged**: Triggered when modifier keys change state

### 4. Key Information Extraction

From each event, we extract several pieces of information:

- **Key code**: Using `CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode)`
- **Character**: Using `CGEventKeyboardGetUnicodeString()`
- **Modifier flags**: Using `CGEventGetFlags(event)`

## Implementation Challenges

### 1. Character vs. Key Code

- **Character** represents the actual text input (e.g., 'a', 'A', '@')
- **Key code** represents the physical key (e.g., key code 0 is always the 'A' key regardless of shift state)

### 2. Key Repeat Handling

A major challenge is handling key repeats properly. When a key is held down, macOS generates multiple KeyDown events. To track unique keypresses:

```objc
// Track which keys are currently pressed
NSMutableDictionary *keyTracker;

// When key is pressed
if (![keyTracker objectForKey:keyString]) {
    // Mark this key as pressed (only count once)
    [keyTracker setObject:@YES forKey:keyString];
    consecutiveChars++;
}

// When key is released
if (type == kCGEventKeyUp) {
    [keyTracker removeObjectForKey:keyString];
}
```

### 3. Modifier Keys Detection

Detecting modifier keys and shortcuts requires checking the event flags:

```objc
CGEventFlags flags = CGEventGetFlags(event);
BOOL isShiftPressed = (flags & kCGEventFlagMaskShift) != 0;
BOOL isControlPressed = (flags & kCGEventFlagMaskControl) != 0;
BOOL isAltPressed = (flags & kCGEventFlagMaskAlternate) != 0;
BOOL isCommandPressed = (flags & kCGEventFlagMaskCommand) != 0;

// Check for shortcut
BOOL isShortcut = isControlPressed || isCommandPressed || isAltPressed;
```

## Platform-Specific Approaches (From espanso)

### macOS (Cocoa)

The macOS implementation in espanso uses:

1. **Objective-C** bindings to hook into macOS events
2. **Channel-based** event communication (sender/receiver pattern)
3. **Special handling** for modifier key state inconsistencies
4. **Workarounds** for external Bluetooth keyboards

Key components:
- `detect_initialize()` function to set up the callback
- `RawInputEvent` struct to store raw event data
- `CocoaSource` class implementing the platform-specific source

### Windows (Win32)

For comparison, Windows implementation uses:

1. **Windows Raw Input API** for event capturing
2. Filtering for software-generated events to avoid loops
3. Key code mapping to a common key representation

### Linux (X11 and Evdev)

Linux implementations use:

1. **X11 Record Extension** (X11) or direct input event interface (Evdev for Wayland)
2. Specific handling for different keyboard layouts
3. Translation of platform keycodes to common representation

## Warning Implementation

The warning system uses multiple mechanisms to ensure visibility:

1. **Console Logging**: Visible in terminal output
   ```
   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   !!! WARNING: TYPED 5 CONSECUTIVE CHARACTERS !!!
   !!! TRY USING KEYBOARD SHORTCUTS INSTEAD    !!!
   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   ```

2. **System Beep**: Using `NSBeep()` for audio alert

3. **Notification**: Using macOS notification center via osascript:
   ```objc
   NSString *scriptContent = 
       @"osascript -e 'display notification \"You have typed %d consecutive characters\" with title \"Typing Too Much!\"'";
   ```

## Performance Considerations

- **Event handling must be efficient** to avoid adding lag to keystrokes
- **Minimal processing** in the event callback
- **Buffer management** to track character sequences
- **Proper deallocation** of resources when application exits

## Comparing with espanso Architecture

Espanso uses a more complex architecture:

1. **Source Trait**: Common interface for all platform implementations
2. **Event Normalization**: Converts platform-specific events to common format
3. **Multi-platform Support**: Abstractions for Windows, macOS, Linux
4. **Plugin System**: For extensibility

Our implementation is simpler:
1. **Single file**: All code in main.m
2. **macOS specific**: No platform abstraction layer
3. **Focused functionality**: Just warning on consecutive typing
4. **Direct notification**: No complex event processing pipeline

## Debugging Tips

For debugging keyboard events:

1. **Log extensively**: Log each key press, release, and character
2. **Include timestamps**: Helps diagnose timing issues
3. **Show character counts**: Track the progression of consecutive characters
4. **Test with different keyboards**: Hardware keyboards and laptop keyboards
5. **Test with different applications**: Different apps may generate different events

## Security and Permissions

For security:

1. **Accessibility permissions**: Required for global event monitoring
2. **Local logging only**: No network access
3. **Minimal data capture**: Only counting characters, not analyzing content
4. **Transparency**: Clear indication when the app is running (menu bar icon)

## Next Steps and Improvements

Potential improvements:

1. **Configuration UI**: Allow changing settings without editing code
2. **Application-specific rules**: Different thresholds for different applications
3. **Learning mode**: Suggest shortcuts based on common typing patterns
4. **Custom shortcuts**: Define your own shortcuts to reset counter
5. **Statistics view**: Show typing patterns over time