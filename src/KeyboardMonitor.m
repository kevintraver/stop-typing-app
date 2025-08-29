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

    // Prose-detection counters (reset on inactivity)
    int burstChars;           // printable, prose-like chars in current burst
    int alphaChars;           // letters counted in current burst
    int spaceChars;           // spaces/newlines in current burst
    int sentencePuncts;       // '.', '!', '?'
    uint32_t letterMask;      // distinct letters bitmask (a-z)
    int distinctLetters;

    // Burst timing
    NSDate *burstStartTime;   // start time of current burst

    // Warning control
    NSDate *lastWarningTime;
    NSDate *lastEscalationTime;
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
        burstChars = 0;
        alphaChars = 0;
        spaceChars = 0;
        sentencePuncts = 0;
        letterMask = 0;
        distinctLetters = 0;
        burstStartTime = [NSDate date];
        lastWarningTime = nil;
        lastEscalationTime = nil;

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
        // Fallback attempt: annotated session event tap (can work on some setups)
        logMessage("Event tap failed at kCGSessionEventTap, trying kCGAnnotatedSessionEventTap");
        eventTap = CGEventTapCreate(
            kCGAnnotatedSessionEventTap,
            kCGHeadInsertEventTap,
            kCGEventTapOptionDefault,
            CGEventMaskBit(kCGEventKeyDown),
            eventCallback,
            (__bridge void *)self
        );
    }

    if (!eventTap) {
        BOOL trusted = AXIsProcessTrusted();
        logMessage("ERROR: Failed to create event tap (trusted=%s). A full app restart may be required after granting Accessibility.",
                   trusted ? "YES" : "NO");
        // Show a one-time user hint to restart if needed
        dispatch_async(dispatch_get_main_queue(), ^{
            NSAlert *alert = [[NSAlert alloc] init];
            alert.alertStyle = NSAlertStyleWarning;
            alert.messageText = @"Accessibility Activation";
            alert.informativeText = @"Keyboard Monitor couldn't start capturing keys. If you just enabled Accessibility, quit and relaunch the app. You can also open Accessibility settings to verify the checkbox is enabled.";
            [alert addButtonWithTitle:@"Open Settings"];
            [alert addButtonWithTitle:@"Close"];
            if ([alert runModal] == NSAlertFirstButtonReturn) {
                NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
                [[NSWorkspace sharedWorkspace] openURL:url];
            }
        });
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
    // Reset prose counters
    burstChars = 0;
    alphaChars = 0;
    spaceChars = 0;
    sentencePuncts = 0;
    letterMask = 0;
    distinctLetters = 0;
    burstStartTime = [NSDate date];
    logMessage("KeyboardMonitor: Counter reset");
}

- (int)currentConsecutiveChars {
    return consecutiveChars;
}

- (BOOL)warningDisplayed {
    return warningDisplayed;
}

#pragma mark - Private Methods

// Character classification helpers
- (BOOL)isLetter:(unichar)c {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}

- (BOOL)isDigit:(unichar)c {
    return (c >= '0' && c <= '9');
}

- (BOOL)isWhitespace:(unichar)c {
    return (c == ' ' || c == '\n' || c == '\r' || c == '\t');
}

- (BOOL)isSentencePunct:(unichar)c {
    return (c == '.' || c == '!' || c == '?');
}

- (BOOL)isProsePunct:(unichar)c {
    switch (c) {
        case ',': case ';': case ':': case '\'': case '"':
        case '-': case '(': case ')': case '[': case ']':
            return YES;
        default:
            return NO;
    }
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

    lastWarningTime = [NSDate date];
}

#pragma mark - Event Callback

// Static callback function for CGEventTap
static CGEventRef eventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    @autoreleasepool {
        KeyboardMonitor *monitor = (__bridge KeyboardMonitor *)refcon;

        // Handle tap disabled events by re-enabling
        if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
            if (monitor->eventTap) {
                CGEventTapEnable(monitor->eventTap, true);
                logMessage("KeyboardMonitor: Event tap re-enabled after %s",
                           (type == kCGEventTapDisabledByTimeout) ? "timeout" : "user input");
            }
            return event;
        }

        if (type == kCGEventKeyDown && monitor.isMonitoring) {
            [monitor handleKeyDown:event];
        }
    }

    // Pass event through to system
    return event;
}

// Handle key down events
- (void)handleKeyDown:(CGEventRef)event {
    // Custom inactivity handling: 5s burst boundary, 2.5s early reset for tiny bursts
    if (!lastKeyPressTime) lastKeyPressTime = [NSDate date];
    NSTimeInterval sinceLast = [[NSDate date] timeIntervalSinceDate:lastKeyPressTime];
    if (sinceLast >= 5.0) {
        [self resetCounter];
    } else if (sinceLast >= 2.5 && burstChars < 10) {
        [self resetCounter];
    }

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

    // Check if it's a letter (first char)
    BOOL isLetterKey = NO;
    if (actualLength > 0) {
        isLetterKey = [self isLetter:buffer[0]];
    }

    // Check for reset keys (navigation-like). Return/Tab are textual and should not reset.
    BOOL isResetKey = (keyCode == kVK_Escape);

    // Log keystroke info (optional for privacy)
    if (kLogKeystrokeDetails) {
        logMessage("KEY: code=%d, char='%s', isLetter=%s, mod=%s",
                  keyCode,
                  [charString UTF8String],
                  isLetterKey ? "YES" : "NO",
                  hasModifier ? "YES" : "NO");
    }

    // Treat Escape as a burst reset point
    if (isResetKey) {
        if (consecutiveChars > 0) {
            if (kLogKeystrokeDetails) {
                logMessage("RESET: Key %d ('%s') pressed - resetting from %d chars",
                          keyCode, [charString UTF8String], consecutiveChars);
            } else {
                logMessage("RESET: Escape pressed - resetting from %d chars",
                          consecutiveChars);
            }
            [self resetCounter];
        }
    }
    // Handle modifier key combinations
    else if (hasModifier) {
        logMessage("SHORTCUT: Count stays at %d", consecutiveChars);
    }
    else {
        // Prose-aware counting: include letters, digits, spaces, and common punctuation
        BOOL countedAny = NO;
        for (NSUInteger i = 0; i < [charString length]; i++) {
            unichar c = [charString characterAtIndex:i];
            if ([self isLetter:c]) {
                alphaChars++;
                burstChars++;
                // track diversity (case-insensitive)
                unichar lc = (c >= 'A' && c <= 'Z') ? (c - 'A' + 'a') : c;
                if (lc >= 'a' && lc <= 'z') {
                    uint32_t bit = 1u << (lc - 'a');
                    if ((letterMask & bit) == 0) {
                        letterMask |= bit;
                        distinctLetters++;
                    }
                }
                countedAny = YES;
            } else if ([self isDigit:c]) {
                burstChars++;
                countedAny = YES;
            } else if ([self isWhitespace:c]) {
                spaceChars++;
                burstChars++; // count whitespace toward overall prose length
                countedAny = YES;
            } else if ([self isSentencePunct:c] || [self isProsePunct:c]) {
                if ([self isSentencePunct:c]) {
                    sentencePuncts++;
                }
                burstChars++;
                countedAny = YES;
            } else {
                // Non-text key (e.g., arrows often come through as no unicode), ignore
            }
        }

        if (countedAny) {
            // Maintain legacy consecutiveChars for UI/log compatibility
            consecutiveChars = burstChars;

            // Keep a short buffer for optional debugging
            [recentChars appendString:charString];
            if ([recentChars length] > 200) {
                [recentChars deleteCharactersInRange:NSMakeRange(0, [recentChars length] - 200)];
            }

            // Compute sentence-level heuristics
            float alphaRatio = (burstChars > 0) ? ((float)alphaChars / (float)burstChars) : 0.0f;
            BOOL diversityOK = (distinctLetters >= 3) || (spaceChars >= 1) || (sentencePuncts >= 1);

            // Thresholds (lower bounds of the requested ranges)
            const int sentenceMin = 25;    // 25–40
            const int paragraphMin = 80;   // 80–100
            const double continuousMinSec = 60.0; // 60–90

            if (!burstStartTime) burstStartTime = [NSDate date];
            NSTimeInterval burstElapsed = [[NSDate date] timeIntervalSinceDate:burstStartTime];

            if (kLogKeystrokeDetails) {
                logMessage("PROSE: chars=%d, spaces=%d, sentences=%d, alpha=%.2f, distinct=%d, elapsed=%.1fs",
                           burstChars, spaceChars, sentencePuncts, alphaRatio, distinctLetters, burstElapsed);
            }

            // Cooldown after warnings (2 minutes)
            BOOL inCooldown = NO;
            if (lastWarningTime) {
                NSTimeInterval sinceWarn = [[NSDate date] timeIntervalSinceDate:lastWarningTime];
                inCooldown = (sinceWarn < 120.0);
            }

            BOOL sentenceTrigger = (burstChars >= sentenceMin && diversityOK);
            BOOL paragraphTrigger = (burstChars >= paragraphMin && diversityOK);
            BOOL continuousTrigger = (burstElapsed >= continuousMinSec);

            if (!warningDisplayed && (sentenceTrigger || paragraphTrigger || continuousTrigger)) {
                [self showWarning];
            } else if (inCooldown && (paragraphTrigger || continuousTrigger)) {
                // Optional escalation once per 30s while in cooldown
                BOOL canEscalate = YES;
                if (lastEscalationTime) {
                    NSTimeInterval sinceEsc = [[NSDate date] timeIntervalSinceDate:lastEscalationTime];
                    canEscalate = (sinceEsc >= 30.0);
                }
                if (canEscalate) {
                    lastEscalationTime = [NSDate date];
                    logMessage("ESCALATION: Continued typing detected (chars=%d, elapsed=%.0fs)", burstChars, burstElapsed);
                    if (_delegate && [_delegate respondsToSelector:@selector(keyboardMonitorDidDetectExcessiveTyping)]) {
                        [_delegate keyboardMonitorDidDetectExcessiveTyping];
                    }
                }
            }
        } else if (kLogKeystrokeDetails) {
            logMessage("NON-TEXT: Key %d ('%s') - not counted", keyCode, [charString UTF8String]);
        }
    }
}

@end
