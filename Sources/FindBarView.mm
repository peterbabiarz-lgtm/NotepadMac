#import "FindBarView.h"

@implementation FindBarView {
    NSTextField *_findField;
    NSTextField *_replaceField;
    NSButton    *_matchCaseBtn;
    NSButton    *_wholeWordBtn;
    NSButton    *_regexBtn;
    NSButton    *_prevBtn;
    NSButton    *_nextBtn;
    NSButton    *_replaceBtn;
    NSButton    *_replaceAllBtn;
    NSTextField *_countLabel;
    NSButton    *_closeBtn;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    [self buildUI];
    return self;
}

- (void)buildUI {
    // Background + top border drawn in drawRect:
    CGFloat W = self.bounds.size.width;

    // ── Row 1: Find ─────────────────────────────────────────────
    CGFloat row1Y = 37;

    NSTextField *findLbl = [NSTextField labelWithString:@"Find:"];
    findLbl.frame = NSMakeRect(10, row1Y + 3, 38, 18);
    findLbl.font = [NSFont systemFontOfSize:12];
    findLbl.textColor = NSColor.secondaryLabelColor;
    [self addSubview:findLbl];

    _findField = [NSTextField textFieldWithString:@""];
    _findField.frame = NSMakeRect(52, row1Y, W - 52 - 240, 22);
    _findField.autoresizingMask = NSViewWidthSizable;
    _findField.placeholderString = @"Suchen…";
    _findField.delegate = self;
    _findField.font = [NSFont systemFontOfSize:13];
    [self addSubview:_findField];

    // Prev / Next buttons
    _prevBtn = [NSButton buttonWithTitle:@"◀" target:self action:@selector(findPrev:)];
    _prevBtn.frame = NSMakeRect(W - 234, row1Y, 36, 22);
    _prevBtn.autoresizingMask = NSViewMinXMargin;
    _prevBtn.bezelStyle = NSBezelStyleRounded;
    _prevBtn.font = [NSFont systemFontOfSize:11];
    [self addSubview:_prevBtn];

    _nextBtn = [NSButton buttonWithTitle:@"▶" target:self action:@selector(findNext:)];
    _nextBtn.frame = NSMakeRect(W - 196, row1Y, 36, 22);
    _nextBtn.autoresizingMask = NSViewMinXMargin;
    _nextBtn.bezelStyle = NSBezelStyleRounded;
    _nextBtn.font = [NSFont systemFontOfSize:11];
    [self addSubview:_nextBtn];

    // Option checkboxes
    _matchCaseBtn = [NSButton checkboxWithTitle:@"Aa" target:self action:@selector(optionChanged:)];
    _matchCaseBtn.frame = NSMakeRect(W - 155, row1Y + 2, 46, 18);
    _matchCaseBtn.autoresizingMask = NSViewMinXMargin;
    _matchCaseBtn.font = [NSFont systemFontOfSize:12];
    _matchCaseBtn.toolTip = @"Groß-/Kleinschreibung beachten";
    [self addSubview:_matchCaseBtn];

    _wholeWordBtn = [NSButton checkboxWithTitle:@"W" target:self action:@selector(optionChanged:)];
    _wholeWordBtn.frame = NSMakeRect(W - 108, row1Y + 2, 40, 18);
    _wholeWordBtn.autoresizingMask = NSViewMinXMargin;
    _wholeWordBtn.font = [NSFont systemFontOfSize:12];
    _wholeWordBtn.toolTip = @"Nur ganze Wörter";
    [self addSubview:_wholeWordBtn];

    _regexBtn = [NSButton checkboxWithTitle:@".*" target:self action:@selector(optionChanged:)];
    _regexBtn.frame = NSMakeRect(W - 66, row1Y + 2, 44, 18);
    _regexBtn.autoresizingMask = NSViewMinXMargin;
    _regexBtn.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    _regexBtn.toolTip = @"Regulärer Ausdruck";
    [self addSubview:_regexBtn];

    // Close button
    _closeBtn = [NSButton buttonWithTitle:@"✕" target:self action:@selector(close:)];
    _closeBtn.frame = NSMakeRect(W - 20, row1Y + 1, 18, 18);
    _closeBtn.autoresizingMask = NSViewMinXMargin;
    _closeBtn.bordered = NO;
    _closeBtn.font = [NSFont systemFontOfSize:11];
    _closeBtn.contentTintColor = NSColor.secondaryLabelColor;
    [self addSubview:_closeBtn];

    // ── Row 2: Replace ──────────────────────────────────────────
    CGFloat row2Y = 8;

    NSTextField *replLbl = [NSTextField labelWithString:@"Ersetzen:"];
    replLbl.frame = NSMakeRect(10, row2Y + 3, 38, 18);
    replLbl.font = [NSFont systemFontOfSize:12];
    replLbl.textColor = NSColor.secondaryLabelColor;
    [self addSubview:replLbl];

    _replaceField = [NSTextField textFieldWithString:@""];
    _replaceField.frame = NSMakeRect(52, row2Y, W - 52 - 240, 22);
    _replaceField.autoresizingMask = NSViewWidthSizable;
    _replaceField.placeholderString = @"Ersetzen durch…";
    _replaceField.font = [NSFont systemFontOfSize:13];
    [self addSubview:_replaceField];

    _replaceBtn = [NSButton buttonWithTitle:@"Ersetzen" target:self action:@selector(replaceCurrent:)];
    _replaceBtn.frame = NSMakeRect(W - 234, row2Y, 90, 22);
    _replaceBtn.autoresizingMask = NSViewMinXMargin;
    _replaceBtn.bezelStyle = NSBezelStyleRounded;
    _replaceBtn.font = [NSFont systemFontOfSize:12];
    [self addSubview:_replaceBtn];

    _replaceAllBtn = [NSButton buttonWithTitle:@"Alle ersetzen" target:self action:@selector(replaceAll:)];
    _replaceAllBtn.frame = NSMakeRect(W - 140, row2Y, 118, 22);
    _replaceAllBtn.autoresizingMask = NSViewMinXMargin;
    _replaceAllBtn.bezelStyle = NSBezelStyleRounded;
    _replaceAllBtn.font = [NSFont systemFontOfSize:12];
    [self addSubview:_replaceAllBtn];

    // Match count label (top right area, between checkboxes and close)
    _countLabel = [NSTextField labelWithString:@""];
    _countLabel.frame = NSMakeRect(W - 234, row1Y + 4, 72, 16);
    _countLabel.autoresizingMask = NSViewMinXMargin;
    _countLabel.font = [NSFont systemFontOfSize:11];
    _countLabel.textColor = NSColor.secondaryLabelColor;
    _countLabel.alignment = NSTextAlignmentRight;
    // Position it before the prev button
    _countLabel.frame = NSMakeRect(W - 310, row1Y + 4, 70, 16);
    [self addSubview:_countLabel];
}

- (void)drawRect:(NSRect)dirtyRect {
    // Background
    BOOL dark = NO;
    if (@available(macOS 10.14, *)) {
        dark = [[self.effectiveAppearance bestMatchFromAppearancesWithNames:
                 @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]]
                isEqualToString:NSAppearanceNameDarkAqua];
    }
    NSColor *bg = dark ? [NSColor colorWithWhite:0.15 alpha:1]
                       : [NSColor colorWithWhite:0.94 alpha:1];
    [bg setFill];
    NSRectFill(self.bounds);

    // Top border
    NSColor *border = dark ? [NSColor colorWithWhite:0.28 alpha:1]
                           : [NSColor colorWithWhite:0.73 alpha:1];
    [border setFill];
    NSRectFill(NSMakeRect(0, self.bounds.size.height - 1, self.bounds.size.width, 1));

    // Row divider
    [[border colorWithAlphaComponent:0.4] setFill];
    NSRectFill(NSMakeRect(10, 32, self.bounds.size.width - 20, 1));
}

// MARK: – Actions

- (IBAction)findNext:(id)sender {
    if (!_findField.stringValue.length) return;
    [_delegate findBar:self findNext:YES];
}

- (IBAction)findPrev:(id)sender {
    if (!_findField.stringValue.length) return;
    [_delegate findBar:self findNext:NO];
}

- (IBAction)replaceCurrent:(id)sender {
    if (!_findField.stringValue.length) return;
    [_delegate findBar:self replaceCurrent:_replaceField.stringValue];
}

- (IBAction)replaceAll:(id)sender {
    if (!_findField.stringValue.length) return;
    [_delegate findBar:self replaceAll:_replaceField.stringValue];
}

- (IBAction)optionChanged:(id)sender {
    [self triggerHighlight];
}

- (IBAction)close:(id)sender {
    [self cancelPendingHighlight];
    [_delegate findBarDidClose:self];
}

- (void)cancelPendingHighlight {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(performHighlight)
                                               object:nil];
}

// MARK: – NSTextFieldDelegate (live search)

- (void)controlTextDidChange:(NSNotification *)obj {
    if (obj.object == _findField) {
        [self triggerHighlight];
    }
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)tv doCommandBySelector:(SEL)cmd {
    if (cmd == @selector(insertNewline:)) {
        NSEvent *evt = NSApp.currentEvent;
        BOOL backward = (evt.modifierFlags & NSEventModifierFlagShift) != 0;
        if (control == _findField) {
            [_delegate findBar:self findNext:!backward];
            return YES;
        }
        if (control == _replaceField) {
            [_delegate findBar:self replaceCurrent:_replaceField.stringValue];
            return YES;
        }
    }
    if (cmd == @selector(cancelOperation:)) {
        [self cancelPendingHighlight];
        [_delegate findBarDidClose:self];
        return YES;
    }
    return NO;
}

// MARK: – Helpers

- (void)triggerHighlight {
    // Debounce: a full-document search runs synchronously on the main thread,
    // so firing it on every keystroke (especially with a costly regex) can
    // freeze the UI. Coalesce rapid input into a single deferred search.
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(performHighlight)
                                               object:nil];
    [self performSelector:@selector(performHighlight) withObject:nil afterDelay:0.18];
}

- (void)performHighlight {
    [_delegate findBar:self highlightAll:_findField.stringValue];
}

- (void)focusFindField {
    [self.window makeFirstResponder:_findField];
    [_findField selectText:nil];
}

- (void)setMatchCount:(NSInteger)count {
    if (!_findField.stringValue.length || count < 0) {
        _countLabel.stringValue = @"";
    } else if (count == 0) {
        _countLabel.stringValue = @"Nicht gefunden";
        _countLabel.textColor = [NSColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1];
    } else {
        _countLabel.stringValue = [NSString stringWithFormat:@"%ld Treffer", (long)count];
        _countLabel.textColor = NSColor.secondaryLabelColor;
    }
}

// MARK: – Properties

- (NSString *)findText    { return _findField.stringValue; }
- (NSString *)replaceText { return _replaceField.stringValue; }

- (NMFindOptions)findOptions {
    return (_matchCaseBtn.state == NSControlStateValueOn ? NMFindMatchCase : 0)
         | (_wholeWordBtn.state  == NSControlStateValueOn ? NMFindWholeWord : 0)
         | (_regexBtn.state      == NSControlStateValueOn ? NMFindRegex     : 0);
}

@end
