#import "AppDelegate.h"

// Global file handle for logging (declared in main.m)
extern FILE *logFile;

// Forward declarations
void logMessage(const char* format, ...);
#import <UserNotifications/UserNotifications.h>
#import "Notifications.h"
#import "Accessibility.h"
#import "PermissionsManager.h"

@interface AppDelegate () {
    NSMenuItem *toggleMenuItem;
    NSMenuItem *statusMenuItem;
    NSTimer *axPollTimer;
}
@end

@implementation AppDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _isMonitoringEnabled = YES; // Start enabled by default
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    logMessage("AppDelegate: applicationDidFinishLaunching called");

    // Debug bundle context
    NSBundle *bundle = [NSBundle mainBundle];
    logMessage("Bundle URL: %s", [[[bundle bundleURL] absoluteString] UTF8String]);
    logMessage("Bundle Identifier: %s", [[bundle bundleIdentifier] UTF8String]);

    // Set up the status bar item
    [self setupStatusItem];

    // Prepare permissions at launch (notifications)
    [[PermissionsManager shared] setupAtLaunch];

    // Ensure Accessibility trust (will prompt if not granted)
    EnsureAccessibilityTrust();

    // Initialize keyboard monitor
    _keyboardMonitor = [[KeyboardMonitor alloc] init];
    _keyboardMonitor.delegate = self;

    // Start monitoring only when Accessibility is trusted
    if (_isMonitoringEnabled && [[PermissionsManager shared] isAccessibilityTrusted]) {
        [_keyboardMonitor startMonitoring];
    } else if (_isMonitoringEnabled && ![[PermissionsManager shared] isAccessibilityTrusted]) {
        logMessage("Waiting for Accessibility permission...");
        axPollTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
            if ([[PermissionsManager shared] isAccessibilityTrusted]) {
                [timer invalidate];
                logMessage("Accessibility granted. Starting monitoring.");
                [_keyboardMonitor startMonitoring];
                Notify(@"Monitoring Enabled", @"Accessibility granted; keyboard monitoring is now active", NO);
                [self updateStatusItemAppearance];
            }
        }];
        [[PermissionsManager shared] ensureAccessibilityPromptOnce];
    }

    // Send a test notification after a short delay to register with macOS
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                  dispatch_get_main_queue(), ^{
        NSString *statusMessage = _isMonitoringEnabled ? @"Monitoring keyboard input for excessive typing" : @"Keyboard monitoring is disabled";
        Notify(@"Keyboard Monitor Active", statusMessage, YES); // Enable sound to make it more noticeable
    });

    logMessage("Application initialization complete");
}

- (void)setupStatusItem {
    logMessage("Setting up status bar item with toggle functionality");

    // Get the system status bar
    NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
    if (!statusBar) {
        logMessage("ERROR: Failed to get system status bar!");
        return;
    }
    logMessage("System status bar obtained: %@", statusBar);

    // Create the status item with variable length for text
    _statusItem = [statusBar statusItemWithLength:NSVariableStatusItemLength];

    if (!_statusItem) {
        logMessage("ERROR: Failed to create status item!");
        return;
    }
    logMessage("Status item created successfully: %@", _statusItem);

    // Create menu for the status item
    NSMenu *menu = [[NSMenu alloc] init];

    // Status indicator item
    statusMenuItem = [[NSMenuItem alloc] initWithTitle:@"Status: Monitoring"
                                                action:nil
                                         keyEquivalent:@""];
    [statusMenuItem setEnabled:NO];
    [menu addItem:statusMenuItem];
    [menu addItem:[NSMenuItem separatorItem]];

    // Toggle monitoring item
    toggleMenuItem = [[NSMenuItem alloc] initWithTitle:@"Disable Monitoring"
                                                action:@selector(toggleMonitoring:)
                                         keyEquivalent:@""];
    [menu addItem:toggleMenuItem];
    [menu addItem:[NSMenuItem separatorItem]];

    // Test notification
    [menu addItemWithTitle:@"Send Test Notification" action:@selector(sendTestNotification:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Check Notification Status" action:@selector(checkNotificationStatus:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Request Notification Permission" action:@selector(requestNotificationPermission:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Check App Bundle Status" action:@selector(checkAppBundleStatus:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Force Register with macOS" action:@selector(forceRegisterWithMacOS:) keyEquivalent:@""];

    // Permissions helpers
    [menu addItemWithTitle:@"Open Accessibility Settings" action:@selector(openAccessibilitySettings:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Open Notification Settings" action:@selector(openNotificationSettings:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];

    // Quit item
    [menu addItemWithTitle:@"Quit" action:@selector(quit:) keyEquivalent:@"q"];

    // Set the menu
    [_statusItem setMenu:menu];

    // Set the status bar icon/title
    [self updateStatusItemAppearance];

    logMessage("Status bar item configured with toggle functionality");
}

- (void)openAccessibilitySettings:(id)sender {
    [[PermissionsManager shared] openAccessibilitySettings];
}

- (void)openNotificationSettings:(id)sender {
    [[PermissionsManager shared] openNotificationSettings];
}

- (void)sendTestNotification:(id)sender {
    Notify(@"Test", @"This is a test notification", NO);
}

- (void)checkNotificationStatus:(id)sender {
    [[PermissionsManager shared] checkNotificationStatusAndReport];
}

- (void)requestNotificationPermission:(id)sender {
    logMessage("Manually requesting notification permission");

    // First check if we're in an app bundle
    NSBundle *bundle = [NSBundle mainBundle];
    if (!bundle || ![bundle bundleIdentifier] || ![[bundle bundlePath] containsString:@".app"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSAlert *alert = [[NSAlert alloc] init];
            alert.alertStyle = NSAlertStyleWarning;
            alert.messageText = @"Bundle Issue";
            alert.informativeText = @"App must be run from .app bundle for notifications to work.\n\nDouble-click KeyboardMonitor.app instead of running the executable directly.";
            [alert addButtonWithTitle:@"OK"];
            [alert runModal];
        });
        return;
    }

    // Force re-request authorization
    NotificationsRequestAuthorization();

    // Also try to manually trigger the system dialog
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                  dispatch_get_main_queue(), ^{
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        UNAuthorizationOptions options = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;

        [center requestAuthorizationWithOptions:options
                              completionHandler:^(BOOL granted, NSError * _Nullable error) {
            logMessage("Manual authorization request: granted=%@ error=%@", granted ? @"YES" : @"NO", error);
        }];
    });
}

- (void)checkAppBundleStatus:(id)sender {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bundlePath = [bundle bundlePath];
    NSString *bundleId = [bundle bundleIdentifier];
    NSString *executablePath = [[NSProcessInfo processInfo] arguments][0];
    BOOL isInAppBundle = [bundlePath containsString:@".app"];

    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleInformational;
        alert.messageText = @"App Bundle Status";
        alert.informativeText = [NSString stringWithFormat:@"Bundle Path: %@\nBundle ID: %@\nExecutable: %@\nIn App Bundle: %@\n\nFor notifications to work, 'In App Bundle' must be YES.",
                                bundlePath, bundleId, executablePath, isInAppBundle ? @"YES" : @"NO"];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    });
}

- (void)forceRegisterWithMacOS:(id)sender {
    logMessage("Forcing registration with macOS by sending multiple notifications");

    // Send a series of notifications to ensure macOS recognizes the app
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                  dispatch_get_main_queue(), ^{
        Notify(@"Registration 1", @"This notification helps register the app with macOS", YES);
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                  dispatch_get_main_queue(), ^{
        Notify(@"Registration 2", @"Multiple notifications ensure proper registration", YES);
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                  dispatch_get_main_queue(), ^{
        Notify(@"Registration Complete", @"App should now appear in System Settings → Notifications", YES);
    });
}

- (void)updateStatusItemAppearance {
    if (_isMonitoringEnabled) {
        // Use simple text "KM" when monitoring
        NSString *title = @"KM";

    if (_statusItem.button) {
        // Modern approach (macOS 10.14+)
        logMessage("Setting button title to: %s", [title UTF8String]);
        _statusItem.button.title = title;
        _statusItem.button.font = [NSFont boldSystemFontOfSize:12.0];
        logMessage("Button title set successfully");
    } else {
        logMessage("WARNING: Status item has no button, using legacy API");
    }

        // Also use the legacy approach as backup
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [_statusItem setTitle:title];
        #pragma clang diagnostic pop

        // Update menu items
        [statusMenuItem setTitle:@"Status: Monitoring"];
        [toggleMenuItem setTitle:@"Disable Monitoring"];
    } else {
        // Use different text when disabled
        NSString *title = @"KM⏸";

        if (_statusItem.button) {
            // Modern approach (macOS 10.14+)
            _statusItem.button.title = title;
            _statusItem.button.font = [NSFont systemFontOfSize:12.0]; // Not bold when disabled
    }

    // Also use the legacy approach as backup
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    logMessage("Setting legacy title to: %s", [title UTF8String]);
    [_statusItem setTitle:title];
    #pragma clang diagnostic pop
    logMessage("Legacy title set successfully");

    // Update menu items
        [statusMenuItem setTitle:@"Status: Disabled"];
        [toggleMenuItem setTitle:@"Enable Monitoring"];
    }
}

- (void)toggleMonitoring:(id)sender {
    _isMonitoringEnabled = !_isMonitoringEnabled;

    if (_isMonitoringEnabled) {
        logMessage("Enabling keyboard monitoring");
        [_keyboardMonitor startMonitoring];
        Notify(@"Monitoring Enabled", @"Keyboard monitoring is now active", NO);
    } else {
        logMessage("Disabling keyboard monitoring");
        [_keyboardMonitor stopMonitoring];
        Notify(@"Monitoring Disabled", @"Keyboard monitoring has been disabled", NO);
    }

    [self updateStatusItemAppearance];
}

- (void)quit:(id)sender {
    logMessage("Quit menu item selected");

    // Stop monitoring before quitting
    if (_keyboardMonitor) {
        [_keyboardMonitor stopMonitoring];
    }

    // Explicitly remove status item before quitting
    if (_statusItem) {
        [[NSStatusBar systemStatusBar] removeStatusItem:_statusItem];
        _statusItem = nil;
    }

    [NSApp terminate:self];
}

#pragma mark - KeyboardMonitorDelegate

- (void)keyboardMonitorDidDetectExcessiveTyping {
    // Show system notification when excessive typing is detected
    NSString *title = @"⚠️ Typing Warning";
    NSString *message = @"You're typing a lot. Try using Super Whisper instead!";
    Notify(title, message, NO);
}

@end
