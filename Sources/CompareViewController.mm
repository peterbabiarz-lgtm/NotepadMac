#import "CompareViewController.h"
#import "DiffEngine.h"
#import "ThemeManager.h"

#include "Scintilla.h"
#include "ScintillaView.h"

// Diff marker indices (must not conflict with fold markers 25-31)
static const int kMarkerAdded   = 0;
static const int kMarkerDeleted = 1;
static const int kMarkerChanged = 2;

@interface CompareViewController ()
@end

@implementation CompareViewController {
    ScintillaView *_left;
    ScintillaView *_right;
    BOOL           _syncing;   // re-entrancy guard for scroll sync
}

- (instancetype)initWithLeftTitle:(NSString *)leftTitle  leftText:(NSString *)leftText
                       rightTitle:(NSString *)rightTitle rightText:(NSString *)rightText {
    NSWindow *win = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 1200, 700)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    win.title    = [NSString stringWithFormat:@"Compare: %@  ↔  %@", leftTitle, rightTitle];
    win.minSize  = NSMakeSize(600, 300);
    [win center];

    self = [super initWithWindow:win];
    if (!self) return nil;

    [self buildUI];
    [self loadLeft:leftText right:rightText];
    [self applyTheme];
    [self highlightDiff:[DiffEngine diffLeft:leftText right:rightText]];
    [self makeReadOnly];
    return self;
}

// MARK: – UI

- (void)buildUI {
    NSView *cv = self.window.contentView;
    NSRect cvb = cv.bounds;

    // NSSplitView filling the whole content view
    NSSplitView *split = [[NSSplitView alloc] initWithFrame:cvb];
    split.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    split.vertical         = YES;
    split.dividerStyle     = NSSplitViewDividerStyleThin;
    [cv addSubview:split];

    // Give each pane an explicit initial frame (half the width)
    CGFloat halfW = floor(cvb.size.width / 2.0);
    NSRect leftFrame  = NSMakeRect(0,     0, halfW,                   cvb.size.height);
    NSRect rightFrame = NSMakeRect(halfW, 0, cvb.size.width - halfW,  cvb.size.height);

    _left  = [self makeEditorWithFrame:leftFrame];
    _right = [self makeEditorWithFrame:rightFrame];

    [split addSubview:_left];
    [split addSubview:_right];

    // Sync scrolling via NSNotificationCenter (avoids unsafe_unretained delegate in paint path)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(sciUpdateUI:)
                                                 name:SCIUpdateUINotification
                                               object:_left];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(sciUpdateUI:)
                                                 name:SCIUpdateUINotification
                                               object:_right];
}

- (ScintillaView *)makeEditorWithFrame:(NSRect)frame {
    ScintillaView *ed = [[ScintillaView alloc] initWithFrame:frame];
    ed.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    // Read-only applied after content loading

    // Font & basic settings
    [ed setFontName:@"Menlo" size:12 bold:NO italic:NO];
    [ed setGeneralProperty:SCI_SETTABWIDTH value:4];
    [ed setGeneralProperty:SCI_SETMARGINTYPEN parameter:0 value:SC_MARGIN_NUMBER];
    [ed setGeneralProperty:SCI_SETMARGINWIDTHN parameter:0 value:44];
    [ed setGeneralProperty:SCI_SETMARGINWIDTHN parameter:2 value:0]; // no fold margin

    // Caret line frame
    [ed setGeneralProperty:SCI_SETCARETLINEVISIBLE value:1];
    [ed setGeneralProperty:SCI_SETCARETLINEFRAME value:2];

    // Scroll width tracking
    [ed setGeneralProperty:SCI_SETSCROLLWIDTHTRACKING value:1];
    [ed setGeneralProperty:SCI_SETSCROLLWIDTH value:1];

    return ed;
}

// MARK: – Content

- (void)loadLeft:(NSString *)leftText right:(NSString *)rightText {
    [_left  setString:leftText  ?: @""];
    [_right setString:rightText ?: @""];
}

- (void)makeReadOnly {
    [_left  setGeneralProperty:SCI_SETREADONLY value:1];
    [_right setGeneralProperty:SCI_SETREADONLY value:1];
}

// MARK: – Theme

- (void)applyTheme {
    ScintillaTheme t = [[ThemeManager shared] themeForAppearance:NSApp.effectiveAppearance];

    for (ScintillaView *ed in @[_left, _right]) {
        [ed setColorProperty:SCI_STYLESETBACK parameter:STYLE_DEFAULT value:t.background];
        [ed setColorProperty:SCI_STYLESETFORE parameter:STYLE_DEFAULT value:t.foreground];
        [ed setGeneralProperty:SCI_STYLECLEARALL value:0];
        [ed setColorProperty:SCI_STYLESETBACK parameter:STYLE_LINENUMBER value:t.lineNumberBg];
        [ed setColorProperty:SCI_STYLESETFORE parameter:STYLE_LINENUMBER value:t.lineNumberFg];
        [ed setColorProperty:SCI_SETSELBACK parameter:1 value:t.selectionBg];

        NSColor *clb = [t.caretLineBg colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
        if (clb) {
            long clr = (long)(clb.redComponent * 255)
                     | ((long)(clb.greenComponent * 255) << 8)
                     | ((long)(clb.blueComponent * 255) << 16);
            [ed setGeneralProperty:SCI_SETCARETLINEBACK parameter:clr value:0];
        }

        // Diff markers: background-fill style
        [ed setGeneralProperty:SCI_MARKERDEFINE parameter:kMarkerAdded   value:SC_MARK_BACKGROUND];
        [ed setGeneralProperty:SCI_MARKERDEFINE parameter:kMarkerDeleted value:SC_MARK_BACKGROUND];
        [ed setGeneralProperty:SCI_MARKERDEFINE parameter:kMarkerChanged value:SC_MARK_BACKGROUND];

        NSColor *green  = [NSColor colorWithRed:0.18 green:0.60 blue:0.18 alpha:1.0];
        NSColor *red    = [NSColor colorWithRed:0.75 green:0.15 blue:0.15 alpha:1.0];
        NSColor *orange = [NSColor colorWithRed:0.80 green:0.52 blue:0.10 alpha:1.0];
        [ed setColorProperty:SCI_MARKERSETBACK parameter:kMarkerAdded   value:green];
        [ed setColorProperty:SCI_MARKERSETBACK parameter:kMarkerDeleted value:red];
        [ed setColorProperty:SCI_MARKERSETBACK parameter:kMarkerChanged value:orange];

        // Make marker text readable against coloured backgrounds
        [ed setColorProperty:SCI_MARKERSETFORE parameter:kMarkerAdded   value:NSColor.whiteColor];
        [ed setColorProperty:SCI_MARKERSETFORE parameter:kMarkerDeleted value:NSColor.whiteColor];
        [ed setColorProperty:SCI_MARKERSETFORE parameter:kMarkerChanged value:NSColor.whiteColor];
    }
}

// MARK: – Diff highlighting

- (void)highlightDiff:(NSArray<DiffHunk *> *)hunks {
    for (DiffHunk *h in hunks) {
        switch (h.type) {
            case DiffHunkTypeAdded:
                // Lines added on right side only
                [self markLines:_right from:h.rightStart to:h.rightEnd marker:kMarkerAdded];
                break;

            case DiffHunkTypeDeleted:
                // Lines deleted from left side only
                [self markLines:_left from:h.leftStart to:h.leftEnd marker:kMarkerDeleted];
                break;

            case DiffHunkTypeChanged:
                [self markLines:_left  from:h.leftStart  to:h.leftEnd  marker:kMarkerChanged];
                [self markLines:_right from:h.rightStart to:h.rightEnd marker:kMarkerChanged];
                break;
        }
    }
}

- (void)markLines:(ScintillaView *)ed from:(NSInteger)start to:(NSInteger)end marker:(int)marker {
    if (start <= 0 || end <= 0) return;
    for (NSInteger line = start; line <= end; line++) {
        // SCI_MARKERADD: wParam=line (0-based), lParam=markerNumber
        [ed setGeneralProperty:SCI_MARKERADD parameter:(line - 1) value:marker];
    }
}

// MARK: – Synchronized scrolling

- (void)sciUpdateUI:(NSNotification *)note {
    if (_syncing) return;
    _syncing = YES;

    ScintillaView *source = (note.object == _left) ? _left : _right;
    ScintillaView *target = (source == _left) ? _right : _left;

    long firstLine = [source getGeneralProperty:SCI_GETFIRSTVISIBLELINE];
    [target setGeneralProperty:SCI_SETFIRSTVISIBLELINE value:firstLine];

    _syncing = NO;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
