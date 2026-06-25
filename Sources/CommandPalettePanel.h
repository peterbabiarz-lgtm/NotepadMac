#pragma once
#import <Cocoa/Cocoa.h>

/// Floating command palette — fuzzy-search all menu items and execute them.
/// Open with ⌘⇧P, dismiss with Escape or click-away.
@interface CommandPalettePanel : NSPanel <NSTableViewDataSource,
                                          NSTableViewDelegate,
                                          NSTextFieldDelegate,
                                          NSWindowDelegate>
+ (instancetype)shared;
- (void)showOverWindow:(NSWindow *)window;
- (void)buildIndex;
@end
