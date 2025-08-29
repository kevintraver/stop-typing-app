#import "Accessibility.h"
#import <ApplicationServices/ApplicationServices.h>
#import <Cocoa/Cocoa.h>

BOOL EnsureAccessibilityTrust(void) {
    NSDictionary *options = @{(__bridge NSString*)kAXTrustedCheckOptionPrompt: @YES};
    Boolean trusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);

    if (!trusted) {
        // Optionally, guide the user to the right Settings pane
        dispatch_async(dispatch_get_main_queue(), ^{
            NSAlert *alert = [[NSAlert alloc] init];
            alert.alertStyle = NSAlertStyleWarning;
            alert.messageText = @"Accessibility Permission Required";
            alert.informativeText = @"To monitor keyboard input, enable Accessibility for Keyboard Monitor in System Settings → Privacy & Security → Accessibility. Click Open Settings, then add and enable the app.";
            [alert addButtonWithTitle:@"Open Settings"];
            [alert addButtonWithTitle:@"Later"];
            NSModalResponse response = [alert runModal];
            if (response == NSAlertFirstButtonReturn) {
                NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
                [[NSWorkspace sharedWorkspace] openURL:url];
            }
        });
    }

    return (BOOL)trusted;
}

