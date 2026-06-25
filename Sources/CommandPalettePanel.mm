#import "CommandPalettePanel.h"

// ── Command entry ─────────────────────────────────────────────────────────────

@interface CommandEntry : NSObject
@property (nonatomic, copy) NSString *title;       // e.g. "File > Save As…"
@property (nonatomic, copy) NSString *shortcut;    // e.g. "⌘S"
@property (nonatomic, weak) NSMenuItem *menuItem;
@property (nonatomic, assign) NSInteger score;     // fuzzy match score (higher = better)
@end

@implementation CommandEntry @end

// ── Panel ─────────────────────────────────────────────────────────────────────

static const CGFloat kPanelWidth  = 560;
static const CGFloat kRowHeight   = 36;
static const CGFloat kMaxVisible  = 10;
static const CGFloat kSearchHeight = 52;

@interface CommandPalettePanel ()
@end

@implementation CommandPalettePanel {
    NSTextField             *_searchField;
    NSTableView             *_tableView;
    NSScrollView            *_scrollView;

    NSArray<CommandEntry *> *_allCommands;   // full index
    NSMutableArray<CommandEntry *> *_filtered; // current display list
}

+ (instancetype)shared {
    static CommandPalettePanel *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[CommandPalettePanel alloc] initPalette]; });
    return s;
}

- (instancetype)initPalette {
    // Start with one row visible; we'll resize in showOverWindow:
    NSRect frame = NSMakeRect(0, 0, kPanelWidth, kSearchHeight + kRowHeight);
    self = [super initWithContentRect:frame
                            styleMask:NSWindowStyleMaskBorderless |
                                      NSWindowStyleMaskNonactivatingPanel
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (!self) return nil;

    self.level              = NSFloatingWindowLevel;
    self.opaque             = NO;
    self.backgroundColor    = NSColor.clearColor;
    self.hasShadow          = YES;
    self.delegate           = self;
    self.releasedWhenClosed = NO;
    self.movableByWindowBackground = NO;

    _filtered = [NSMutableArray array];
    [self buildContentView];
    return self;
}

// MARK: – Content view

- (void)buildContentView {
    // Container with rounded corners + system material
    NSVisualEffectView *vfx = [[NSVisualEffectView alloc]
                                initWithFrame:NSMakeRect(0, 0, kPanelWidth, kSearchHeight)];
    vfx.material      = NSVisualEffectMaterialHUDWindow;
    vfx.blendingMode  = NSVisualEffectBlendingModeBehindWindow;
    vfx.state         = NSVisualEffectStateActive;
    vfx.wantsLayer    = YES;
    vfx.layer.cornerRadius = 10;
    vfx.layer.masksToBounds = YES;
    vfx.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.contentView  = vfx;

    // Search field
    _searchField = [[NSTextField alloc] initWithFrame:
                    NSMakeRect(16, kSearchHeight - 44, kPanelWidth - 32, 32)];
    _searchField.placeholderString = @"Type a command…";
    _searchField.bordered          = NO;
    _searchField.drawsBackground   = NO;
    _searchField.focusRingType     = NSFocusRingTypeNone;
    _searchField.font              = [NSFont systemFontOfSize:18];
    _searchField.delegate          = self;
    _searchField.autoresizingMask  = NSViewWidthSizable;
    [vfx addSubview:_searchField];

    // Separator line
    NSBox *sep = [[NSBox alloc] initWithFrame:NSMakeRect(0, kSearchHeight - 46, kPanelWidth, 1)];
    sep.boxType          = NSBoxSeparator;
    sep.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [vfx addSubview:sep];

    // Scroll + table (initially hidden; appears when there are results)
    _scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, kPanelWidth, 0)];
    _scrollView.hasVerticalScroller   = YES;
    _scrollView.drawsBackground       = NO;
    _scrollView.autohidesScrollers    = YES;
    _scrollView.autoresizingMask      = NSViewWidthSizable | NSViewMinYMargin;
    [vfx addSubview:_scrollView];

    _tableView = [[NSTableView alloc] init];
    _tableView.dataSource          = self;
    _tableView.delegate            = self;
    _tableView.headerView          = nil;
    _tableView.backgroundColor     = NSColor.clearColor;
    _tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    _tableView.rowHeight           = kRowHeight;
    _tableView.intercellSpacing    = NSMakeSize(0, 0);

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"cmd"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:col];
    _tableView.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;

    _scrollView.documentView = _tableView;

    _tableView.action       = @selector(executeSelected:);
    _tableView.target       = self;
    _tableView.doubleAction = @selector(executeSelected:);
}

// MARK: – Show / hide

- (void)showOverWindow:(NSWindow *)parent {
    [self buildIndex];
    _searchField.stringValue = @"";
    [self filterWith:@""];

    // Size and center over parent
    [self resizeToFitResults];
    NSRect pf = parent.frame;
    NSPoint center = NSMakePoint(NSMidX(pf) - kPanelWidth / 2,
                                 NSMidY(pf) + 60);
    [self setFrameOrigin:center];

    [parent addChildWindow:self ordered:NSWindowAbove];
    [self makeKeyAndOrderFront:nil];
    [self.contentView.window makeFirstResponder:_searchField];
}

- (void)dismiss {
    [self.parentWindow removeChildWindow:self];
    [self orderOut:nil];
}

- (void)resizeToFitResults {
    NSInteger count   = MIN((NSInteger)_filtered.count, kMaxVisible);
    CGFloat tableH    = count * kRowHeight;
    CGFloat totalH    = kSearchHeight + tableH;

    NSRect frame      = self.frame;
    frame.origin.y   += frame.size.height - totalH;
    frame.size.height = totalH;
    [self setFrame:frame display:YES animate:NO];

    NSRect svFrame    = NSMakeRect(0, 0, kPanelWidth, tableH);
    _scrollView.frame = svFrame;
    [_tableView sizeLastColumnToFit];
}

// MARK: – Index building

- (void)buildIndex {
    NSMutableArray<CommandEntry *> *cmds = [NSMutableArray array];
    [self collectMenuItems:NSApp.mainMenu prefix:@"" into:cmds];
    _allCommands = [cmds copy];
}

- (void)collectMenuItems:(NSMenu *)menu prefix:(NSString *)prefix into:(NSMutableArray *)cmds {
    for (NSMenuItem *item in menu.itemArray) {
        if (item.isSeparatorItem) continue;
        NSString *title = item.title;
        if (!title.length) continue;
        NSString *fullTitle = prefix.length
            ? [NSString stringWithFormat:@"%@ › %@", prefix, title]
            : title;

        if (item.hasSubmenu) {
            [self collectMenuItems:item.submenu prefix:fullTitle into:cmds];
        } else if (item.action && item.isEnabled) {
            CommandEntry *e = [CommandEntry new];
            e.title    = fullTitle;
            e.shortcut = [self shortcutString:item];
            e.menuItem = item;
            [cmds addObject:e];
        }
    }
}

- (NSString *)shortcutString:(NSMenuItem *)item {
    if (!item.keyEquivalent.length) return @"";
    NSEventModifierFlags mods = item.keyEquivalentModifierMask;
    NSMutableString *s = [NSMutableString string];
    if (mods & NSEventModifierFlagControl)  [s appendString:@"⌃"];
    if (mods & NSEventModifierFlagOption)   [s appendString:@"⌥"];
    if (mods & NSEventModifierFlagShift)    [s appendString:@"⇧"];
    if (mods & NSEventModifierFlagCommand)  [s appendString:@"⌘"];
    [s appendString:item.keyEquivalent.uppercaseString];
    return s;
}

// MARK: – Fuzzy filtering

- (void)filterWith:(NSString *)query {
    if (query.length == 0) {
        // Show all, sorted by menu order
        NSMutableArray *all = [_allCommands mutableCopy];
        for (CommandEntry *e in all) e.score = 0;
        _filtered = all;
    } else {
        NSMutableArray<CommandEntry *> *matches = [NSMutableArray array];
        for (CommandEntry *e in _allCommands) {
            NSInteger score = [self fuzzyScore:query in:e.title];
            if (score > 0) {
                e.score = score;
                [matches addObject:e];
            }
        }
        [matches sortUsingComparator:^NSComparisonResult(CommandEntry *a, CommandEntry *b) {
            if (b.score > a.score) return NSOrderedAscending;
            if (b.score < a.score) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        _filtered = matches;
    }

    [_tableView reloadData];
    if (_filtered.count > 0) [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                                      byExtendingSelection:NO];
    [self resizeToFitResults];
}

/// Simple fuzzy scorer: consecutive matches score higher, case-insensitive.
- (NSInteger)fuzzyScore:(NSString *)query in:(NSString *)target {
    NSString *q = query.lowercaseString;
    NSString *t = target.lowercaseString;
    NSInteger qi = 0, score = 0, consecutive = 0;
    NSInteger qLen = (NSInteger)q.length;
    NSInteger tLen = (NSInteger)t.length;

    for (NSInteger ti = 0; ti < tLen && qi < qLen; ti++) {
        if ([t characterAtIndex:(NSUInteger)ti] == [q characterAtIndex:(NSUInteger)qi]) {
            score += 1 + consecutive * 2; // bonus for consecutive chars
            consecutive++;
            qi++;
        } else {
            consecutive = 0;
        }
    }
    return (qi == qLen) ? score : 0; // must match all query chars
}

// MARK: – Execution

- (void)executeSelected:(id)sender {
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)_filtered.count) return;
    CommandEntry *e = _filtered[row];
    [self dismiss];
    // Fire through responder chain, just like the real menu item would
    if (e.menuItem.action) {
        [NSApp sendAction:e.menuItem.action to:e.menuItem.target from:e.menuItem];
    }
}

// MARK: – NSTextFieldDelegate

- (void)controlTextDidChange:(NSNotification *)note {
    [self filterWith:_searchField.stringValue];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)tv
        doCommandBySelector:(SEL)cmd {
    if (cmd == @selector(cancelOperation:)) {   // Escape
        [self dismiss]; return YES;
    }
    if (cmd == @selector(insertNewline:)) {     // Return
        [self executeSelected:nil]; return YES;
    }
    if (cmd == @selector(moveUp:)) {
        NSInteger row = _tableView.selectedRow - 1;
        if (row >= 0) {
            [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                    byExtendingSelection:NO];
            [_tableView scrollRowToVisible:row];
        }
        return YES;
    }
    if (cmd == @selector(moveDown:)) {
        NSInteger row = _tableView.selectedRow + 1;
        if (row < (NSInteger)_filtered.count) {
            [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                    byExtendingSelection:NO];
            [_tableView scrollRowToVisible:row];
        }
        return YES;
    }
    return NO;
}

// MARK: – NSWindowDelegate

- (void)windowDidResignKey:(NSNotification *)note {
    [self dismiss];
}

// MARK: – NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    return (NSInteger)_filtered.count;
}

// MARK: – NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    CommandEntry *e = _filtered[row];

    NSTableCellView *cell = [tv makeViewWithIdentifier:@"cmd" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] init];
        cell.identifier = @"cmd";

        // Title label
        NSTextField *title = [NSTextField labelWithString:@""];
        title.identifier = @"title";
        title.font = [NSFont systemFontOfSize:13];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:title];
        cell.textField = title;

        // Shortcut label (right-aligned)
        NSTextField *sc = [NSTextField labelWithString:@""];
        sc.identifier = @"shortcut";
        sc.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
        sc.textColor = NSColor.tertiaryLabelColor;
        sc.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:sc];

        NSDictionary *views = @{@"t": title, @"s": sc};
        [cell addConstraints:[NSLayoutConstraint
            constraintsWithVisualFormat:@"H:|-12-[t]-(>=8)-[s]-12-|"
            options:NSLayoutFormatAlignAllCenterY metrics:nil views:views]];
        [NSLayoutConstraint activateConstraints:@[
            [title.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }

    NSTextField *shortcutLabel = nil;
    for (NSView *v in cell.subviews) {
        if ([v.identifier isEqualToString:@"shortcut"]) {
            shortcutLabel = (NSTextField *)v; break;
        }
    }

    cell.textField.stringValue = e.title;
    shortcutLabel.stringValue  = e.shortcut ?: @"";
    return cell;
}

- (CGFloat)tableView:(NSTableView *)tv heightOfRow:(NSInteger)row {
    return kRowHeight;
}

- (BOOL)tableView:(NSTableView *)tv shouldSelectRow:(NSInteger)row {
    return YES;
}

@end
