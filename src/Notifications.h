#import <Foundation/Foundation.h>

// Simple notifications helper using UserNotifications
// Call Notify(...) after requesting authorization once at launch.
void NotificationsRequestAuthorization(void);
void Notify(NSString *title, NSString *message, BOOL playSound);
// Variant that attempts to attach an image from the app bundle by name
// Accepted extensions: .png, .jpg, .jpeg, .gif
void NotifyWithIcon(NSString *title, NSString *message, BOOL playSound, NSString *iconNameOrNil);
