#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Renders the built-in keyboard-off SVG to a PNG in the temp dir
// Returns a file URL to the generated PNG, or nil on failure
NSURL *EnsureKeyboardOffPNG(void);

