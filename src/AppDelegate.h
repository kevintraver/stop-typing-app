#import <Cocoa/Cocoa.h>
#import "KeyboardMonitor.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, KeyboardMonitorDelegate>

@property (nonatomic, strong) KeyboardMonitor *keyboardMonitor;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, assign) BOOL isMonitoringEnabled;

- (void)setupStatusItem;
- (void)toggleMonitoring:(id)sender;
- (void)quit:(id)sender;

@end
