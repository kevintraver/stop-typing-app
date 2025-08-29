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
    NSString *bid = [bundle bundleIdentifier];
    if (bid.length == 0) return NO;
    NSURL *url = [bundle bundleURL];
    return [[url pathExtension].lowercaseString isEqualToString:@"app"];
}

static BOOL notificationsAuthorized = NO;
static NotificationsDelegate *notificationsDelegate = nil;

void NotificationsRequestAuthorization(void) {
    if (!RunningInAppBundle()) {
        // UNUserNotificationCenter requires a proper app bundle context.
        return;
    }
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    // Install delegate early so foreground notifications present
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        notificationsDelegate = [NotificationsDelegate new];
        center.delegate = notificationsDelegate;
    });
    UNAuthorizationOptions options = (UNAuthorizationOptionAlert | UNAuthorizationOptionSound);
    [center requestAuthorizationWithOptions:options
                          completionHandler:^(BOOL granted, NSError * _Nullable error) {
        notificationsAuthorized = granted && (error == nil);
        if (!notificationsAuthorized) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSAlert *alert = [[NSAlert alloc] init];
                alert.alertStyle = NSAlertStyleInformational;
                alert.messageText = @"Allow Notifications";
                alert.informativeText = @"To see alerts, enable notifications for Keyboard Monitor in System Settings → Notifications.";
                [alert addButtonWithTitle:@"Open Notification Settings"];
                [alert addButtonWithTitle:@"Later"];
                if ([alert runModal] == NSAlertFirstButtonReturn) {
                    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.notifications"];
                    [[NSWorkspace sharedWorkspace] openURL:url];
                }
            });
        }
    }];
}

void Notify(NSString *title, NSString *message, BOOL playSound) {
    if (!RunningInAppBundle()) {
        // Silently skip notifications when not running from an .app bundle
        return;
    }
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = title ?: @"";
    content.body = message ?: @"";
    if (playSound) {
        content.sound = [UNNotificationSound defaultSound];
    }

    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:0.1 repeats:NO];
    NSString *identifier = [NSString stringWithFormat:@"KeyboardMonitor-%f", [NSDate timeIntervalSinceReferenceDate]];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger];

    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"Notify: failed to add request: %@", error);
        }
    }];
}
