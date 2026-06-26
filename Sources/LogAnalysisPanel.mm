#import "LogAnalysisPanel.h"
#import "LogParser.h"

// ── Row model ─────────────────────────────────────────────────────────────────

@interface NMLogRow : NSObject
@property (nonatomic, assign) NSInteger lineNumber;
@property (nonatomic, copy)   NSString  *vendor;
@property (nonatomic, copy)   NSString  *rawLine;
// Flat dict of every scalar value extracted (network sub-dict is flattened in)
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *fields;
@end
@implementation NMLogRow @end

// ── Detail popover ────────────────────────────────────────────────────────────

@interface NMLogDetailController : NSViewController
- (void)showRow:(NMLogRow *)row;
@end

@implementation NMLogDetailController {
    NSTextView *_textView;
}
- (void)loadView {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,420,300)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSNoBorder;
    _textView = [[NSTextView alloc] initWithFrame:scroll.bounds];
    _textView.editable = NO;
    _textView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    _textView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.documentView = _textView;
    self.view = scroll;
}
- (void)showRow:(NMLogRow *)row {
    NSMutableString *s = [NSMutableString stringWithFormat:@"Zeile %ld  [%@]\n\n",
                          (long)row.lineNumber, row.vendor];
    for (NSString *k in [row.fields.allKeys sortedArrayUsingSelector:@selector(compare:)])
        [s appendFormat:@"%-24s %@\n", k.UTF8String, row.fields[k]];
    _textView.string = s;
}
@end

// ── Fixed columns (always shown) ──────────────────────────────────────────────

// Each entry: { identifier, title, width }
static NSArray<NSArray *> *NMFixedColumns(void) {
    return @[
        @[@"_line",      @"Zeile",      @48 ],
        @[@"_vendor",    @"Vendor",     @80 ],
        @[@"timestamp",  @"Zeitstempel",@140],
        @[@"action",     @"Aktion",     @70 ],
        @[@"srcip",      @"Quell-IP",   @110],
        @[@"srcport",    @"Q-Port",     @55 ],
        @[@"dstip",      @"Ziel-IP",    @110],
        @[@"dstport",    @"Z-Port",     @55 ],
    ];
}

// ── Panel ─────────────────────────────────────────────────────────────────────

@implementation LogAnalysisPanel {
    NSTableView              *_tableView;
    NSTextField              *_statusLabel;
    NSTextField              *_filterField;
    NSButton                 *_parseBtn;
    NSButton                 *_columnsBtn;

    NSMutableArray<NMLogRow *> *_allRows;
    NSMutableArray<NMLogRow *> *_filteredRows;

    // All optional column keys seen in parsed data (sorted)
    NSMutableOrderedSet<NSString *> *_availableOptKeys;
    // Currently active optional column identifiers
    NSMutableOrderedSet<NSString *> *_activeOptKeys;

    NSString                 *_currentText;
    NSString                 *_currentPath;

    NSPopover                *_detailPopover;
    NMLogDetailController    *_detailCtrl;
}

+ (nonnull instancetype)shared {
    static LogAnalysisPanel *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[LogAnalysisPanel alloc] init]; });
    return instance;
}

- (instancetype)init {
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0,0,960,500)
                  styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable
                            |NSWindowStyleMaskResizable|NSWindowStyleMaskUtilityWindow
                    backing:NSBackingStoreBuffered defer:NO];
    panel.title = @"Log-Analyse";
    panel.minSize = NSMakeSize(600, 300);
    [panel center];
    self = [super initWithWindow:panel];
    if (!self) return nil;

    _allRows         = [NSMutableArray array];
    _filteredRows    = [NSMutableArray array];
    _availableOptKeys = [NSMutableOrderedSet orderedSet];
    _activeOptKeys   = [NSMutableOrderedSet orderedSet];

    [self buildUI];

    _detailCtrl    = [[NMLogDetailController alloc] init];
    _detailPopover = [[NSPopover alloc] init];
    _detailPopover.contentViewController = _detailCtrl;
    _detailPopover.behavior = NSPopoverBehaviorTransient;

    return self;
}

- (void)showWithText:(NSString * _Nonnull)text filePath:(NSString * _Nullable)filePath {
    NSLog(@"[LogAnalysis] showWithText called, textLen=%lu path=%@",
          (unsigned long)text.length, filePath);
    _currentText = text;
    _currentPath = filePath;
    [self parseText:text];
    [self applyFilter];
    NSString *name = filePath.lastPathComponent ?: @"aktuelles Dokument";
    self.window.title = [NSString stringWithFormat:@"Log-Analyse — %@", name];
    NSLog(@"[LogAnalysis] window=%@ visible=%d", self.window, self.window.isVisible);
    [self showWindow:nil];
}

// MARK: – Parsing

// Flatten a parsed dict: scalar values kept, sub-dicts (like "network") flattened one level.
- (NSDictionary<NSString *, NSString *> *)flattenParsed:(NSDictionary<NSString *, id> *)parsed {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *k in parsed) {
        id v = parsed[k];
        if ([v isKindOfClass:[NSDictionary class]]) {
            [(NSDictionary *)v enumerateKeysAndObjectsUsingBlock:^(id k2, id v2, BOOL *s) {
                if ([v2 isKindOfClass:[NSString class]]) out[k2] = v2;
            }];
        } else if ([v isKindOfClass:[NSString class]]) {
            out[k] = v;
        }
    }
    return [out copy];
}

- (void)parseText:(NSString *)text {
    [_allRows removeAllObjects];
    [_availableOptKeys removeAllObjects];

    // Keys that are fixed columns — don't offer them as optional
    NSSet *fixedKeys = [NSSet setWithArray:@[
        @"timestamp", @"action", @"srcip", @"srcport", @"dstip", @"dstport"
    ]];

    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    NMLogParserRegistry *reg   = [NMLogParserRegistry shared];

    NSInteger lineNum = 0;
    for (NSString *raw in lines) {
        lineNum++;
        NSString *trimmed = [raw stringByTrimmingCharactersInSet:
                             NSCharacterSet.whitespaceCharacterSet];
        if (!trimmed.length) continue;

        NMLogRow *row  = [[NMLogRow alloc] init];
        row.lineNumber = lineNum;
        row.rawLine    = trimmed;

        NSString *matchedVendor = nil;
        NSDictionary<NSString *, id> *parsed = nil;
        for (id<NMLogParser> parser in reg.parsers) {
            if ([parser canParseLine:trimmed]) {
                matchedVendor = parser.vendorName;
                parsed = [parser parseLine:trimmed];
                break;
            }
        }

        if (parsed && matchedVendor) {
            row.vendor = matchedVendor;
            NSMutableDictionary *flat = [[self flattenParsed:parsed] mutableCopy];
            row.fields = [flat copy];
        } else {
            row.vendor = @"—";
            // Fall back to generic key=value tokenizer so any log format exposes columns
            NMBaseLogParser *base = [[NMBaseLogParser alloc] init];
            NSDictionary *flat = [base parseKeyValuePairs:trimmed];
            row.fields = flat.count ? flat : @{ @"_raw": trimmed };
        }
        // Collect optional keys from whatever we parsed
        for (NSString *k in row.fields) {
            if (![fixedKeys containsObject:k] && ![k hasPrefix:@"_"])
                [_availableOptKeys addObject:k];
        }
        [_allRows addObject:row];
    }

    // Sort available optional keys alphabetically
    NSArray *sorted = [_availableOptKeys.array sortedArrayUsingSelector:@selector(compare:)];
    [_availableOptKeys removeAllObjects];
    [_availableOptKeys addObjectsFromArray:sorted];

    // Remove active optional keys that are no longer available
    NSMutableOrderedSet *toRemove = [NSMutableOrderedSet orderedSet];
    for (NSString *k in _activeOptKeys)
        if (![_availableOptKeys containsObject:k]) [toRemove addObject:k];
    [_activeOptKeys minusOrderedSet:toRemove];

    [self rebuildOptionalColumns];
}

// MARK: – Dynamic columns

- (void)rebuildOptionalColumns {
    // Remove all non-fixed columns
    NSMutableArray *toRemove = [NSMutableArray array];
    NSMutableSet *fixedIDs = [NSMutableSet set];
    for (NSArray *def in NMFixedColumns()) [fixedIDs addObject:def[0]];
    for (NSTableColumn *col in _tableView.tableColumns) {
        if (![fixedIDs containsObject:col.identifier]) [toRemove addObject:col];
    }
    for (NSTableColumn *col in toRemove) [_tableView removeTableColumn:col];

    // Add active optional columns
    for (NSString *key in _activeOptKeys) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:key];
        col.title = key;
        col.width    = 100;
        col.minWidth = 50;
        col.maxWidth = 400;
        col.resizingMask = NSTableColumnUserResizingMask;
        [_tableView addTableColumn:col];
    }
    [_tableView reloadData];
}

// MARK: – Filter

- (void)applyFilter {
    NSString *q = [_filterField.stringValue
                   stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
                   .lowercaseString;
    if (!q.length) {
        [_filteredRows setArray:_allRows];
    } else {
        [_filteredRows removeAllObjects];
        for (NMLogRow *r in _allRows) {
            __block BOOL hit = [r.vendor.lowercaseString containsString:q];
            if (!hit) {
                [r.fields enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
                    if ([v.lowercaseString containsString:q]) { hit = YES; *stop = YES; }
                }];
            }
            if (hit) [_filteredRows addObject:r];
        }
    }

    NSInteger parsed = 0;
    for (NMLogRow *r in _allRows) if (![r.vendor isEqualToString:@"—"]) parsed++;
    _statusLabel.stringValue = [NSString stringWithFormat:
        @"%ld erkannte Log-Zeilen von %ld  |  %ld angezeigt%@",
        (long)parsed, (long)_allRows.count, (long)_filteredRows.count,
        q.length ? [NSString stringWithFormat:@"  (Filter: \"%@\")", _filterField.stringValue] : @""];
    [_tableView reloadData];
}

// MARK: – UI

- (void)buildUI {
    NSView *cv = self.window.contentView;
    CGFloat W  = cv.bounds.size.width;
    CGFloat H  = cv.bounds.size.height;

    // ── Toolbar ───────────────────────────────────────────────────────────────
    CGFloat y = H - 36;

    NSTextField *lbl = [NSTextField labelWithString:@"Filter:"];
    lbl.frame = NSMakeRect(8, y+4, 40, 18);
    lbl.font  = [NSFont systemFontOfSize:12];
    [cv addSubview:lbl];

    _filterField = [[NSTextField alloc] initWithFrame:NSMakeRect(52, y, W - 260, 22)];
    _filterField.placeholderString = @"Vendor, IP, Port, Action, …";
    _filterField.bezelStyle = NSTextFieldSquareBezel;
    _filterField.bordered   = YES;
    _filterField.editable   = YES;
    _filterField.target     = self;
    _filterField.action     = @selector(filterChanged:);
    _filterField.autoresizingMask = NSViewWidthSizable;
    [cv addSubview:_filterField];

    _columnsBtn = [[NSButton alloc] initWithFrame:NSMakeRect(W - 200, y, 88, 22)];
    _columnsBtn.title      = @"Spalten …";
    _columnsBtn.target     = self;
    _columnsBtn.action     = @selector(showColumnsMenu:);
    _columnsBtn.bezelStyle = NSBezelStyleRounded;
    _columnsBtn.autoresizingMask = NSViewMinXMargin;
    [cv addSubview:_columnsBtn];

    _parseBtn = [[NSButton alloc] initWithFrame:NSMakeRect(W - 106, y, 98, 22)];
    _parseBtn.title      = @"Neu parsen";
    _parseBtn.target     = self;
    _parseBtn.action     = @selector(reparseAction:);
    _parseBtn.bezelStyle = NSBezelStyleRounded;
    _parseBtn.autoresizingMask = NSViewMinXMargin;
    [cv addSubview:_parseBtn];

    // ── Status ────────────────────────────────────────────────────────────────
    _statusLabel = [NSTextField labelWithString:@"Bereit."];
    _statusLabel.frame = NSMakeRect(8, 4, W-16, 18);
    _statusLabel.autoresizingMask = NSViewWidthSizable;
    _statusLabel.font = [NSFont systemFontOfSize:11];
    _statusLabel.textColor = NSColor.secondaryLabelColor;
    [cv addSubview:_statusLabel];

    // ── Table ─────────────────────────────────────────────────────────────────
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 24, W, H-62)];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = YES;
    scroll.borderType = NSNoBorder;

    _tableView = [[NSTableView alloc] initWithFrame:scroll.bounds];
    _tableView.dataSource = self;
    _tableView.delegate   = self;
    _tableView.allowsEmptySelection = YES;
    _tableView.usesAlternatingRowBackgroundColors = YES;
    _tableView.columnAutoresizingStyle = NSTableViewNoColumnAutoresizing;

    for (NSArray *def in NMFixedColumns()) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:def[0]];
        col.title = def[1];
        col.width    = [def[2] doubleValue];
        col.minWidth = [def[2] doubleValue] * 0.5;
        col.maxWidth = [def[2] doubleValue] * 4;
        col.resizingMask = NSTableColumnUserResizingMask;
        [_tableView addTableColumn:col];
    }

    _tableView.doubleAction = @selector(rowDoubleClicked:);
    _tableView.target = self;
    scroll.documentView = _tableView;
    [cv addSubview:scroll];
}

// MARK: – Actions

- (IBAction)filterChanged:(id)sender   { [self applyFilter]; }
- (IBAction)reparseAction:(id)sender {
    if (_currentText) { [self parseText:_currentText]; [self applyFilter]; }
}

- (IBAction)showColumnsMenu:(id)sender {
    if (!_availableOptKeys.count) {
        NSAlert *a = [NSAlert new];
        a.messageText = @"Keine optionalen Spalten verfügbar.";
        a.informativeText = @"Lade zuerst eine Log-Datei.";
        [a runModal];
        return;
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Spalten"];
    for (NSString *key in _availableOptKeys) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:key
                                                      action:@selector(toggleOptionalColumn:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = key;
        item.state = [_activeOptKeys containsObject:key]
                     ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:item];
    }

    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *all = [[NSMenuItem alloc] initWithTitle:@"Alle hinzufügen"
                                                 action:@selector(addAllOptionalColumns:)
                                          keyEquivalent:@""];
    all.target = self;
    [menu addItem:all];
    NSMenuItem *none = [[NSMenuItem alloc] initWithTitle:@"Alle entfernen"
                                                  action:@selector(removeAllOptionalColumns:)
                                           keyEquivalent:@""];
    none.target = self;
    [menu addItem:none];

    [menu popUpMenuPositioningItem:nil
                        atLocation:NSMakePoint(0, _columnsBtn.bounds.size.height)
                            inView:_columnsBtn];
}

- (IBAction)toggleOptionalColumn:(NSMenuItem *)item {
    NSString *key = item.representedObject;
    if ([_activeOptKeys containsObject:key])
        [_activeOptKeys removeObject:key];
    else
        [_activeOptKeys addObject:key];
    [self rebuildOptionalColumns];
}

- (IBAction)addAllOptionalColumns:(id)sender {
    [_activeOptKeys unionOrderedSet:_availableOptKeys];
    [self rebuildOptionalColumns];
}

- (IBAction)removeAllOptionalColumns:(id)sender {
    [_activeOptKeys removeAllObjects];
    [self rebuildOptionalColumns];
}

- (void)rowDoubleClicked:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row < 0 || row >= (NSInteger)_filteredRows.count) return;
    NMLogRow *r = _filteredRows[row];

    if (_currentPath.length) {
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"NMOpenFileAtLine"
                          object:nil
                        userInfo:@{@"path": _currentPath, @"line": @(r.lineNumber)}];
    }

    [_detailCtrl showRow:r];
    NSView *rowView = [_tableView rowViewAtRow:row makeIfNecessary:YES];
    if (rowView) {
        [_detailPopover showRelativeToRect:rowView.bounds
                                   ofView:rowView
                            preferredEdge:NSRectEdgeMaxY];
    }
}

// MARK: – NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    return (NSInteger)_filteredRows.count;
}

// MARK: – NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    NSString *ident = col.identifier;
    NMLogRow *r = _filteredRows[row];

    NSString *value;
    if ([ident isEqual:@"_line"])
        value = [NSString stringWithFormat:@"%ld", (long)r.lineNumber];
    else if ([ident isEqual:@"_vendor"])
        value = r.vendor;
    else
        value = r.fields[ident] ?: @"";

    NSTextField *cell = [tv makeViewWithIdentifier:ident owner:self];
    if (!cell) {
        cell = [NSTextField labelWithString:@""];
        cell.identifier = ident;
        BOOL mono = [@[@"_line",@"srcip",@"srcport",@"dstip",@"dstport",@"timestamp"]
                     containsObject:ident];
        cell.font = mono
            ? [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]
            : [NSFont systemFontOfSize:11];
    }
    cell.stringValue = value;

    // Color: action
    if ([ident isEqual:@"action"]) {
        NSString *lc = value.lowercaseString;
        if ([@[@"deny",@"block",@"drop"] containsObject:lc])
            cell.textColor = [NSColor colorWithRed:0.85 green:0.20 blue:0.20 alpha:1];
        else if ([@[@"accept",@"allow",@"permit"] containsObject:lc])
            cell.textColor = [NSColor colorWithRed:0.15 green:0.60 blue:0.25 alpha:1];
        else
            cell.textColor = NSColor.labelColor;
    } else if ([ident isEqual:@"_vendor"] && [value isEqual:@"—"]) {
        cell.textColor = NSColor.tertiaryLabelColor;
    } else {
        cell.textColor = NSColor.labelColor;
    }
    return cell;
}

- (CGFloat)tableView:(NSTableView *)tv heightOfRow:(NSInteger)row { return 18; }
- (BOOL)tableView:(NSTableView *)tv shouldSelectRow:(NSInteger)row { return YES; }

@end
