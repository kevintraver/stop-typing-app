#import <Foundation/Foundation.h>

// Ensures the app has Accessibility trust. Prompts the user once if needed.
// Returns YES if trusted, NO otherwise.
BOOL EnsureAccessibilityTrust(void);

// Lightweight check without prompting.
BOOL AXTrusted(void);
