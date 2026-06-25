#import "WindowController.h"
#import "EditorViewController.h"
#import "FindReplacePanel.h"
#import "FindInFilesPanel.h"
#import "CommandPalettePanel.h"
#import "Document.h"
#import "LexerManager.h"

@interface WindowController () <NSTabViewDelegate, EditorViewControllerDelegate>
@end

static NSString *const kRecentFilesKey = @"RecentFiles";
static const NSInteger kMaxRecentFiles = 10;

@implementation WindowController {
    NSTabView             *_tabView;
    NSTextField           *_statusLabel;
    FindReplacePanel      *_findPanel;
    NSMutableArray<EditorViewController *> *_editors;
    NSMenu                *_recentFilesMenu;
}

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 900, 650);
    NSWindowStyleMask style = NSWindowStyleMaskTitled
                            | NSWindowStyleMaskClosable
                            | NSWindowStyleMaskMiniaturizable
                            | NSWindowStyleMaskResizable;
    NSWindow *win = [[NSWindow alloc] initWithContentRect:frame
                                                styleMask:style
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    win.title = @"NotepadMac";
    win.minSize = NSMakeSize(400, 300);
    [win center];

    self = [super initWithWindow:win];
    if (!self) return nil;
    _editors = [NSMutableArray array];
    [self buildUI];
    [self buildMenuBar];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(openFileAtLine:)
                                                 name:@"NMOpenFileAtLine"
                                               object:nil];
    return self;
}

// MARK: – UI Construction

- (void)buildUI {
    NSView *content = self.window.contentView;

    // Status bar at bottom
    NSView *statusBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, content.bounds.size.width, 22)];
    statusBar.autoresizingMask = NSViewWidthSizable;
    [content addSubview:statusBar];

    NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(0, 21, content.bounds.size.width, 1)];
    separator.boxType = NSBoxSeparator;
    separator.autoresizingMask = NSViewWidthSizable;
    [content addSubview:separator];

    _statusLabel = [NSTextField labelWithString:@"Ln 1, Col 1  |  UTF-8  |  Plain Text"];
    _statusLabel.frame = NSMakeRect(8, 2, content.bounds.size.width - 16, 18);
    _statusLabel.autoresizingMask = NSViewWidthSizable;
    _statusLabel.font = [NSFont systemFontOfSize:11];
    _statusLabel.textColor = NSColor.secondaryLabelColor;
    [statusBar addSubview:_statusLabel];

    // Tab view above status bar
    CGFloat tabH = content.bounds.size.height - 23;
    _tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 23, content.bounds.size.width, tabH)];
    _tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _tabView.tabViewType = NSTopTabsBezelBorder;
    _tabView.delegate = self;
    [content addSubview:_tabView];
}

// MARK: – Menu Bar

- (void)buildMenuBar {
    // Always build a fresh main menu — no NIB, so NSApp.mainMenu is nil at start.
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
    [NSApp setMainMenu:mainMenu];

    // ── App menu ──────────────────────────────────────────────────────────
    // The first top-level item is the application menu; its title is ignored
    // by macOS (it always shows the running app's name).
    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"Apple" action:nil keyEquivalent:@""];
    [mainMenu addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Apple"];
    appItem.submenu = appMenu;
    [appMenu addItemWithTitle:@"About NotepadMac"
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Hide NotepadMac"
                       action:@selector(hide:)
                keyEquivalent:@"h"];
    NSMenuItem *hideOthers = [appMenu addItemWithTitle:@"Hide Others"
                                                action:@selector(hideOtherApplications:)
                                         keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit NotepadMac" action:@selector(terminate:) keyEquivalent:@"q"];

    // ── File menu ─────────────────────────────────────────────────────────
    NSMenuItem *fileItem = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
    [mainMenu addItem:fileItem];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    fileItem.submenu = fileMenu;
    [fileMenu addItemWithTitle:@"New"   action:@selector(menuNew:)  keyEquivalent:@"n"].target = self;
    [fileMenu addItemWithTitle:@"Open…" action:@selector(menuOpen:) keyEquivalent:@"o"].target = self;

    // Open Recent submenu
    NSMenuItem *recentItem = [[NSMenuItem alloc] initWithTitle:@"Open Recent" action:nil keyEquivalent:@""];
    _recentFilesMenu = [[NSMenu alloc] initWithTitle:@"Open Recent"];
    recentItem.submenu = _recentFilesMenu;
    [fileMenu addItem:recentItem];
    [self rebuildRecentFilesMenu];

    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Save"  action:@selector(menuSave:) keyEquivalent:@"s"].target = self;
    NSMenuItem *saveAs = [fileMenu addItemWithTitle:@"Save As…"
                                             action:@selector(menuSaveAs:)
                                      keyEquivalent:@"S"];   // ⇧⌘S
    saveAs.target = self;
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Close Tab"
                        action:@selector(menuCloseTab:)
                 keyEquivalent:@"w"].target = self;

    // ── Edit menu ─────────────────────────────────────────────────────────
    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
    [mainMenu addItem:editItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    editItem.submenu = editMenu;
    // Undo/Redo go through the responder chain to the first responder (ScintillaView handles them)
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem *redo = [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut"        action:@selector(cut:)       keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy"       action:@selector(copy:)      keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste"      action:@selector(paste:)     keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Find…"          action:@selector(menuFind:)        keyEquivalent:@"f"].target = self;
    NSMenuItem *fif = [editMenu addItemWithTitle:@"Find in Files…"
                                          action:@selector(menuFindInFiles:)
                                   keyEquivalent:@"F"];  // ⇧⌘F
    fif.target = self;
    [editMenu addItemWithTitle:@"Go to Line…"  action:@selector(menuGoToLine:)  keyEquivalent:@"g"].target = self;

    // ── View menu ─────────────────────────────────────────────────────────
    NSMenuItem *viewItem = [[NSMenuItem alloc] initWithTitle:@"View" action:nil keyEquivalent:@""];
    [mainMenu addItem:viewItem];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    viewItem.submenu = viewMenu;
    [viewMenu addItemWithTitle:@"Increase Font Size" action:@selector(menuFontBigger:)  keyEquivalent:@"+"].target = self;
    [viewMenu addItemWithTitle:@"Decrease Font Size" action:@selector(menuFontSmaller:) keyEquivalent:@"-"].target = self;
    [viewMenu addItemWithTitle:@"Reset Font Size"    action:@selector(menuFontReset:)   keyEquivalent:@"0"].target = self;
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Word Wrap" action:@selector(menuToggleWrap:) keyEquivalent:@""].target = self;
    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *palette = [viewMenu addItemWithTitle:@"Command Palette"
                                              action:@selector(menuCommandPalette:)
                                       keyEquivalent:@"P"];   // ⌘⇧P
    palette.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    palette.target = self;

    // ── Window menu ───────────────────────────────────────────────────────
    NSMenuItem *winItem = [[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""];
    [mainMenu addItem:winItem];
    NSMenu *winMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    winItem.submenu = winMenu;
    [winMenu addItemWithTitle:@"Minimize" action:@selector(miniaturize:) keyEquivalent:@"m"];
    [winMenu addItemWithTitle:@"Zoom"     action:@selector(zoom:)        keyEquivalent:@""];
    [NSApp setWindowsMenu:winMenu];
}

// MARK: – Tab management

- (void)newDocument {
    Document *doc = [[Document alloc] initUntitled];
    [self openDocument:doc];
}

- (void)openDocument:(Document *)document {
    EditorViewController *evc = [[EditorViewController alloc] initWithDocument:document];
    evc.delegate = self;
    [_editors addObject:evc];

    // Force the view to load before touching NSTabViewItem so any Scintilla
    // init happens in a clean context, not inside NSTabViewItem's setter.
    NSView *editorView = evc.view;

    // Store evc as identifier so we can retrieve it later without .viewController
    // (.viewController is nil when we set .view directly)
    NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:evc];
    item.label = document.displayName;
    item.view  = editorView;
    [_tabView addTabViewItem:item];
    [_tabView selectTabViewItem:item];
    [self updateTitle];
    // Give keyboard focus to the editor — viewDidAppear is not called for manually
    // embedded views, so we do this explicitly after the tab is selected.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.window makeFirstResponder:editorView];
    });

    if (document.fileURL) {
        [self addToRecentFiles:document.fileURL];
    }
}

- (EditorViewController *)currentEditor {
    NSTabViewItem *sel = _tabView.selectedTabViewItem;
    if (![sel.identifier isKindOfClass:[EditorViewController class]]) return nil;
    return (EditorViewController *)sel.identifier;
}

- (void)closeTabAtIndex:(NSInteger)idx {
    if (_tabView.numberOfTabViewItems == 0) return;
    if (idx == NSNotFound || idx < 0 || idx >= _tabView.numberOfTabViewItems) return;
    NSTabViewItem *item = [_tabView tabViewItemAtIndex:idx];
    if (![item.identifier isKindOfClass:[EditorViewController class]]) return;
    EditorViewController *evc = (EditorViewController *)item.identifier;

    if (evc.document.hasUnsavedChanges) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = [NSString stringWithFormat:@"Save changes to \"%@\"?", evc.document.displayName];
        alert.informativeText = @"Your changes will be lost if you don't save them.";
        [alert addButtonWithTitle:@"Save"];
        [alert addButtonWithTitle:@"Don't Save"];
        [alert addButtonWithTitle:@"Cancel"];
        NSModalResponse r = [alert runModal];
        if (r == NSAlertFirstButtonReturn) {
            [self saveDocument:evc];
        } else if (r == NSAlertThirdButtonReturn) {
            return;
        }
    }

    [_editors removeObject:evc];
    [_tabView removeTabViewItem:item];

    if (_tabView.numberOfTabViewItems == 0) {
        [self newDocument];
    }
}

// MARK: – Menu actions

- (IBAction)menuNew:(id)sender    { [self newDocument]; }

- (IBAction)menuOpen:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = YES;
    if ([panel runModal] == NSModalResponseOK) {
        for (NSURL *url in panel.URLs) {
            NSError *err;
            Document *doc = [[Document alloc] initWithURL:url error:&err];
            if (doc) {
                [self openDocument:doc];
            } else {
                [[NSAlert alertWithError:err] runModal];
            }
        }
    }
}

- (IBAction)menuSave:(id)sender {
    [self saveDocument:[self currentEditor]];
}

- (IBAction)menuSaveAs:(id)sender {
    EditorViewController *evc = [self currentEditor];
    if (!evc) return;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = evc.document.displayName;
    if ([panel runModal] == NSModalResponseOK) {
        evc.document.content = [evc currentContent];
        NSError *err;
        if (![evc.document saveToURL:panel.URL error:&err]) {
            [[NSAlert alertWithError:err] runModal];
        } else {
            [self updateCurrentTabTitle];
            [self updateTitle];
        }
    }
}

- (IBAction)menuCloseTab:(id)sender {
    NSInteger idx = [_tabView indexOfTabViewItem:_tabView.selectedTabViewItem];
    [self closeTabAtIndex:idx];
}

- (IBAction)menuFindInFiles:(id)sender {
    [[FindInFilesPanel shared] showPanel];
}

- (IBAction)menuCommandPalette:(id)sender {
    [[CommandPalettePanel shared] showOverWindow:self.window];
}

- (void)openFileAtLine:(NSNotification *)note {
    NSString *path = note.userInfo[@"path"];
    NSInteger line = [note.userInfo[@"line"] integerValue];
    if (!path) return;

    // Check if already open in a tab
    for (NSInteger i = 0; i < _tabView.numberOfTabViewItems; i++) {
        NSTabViewItem *item = [_tabView tabViewItemAtIndex:i];
        if (![item.identifier isKindOfClass:[EditorViewController class]]) continue;
        EditorViewController *evc = (EditorViewController *)item.identifier;
        if ([evc.document.fileURL.path isEqual:path]) {
            [_tabView selectTabViewItemAtIndex:i];
            [evc goToLine:line];
            return;
        }
    }
    // Not open yet — open it
    NSError *err;
    Document *doc = [[Document alloc] initWithURL:[NSURL fileURLWithPath:path] error:&err];
    if (doc) {
        [self openDocument:doc];
        EditorViewController *newEvc = [self currentEditor];
        // Defer goToLine: so Scintilla finishes its initial layout before we scroll
        dispatch_async(dispatch_get_main_queue(), ^{
            [newEvc goToLine:line];
        });
    } else if (err) {
        [[NSAlert alertWithError:err] runModal];
    }
}

- (IBAction)menuFind:(id)sender {
    EditorViewController *evc = [self currentEditor];
    if (!evc) return;
    if (!_findPanel) {
        _findPanel = [[FindReplacePanel alloc] initForEditor:evc];
    }
    _findPanel.editor = evc;
    [_findPanel makeKeyAndOrderFront:nil];
}

- (IBAction)menuFontBigger:(id)sender  { [[self currentEditor] changeFontSize:+1]; }
- (IBAction)menuFontSmaller:(id)sender { [[self currentEditor] changeFontSize:-1]; }
- (IBAction)menuFontReset:(id)sender   { [[self currentEditor] changeFontSize:0];  }

- (IBAction)menuToggleWrap:(id)sender {
    EditorViewController *evc = [self currentEditor];
    if (!evc) return;
    [evc toggleWordWrap];
    // Update checkmark
    NSMenuItem *item = (NSMenuItem *)sender;
    item.state = evc.wordWrap ? NSControlStateValueOn : NSControlStateValueOff;
}

// MARK: – Helpers

- (void)saveDocument:(EditorViewController *)evc {
    if (!evc) return;
    if (!evc.document.fileURL) {
        [self menuSaveAs:nil];
        return;
    }
    evc.document.content = [evc currentContent];
    NSError *err;
    if (![evc.document save:&err]) {
        [[NSAlert alertWithError:err] runModal];
    } else {
        [self updateCurrentTabTitle];
    }
}

- (void)updateCurrentTabTitle {
    NSTabViewItem *sel = _tabView.selectedTabViewItem;
    if (!sel) return;
    EditorViewController *evc = (EditorViewController *)sel.identifier;
    NSString *name = evc.document.displayName;
    sel.label = evc.document.hasUnsavedChanges ? [name stringByAppendingString:@" •"] : name;
}

- (void)updateTitle {
    EditorViewController *evc = [self currentEditor];
    self.window.title = evc ? evc.document.displayName : @"NotepadMac";
}

- (void)updateStatusBar {
    EditorViewController *evc = [self currentEditor];
    if (!evc) return;
    NSString *lang = [[LexerManager shared] languageNameForExtension:
                      evc.document.fileURL.pathExtension ?: @""];
    NSString *enc  = [NSString localizedNameOfStringEncoding:evc.document.encoding];
    _statusLabel.stringValue = [NSString stringWithFormat:
        @"Ln %ld, Col %ld  |  %@  |  %@  |  Lines: %ld",
        (long)[evc currentLine], (long)[evc currentColumn],
        enc, lang, (long)[evc totalLines]];
}


// MARK: – Session

- (void)saveSession {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSInteger i = 0; i < _tabView.numberOfTabViewItems; i++) {
        NSTabViewItem *item = [_tabView tabViewItemAtIndex:i];
        EditorViewController *evc = (EditorViewController *)item.identifier;
        if (evc.document.fileURL) {
            [paths addObject:evc.document.fileURL.path];
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:paths forKey:@"SessionFiles"];
}

// MARK: – Go to Line

- (IBAction)menuGoToLine:(id)sender {
    EditorViewController *evc = [self currentEditor];
    if (!evc) return;

    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Go to Line";
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 180, 24)];
    input.placeholderString = [NSString stringWithFormat:@"1 – %ld", (long)[evc totalLines]];
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"Go"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert.window makeFirstResponder:input];

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSInteger line = input.integerValue;
        if (line > 0) [evc goToLine:line];
    }
}

// MARK: – Recent Files

- (void)addToRecentFiles:(NSURL *)url {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSMutableArray *paths = [([ud arrayForKey:kRecentFilesKey] ?: @[]) mutableCopy];
    [paths removeObject:url.path];
    [paths insertObject:url.path atIndex:0];
    if ((NSInteger)paths.count > kMaxRecentFiles) [paths removeLastObject];
    [ud setObject:paths forKey:kRecentFilesKey];
    [self rebuildRecentFilesMenu];
}

- (void)rebuildRecentFilesMenu {
    [_recentFilesMenu removeAllItems];
    NSArray *paths = [[NSUserDefaults standardUserDefaults] arrayForKey:kRecentFilesKey] ?: @[];
    if (paths.count == 0) {
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"No Recent Files" action:nil keyEquivalent:@""];
        empty.enabled = NO;
        [_recentFilesMenu addItem:empty];
        return;
    }
    for (NSString *path in paths) {
        NSString *title = path.lastPathComponent;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(menuOpenRecent:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = path;
        item.toolTip = path;
        [_recentFilesMenu addItem:item];
    }
    [_recentFilesMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *clear = [[NSMenuItem alloc] initWithTitle:@"Clear Recent Files" action:@selector(menuClearRecents:) keyEquivalent:@""];
    clear.target = self;
    [_recentFilesMenu addItem:clear];
}

- (IBAction)menuOpenRecent:(NSMenuItem *)sender {
    NSString *path = sender.representedObject;
    NSURL *url = [NSURL fileURLWithPath:path];
    [self openFileURL:url];
}

- (IBAction)menuClearRecents:(id)sender {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kRecentFilesKey];
    [self rebuildRecentFilesMenu];
}

- (void)openFileURL:(NSURL *)url {
    NSError *err;
    Document *doc = [[Document alloc] initWithURL:url error:&err];
    if (doc) {
        [self openDocument:doc];
    } else if (err) {
        [[NSAlert alertWithError:err] runModal];
    }
}

// MARK: – NSTabViewDelegate

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    [self updateTitle];
    [self updateStatusBar];
    if (_findPanel.isVisible) {
        if ([tabViewItem.identifier isKindOfClass:[EditorViewController class]])
            _findPanel.editor = (EditorViewController *)tabViewItem.identifier;
    }
}

// MARK: – EditorViewControllerDelegate

- (void)editorDidChangeContent:(EditorViewController *)editor {
    // Scintilla fires notifications during drawRect: (paint pass).
    // Any UI mutation (setLabel:, layout) must not happen inside a draw pass —
    // dispatch to the next runloop iteration to avoid the re-entrant layout crash.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateCurrentTabTitle];
        [self updateStatusBar];
    });
}

@end
