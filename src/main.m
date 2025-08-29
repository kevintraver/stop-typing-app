#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>

// Global file handle for logging
FILE *logFile = NULL;

// Forward declarations
void logMessage(const char* format, ...);
void showNotification(NSString *title, NSString *message, BOOL playSound);

// Disable deprecation warnings for NSUserNotification APIs
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

// Define notification delegate
@interface NotificationDelegate : NSObject <NSUserNotificationCenterDelegate>
@end

@implementation NotificationDelegate
- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center 
    shouldPresentNotification:(NSUserNotification *)notification {
    // Always show notifications, even when app is in foreground
    return YES;
}
@end
#pragma clang diagnostic pop

// Application delegate to handle menu bar and app lifecycle
@interface AppDelegate : NSObject <NSApplicationDelegate>
{
    NSStatusItem *statusItem;
    NotificationDelegate *retainedNotificationDelegate; // Keep a strong reference
}
- (void)setupStatusItem;
- (void)quit:(id)sender;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    logMessage("AppDelegate: applicationDidFinishLaunching called");
    
    // Set up the status bar item
    [self setupStatusItem];
    
    // Set up NSUserNotificationCenter with retained delegate
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    retainedNotificationDelegate = [[NotificationDelegate alloc] init];
    NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
    [center setDelegate:retainedNotificationDelegate];
    #pragma clang diagnostic pop
    
    // Send a test notification after a short delay
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), 
                  dispatch_get_main_queue(), ^{
        showNotification(@"Keyboard Monitor Active", 
                     @"Monitoring keyboard input for excessive typing", 
                     NO);
    });
    
    logMessage("Application initialization complete");
}

- (void)setupStatusItem {
    logMessage("Setting up status bar item with text title only");
    
    // Create the status item with variable length for text
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    
    if (!statusItem) {
        logMessage("ERROR: Failed to create status item!");
        return;
    }
    
    // Create menu for the status item
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"Keyboard Monitor" action:nil keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit" action:@selector(quit:) keyEquivalent:@"q"];
    
    // Set the menu
    [statusItem setMenu:menu];
    
    // Try simple text title "KM" instead of emoji - using both modern and legacy methods
    NSString *plainTitle = @"KM";
    
    if (statusItem.button) {
        // Modern approach (macOS 10.14+)
        logMessage("Using modern button API for title");
        statusItem.button.title = plainTitle;
        
        // Make sure it's properly styled
        statusItem.button.font = [NSFont boldSystemFontOfSize:12.0];
    }
    
    // Also use the legacy approach as backup
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [statusItem setTitle:plainTitle];
    #pragma clang diagnostic pop
    
    logMessage("Status bar item configured with plain text title '%s'", [plainTitle UTF8String]);
}

- (void)quit:(id)sender {
    logMessage("Quit menu item selected");
    
    // Explicitly remove status item before quitting
    if (statusItem) {
        [[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
        statusItem = nil;
    }
    
    [NSApp terminate:self];
}

@end

// Typing monitoring settings
const int MAX_CONSECUTIVE_CHARS = 15;     // Warning after 15 consecutive characters
const int TYPING_COOLDOWN_MS = 3000;      // 3 seconds debounce period
BOOL showDebounceInfo = YES;              // Show detailed timing information

// Global tracking state
NSMutableString *recentChars;             // Buffer of recent characters
NSDate *lastKeyPressTime;                 // Last keypress timestamp
BOOL warningDisplayed = NO;               // Flag to prevent multiple warnings
int consecutiveChars = 0;                 // Count of consecutive characters typed

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

// Show a notification using classic NSUserNotification
void showNotification(NSString *title, NSString *message, BOOL playSound) {
    @autoreleasepool {
        // Disable deprecation warnings for NSUserNotification APIs
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        
        // Create notification
        NSUserNotification *notification = [[NSUserNotification alloc] init];
        notification.title = title;
        notification.informativeText = message;
        
        // Add sound if requested
        if (playSound) {
            notification.soundName = NSUserNotificationDefaultSoundName;
        } else {
            notification.soundName = nil; // No sound
        }
        
        // Add a timestamp
        notification.deliveryDate = [NSDate date];
        
        // Set a unique identifier
        notification.identifier = [NSString stringWithFormat:@"KeyboardMonitor-%lld", 
                                 (long long)[[NSDate date] timeIntervalSince1970]];
        
        // Try both notification methods
        NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
        [center deliverNotification:notification];
        
        // Also immediately schedule it
        [center scheduleNotification:notification];
        
        #pragma clang diagnostic pop
        
        logMessage("Notification delivered to NSUserNotificationCenter");
        
        // For extremely robust notification, also try AppleScript as fallback
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *escapedMessage = [message stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
            NSString *escapedTitle = [title stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
            NSString *scriptCommand = [NSString stringWithFormat:
                @"/usr/bin/osascript -e 'display notification \"%@\" with title \"%@\" without sound'",
                escapedMessage, escapedTitle];
            
            system([scriptCommand UTF8String]);
        });
    }
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
}

// Check if a character is a letter (A-Z, a-z)
BOOL isLetter(unichar c) {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}

// Callback function called for each keyboard event
CGEventRef eventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    @autoreleasepool {
        if (type == kCGEventKeyDown) {
            // Check for inactivity
            checkInactivityReset();
            
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
            
            // Check for reset keys
            BOOL isResetKey = (keyCode == kVK_Return || keyCode == kVK_Escape);
            
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
            
            // Handle letter keys - count them
            if (isLetterKey && !hasModifier) {
                // Increment counter
                consecutiveChars++;
                
                // Add to buffer
                [recentChars appendString:charString];
                
                // Calculate how many more characters until warning
                int remaining = MAX_CONSECUTIVE_CHARS - consecutiveChars;
                
                // Log counter with progress toward warning
                if (remaining > 0) {
                    logMessage("LETTER COUNT: %d/%d - Added: '%s' (%d more until warning)", 
                            consecutiveChars, MAX_CONSECUTIVE_CHARS, 
                            [charString UTF8String], remaining);
                } else {
                    logMessage("LETTER COUNT: %d/%d - Added: '%s' (OVER LIMIT)", 
                            consecutiveChars, MAX_CONSECUTIVE_CHARS, 
                            [charString UTF8String]);
                }
                
                // Check warning threshold
                if (consecutiveChars >= MAX_CONSECUTIVE_CHARS && !warningDisplayed) {
                    showWarning();
                }
            }
            // Handle reset keys
            else if (isResetKey) {
                if (consecutiveChars > 0) {
                    logMessage("RESET: Key %d ('%s') pressed - resetting from %d chars", 
                             keyCode, [charString UTF8String], consecutiveChars);
                    consecutiveChars = 0;
                    if (recentChars) {
                        [recentChars setString:@""];
                    }
                }
            }
            // Handle modifier key combinations
            else if (hasModifier) {
                logMessage("SHORTCUT: Key %d with modifiers - count stays at %d", 
                         keyCode, consecutiveChars);
            }
            // Other keys - just log
            else {
                logMessage("NON-LETTER: Key %d ('%s') - count stays at %d", 
                         keyCode, [charString UTF8String], consecutiveChars);
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
        
        // Set activation policy EARLY - critical for menu bar apps
        logMessage("Setting activation policy to Accessory (menu bar app)");
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        
        // ---- STEP 3: Set up app delegate ----
        logMessage("Creating and setting application delegate");
        AppDelegate *appDelegate = [[AppDelegate alloc] init];
        [NSApp setDelegate:appDelegate];
        
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
        
        // ---- STEP 5: Set up keyboard event monitoring ----
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
            logMessage("ERROR: Failed to create event tap - accessibility permissions required");
            
            // Show a helpful dialog to guide the user to enable accessibility permissions
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Accessibility Permission Required"];
            [alert setInformativeText:@"KeyboardMonitor needs accessibility permissions to monitor keyboard input.\n\n"
                                      "1. Click 'Open Privacy Settings'\n"
                                      "2. Click the lock icon and enter your password\n"
                                      "3. Click the '+' button under the app list\n" 
                                      "4. Navigate to this location and select the app:\n"
                                      "   /Users/kevin/Code/macos_keylogger/build/KeyboardMonitor.app\n"
                                      "5. Check the box next to KeyboardMonitor\n"
                                      "6. Restart the app"];
            [alert setAlertStyle:NSAlertStyleWarning];
            
            // Add buttons
            [alert addButtonWithTitle:@"Open Privacy Settings"];
            [alert addButtonWithTitle:@"Quit"];
            
            NSModalResponse response = [alert runModal];
            
            if (response == NSAlertFirstButtonReturn) {
                // Open System Preferences to the Accessibility pane
                NSURL *prefsURL = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
                [[NSWorkspace sharedWorkspace] openURL:prefsURL];
                
                // Also open the Finder to show where the app is
                [[NSWorkspace sharedWorkspace] selectFile:
                  [NSString stringWithFormat:@"%@/Code/macos_keylogger/build/KeyboardMonitor.app", 
                   NSHomeDirectory()] 
                                  inFileViewerRootedAtPath:@""];
            }
            
            // Quit the app
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
        
        // ---- STEP 6: Start the application ----
        // This call blocks until app termination
        [NSApp run];
        
        // ---- STEP 7: Clean up (runs on app termination) ----
        logMessage("Application terminating - cleaning up resources");
        CFRelease(runLoopSource);
        CFRelease(eventTap);
        fclose(logFile);
    }
    return 0;
}