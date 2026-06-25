#import "FindReplacePanel.h"

@implementation FindReplacePanel {
    NSTextField *_findField;
    NSTextField *_replaceField;
    NSButton    *_matchCaseCheck;
    NSButton    *_wholeWordCheck;
    NSButton    *_findPrev;
    NSButton    *_findNext;
    NSButton    *_replaceAll;
    NSTextField *_statusLabel;
}

- (instancetype)initForEditor:(EditorViewController *)editor {
    self = [super initWithContentRect:NSMakeRect(0, 0, 460, 148)
                            styleMask:NSWindowStyleMaskTitled |
                                      NSWindowStyleMaskClosable |
                                      NSWindowStyleMaskUtilityWindow
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (!self) return nil;
    self.title = @"Find & Replace";
    self.floatingPanel = YES;
    self.editor = editor;
    [self buildUI];
    return self;
}

- (void)buildUI {
    NSView *v = self.contentView;
    CGFloat w = v.bounds.size.width;
    CGFloat pad = 14;

    auto label = ^NSTextField *(NSString *s, CGFloat x, CGFloat y) {
        NSTextField *f = [NSTextField labelWithString:s];
        f.frame = NSMakeRect(x, y, 70, 20);
        f.alignment = NSTextAlignmentRight;
        [v addSubview:f];
        return f;
    };
    auto field = ^NSTextField *(CGFloat x, CGFloat y, CGFloat fw) {
        NSTextField *f = [NSTextField textFieldWithString:@""];
        f.frame = NSMakeRect(x, y, fw, 22);
        [v addSubview:f];
        return f;
    };
    auto check = ^NSButton *(NSString *s, CGFloat x, CGFloat y) {
        NSButton *b = [NSButton checkboxWithTitle:s target:nil action:nil];
        b.frame = NSMakeRect(x, y, 120, 20);
        [v addSubview:b];
        return b;
    };
    auto btn = ^NSButton *(NSString *s, CGFloat x, CGFloat y, CGFloat bw, id tgt, SEL act) {
        NSButton *b = [NSButton buttonWithTitle:s target:tgt action:act];
        b.frame = NSMakeRect(x, y, bw, 28);
        [v addSubview:b];
        return b;
    };

    CGFloat fieldW = w - pad - 90 - pad;
    label(@"Find:", pad, 110);
    _findField = field(pad + 76, 108, fieldW);

    label(@"Replace:", pad, 78);
    _replaceField = field(pad + 76, 76, fieldW);

    _matchCaseCheck = check(@"Match case",   pad,       50);
    _wholeWordCheck  = check(@"Whole word",   pad + 130, 50);

    _findPrev   = btn(@"◀ Prev",    pad,           16, 80,  self, @selector(findPrev:));
    _findNext   = btn(@"Next ▶",    pad + 86,      16, 80,  self, @selector(findNext:));
    _replaceAll = btn(@"Replace All", pad + 176,   16, 110, self, @selector(replaceAll:));

    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.frame = NSMakeRect(pad + 292, 20, w - pad - 292, 20);
    _statusLabel.textColor = NSColor.secondaryLabelColor;
    [v addSubview:_statusLabel];
}

- (BOOL)matchCase  { return _matchCaseCheck.state == NSControlStateValueOn; }
- (BOOL)wholeWord  { return _wholeWordCheck.state  == NSControlStateValueOn; }

- (IBAction)findNext:(id)sender {
    if (!_findField.stringValue.length) return;
    BOOL found = [self.editor findText:_findField.stringValue
                             matchCase:[self matchCase]
                             wholeWord:[self wholeWord]
                               forward:YES];
    _statusLabel.stringValue = found ? @"" : @"Not found";
}

- (IBAction)findPrev:(id)sender {
    if (!_findField.stringValue.length) return;
    BOOL found = [self.editor findText:_findField.stringValue
                             matchCase:[self matchCase]
                             wholeWord:[self wholeWord]
                               forward:NO];
    _statusLabel.stringValue = found ? @"" : @"Not found";
}

- (IBAction)replaceAll:(id)sender {
    if (!_findField.stringValue.length) return;
    NSInteger n = [self.editor replaceAll:_findField.stringValue
                                     with:_replaceField.stringValue
                                matchCase:[self matchCase]
                                wholeWord:[self wholeWord]];
    _statusLabel.stringValue = [NSString stringWithFormat:@"%ld replacement(s)", (long)n];
}

@end
