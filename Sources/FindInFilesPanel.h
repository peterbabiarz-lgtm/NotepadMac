#pragma once
#import <Cocoa/Cocoa.h>

@interface FindInFilesPanel : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>

+ (instancetype)shared;
- (void)showPanel;

@end
