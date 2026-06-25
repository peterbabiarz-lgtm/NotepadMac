#import "ThemeManager.h"

static NSColor *hex(NSString *h) {
    unsigned int rgb = 0;
    BOOL ok = [[NSScanner scannerWithString:h] scanHexInt:&rgb];
    NSCAssert(ok, @"ThemeManager: malformed hex color '%@'", h);
    (void)ok;
    return [NSColor colorWithRed:((rgb>>16)&0xFF)/255.0
                           green:((rgb>>8)&0xFF)/255.0
                            blue:(rgb&0xFF)/255.0
                           alpha:1.0];
}

@implementation ThemeManager

+ (instancetype)shared {
    static ThemeManager *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [ThemeManager new]; });
    return instance;
}

- (ScintillaTheme)themeForAppearance:(NSAppearance *)appearance {
    NSAppearanceName best = [appearance bestMatchFromAppearancesWithNames:@[
        NSAppearanceNameAqua, NSAppearanceNameDarkAqua
    ]];
    BOOL dark = [best isEqualToString:NSAppearanceNameDarkAqua];
    return dark ? [self darkTheme] : [self lightTheme];
}

- (ScintillaTheme)lightTheme {
    return (ScintillaTheme){
        .background    = hex(@"FFFFFF"),
        .foreground    = hex(@"000000"),
        .keyword       = hex(@"0000CC"),
        .string        = hex(@"008000"),
        .comment       = hex(@"808080"),
        .number        = hex(@"FF8000"),
        .preprocessor  = hex(@"804000"),
        .operator_     = hex(@"000000"),
        .identifier    = hex(@"000000"),
        .lineNumberFg  = hex(@"808080"),
        .lineNumberBg  = hex(@"F0F0F0"),
        .selectionBg   = hex(@"B8D6FD"),
        .caretFg       = hex(@"000000"),
        .caretLineBg   = hex(@"EFF5FF"),
    };
}

- (ScintillaTheme)darkTheme {
    return (ScintillaTheme){
        .background    = hex(@"1E1E1E"),
        .foreground    = hex(@"D4D4D4"),
        .keyword       = hex(@"569CD6"),
        .string        = hex(@"CE9178"),
        .comment       = hex(@"6A9955"),
        .number        = hex(@"B5CEA8"),
        .preprocessor  = hex(@"C586C0"),
        .operator_     = hex(@"D4D4D4"),
        .identifier    = hex(@"9CDCFE"),
        .lineNumberFg  = hex(@"858585"),
        .lineNumberBg  = hex(@"1E1E1E"),
        .selectionBg   = hex(@"264F78"),
        .caretFg       = hex(@"AEAFAD"),
        .caretLineBg   = hex(@"282828"),
    };
}

@end
