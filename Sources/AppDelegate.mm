#import "AppDelegate.h"
#import "WindowController.h"
#import "Document.h"

static NSString *const kSessionKey = @"SessionFiles";

@implementation AppDelegate {
    WindowController *_windowController;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    _windowController = [[WindowController alloc] init];
    [_windowController showWindow:nil];

    // Restore last session
    NSArray<NSString *> *session = [[NSUserDefaults standardUserDefaults] arrayForKey:kSessionKey];
    BOOL restored = NO;
    for (NSString *path in session) {
        NSURL *url = [NSURL fileURLWithPath:path];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [_windowController openFileURL:url];
            restored = YES;
        }
    }
    if (!restored) {
        [_windowController newDocument];
    }
}

- (void)applicationWillTerminate:(NSNotification *)note {
    // Save open file URLs for next launch (untitled docs are skipped)
    [self saveSession];
}

- (void)saveSession {
    // Walk all tab items via the window controller's public API indirectly:
    // WindowController exposes openDocument/newDocument, but not the tab list.
    // We read the session by inspecting the tab view via a notification-safe path.
    // Actually, the simplest approach: WindowController saves the session itself.
    // We notify it via a custom selector so AppDelegate stays thin.
    if ([_windowController respondsToSelector:@selector(saveSession)]) {
        [_windowController performSelector:@selector(saveSession)];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return YES;
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    NSURL *url = [NSURL fileURLWithPath:filename];
    NSError *err;
    Document *doc = [[Document alloc] initWithURL:url error:&err];
    if (doc) {
        [_windowController openDocument:doc];
        return YES;
    }
    return NO;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray<NSString *> *)filenames {
    for (NSString *path in filenames) {
        [self application:sender openFile:path];
    }
}

@end
