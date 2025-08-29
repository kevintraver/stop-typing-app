#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
#import <UserNotifications/UserNotifications.h>
#import "PermissionsManager.h"
#import "Notifications.h"

// Global file handle for logging
FILE *logFile = NULL;

// Forward declarations
void logMessage(const char* format, ...);
void showNotification(NSString *title, NSString *message, BOOL playSound);

// Modern notification delegate using UserNotifications framework
@interface NotificationDelegate : NSObject <UNUserNotificationCenterDelegate>
@end

@implementation NotificationDelegate
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler {
    // Show notifications even when app is in foreground
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void(^)(void))completionHandler {
    completionHandler();
}
@end

// Import the AppDelegate from AppDelegate.h
#import "AppDelegate.h"

// Typing monitoring settings
const int MAX_CONSECUTIVE_CHARS = 15;     // Warning after 15 consecutive characters
const int TYPING_COOLDOWN_MS = 3000;      // 3 seconds debounce period
BOOL showDebounceInfo = YES;              // Show detailed timing information

// Global tracking state (used by event callback)
NSMutableString *recentChars;             // Buffer of recent characters
NSDate *lastKeyPressTime;                 // Last keypress timestamp
BOOL warningDisplayed = NO;               // Flag to prevent multiple warnings
int consecutiveChars = 0;                 // Legacy counter (mirrors burstChars)

// Prose-aware counters (reset on inactivity)
int burstChars = 0;       // printable, prose-like chars in current burst
int alphaChars = 0;       // letters counted in current burst
int spaceChars = 0;       // spaces/newlines in current burst
int sentencePuncts = 0;   // '.', '!', '?'
uint32_t letterMask = 0;  // distinct letters bitmask (a-z)
int distinctLetters = 0;  // number of distinct letters
NSDate *burstStartTime;   // start time of current burst
NSDate *lastEscalationTime; // pacing for escalations
NSDate *lastWarningTime;  // cooldown reference

// Global file handle for logging (used by AppDelegate) - declared at top of file

// Function to get current time formatted as a string
NSString* getCurrentTimeString() {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    return [dateFormatter stringFromDate:[NSDate date]];
}

// Function to log messages to both file and standard output
void logMessage(const char* format, ...) {
    // Get current timestamp
    NSString *timestamp = getCurrentTimeString();
    
    // Format the message
    va_list args, args_copy;
    va_start(args, format);
    va_copy(args_copy, args);
    
    // First write to the log file if available
    if (logFile) {
        fprintf(logFile, "[%s] ", [timestamp UTF8String]);
        vfprintf(logFile, format, args);
        fprintf(logFile, "\n");
        fflush(logFile);
    }
    
    // Now write to standard output
    printf("[%s] ", [timestamp UTF8String]);
    vprintf(format, args_copy);
    printf("\n");
    fflush(stdout);
    
    va_end(args);
    va_end(args_copy);
}

// Show a notification using modern UserNotifications framework
void showNotification(NSString *title, NSString *message, BOOL playSound) {
    // Prefer attaching a custom icon if available
    NotifyWithIcon(title, message, playSound, @"keyboard-off");
    logMessage("Notification delivered via UserNotifications framework (icon: keyboard-off)");
}

// Reset all tracking state
void resetTracking() {
    if (!recentChars) {
        recentChars = [[NSMutableString alloc] init];
    }
    
    consecutiveChars = 0;
    warningDisplayed = NO;
    lastKeyPressTime = [NSDate date];
    [recentChars setString:@""];
    // Reset prose-aware counters
    burstChars = 0;
    alphaChars = 0;
    spaceChars = 0;
    sentencePuncts = 0;
    letterMask = 0;
    distinctLetters = 0;
    burstStartTime = [NSDate date];
    logMessage("Tracking state reset");
}

// Check for inactivity timeout
void checkInactivityReset() {
    if (!lastKeyPressTime) {
        lastKeyPressTime = [NSDate date];
        return;
    }
    
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:lastKeyPressTime];
    double seconds = elapsed;
    
    // Show detailed timing if enabled
    if (showDebounceInfo && consecutiveChars > 0) {
        float cooldownThreshold = TYPING_COOLDOWN_MS/1000.0;
        float timeRemaining = cooldownThreshold - seconds;
        
        if (timeRemaining > 0) {
            logMessage("COOLDOWN: %.1f seconds elapsed, %.1f seconds remaining before reset",
                     seconds, timeRemaining);
        }
    }
    
    if (seconds > TYPING_COOLDOWN_MS/1000.0) {
        // Only log if we had activity to reset
        if (consecutiveChars > 0) {
            logMessage("COOLDOWN TRIGGERED: %.1f seconds of inactivity - resetting counter from %d", 
                     seconds, consecutiveChars);
            resetTracking();
        }
        
        // Clear warning after the same cooldown time (more aggressive)
        if (seconds > TYPING_COOLDOWN_MS/1000.0) {
            if (warningDisplayed) {
                logMessage("WARNING CLEARED: %.1f seconds of inactivity", seconds);
                warningDisplayed = NO;
            }
        }
    }
}

// Show warning when threshold is reached
void showWarning() {
    if (warningDisplayed) return;
    
    warningDisplayed = YES;
    
    // Make the warning visible in console
    logMessage("");
    logMessage("⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️");
    logMessage("⚠️           W A R N I N G                    ⚠️");
    logMessage("⚠️  YOU'RE TYPING A LOT!                    ⚠️");
    
    if (recentChars) {
        logMessage("⚠️  RECENT KEYS: %s", [recentChars UTF8String]);
    }
    
    logMessage("⚠️  TRY USING SUPER WHISPER INSTEAD         ⚠️");
    logMessage("⚠️  Warning will clear after %d sec of inactivity  ⚠️", TYPING_COOLDOWN_MS/1000);
    logMessage("⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️ ⚠️");
    logMessage("");
    
    // Prepare notification message
    NSString *title = @"⚠️ Typing Warning";
    NSString *message = @"You're typing a lot. Try using Super Whisper instead!";
    
    // Show system notification - no sound
    showNotification(title, message, NO);
    lastWarningTime = [NSDate date];
}

// Check if a character is a letter (A-Z, a-z)
BOOL isLetter(unichar c) {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}

BOOL isDigit(unichar c) {
    return (c >= '0' && c <= '9');
}

BOOL isWhitespace(unichar c) {
    return (c == ' ' || c == '\n' || c == '\r' || c == '\t');
}

BOOL isSentencePunct(unichar c) {
    return (c == '.' || c == '!' || c == '?');
}

BOOL isProsePunct(unichar c) {
    switch (c) {
        case ',': case ';': case ':': case '\'': case '"':
        case '-': case '(': case ')': case '[': case ']':
            return YES;
        default:
            return NO;
    }
}

// Callback function called for each keyboard event
CGEventRef eventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    @autoreleasepool {
        if (type == kCGEventKeyDown) {
            // Custom inactivity handling to set burst boundaries
            if (!lastKeyPressTime) lastKeyPressTime = [NSDate date];
            NSTimeInterval sinceLast = [[NSDate date] timeIntervalSinceDate:lastKeyPressTime];
            if (sinceLast >= 5.0) {
                resetTracking();
            } else if (sinceLast >= 2.5 && burstChars < 10) {
                resetTracking();
            }
            
            // Update typing tracking timestamp
            lastKeyPressTime = [NSDate date];
            
            // Get the actual Unicode character
            UniChar buffer[4];
            UniCharCount actualLength = 0;
            CGEventKeyboardGetUnicodeString(event, 4, &actualLength, buffer);
            
            // Skip if no character
            if (actualLength == 0) {
                return event;
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
                isLetterKey = isLetter(buffer[0]);
            }
            
            // Check for reset keys (Escape only). Return/Tab count as textual.
            BOOL isResetKey = (keyCode == kVK_Escape);
            
            // Log keystroke info
            logMessage("KEY: code=%d, char='%s', isLetter=%s, mod=%s", 
                     keyCode, 
                     [charString UTF8String],
                     isLetterKey ? "YES" : "NO",
                     hasModifier ? "YES" : "NO");
            
            // Make sure recentChars is initialized
            if (!recentChars) {
                recentChars = [[NSMutableString alloc] init];
            }
            
            // Treat Escape as burst reset point
            if (isResetKey) {
                if (consecutiveChars > 0) {
                    logMessage("RESET: Key %d ('%s') pressed - resetting from %d chars", 
                             keyCode, [charString UTF8String], consecutiveChars);
                    resetTracking();
                }
            }
            // Handle modifier key combinations
            else if (hasModifier) {
                logMessage("SHORTCUT: Key %d with modifiers - count stays at %d", 
                         keyCode, consecutiveChars);
            }
            // Prose-aware counting for text-like input (letters/digits/space/punct)
            else {
                BOOL countedAny = NO;
                for (NSUInteger i = 0; i < [charString length]; i++) {
                    unichar c = [charString characterAtIndex:i];
                    if (isLetter(c)) {
                        alphaChars++;
                        burstChars++;
                        // track distinct letters (case-insensitive)
                        unichar lc = (c >= 'A' && c <= 'Z') ? (c - 'A' + 'a') : c;
                        if (lc >= 'a' && lc <= 'z') {
                            uint32_t bit = 1u << (lc - 'a');
                            if ((letterMask & bit) == 0) {
                                letterMask |= bit;
                                distinctLetters++;
                            }
                        }
                        countedAny = YES;
                    } else if (isDigit(c)) {
                        burstChars++;
                        countedAny = YES;
                    } else if (isWhitespace(c)) {
                        spaceChars++;
                        burstChars++;
                        countedAny = YES;
                    } else if (isSentencePunct(c) || isProsePunct(c)) {
                        if (isSentencePunct(c)) {
                            sentencePuncts++;
                        }
                        burstChars++;
                        countedAny = YES;
                    } else {
                        // Not a textual char -> ignore
                    }
                }

                if (countedAny) {
                    consecutiveChars = burstChars; // maintain legacy counter semantics
                    [recentChars appendString:charString];
                    if ([recentChars length] > 200) {
                        [recentChars deleteCharactersInRange:NSMakeRange(0, [recentChars length] - 200)];
                    }

                    float alphaRatio = (burstChars > 0) ? ((float)alphaChars / (float)burstChars) : 0.0f;
                    BOOL diversityOK = (distinctLetters >= 3) || (spaceChars >= 1) || (sentencePuncts >= 1);

                    if (!burstStartTime) burstStartTime = [NSDate date];
                    NSTimeInterval burstElapsed = [[NSDate date] timeIntervalSinceDate:burstStartTime];

                    const int sentenceMin = 25;     // 25–40
                    const int paragraphMin = 80;    // 80–100
                    const double continuousMinSec = 60.0; // 60–90

                    BOOL inCooldown = NO;
                    if (lastWarningTime) {
                        NSTimeInterval sinceWarn = [[NSDate date] timeIntervalSinceDate:lastWarningTime];
                        inCooldown = (sinceWarn < 120.0);
                    }

                    BOOL sentenceTrigger = (burstChars >= sentenceMin && diversityOK);
                    BOOL paragraphTrigger = (burstChars >= paragraphMin && diversityOK);
                    BOOL continuousTrigger = (burstElapsed >= continuousMinSec);

                    if (showDebounceInfo) {
                        logMessage("PROSE: chars=%d, spaces=%d, sentences=%d, alpha=%.2f, distinct=%d, elapsed=%.1fs",
                                   burstChars, spaceChars, sentencePuncts, alphaRatio, distinctLetters, burstElapsed);
                    }

                    if (!warningDisplayed && (sentenceTrigger || paragraphTrigger || continuousTrigger)) {
                        showWarning();
                    } else if (inCooldown && (paragraphTrigger || continuousTrigger)) {
                        BOOL canEscalate = YES;
                        if (lastEscalationTime) {
                            NSTimeInterval sinceEsc = [[NSDate date] timeIntervalSinceDate:lastEscalationTime];
                            canEscalate = (sinceEsc >= 30.0);
                        }
                        if (canEscalate) {
                            lastEscalationTime = [NSDate date];
                            logMessage("ESCALATION: Continued typing detected (chars=%d, elapsed=%.0fs)", burstChars, burstElapsed);
                            showNotification(@"⚠️ Typing Warning", @"Seriously — switch to voice.", NO);
                        }
                    }
                } else {
                    logMessage("NON-TEXT: Key %d ('%s') - not counted", keyCode, [charString UTF8String]);
                }
            }
        }
    }
    
    // Pass event through to system
    return event;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // ---- STEP 1: Initialize logging ----
        NSString *logPath = [NSString stringWithFormat:@"%@/keylog.txt", NSHomeDirectory()];
        logFile = fopen([logPath UTF8String], "a");

        if (!logFile) {
            NSLog(@"Failed to open log file at %@", logPath);
            printf("Failed to open log file at %s\n", [logPath UTF8String]);
            return 1;
        }

        logMessage("==============================================");
        logMessage("                 KEYBOARD MONITOR");
        logMessage("==============================================");
        logMessage("App starting up...");

        // ---- STEP 2: Initialize application ----
        logMessage("Creating NSApplication instance");
        [NSApplication sharedApplication];

        // For menu bar apps, we need to transform the process
        // This is an essential step for menu bar apps on modern macOS
        logMessage("Transforming to UI Element Application (critical for menu bar)");
        ProcessSerialNumber psn = { 0, kCurrentProcess };
        OSStatus err = TransformProcessType(&psn, kProcessTransformToUIElementApplication);
        if (err != noErr) {
            logMessage("WARNING: Failed to transform process: Error %d", (int)err);
        }

        // Start as regular app for notification registration
        logMessage("Setting activation policy to Regular (needed for notifications)");
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        // ---- STEP 3: Set up app delegate ----
        logMessage("Creating and setting application delegate");
        AppDelegate *appDelegate = [[AppDelegate alloc] init];
        [NSApp setDelegate:appDelegate];

        // ---- STEP 3.5: Switch to accessory mode after initialization ----
        logMessage("Will switch to accessory mode after notification setup");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            logMessage("Switching to accessory mode to hide from dock");
            [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        });

        // ---- STEP 3.5: Create a hidden window to help with notification registration ----
        logMessage("Creating hidden window for notification registration");
        NSWindow *hiddenWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1, 1)
                                                             styleMask:NSWindowStyleMaskBorderless
                                                               backing:NSBackingStoreBuffered
                                                                 defer:NO];
        [hiddenWindow setReleasedWhenClosed:NO];
        [hiddenWindow orderOut:nil]; // Hide the window
        logMessage("Hidden window created and hidden");

        // ---- STEP 4: Initialize tracking state ----
        logMessage("Initializing typing tracking state");
        recentChars = [[NSMutableString alloc] init];
        lastKeyPressTime = [NSDate date];
        consecutiveChars = 0;
        warningDisplayed = NO;
        
        // Log configuration
        logMessage("⚠️  WARNING AFTER: %d consecutive letter keys", MAX_CONSECUTIVE_CHARS);
        logMessage("🔄  COUNTER RESETS: After %d seconds of inactivity", TYPING_COOLDOWN_MS/1000);
        logMessage("💬  SUGGESTION: Use Super Whisper instead of typing");
        logMessage("📝  LOG LOCATION: %s", [logPath UTF8String]);
        logMessage("==============================================");
        
        // ---- STEP 5: Ensure accessibility permissions ----
        logMessage("Checking accessibility permissions...");

        // Use the permissions manager to ensure accessibility is enabled
        [[PermissionsManager shared] ensureAccessibilityPromptOnce];

        // Wait a moment for the user to potentially grant permissions
        [NSThread sleepForTimeInterval:1.0];

        // Check if we have accessibility permissions
        if (!AXIsProcessTrusted()) {
            logMessage("ERROR: Accessibility permissions not granted");

            // Show a helpful dialog to guide the user
            dispatch_async(dispatch_get_main_queue(), ^{
                NSAlert *alert = [[NSAlert alloc] init];
                [alert setMessageText:@"Accessibility Permission Required"];
                [alert setInformativeText:@"StopTyping needs accessibility permissions to monitor keyboard input.\n\n"
                                           "Please enable accessibility permissions in System Settings → Privacy & Security → Accessibility, then restart the app."];
                [alert setAlertStyle:NSAlertStyleWarning];

                [alert addButtonWithTitle:@"Open Accessibility Settings"];
                [alert addButtonWithTitle:@"Quit"];

                NSModalResponse response = [alert runModal];

                if (response == NSAlertFirstButtonReturn) {
                    [[PermissionsManager shared] openAccessibilitySettings];
                }
            });

            // Quit the app
            fclose(logFile);
            return 1;
        }

        logMessage("Accessibility permissions granted - setting up keyboard monitoring...");

        // ---- STEP 6: Set up keyboard event monitoring ----
        logMessage("Setting up keyboard event monitoring...");

        // Create an event tap to monitor keyboard events
        CFMachPortRef eventTap = CGEventTapCreate(
            kCGSessionEventTap,        // Tap at session level
            kCGHeadInsertEventTap,     // Insert at start of event chain
            kCGEventTapOptionDefault,  // Default options
            CGEventMaskBit(kCGEventKeyDown), // Only monitor key down events
            eventCallback,             // Callback function
            NULL                       // User data
        );

        if (!eventTap) {
            logMessage("ERROR: Failed to create event tap - this should not happen if accessibility is granted");

            // Show error dialog
            dispatch_async(dispatch_get_main_queue(), ^{
                NSAlert *alert = [[NSAlert alloc] init];
                [alert setMessageText:@"Event Tap Creation Failed"];
                [alert setInformativeText:@"Failed to create keyboard event tap. This may be due to insufficient permissions or system restrictions."];
                [alert setAlertStyle:NSAlertStyleCritical];
                [alert addButtonWithTitle:@"Quit"];
                [alert runModal];
            });

            fclose(logFile);
            return 1;
        }
        
        // Create a run loop source from the event tap
        CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(
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
        
        logMessage("Keyboard event monitoring successfully set up");
        logMessage("Starting application run loop - menu bar icon should appear");

        // ---- STEP 7: Start the application ----
        // This call blocks until app termination
        [NSApp run];

        // ---- STEP 8: Clean up (runs on app termination) ----
        logMessage("Application terminating - cleaning up resources");
        CFRelease(runLoopSource);
        CFRelease(eventTap);
        fclose(logFile);
    }
    return 0;
}
