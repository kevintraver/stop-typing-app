#import "SVGRenderer.h"
#import <WebKit/WebKit.h>
#import <AppKit/AppKit.h>

static NSString *KeyboardOffSVG(void) {
    // User-provided lucide keyboard-off SVG paths
    return @"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"256\" height=\"256\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"#000\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M 20 4 A2 2 0 0 1 22 6\"></path><path d=\"M 22 6 L 22 16.41\"></path><path d=\"M 7 16 L 16 16\"></path><path d=\"M 9.69 4 L 20 4\"></path><path d=\"M14 8h.01\"></path><path d=\"M18 8h.01\"></path><path d=\"m2 2 20 20\"></path><path d=\"M20 20H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2\"></path><path d=\"M6 8h.01\"></path><path d=\"M8 12h.01\"></path></svg>";
}

static NSString *HTMLForSVG(NSString *svg) {
    // Transparent background; center the SVG
    return [NSString stringWithFormat:@"<!doctype html>\n<html><head><meta charset=\"utf-8\">\n<style>html,body{margin:0;background:transparent;width:256px;height:256px;display:grid;place-items:center;}</style>\n</head><body>%@</body></html>", svg ?: @""];
}

static NSURL *RenderSVGToTempPNG(NSString *html, CGSize size, NSString *outName) {
    __block NSImage *snapshotImg = nil;
    __block BOOL finished = NO;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    void (^renderBlock)(void) = ^{
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        WKWebView *webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)
                                               configuration:config];
        webView.wantsLayer = YES;

        id<WKNavigationDelegate> delegate = (id<WKNavigationDelegate>)[[NSObject alloc] init];
        // Use a lightweight delegate via a category block pattern
        // We’ll rely on a small delay post-load if delegate hooks aren’t available here.
        (void)delegate;

        [webView loadHTMLString:html baseURL:nil];

        // Give WebKit a brief moment to render, then snapshot
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            WKSnapshotConfiguration *cfg = [[WKSnapshotConfiguration alloc] init];
            cfg.afterScreenUpdates = YES;
            cfg.rect = CGRectMake(0, 0, size.width, size.height);
            [webView takeSnapshotWithConfiguration:cfg completionHandler:^(NSImage * _Nullable image, NSError * _Nullable error) {
                snapshotImg = image;
                finished = YES;
                dispatch_semaphore_signal(sema);
            }];
        });
    };

    if ([NSThread isMainThread]) {
        renderBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), renderBlock);
    }

    // Wait up to 2 seconds
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC));
    (void)dispatch_semaphore_wait(sema, timeout);

    if (!snapshotImg) return nil;

    NSData *tiff = [snapshotImg TIFFRepresentation];
    if (!tiff) return nil;
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:tiff];
    if (!rep) return nil;
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (!png) return nil;

    NSString *outPath = [NSTemporaryDirectory() stringByAppendingPathComponent:outName ?: @"keyboard-off.png"];
    if ([png writeToFile:outPath atomically:YES]) {
        return [NSURL fileURLWithPath:outPath];
    }
    return nil;
}

NSURL *EnsureKeyboardOffPNG(void) {
    NSString *tempPath = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"keyboard-off.png"] copy];
    if ([[NSFileManager defaultManager] fileExistsAtPath:tempPath]) {
        return [NSURL fileURLWithPath:tempPath];
    }
    NSString *html = HTMLForSVG(KeyboardOffSVG());
    return RenderSVGToTempPNG(html, CGSizeMake(256, 256), @"keyboard-off.png");
}

