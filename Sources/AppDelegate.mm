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

    // Auto-save when the app loses focus
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidResignActive:)
                                                 name:NSApplicationDidResignActiveNotification
                                               object:nil];

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

- (void)appDidResignActive:(NSNotification *)note {
    [_windowController autoSaveAll];
}

- (void)applicationWillTerminate:(NSNotification *)note {
    // Save open file URLs for next launch (untitled docs are skipped)
    [self saveSession];
}

- (void)saveSession {
    [_windowController saveSession];
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
    if (err) [[NSAlert alertWithError:err] runModal];
    return NO;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray<NSString *> *)filenames {
    for (NSString *path in filenames) {
        [self application:sender openFile:path];
    }
}

@end
