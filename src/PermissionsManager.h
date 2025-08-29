#import <Foundation/Foundation.h>

@interface PermissionsManager : NSObject

+ (instancetype)shared;

// Call at launch to prepare permissions (notifications) and ensure prompts are visible
- (void)setupAtLaunch;

// Accessibility helpers
- (BOOL)isAccessibilityTrusted;
- (void)ensureAccessibilityPromptOnce;
- (void)openAccessibilitySettings;

// Notifications helpers
- (void)requestNotificationAuthorization;
- (void)openNotificationSettings;

// Diagnostics
- (void)checkNotificationStatusAndReport;

@end
