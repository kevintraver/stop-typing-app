#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import "AppDelegate.h"
#import "Notifications.h"

// Global file handle for logging
FILE *logFile = NULL;

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

// (Notifications are handled via Notifications.h / UNUserNotificationCenter)

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

        // Do NOT force-transform the process to UIElement here.
        // Rely on Info.plist (LSUIElement) and allow PermissionsManager
        // to temporarily switch activation policy for permission prompts.
        logMessage("Skipping Carbon UIElement transform to allow permission prompts");

        // ---- STEP 3: Set up app delegate ----
        logMessage("Creating and setting application delegate");
        AppDelegate *appDelegate = [[AppDelegate alloc] init];
        [NSApp setDelegate:appDelegate];

        // Log configuration
        logMessage("⚠️  WARNING AFTER: 15 consecutive letter keys");
        logMessage("🔄  COUNTER RESETS: After 3 seconds of inactivity");
        logMessage("💬  SUGGESTION: Use Super Whisper instead of typing");
        logMessage("📝  LOG LOCATION: %s", [logPath UTF8String]);
        logMessage("==============================================");

        // ---- STEP 4: Start the application ----
        // This call blocks until app termination
        [NSApp run];

        // ---- STEP 5: Clean up (runs on app termination) ----
        logMessage("Application terminating - cleaning up resources");
        fclose(logFile);
    }
    return 0;
}
