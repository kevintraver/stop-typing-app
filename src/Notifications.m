#import "Notifications.h"
#import <UserNotifications/UserNotifications.h>
#import <Cocoa/Cocoa.h>

@interface NotificationsDelegate : NSObject <UNUserNotificationCenterDelegate>
@end

@implementation NotificationsDelegate
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler {
    // Ensure banner shows even if app is foreground/accessory
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound | UNNotificationPresentationOptionList);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler {
    completionHandler();
}
@end

static BOOL RunningInAppBundle(void) {
    NSBundle *bundle = [NSBundle mainBundle];
    if (!bundle) return NO;

    // Check bundle identifier first
    NSString *bid = [bundle bundleIdentifier];
    if (bid.length == 0) return NO;

    // Check if we're in an app bundle by examining the path
    NSString *bundlePath = [bundle bundlePath];
    if (!bundlePath) return NO;

    // Check for .app extension
    if ([[bundlePath pathExtension] isEqualToString:@"app"]) {
        return YES;
    }

    // Also check if the executable path contains .app
    NSString *executablePath = [[NSProcessInfo processInfo] arguments][0];
    if ([executablePath containsString:@".app"]) {
        return YES;
    }

    // For development builds, also check if we're in a Contents/MacOS directory
    if ([bundlePath containsString:@"Contents/MacOS"]) {
        return YES;
    }

    // If we get here, we're likely running as a standalone executable
    // UNUserNotificationCenter won't work, but we can still log the issue
    NSLog(@"Notifications: Not running in app bundle - bundlePath: %@", bundlePath);
    return NO;
}

static BOOL notificationsAuthorized = NO;
static NotificationsDelegate *notificationsDelegate = nil;

void NotificationsRequestAuthorization(void) {
    NSLog(@"Notifications: requestAuthorization called");

    // Check bundle info
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bundlePath = [bundle bundlePath];
    NSString *bundleId = [bundle bundleIdentifier];
    NSString *executablePath = [[NSProcessInfo processInfo] arguments][0];
    NSString *appName = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
    NSLog(@"Notifications: bundlePath=%@", bundlePath);
    NSLog(@"Notifications: bundleId=%@", bundleId);
    NSLog(@"Notifications: executablePath=%@", executablePath);
    NSLog(@"Notifications: appName=%@", appName);
    NSLog(@"Notifications: RunningInAppBundle()=%@", RunningInAppBundle() ? @"YES" : @"NO");

    // Check if we're a UI element
    NSNumber *isUIElement = [bundle objectForInfoDictionaryKey:@"LSUIElement"];
    NSLog(@"Notifications: LSUIElement=%@", isUIElement ? ([isUIElement boolValue] ? @"YES" : @"NO") : @"not set");

    if (!RunningInAppBundle()) {
        // UNUserNotificationCenter requires a proper app bundle context.
        NSLog(@"Notifications: not running in app bundle, skipping");
        dispatch_async(dispatch_get_main_queue(), ^{
            NSAlert *alert = [[NSAlert alloc] init];
            alert.alertStyle = NSAlertStyleWarning;
            alert.messageText = @"Bundle Issue";
            alert.informativeText = [NSString stringWithFormat:@"App not running from proper bundle.\nBundle Path: %@\nExecutable: %@", bundlePath, executablePath];
            [alert addButtonWithTitle:@"OK"];
            [alert runModal];
        });
        return;
    }

    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];

    // Install delegate early so foreground notifications present
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        notificationsDelegate = [[NotificationsDelegate alloc] init];
        center.delegate = notificationsDelegate;
        NSLog(@"Notifications: delegate installed successfully");
    });

    // Check current authorization status first
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
        UNAuthorizationStatus status = settings.authorizationStatus;
        NSLog(@"Notifications: current authorization status: %ld", (long)status);

        if (status == UNAuthorizationStatusAuthorized
#ifdef UNAuthorizationStatusProvisional
            || status == UNAuthorizationStatusProvisional
#endif
            ) {
            notificationsAuthorized = YES;
            NSLog(@"Notifications: already authorized");
            return;
        }

        if (status == UNAuthorizationStatusDenied) {
            notificationsAuthorized = NO;
            NSLog(@"Notifications: authorization denied by user");
            dispatch_async(dispatch_get_main_queue(), ^{
                NSAlert *alert = [[NSAlert alloc] init];
                alert.alertStyle = NSAlertStyleInformational;
                alert.messageText = @"Notifications Disabled";
                alert.informativeText = @"Notifications are disabled for StopTyping. Enable them in System Settings → Notifications to receive typing warnings.";
                [alert addButtonWithTitle:@"Open Notification Settings"];
                [alert addButtonWithTitle:@"Close"];
                if ([alert runModal] == NSAlertFirstButtonReturn) {
                    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.notifications"];
                    [[NSWorkspace sharedWorkspace] openURL:url];
                }
            });
            return;
        }

        // Request authorization with multiple attempts if needed
        UNAuthorizationOptions options = (UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge);
#ifdef UNAuthorizationOptionProvisional
        options |= UNAuthorizationOptionProvisional; // helps registration on some systems
#endif

        NSLog(@"Notifications: requesting authorization with options: %lu", (unsigned long)options);

        // Try authorization request
        [center requestAuthorizationWithOptions:options
                              completionHandler:^(BOOL granted, NSError * _Nullable error) {
            notificationsAuthorized = granted && (error == nil);
            NSLog(@"Notifications: authorization request result: granted=%@ error=%@",
                  granted ? @"YES" : @"NO", error);

            if (!notificationsAuthorized) {
                // If not granted, try again after a short delay (sometimes helps with registration)
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                              dispatch_get_main_queue(), ^{
                    NSLog(@"Notifications: retrying authorization request...");
                    [center requestAuthorizationWithOptions:options
                                          completionHandler:^(BOOL granted2, NSError * _Nullable error2) {
                        notificationsAuthorized = granted2 && (error2 == nil);
                        NSLog(@"Notifications: retry authorization result: granted=%@ error=%@",
                              granted2 ? @"YES" : @"NO", error2);

                        if (!notificationsAuthorized) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                NSAlert *alert = [[NSAlert alloc] init];
                                alert.alertStyle = NSAlertStyleInformational;
                                alert.messageText = @"Allow Notifications";
                                alert.informativeText = @"To enable notifications:\n\n1. Go to System Settings → Notifications\n2. Find 'StopTyping' in the app list\n3. Turn on 'Allow Notifications'\n4. Enable alerts and sounds\n\nIf you don't see the app in the list, try:\n- Restarting the app\n- Restarting your Mac\n- Checking Console.app for errors";
                                [alert addButtonWithTitle:@"Open Notification Settings"];
                                [alert addButtonWithTitle:@"Later"];
                                if ([alert runModal] == NSAlertFirstButtonReturn) {
                                    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.notifications"];
                                    [[NSWorkspace sharedWorkspace] openURL:url];
                                }
                            });
                        } else {
                            // Send a test notification to ensure everything works
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                                          dispatch_get_main_queue(), ^{
                                Notify(@"Notifications Enabled", @"StopTyping notifications are now active", YES);
                            });
                        }
                    }];
                });
            } else {
                // Send a test notification to ensure everything works
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                              dispatch_get_main_queue(), ^{
                    Notify(@"Notifications Enabled", @"StopTyping notifications are now active", YES);
                });
            }
        }];
    }];
}

void Notify(NSString *title, NSString *message, BOOL playSound) {
    if (!RunningInAppBundle()) {
        // Silently skip notifications when not running from an .app bundle
        NSLog(@"Notify: skipping - not in app bundle");
        return;
    }

    // Check if we have authorization
    if (!notificationsAuthorized) {
        NSLog(@"Notify: skipping - not authorized yet");
        return;
    }

    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = title ?: @"";
    content.body = message ?: @"";

    // Set sound
    if (playSound) {
        content.sound = [UNNotificationSound defaultSound];
    }

    // Create trigger for immediate delivery
    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:0.1 repeats:NO];

    // Create unique identifier
    NSString *identifier = [NSString stringWithFormat:@"KeyboardMonitor-%f", [NSDate timeIntervalSinceReferenceDate]];

    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger];

    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"Notify: failed to add request: %@", error);
            // If we get an error, it might be because authorization changed
            // Try to re-authorize
            if (error.code == UNErrorCodeNotificationsNotAllowed) {
                notificationsAuthorized = NO;
                NSLog(@"Notify: authorization lost, will re-request on next notification");
            }
        } else {
            NSLog(@"Notify: notification sent successfully - %@", title);
        }
    }];
}
