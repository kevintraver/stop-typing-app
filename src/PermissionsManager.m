#import "PermissionsManager.h"
#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>
#import "Notifications.h"
#import "Accessibility.h"

@implementation PermissionsManager {
    BOOL _promptedAXThisRun;
}

static BOOL RunningInAppBundleLocal(void) {
    NSBundle *bundle = [NSBundle mainBundle];
    if (!bundle) return NO;
    if (bundle.bundleIdentifier.length == 0) return NO;
    NSString *ext = [[bundle bundleURL].pathExtension lowercaseString];
    return [ext isEqualToString:@"app"];
}

+ (instancetype)shared {
    static PermissionsManager *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ s = [PermissionsManager new]; });
    return s;
}

- (void)setupAtLaunch {
    NSLog(@"PermissionsManager: setupAtLaunch called");

    // Add a small delay to ensure the app is fully initialized
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"PermissionsManager: requesting notification authorization after delay");
        [self requestNotificationAuthorization];
    });
}

- (void)requestNotificationAuthorization {
    NSLog(@"PermissionsManager: requestNotificationAuthorization called");

    // Only operate when running from an .app bundle
    if (!RunningInAppBundleLocal()) {
        NSLog(@"PermissionsManager: not an app bundle; skipping notification auth.");
        return;
    }

    NSLog(@"PermissionsManager: running in app bundle, proceeding with notification auth");

    // For accessory apps, temporarily change activation policy to show permission dialogs
    NSApplicationActivationPolicy prevPolicy = [NSApp activationPolicy];
    __block BOOL changedPolicy = NO;

    if (prevPolicy == NSApplicationActivationPolicyAccessory) {
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp activateIgnoringOtherApps:YES];
        changedPolicy = YES;
    }

    // Request notification authorization
    NotificationsRequestAuthorization();

    // Poll notification settings and restore policy when done
    __block NSUInteger attempts = 0;
    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull t) {
        attempts++;
        if (!RunningInAppBundleLocal()) {
            [t invalidate];
            if (changedPolicy && prevPolicy == NSApplicationActivationPolicyAccessory) {
                [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
            }
            return;
        }
        [[UNUserNotificationCenter currentNotificationCenter] getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
            UNAuthorizationStatus status = settings.authorizationStatus;

            // Continue polling if still undetermined, or stop after max attempts
            if (status != UNAuthorizationStatusNotDetermined || attempts > 15) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [t invalidate];

                    // Restore original activation policy if we changed it
                    if (changedPolicy && prevPolicy == NSApplicationActivationPolicyAccessory) {
                        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
                    }

                    // Send test notification if authorized
                    if (status == UNAuthorizationStatusAuthorized
#ifdef UNAuthorizationStatusProvisional
                        || status == UNAuthorizationStatusProvisional
#endif
                        ) {
                         dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                                       dispatch_get_main_queue(), ^{
                             // Notify(@"Keyboard Monitor Ready", @"Notifications are enabled and working", NO);
                         });
                    }
                });
            }
        }];
    }];
}

- (BOOL)isAccessibilityTrusted {
    return AXTrusted();
}

- (void)ensureAccessibilityPromptOnce {
    if (_promptedAXThisRun) return;
    _promptedAXThisRun = YES;
    (void)EnsureAccessibilityTrust();
}

- (void)openAccessibilitySettings {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)openNotificationSettings {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.notifications"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)checkNotificationStatusAndReport {
    // Check if we're in an app bundle first
    if (!RunningInAppBundleLocal()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSAlert *alert = [[NSAlert alloc] init];
            alert.alertStyle = NSAlertStyleInformational;
            alert.messageText = @"Development Mode";
            alert.informativeText = @"Notifications are not available when running as a standalone executable.\n\nRun the app from its .app bundle to enable notifications.";
            [alert addButtonWithTitle:@"OK"];
            [alert runModal];
        });
        return;
    }

    [[UNUserNotificationCenter currentNotificationCenter] getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
        UNAuthorizationStatus status = settings.authorizationStatus;
        NSString *statusText = @"Unknown";
        switch (status) {
            case UNAuthorizationStatusNotDetermined: statusText = @"Not Determined"; break;
            case UNAuthorizationStatusDenied: statusText = @"Denied"; break;
            case UNAuthorizationStatusAuthorized: statusText = @"Authorized"; break;
#ifdef UNAuthorizationStatusProvisional
            case UNAuthorizationStatusProvisional: statusText = @"Provisional"; break;
#endif
#ifdef UNAuthorizationStatusEphemeral
            case UNAuthorizationStatusEphemeral: statusText = @"Ephemeral"; break;
#endif
            default: break;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            NSAlert *alert = [[NSAlert alloc] init];
            alert.alertStyle = NSAlertStyleInformational;
            alert.messageText = @"Notification Status";
            alert.informativeText = [NSString stringWithFormat:@"Authorization: %@\nAlert: %@\nSound: %@\nBadge: %@",
                                      statusText,
                                      (settings.alertSetting == UNNotificationSettingEnabled ? @"Enabled" : @"Disabled"),
                                      (settings.soundSetting == UNNotificationSettingEnabled ? @"Enabled" : @"Disabled"),
                                      (settings.badgeSetting == UNNotificationSettingEnabled ? @"Enabled" : @"Disabled")];
            [alert addButtonWithTitle:@"Open Notification Settings"];
            [alert addButtonWithTitle:@"Close"];
            if ([alert runModal] == NSAlertFirstButtonReturn) {
                [self openNotificationSettings];
            }
        });
    }];
}

@end
