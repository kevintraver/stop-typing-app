#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <AppKit/AppKit.h>

static void usage(void) {
    fprintf(stderr, "Usage: svg2png <input.svg> <output.png> <size>\n");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 4) { usage(); return 2; }
        NSString *inPath = [NSString stringWithUTF8String:argv[1]];
        NSString *outPath = [NSString stringWithUTF8String:argv[2]];
        CGFloat size = (CGFloat)atof(argv[3]);
        if (size <= 0) { usage(); return 2; }

        NSError *err = nil;
        NSString *svg = [NSString stringWithContentsOfFile:inPath encoding:NSUTF8StringEncoding error:&err];
        if (!svg) {
            fprintf(stderr, "Failed to read SVG: %s\n", [[err description] UTF8String]);
            return 1;
        }
        NSString *html = [NSString stringWithFormat:@"<!doctype html><html><head><meta charset=\"utf-8\"><style>html,body{margin:0;background:transparent;width:%0.0fpx;height:%0.0fpx;display:grid;place-items:center;}</style></head><body>%@</body></html>", size, size, svg];

        __block NSImage *snapshotImg = nil;
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);

        dispatch_async(dispatch_get_main_queue(), ^{
            WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
            WKWebView *webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, size, size)
                                                   configuration:config];
            [webView loadHTMLString:html baseURL:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                WKSnapshotConfiguration *cfg = [[WKSnapshotConfiguration alloc] init];
                cfg.afterScreenUpdates = YES;
                cfg.rect = CGRectMake(0, 0, size, size);
                [webView takeSnapshotWithConfiguration:cfg completionHandler:^(NSImage * _Nullable image, NSError * _Nullable error) {
                    snapshotImg = image;
                    dispatch_semaphore_signal(sema);
                }];
            });
        });

        // Create a run loop to execute WebKit work
        while (dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)))) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }

        if (!snapshotImg) { fprintf(stderr, "Snapshot failed\n"); return 1; }
        NSData *tiff = [snapshotImg TIFFRepresentation];
        if (!tiff) { fprintf(stderr, "TIFF rep failed\n"); return 1; }
        NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:tiff];
        if (!rep) { fprintf(stderr, "Bitmap rep failed\n"); return 1; }
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (!png) { fprintf(stderr, "PNG rep failed\n"); return 1; }
        if (![png writeToFile:outPath atomically:YES]) { fprintf(stderr, "Write PNG failed\n"); return 1; }
        return 0;
    }
}

