// NotepadMac — main entry point
// We skip NSApplicationMain (which needs a NIB to find the delegate) and wire
// everything up manually — the standard pattern for NIB-free Cocoa apps.
#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

int main(int argc, const char *argv[]) {
    NSApplication *app = [NSApplication sharedApplication];
    AppDelegate   *delegate = [[AppDelegate alloc] init];
    app.delegate = delegate;
    [app run];
    return 0;
}
