 #import "Accessibility.h"
 #import <ApplicationServices/ApplicationServices.h>
 #import <Cocoa/Cocoa.h>

 static BOOL gPromptedForAX = NO;
 static BOOL gGuidanceShown = NO;

 BOOL AXTrusted(void) {
     return AXIsProcessTrusted();
 }

 BOOL EnsureAccessibilityTrust(void) {
     if (AXIsProcessTrusted()) {
         return YES;
     }

     if (!gPromptedForAX) {
         gPromptedForAX = YES;
         NSDictionary *options = @{(__bridge NSString*)kAXTrustedCheckOptionPrompt: @YES};
         (void)AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);

         // After prompting, wait briefly; only show guidance if still not trusted
         dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
             if (!AXIsProcessTrusted() && !gGuidanceShown) {
                 gGuidanceShown = YES;
                 NSAlert *alert = [[NSAlert alloc] init];
                 alert.alertStyle = NSAlertStyleWarning;
                 alert.messageText = @"Accessibility Permission Required";
                 alert.informativeText = @"Enable Accessibility for StopTyping in System Settings → Privacy & Security → Accessibility. After enabling, return to the app; it will start automatically.";
                 [alert addButtonWithTitle:@"Open Settings"];
                 [alert addButtonWithTitle:@"Later"];
                 NSModalResponse response = [alert runModal];
                 if (response == NSAlertFirstButtonReturn) {
                     NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
                     [[NSWorkspace sharedWorkspace] openURL:url];
                 }
             }
         });
     }

     return NO;
 }
