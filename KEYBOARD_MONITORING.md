# Keyboard Monitoring in macOS Applications

This guide explains how keyboard monitoring works in macOS and how to implement it in your own applications.

## Fundamental Concepts

### Event Handling in macOS

macOS uses a system-wide event handling mechanism where events (mouse clicks, keypresses, etc.) are processed through an event stream. The Core Graphics framework provides APIs to tap into this event stream.

### Core Graphics Event Tap

An Event Tap is a mechanism that allows your application to:

1. Monitor events before they're delivered to applications
2. Intercept and modify events 
3. Generate synthetic events

Event taps operate at different levels:
- **Session level**: System-wide events
- **Process level**: Events for a specific process
- **Annotation level**: Events after they're processed by applications

## Setting Up Keyboard Monitoring

### 1. Request Permissions

Applications must request Accessibility permissions to monitor keyboard input. In macOS, this is controlled via:

- Privacy & Security settings
- Accessibility permission dialog
- Entitlements in the application bundle

### 2. Create an Event Tap

```objc
// Create event tap to monitor keyboard events
CFMachPortRef eventTap = CGEventTapCreate(
    kCGSessionEventTap,        // Monitor at session level
    kCGHeadInsertEventTap,     // Insert at start of chain 
    kCGEventTapOptionDefault,  // Default options
    CGEventMaskBit(kCGEventKeyDown) | 
    CGEventMaskBit(kCGEventKeyUp) | 
    CGEventMaskBit(kCGEventFlagsChanged),  // Event types to monitor
    eventCallback,             // Callback function
    NULL                       // User data (context)
);
```

### 3. Create a Run Loop Source

```objc
// Add the event tap to the run loop
CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(
    kCFAllocatorDefault, 
    eventTap, 
    0
);

CFRunLoopAddSource(
    CFRunLoopGetCurrent(),
    runLoopSource,
    kCFRunLoopCommonModes
);
```

### 4. Process Events in Callback

```objc
CGEventRef eventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    // Get key code
    CGKeyCode keyCode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    
    // Get character (for key down events)
    if (type == kCGEventKeyDown) {
        UniChar buffer[4];
        UniCharCount actualLength = 0;
        
        CGEventKeyboardGetUnicodeString(event, 4, &actualLength, buffer);
        if (actualLength > 0) {
            NSString *character = [[NSString alloc] initWithCharacters:buffer length:actualLength];
            // Process the character
        }
    }
    
    // Get modifier flags
    CGEventFlags flags = CGEventGetFlags(event);
    BOOL isShiftPressed = (flags & kCGEventFlagMaskShift) != 0;
    BOOL isControlPressed = (flags & kCGEventFlagMaskControl) != 0;
    
    // Process event based on type, key code, modifiers, etc.
    
    // Return the event (passing it along to other applications)
    return event;
}
```

## Understanding Keyboard Events

### Event Types

1. **kCGEventKeyDown**: Triggered when a key is pressed
2. **kCGEventKeyUp**: Triggered when a key is released
3. **kCGEventFlagsChanged**: Triggered when a modifier key state changes

### Key Components

Each keyboard event contains:

1. **Key Code**: Hardware-specific code identifying the physical key
2. **Character**: The actual character(s) produced by the keypress
3. **Modifier Flags**: State of modifier keys (Shift, Ctrl, Alt, Command)
4. **Timestamp**: When the event occurred

### Modifier Keys

Modifier keys require special handling:

- They generate `kCGEventFlagsChanged` events
- The event doesn't specify which modifier changed
- You need to check all modifier flags to determine what changed

## Advanced Techniques

### Handling Key Repeats

When a key is held down, macOS generates repeated KeyDown events. To count each key only once:

```objc
// Dictionary to track pressed keys
NSMutableDictionary *keyTracker;

// On key down
NSString *keyString = [NSString stringWithFormat:@"%d", keyCode];
if (![keyTracker objectForKey:keyString]) {
    [keyTracker setObject:@YES forKey:keyString];
    // Count the key (only once)
}

// On key up
[keyTracker removeObjectForKey:keyString];
```

### Detecting Keyboard Shortcuts

```objc
BOOL isShortcut = isControlPressed || isCommandPressed || isAltPressed;
if (isShortcut) {
    // This is a keyboard shortcut
}
```

### Distinguishing Software vs Hardware Generated Events

In some cases, you need to distinguish between hardware keypresses and software-generated ones:

- On Windows, espanso uses the `has_known_source` flag
- On macOS, this distinction is more challenging 
- Consider context (timing, event sequence) to detect software events

## Common Challenges

### 1. Security and Privacy

- **User consent**: Always inform users about keyboard monitoring
- **Data protection**: Be careful with sensitive data (passwords, etc.)
- **Secure storage**: Encrypt any logs containing keystrokes

### 2. Cross-Platform Compatibility

Different operating systems handle keyboard events differently:

- **macOS**: Uses Core Graphics Event Taps and Cocoa events
- **Windows**: Uses Raw Input API or keyboard hooks
- **Linux**: Uses X11 Record Extension or evdev

### 3. Different Keyboard Layouts

- Key codes may be consistent across layouts, but characters differ
- Consider using key codes for shortcuts and characters for text input
- Be aware of different modifier key placements on international keyboards

### 4. Accessibility

- Some users rely on assistive technologies (screen readers, etc.)
- Ensure your keyboard monitoring doesn't interfere with these tools
- Test with VoiceOver and other accessibility features

## Code Examples

### Creating a Simple Key Logger

```objc
void logKeyPress(CGKeyCode keyCode, NSString *character) {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timestamp = [dateFormatter stringFromDate:[NSDate date]];
    
    printf("[%s] Key %d pressed [char: %s]\n", 
           [timestamp UTF8String], 
           keyCode, 
           [character UTF8String]);
}
```

### Detecting Specific Key Combinations

```objc
BOOL isCommandS = (keyCode == kVK_ANSI_S && isCommandPressed);
if (isCommandS) {
    // Handle Command+S
}
```

## Resources for Further Learning

### Apple Documentation
- [Core Graphics Event Taps](https://developer.apple.com/documentation/coregraphics/quartz_event_services)
- [CGEventTapCreate](https://developer.apple.com/documentation/coregraphics/1454426-cgeventtapcreate)
- [CGEventType](https://developer.apple.com/documentation/coregraphics/cgeventtype)

### Related Projects
- [espanso](https://github.com/espanso/espanso): Text expander with keyboard monitoring
- [KeyboardKit](https://github.com/KeyboardKit/KeyboardKit): Keyboard utilities for Swift

### Key Code Reference

```swift
// Common Virtual Key Codes (kVK_*)
kVK_Return        = 0x24
kVK_Tab           = 0x30
kVK_Space         = 0x31
kVK_Delete        = 0x33
kVK_Escape        = 0x35
kVK_Command       = 0x37
kVK_Shift         = 0x38
kVK_CapsLock      = 0x39
kVK_Option        = 0x3A
kVK_Control       = 0x3B
kVK_RightShift    = 0x3C
kVK_RightOption   = 0x3D
kVK_RightControl  = 0x3E
```

## Security Practices

### 1. Limit Data Collection

- Only collect what you need
- Avoid logging password fields or sensitive data
- Consider using a blocklist for sensitive applications

### 2. Local Processing

- Process data locally when possible
- Avoid sending keyboard data over the network
- If network transmission is necessary, use strong encryption

### 3. Clear Indicators

- Provide a clear indication when monitoring is active
- Allow users to easily disable monitoring
- Document all keyboard monitoring in your privacy policy

## Conclusion

Keyboard monitoring in macOS provides powerful capabilities for creating productivity tools, accessibility features, and more. However, it comes with significant responsibility to protect user privacy and security. By following the techniques and best practices outlined in this guide, you can create responsible and effective keyboard-aware applications.