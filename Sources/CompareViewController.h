#pragma once
#import <Cocoa/Cocoa.h>

@interface CompareViewController : NSWindowController

- (instancetype)initWithLeftTitle:(NSString *)leftTitle  leftText:(NSString *)leftText
                       rightTitle:(NSString *)rightTitle rightText:(NSString *)rightText;

@end
