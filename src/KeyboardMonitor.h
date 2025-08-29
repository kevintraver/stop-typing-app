#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>

@protocol KeyboardMonitorDelegate <NSObject>
- (void)keyboardMonitorDidDetectExcessiveTyping;
@end

@interface KeyboardMonitor : NSObject

@property (nonatomic, weak) id<KeyboardMonitorDelegate> delegate;
@property (nonatomic, assign) BOOL isMonitoring;
@property (nonatomic, assign) int maxConsecutiveChars;
@property (nonatomic, assign) int typingCooldownMs;

// Initialize with default settings
- (instancetype)init;

// Start monitoring keyboard events
- (void)startMonitoring;

// Stop monitoring keyboard events
- (void)stopMonitoring;

// Reset the typing counter
- (void)resetCounter;

// Get current consecutive character count
- (int)currentConsecutiveChars;

// Check if warning has been displayed
- (BOOL)warningDisplayed;

@end
