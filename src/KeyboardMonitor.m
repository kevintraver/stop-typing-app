#import "KeyboardMonitor.h"

// Global file handle for logging (declared in main.m)
extern FILE *logFile;

// Forward declarations
void logMessage(const char* format, ...);

static const BOOL kLogKeystrokeDetails = NO;
static const BOOL kLogRecentChars = NO;

@interface KeyboardMonitor () {
    CFMachPortRef eventTap;
    CFRunLoopSourceRef runLoopSource;
    NSMutableString *recentChars;
    NSDate *lastKeyPressTime;
    int consecutiveChars;
    BOOL warningDisplayed;
    BOOL showDebounceInfo;
}
@end

@implementation KeyboardMonitor

- (instancetype)init {
    self = [super init];
    if (self) {
        // Default settings
        _maxConsecutiveChars = 15;
        _typingCooldownMs = 3000;
        _isMonitoring = NO;
        showDebounceInfo = YES;

        // Initialize tracking state
        recentChars = [[NSMutableString alloc] init];
        lastKeyPressTime = [NSDate date];
        consecutiveChars = 0;
        warningDisplayed = NO;

        logMessage("KeyboardMonitor initialized with threshold: %d chars, cooldown: %d ms",
                  _maxConsecutiveChars, _typingCooldownMs);
    }
    return self;
}

- (void)dealloc {
    [self stopMonitoring];
}

#pragma mark - Public Methods

- (void)startMonitoring {
    if (_isMonitoring) {
        logMessage("KeyboardMonitor: Already monitoring");
        return;
    }

    logMessage("KeyboardMonitor: Starting keyboard monitoring...");

    // Create an event tap to monitor keyboard events
    eventTap = CGEventTapCreate(
        kCGSessionEventTap,        // Tap at session level
        kCGHeadInsertEventTap,     // Insert at start of event chain
        kCGEventTapOptionDefault,  // Default options
        CGEventMaskBit(kCGEventKeyDown), // Only monitor key down events
        eventCallback,             // Callback function
        (__bridge void *)self      // Pass self as user data
    );

    if (!eventTap) {
        logMessage("ERROR: Failed to create event tap - accessibility permissions required");
        return;
    }

    // Create a run loop source from the event tap
    runLoopSource = CFMachPortCreateRunLoopSource(
        kCFAllocatorDefault,
        eventTap,
        0
    );

    // Add the run loop source to the current run loop
    CFRunLoopAddSource(
        CFRunLoopGetCurrent(),
        runLoopSource,
        kCFRunLoopCommonModes
    );

    // Enable the event tap
    CGEventTapEnable(eventTap, true);

    _isMonitoring = YES;
    logMessage("KeyboardMonitor: Successfully started monitoring");
}

- (void)stopMonitoring {
    if (!_isMonitoring) {
        logMessage("KeyboardMonitor: Not currently monitoring");
        return;
    }

    logMessage("KeyboardMonitor: Stopping keyboard monitoring...");

    if (runLoopSource) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
        CFRelease(runLoopSource);
        runLoopSource = NULL;
    }

    if (eventTap) {
        CFRelease(eventTap);
        eventTap = NULL;
    }

    _isMonitoring = NO;
    logMessage("KeyboardMonitor: Monitoring stopped");
}

- (void)resetCounter {
    consecutiveChars = 0;
    warningDisplayed = NO;
    [recentChars setString:@""];
    lastKeyPressTime = [NSDate date];
    logMessage("KeyboardMonitor: Counter reset");
}

- (int)currentConsecutiveChars {
    return consecutiveChars;
}

- (BOOL)warningDisplayed {
    return warningDisplayed;
}

#pragma mark - Private Methods

// Check if a character is a letter (A-Z, a-z)
- (BOOL)isLetter:(unichar)c {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}

// Check for inactivity timeout
- (void)checkInactivityReset {
    if (!lastKeyPressTime) {
        lastKeyPressTime = [NSDate date];
        return;
    }

    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:lastKeyPressTime];
    double seconds = elapsed;

    // Show detailed timing if enabled
    if (showDebounceInfo && consecutiveChars > 0) {
        float cooldownThreshold = _typingCooldownMs/1000.0;
        float timeRemaining = cooldownThreshold - seconds;

        if (timeRemaining > 0) {
            logMessage("COOLDOWN: %.1f seconds elapsed, %.1f seconds remaining before reset",
                      seconds, timeRemaining);
        }
    }

    if (seconds > _typingCooldownMs/1000.0) {
        // Only log if we had activity to reset
        if (consecutiveChars > 0) {
            logMessage("COOLDOWN TRIGGERED: %.1f seconds of inactivity - resetting counter from %d",
                      seconds, consecutiveChars);
            [self resetCounter];
        }

        // Clear warning after the same cooldown time
        if (seconds > _typingCooldownMs/1000.0) {
            if (warningDisplayed) {
                logMessage("WARNING CLEARED: %.1f seconds of inactivity", seconds);
                warningDisplayed = NO;
            }
        }
    }
}

// Show warning when threshold is reached
- (void)showWarning {
    if (warningDisplayed) return;

    warningDisplayed = YES;

    // Make the warning visible in console
    logMessage("");
    logMessage("⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️");
    logMessage("⚠️           W A R N I N G                    ⚠️");
    logMessage("⚠️  YOU'RE TYPING A LOT!                    ⚠️");

    if (kLogRecentChars && recentChars && [recentChars length] > 0) {
        logMessage("⚠️  RECENT KEYS: %s", [recentChars UTF8String]);
    }

    logMessage("⚠️  TRY USING SUPER WHISPER INSTEAD         ⚠️");
    logMessage("⚠️  Warning will clear after %d sec of inactivity  ⚠️", _typingCooldownMs/1000);
    logMessage("⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️");
    logMessage("");

    // Notify delegate
    if (_delegate && [_delegate respondsToSelector:@selector(keyboardMonitorDidDetectExcessiveTyping)]) {
        [_delegate keyboardMonitorDidDetectExcessiveTyping];
    }
}

#pragma mark - Event Callback

// Static callback function for CGEventTap
static CGEventRef eventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    @autoreleasepool {
        KeyboardMonitor *monitor = (__bridge KeyboardMonitor *)refcon;

        if (type == kCGEventKeyDown && monitor.isMonitoring) {
            [monitor handleKeyDown:event];
        }
    }

    // Pass event through to system
    return event;
}

// Handle key down events
- (void)handleKeyDown:(CGEventRef)event {
    // Check for inactivity
    [self checkInactivityReset];

    // Update typing tracking timestamp
    lastKeyPressTime = [NSDate date];

    // Get the actual Unicode character
    UniChar buffer[4];
    UniCharCount actualLength = 0;
    CGEventKeyboardGetUnicodeString(event, 4, &actualLength, buffer);

    // Skip if no character
    if (actualLength == 0) {
        return;
    }

    // Get the first character as a string
    NSString *charString = [[NSString alloc] initWithCharacters:buffer length:actualLength];

    // Get key code for logging
    CGKeyCode keyCode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);

    // Get modifier flags
    CGEventFlags flags = CGEventGetFlags(event);
    BOOL hasModifier = ((flags & kCGEventFlagMaskCommand) ||
                       (flags & kCGEventFlagMaskControl) ||
                       (flags & kCGEventFlagMaskAlternate));

    // Check if it's a letter
    BOOL isLetterKey = NO;
    if (actualLength > 0) {
        isLetterKey = [self isLetter:buffer[0]];
    }

    // Check for reset keys
    BOOL isResetKey = (keyCode == kVK_Return || keyCode == kVK_Escape);

    // Log keystroke info (optional for privacy)
    if (kLogKeystrokeDetails) {
        logMessage("KEY: code=%d, char='%s', isLetter=%s, mod=%s",
                  keyCode,
                  [charString UTF8String],
                  isLetterKey ? "YES" : "NO",
                  hasModifier ? "YES" : "NO");
    }

    // Handle letter keys - count them
    if (isLetterKey && !hasModifier) {
        // Increment counter
        consecutiveChars++;

        // Add to buffer (kept only in-memory)
        [recentChars appendString:charString];

        // Calculate how many more characters until warning
        int remaining = _maxConsecutiveChars - consecutiveChars;

        // Log counter with progress toward warning
        if (remaining > 0) {
            logMessage("LETTER COUNT: %d/%d (%d more until warning)",
                       consecutiveChars, _maxConsecutiveChars, remaining);
        } else {
            logMessage("LETTER COUNT: %d/%d (OVER LIMIT)",
                       consecutiveChars, _maxConsecutiveChars);
        }

        // Check warning threshold
        if (consecutiveChars >= _maxConsecutiveChars && !warningDisplayed) {
            [self showWarning];
        }
    }
    // Handle reset keys
    else if (isResetKey) {
        if (consecutiveChars > 0) {
            if (kLogKeystrokeDetails) {
                logMessage("RESET: Key %d ('%s') pressed - resetting from %d chars",
                          keyCode, [charString UTF8String], consecutiveChars);
            } else {
                logMessage("RESET: Return/Escape pressed - resetting from %d chars",
                          consecutiveChars);
            }
            consecutiveChars = 0;
            [recentChars setString:@""];
        }
    }
    // Handle modifier key combinations
    else if (hasModifier) {
        logMessage("SHORTCUT: Count stays at %d", consecutiveChars);
    }
    // Other keys - just log
    else {
        if (kLogKeystrokeDetails) {
            logMessage("NON-LETTER: Key %d ('%s') - count stays at %d",
                      keyCode, [charString UTF8String], consecutiveChars);
        }
    }
}

@end
