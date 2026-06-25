#pragma once
#import <Cocoa/Cocoa.h>

typedef struct {
    NSColor *background;
    NSColor *foreground;
    NSColor *keyword;
    NSColor *string;
    NSColor *comment;
    NSColor *number;
    NSColor *preprocessor;
    NSColor *operator_;
    NSColor *identifier;
    NSColor *lineNumberFg;
    NSColor *lineNumberBg;
    NSColor *selectionBg;
    NSColor *caretFg;
    NSColor *caretLineBg;
} ScintillaTheme;

@interface ThemeManager : NSObject

+ (instancetype)shared;
- (ScintillaTheme)themeForAppearance:(NSAppearance *)appearance;

@end
