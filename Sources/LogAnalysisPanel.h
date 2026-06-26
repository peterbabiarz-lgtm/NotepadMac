#pragma once
#import <Cocoa/Cocoa.h>

@interface LogAnalysisPanel : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>

+ (nonnull instancetype)shared;
- (void)showWithText:(NSString * _Nonnull)text filePath:(NSString * _Nullable)filePath;

@end
