#import <Foundation/Foundation.h>

// Simple notifications helper using UserNotifications
// Call Notify(...) after requesting authorization once at launch.
void NotificationsRequestAuthorization(void);
void Notify(NSString *title, NSString *message, BOOL playSound);

