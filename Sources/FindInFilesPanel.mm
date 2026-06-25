#import "FindInFilesPanel.h"
#import "SearchEngine.h"

// ── Result-tree rows ──────────────────────────────────────────────────────────

@interface ResultRow : NSObject
@property (nonatomic, copy) NSString *filePath;   // non-nil → file header row
@property (nonatomic, strong) SearchResult *result; // non-nil → match row
@property (nonatomic, assign) BOOL isHeader;
@property (nonatomic, assign) BOOL expanded;
@property (nonatomic, assign) NSInteger childCount;
@end
@implementation ResultRow @end

// ── Panel ─────────────────────────────────────────────────────────────────────

@interface FindInFilesPanel ()
@end

@implementation FindInFilesPanel {
    // Search controls
    NSTextField   *_searchField;
    NSTextField   *_filterField;
    NSTextField   *_directoryField;
    NSButton      *_matchCaseCheck;
    NSButton      *_wholeWordCheck;
    NSButton      *_regexCheck;
    NSButton      *_recursiveCheck;
    NSButton      *_findButton;
    NSButton      *_cancelButton;
    NSButton      *_browseButton;

    // Results
    NSTableView   *_tableView;
    NSTextField   *_statusLabel;

    // State
    NSMutableArray<ResultRow *> *_rows;   // flat display list (headers + matches)
    NSMutableArray<FileResults *> *_fileResults;
    BOOL           _searching;
    BOOL           _cancelFlag;
}

+ (instancetype)shared {
    static FindInFilesPanel *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[FindInFilesPanel alloc] init]; });
    return instance;
}

- (instancetype)init {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 700, 520)
                                                styleMask:NSWindowStyleMaskTitled
                                                         |NSWindowStyleMaskClosable
                                                         |NSWindowStyleMaskResizable
                                                         |NSWindowStyleMaskUtilityWindow
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.title = @"Find in Files";
    panel.minSize = NSMakeSize(500, 380);
    [panel center];
    self = [super initWithWindow:panel];
    if (!self) return nil;
    _rows        = [NSMutableArray array];
    _fileResults = [NSMutableArray array];
    [self buildUI];
    return self;
}

- (void)showPanel {
    [self.window makeKeyAndOrderFront:nil];
}

// MARK: – UI

- (void)buildUI {
    NSView *cv = self.window.contentView;
    CGFloat W = cv.bounds.size.width;

    // ── Search row ────────────────────────────────────────────────────────────
    CGFloat y = cv.bounds.size.height - 36;

    [self label:@"Search:" at:NSMakePoint(8, y + 4) in:cv];
    _searchField = [self field:@"" frame:NSMakeRect(70, y, W - 170, 22) in:cv];
    _findButton  = [self button:@"Find All" action:@selector(startSearch:)
                          frame:NSMakeRect(W - 92, y, 84, 22) in:cv];
    _findButton.keyEquivalent = @"\r";

    // ── Directory row ─────────────────────────────────────────────────────────
    y -= 30;
    [self label:@"Folder:" at:NSMakePoint(8, y + 4) in:cv];
    _directoryField = [self field:NSHomeDirectory()
                            frame:NSMakeRect(70, y, W - 170, 22) in:cv];
    _browseButton   = [self button:@"…" action:@selector(browseDirectory:)
                             frame:NSMakeRect(W - 92, y, 30, 22) in:cv];
    _cancelButton   = [self button:@"Stop" action:@selector(cancelSearch:)
                             frame:NSMakeRect(W - 56, y, 48, 22) in:cv];
    _cancelButton.enabled = NO;

    // ── Filters row ───────────────────────────────────────────────────────────
    y -= 30;
    [self label:@"Filters:" at:NSMakePoint(8, y + 4) in:cv];
    _filterField = [self field:@"*.mm;*.h;*.py;*.js;*.ts;*.swift;*.rb;*.go;*.rs;*.c;*.cpp;*.txt;*.md"
                         frame:NSMakeRect(70, y, W - 170, 22) in:cv];

    // ── Option checkboxes ─────────────────────────────────────────────────────
    y -= 28;
    _matchCaseCheck = [self check:@"Match case"  frame:NSMakeRect(70,  y, 110, 18) in:cv];
    _wholeWordCheck = [self check:@"Whole word"  frame:NSMakeRect(188, y, 110, 18) in:cv];
    _regexCheck     = [self check:@"Regex"       frame:NSMakeRect(306, y,  80, 18) in:cv];
    _recursiveCheck = [self check:@"Recursive"   frame:NSMakeRect(394, y, 100, 18) in:cv];
    _recursiveCheck.state = NSControlStateValueOn;

    // ── Separator ─────────────────────────────────────────────────────────────
    y -= 12;
    NSBox *sep = [[NSBox alloc] initWithFrame:NSMakeRect(0, y, W, 1)];
    sep.boxType = NSBoxSeparator;
    sep.autoresizingMask = NSViewWidthSizable;
    [cv addSubview:sep];

    // ── Status label ─────────────────────────────────────────────────────────
    _statusLabel = [NSTextField labelWithString:@"Ready."];
    _statusLabel.frame = NSMakeRect(8, 4, W - 16, 18);
    _statusLabel.autoresizingMask = NSViewWidthSizable;
    _statusLabel.font = [NSFont systemFontOfSize:11];
    _statusLabel.textColor = NSColor.secondaryLabelColor;
    [cv addSubview:_statusLabel];

    // ── Results table ─────────────────────────────────────────────────────────
    CGFloat tableH = y - 28;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 24, W, tableH)];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSNoBorder;

    _tableView = [[NSTableView alloc] initWithFrame:scroll.bounds];
    _tableView.dataSource = self;
    _tableView.delegate   = self;
    _tableView.allowsEmptySelection = YES;
    _tableView.usesAlternatingRowBackgroundColors = NO;
    _tableView.headerView = nil;

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"result"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:col];
    _tableView.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;

    scroll.documentView = _tableView;
    [cv addSubview:scroll];

    // Double-click to open file at line
    _tableView.doubleAction = @selector(openResultAtRow:);
    _tableView.target = self;

    // Autoresize
    for (NSView *v in @[_searchField, _filterField, _directoryField]) {
        v.autoresizingMask = NSViewWidthSizable;
    }
    _findButton.autoresizingMask  = NSViewMinXMargin;
    _cancelButton.autoresizingMask = NSViewMinXMargin;
    _browseButton.autoresizingMask = NSViewMinXMargin;
}

// MARK: – Actions

- (IBAction)startSearch:(id)sender {
    NSString *term = _searchField.stringValue;
    if (term.length == 0) return;
    NSString *dir  = _directoryField.stringValue;
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
        _statusLabel.stringValue = @"Folder does not exist.";
        return;
    }

    SearchOptions *opts = [SearchOptions new];
    opts.searchText  = term;
    opts.matchCase   = _matchCaseCheck.state == NSControlStateValueOn;
    opts.wholeWord   = _wholeWordCheck.state == NSControlStateValueOn;
    opts.useRegex    = _regexCheck.state     == NSControlStateValueOn;
    opts.recursive   = _recursiveCheck.state == NSControlStateValueOn;
    opts.directory   = dir;
    opts.fileFilters = _filterField.stringValue.length ? _filterField.stringValue : @"*";

    [_fileResults removeAllObjects];
    [_rows removeAllObjects];
    [_tableView reloadData];

    _searching = YES;
    _cancelFlag = NO;
    _findButton.enabled   = NO;
    _cancelButton.enabled = YES;
    _statusLabel.stringValue = @"Searching…";

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSInteger totalFiles = 0;
        BOOL cancel = NO;

        NSArray<FileResults *> *results =
            [SearchEngine findInDirectory:dir
                                  options:opts
                            progressBlock:^(NSString *file, NSInteger hits) {
                                self->_statusLabel.stringValue =
                                    [NSString stringWithFormat:@"Found %ld hits… (%@)",
                                     (long)hits, file.lastPathComponent];
                            }
                               cancelFlag:&cancel
                        totalFilesScanned:&totalFiles];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_fileResults addObjectsFromArray:results];
            [self buildRows];
            [self->_tableView reloadData];

            NSInteger totalHits = 0;
            for (FileResults *fr in results) totalHits += fr.results.count;

            if (cancel) {
                self->_statusLabel.stringValue =
                    [NSString stringWithFormat:@"Cancelled. %ld hits in %ld files (%ld scanned).",
                     (long)totalHits, (long)results.count, (long)totalFiles];
            } else {
                self->_statusLabel.stringValue =
                    [NSString stringWithFormat:@"%ld hits in %ld files (%ld scanned).",
                     (long)totalHits, (long)results.count, (long)totalFiles];
            }
            self->_searching = NO;
            self->_findButton.enabled   = YES;
            self->_cancelButton.enabled = NO;
        });
    });
}

- (IBAction)cancelSearch:(id)sender {
    _cancelFlag = YES;
}

- (IBAction)browseDirectory:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles       = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.directoryURL = [NSURL fileURLWithPath:_directoryField.stringValue];
    if ([panel runModal] == NSModalResponseOK) {
        _directoryField.stringValue = panel.URL.path;
    }
}

- (void)openResultAtRow:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row < 0 || row >= (NSInteger)_rows.count) return;
    ResultRow *r = _rows[row];
    if (r.isHeader) {
        // Toggle expand/collapse
        [self toggleExpansionAt:row];
        return;
    }
    // Open file in editor
    NSString *path = r.result.filePath;
    NSInteger line = r.result.lineNumber;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
    // Notify WindowController to open file and jump to line
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"NMOpenFileAtLine"
                      object:nil
                    userInfo:@{@"path": path, @"line": @(line)}];
}

// MARK: – Row building (flat list with collapsible file headers)

- (void)buildRows {
    [_rows removeAllObjects];
    for (FileResults *fr in _fileResults) {
        ResultRow *header = [ResultRow new];
        header.filePath   = fr.filePath;
        header.isHeader   = YES;
        header.expanded   = YES;
        header.childCount = (NSInteger)fr.results.count;
        [_rows addObject:header];

        for (SearchResult *sr in fr.results) {
            ResultRow *rr  = [ResultRow new];
            rr.result      = sr;
            rr.isHeader    = NO;
            [_rows addObject:rr];
        }
    }
}

- (void)toggleExpansionAt:(NSInteger)headerIdx {
    ResultRow *header = _rows[headerIdx];
    if (!header.isHeader) return;
    header.expanded = !header.expanded;

    // Find the FileResults for this header
    FileResults *fr = nil;
    for (FileResults *f in _fileResults) {
        if ([f.filePath isEqual:header.filePath]) { fr = f; break; }
    }
    if (!fr) return;

    if (!header.expanded) {
        // Remove child rows right after the header
        NSRange childRange = NSMakeRange((NSUInteger)(headerIdx + 1), (NSUInteger)fr.results.count);
        [_rows removeObjectsInRange:childRange];
    } else {
        // Re-insert child rows
        NSMutableArray *children = [NSMutableArray array];
        for (SearchResult *sr in fr.results) {
            ResultRow *rr = [ResultRow new];
            rr.result     = sr;
            rr.isHeader   = NO;
            [children addObject:rr];
        }
        NSIndexSet *idxs = [NSIndexSet indexSetWithIndexesInRange:
                            NSMakeRange((NSUInteger)(headerIdx + 1), children.count)];
        [_rows insertObjects:children atIndexes:idxs];
    }
    [_tableView reloadData];
}

// MARK: – NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    return (NSInteger)_rows.count;
}

// MARK: – NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    ResultRow *r = _rows[row];

    if (r.isHeader) {
        NSTextField *cell = [tv makeViewWithIdentifier:@"header" owner:self];
        if (!cell) {
            cell = [NSTextField labelWithString:@""];
            cell.identifier = @"header";
            cell.font = [NSFont boldSystemFontOfSize:12];
        }
        NSString *displayPath = [r.filePath stringByAbbreviatingWithTildeInPath];
        cell.stringValue = [NSString stringWithFormat:@"%@ %@ (%ld)",
                            r.expanded ? @"▾" : @"▸", displayPath, (long)r.childCount];
        cell.textColor = NSColor.labelColor;
        return cell;
    }

    // Match row
    NSTextField *cell = [tv makeViewWithIdentifier:@"match" owner:self];
    if (!cell) {
        cell = [NSTextField labelWithString:@""];
        cell.identifier = @"match";
        cell.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    }

    NSString *prefix = [NSString stringWithFormat:@"  %4ld  ", (long)r.result.lineNumber];
    NSString *line   = [r.result.lineText stringByTrimmingCharactersInSet:
                        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    cell.stringValue = [prefix stringByAppendingString:line];
    cell.textColor   = NSColor.secondaryLabelColor;
    return cell;
}

- (CGFloat)tableView:(NSTableView *)tv heightOfRow:(NSInteger)row {
    return _rows[row].isHeader ? 22 : 19;
}

- (BOOL)tableView:(NSTableView *)tv shouldSelectRow:(NSInteger)row {
    return YES;
}

// MARK: – Helpers

- (NSTextField *)label:(NSString *)s at:(NSPoint)p in:(NSView *)v {
    NSTextField *f = [NSTextField labelWithString:s];
    f.frame = NSMakeRect(p.x, p.y, 60, 18);
    f.alignment = NSTextAlignmentRight;
    f.font = [NSFont systemFontOfSize:12];
    [v addSubview:f];
    return f;
}

- (NSTextField *)field:(NSString *)s frame:(NSRect)r in:(NSView *)v {
    NSTextField *f = [[NSTextField alloc] initWithFrame:r];
    f.stringValue = s;
    f.bezelStyle  = NSTextFieldSquareBezel;
    f.bordered    = YES;
    f.editable    = YES;
    [v addSubview:f];
    return f;
}

- (NSButton *)button:(NSString *)t action:(SEL)a frame:(NSRect)r in:(NSView *)v {
    NSButton *b = [[NSButton alloc] initWithFrame:r];
    b.title  = t;
    b.target = self;
    b.action = a;
    b.bezelStyle = NSBezelStyleRounded;
    [v addSubview:b];
    return b;
}

- (NSButton *)check:(NSString *)t frame:(NSRect)r in:(NSView *)v {
    NSButton *b = [NSButton checkboxWithTitle:t target:nil action:nil];
    b.frame = r;
    [v addSubview:b];
    return b;
}

@end
