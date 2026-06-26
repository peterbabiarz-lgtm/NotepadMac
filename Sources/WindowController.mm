#import "WindowController.h"
#import "EditorViewController.h"
#import "FindReplacePanel.h"
#import "FindInFilesPanel.h"
#import "CommandPalettePanel.h"
#import "CompareViewController.h"
#import "Document.h"
#import "LexerManager.h"
#import "TabBarView.h"
#import "FindBarView.h"
#import "LogAnalysisPanel.h"
#import "ConfigParser.h"
#include "Scintilla.h"

// MARK: – File-drop overlay (transparent, sits on top, passes through mouse clicks)

@protocol _NMDropTarget <NSObject>
- (void)openDroppedURLs:(NSArray<NSURL *> *)urls;
@end

@interface _NMDropView : NSView
@property (nonatomic, weak) id<_NMDropTarget> dropTarget;
@end

@implementation _NMDropView {
    BOOL _hovering;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    return self;
}

// Let all mouse clicks fall through to views below.
- (NSView *)hitTest:(NSPoint)point { return nil; }

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    if (![sender.draggingPasteboard canReadObjectForClasses:@[NSURL.class]
          options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}])
        return NSDragOperationNone;
    _hovering = YES;
    [self setNeedsDisplay:YES];
    return NSDragOperationCopy;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    _hovering = NO;
    [self setNeedsDisplay:YES];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    _hovering = NO;
    [self setNeedsDisplay:YES];
    NSArray<NSURL *> *urls = [sender.draggingPasteboard
        readObjectsForClasses:@[NSURL.class]
        options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    if (!urls.count) return NO;
    [_dropTarget openDroppedURLs:urls];
    return YES;
}

// Draw a subtle blue border while a file is being dragged over the window.
- (void)drawRect:(NSRect)dirtyRect {
    if (!_hovering) return;
    NSColor *highlight = [NSColor colorWithRed:0.20 green:0.50 blue:1.00 alpha:0.18];
    [highlight setFill];
    NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);
    [[NSColor colorWithRed:0.20 green:0.50 blue:1.00 alpha:0.70] setStroke];
    NSBezierPath *border = [NSBezierPath bezierPathWithRect:NSInsetRect(self.bounds, 2, 2)];
    border.lineWidth = 3;
    [border stroke];
}

@end

// MARK: –

@interface WindowController () <NSTabViewDelegate, EditorViewControllerDelegate, TabBarViewDelegate, _NMDropTarget, FindBarViewDelegate>
@end

static NSString *const kRecentFilesKey = @"RecentFiles";
static const NSInteger kMaxRecentFiles = 10;

static const CGFloat kFindBarH = 74.0;

// Returns the table of supported encodings: @[@(name), @(NSStringEncoding), @(hasBOM)]
static NSArray<NSArray *> *NMEncodingTable(void) {
    static NSArray *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = @[
            @[@"UTF-8",                        @(NSUTF8StringEncoding),              @NO],
            @[@"UTF-8 mit BOM",                @(NSUTF8StringEncoding),              @YES],
            @[@"UTF-16 LE",                    @(NSUTF16LittleEndianStringEncoding), @NO],
            @[@"UTF-16 BE",                    @(NSUTF16BigEndianStringEncoding),    @NO],
            @[@"ISO Latin-1 (ISO-8859-1)",     @(NSISOLatin1StringEncoding),         @NO],
            @[@"Windows-1252 (Westeuropa)",    @(NSWindowsCP1252StringEncoding),     @NO],
            @[@"Windows-1250 (Mitteleuropa)",  @(NSWindowsCP1250StringEncoding),     @NO],
            @[@"Windows-1251 (Kyrillisch)",    @(NSWindowsCP1251StringEncoding),     @NO],
            @[@"Shift-JIS",                    @(NSShiftJISStringEncoding),          @NO],
            @[@"EUC-JP",                       @(NSJapaneseEUCStringEncoding),       @NO],
            @[@"Mac Roman",                    @(NSMacOSRomanStringEncoding),        @NO],
        ];
    });
    return t;
}

static NSString *NMShortEncodingName(NSStringEncoding enc, BOOL bom) {
    for (NSArray *e in NMEncodingTable()) {
        if ([e[1] unsignedIntegerValue] == enc && [e[2] boolValue] == bom)
            return e[0];
    }
    return [NSString localizedNameOfStringEncoding:enc];
}

@implementation WindowController {
    NSTabView             *_tabView;
    TabBarView            *_tabBar;
    FindBarView           *_findBar;
    NSTextField           *_statusLabel;
    NSButton              *_encodingBtn;
    FindReplacePanel      *_findPanel;   // kept for legacy callers
    NSMutableArray<EditorViewController *> *_editors;
    NSMenu                *_recentFilesMenu;
    NSMutableArray        *_compareControllers;
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
    _compareControllers = [NSMutableArray array];
    [self buildUI];
    [self buildMenuBar];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(openFileAtLine:)
                                                 name:@"NMOpenFileAtLine"
                                               object:nil];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// MARK: – UI Construction

- (void)buildUI {
    NSView *content = self.window.contentView;
    CGFloat W = content.bounds.size.width;
    CGFloat H = content.bounds.size.height;

    // Status bar at bottom
    NSView *statusBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, W, 22)];
    statusBar.autoresizingMask = NSViewWidthSizable;
    [content addSubview:statusBar];

    NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(0, 21, W, 1)];
    separator.boxType = NSBoxSeparator;
    separator.autoresizingMask = NSViewWidthSizable;
    [content addSubview:separator];

    _statusLabel = [NSTextField labelWithString:@"Ln 1, Col 1  |  Plain Text  |  LF"];
    _statusLabel.frame = NSMakeRect(8, 2, W - 170, 18);
    _statusLabel.autoresizingMask = NSViewWidthSizable;
    _statusLabel.font = [NSFont systemFontOfSize:11];
    _statusLabel.textColor = NSColor.secondaryLabelColor;
    [statusBar addSubview:_statusLabel];

    _encodingBtn = [NSButton buttonWithTitle:@"UTF-8"
                                      target:self
                                      action:@selector(showEncodingMenu:)];
    _encodingBtn.frame = NSMakeRect(W - 158, 1, 154, 20);
    _encodingBtn.autoresizingMask = NSViewMinXMargin;
    _encodingBtn.bezelStyle = NSBezelStyleRounded;
    _encodingBtn.font = [NSFont systemFontOfSize:11];
    [statusBar addSubview:_encodingBtn];

    // Custom tab bar at top
    static const CGFloat kTabBarH = 33.0;
    _tabBar = [[TabBarView alloc] initWithFrame:NSMakeRect(0, H - kTabBarH, W, kTabBarH)];
    _tabBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _tabBar.delegate = self;
    [content addSubview:_tabBar];

    // Tab view between status bar and tab bar (no built-in tab chrome)
    CGFloat tvH = H - 23 - kTabBarH;
    _tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 23, W, tvH)];
    _tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _tabView.tabViewType = NSNoTabsNoBorder;
    _tabView.delegate = self;
    [content addSubview:_tabView];

    // Inline find bar (hidden by default, slides in above status bar)
    _findBar = [[FindBarView alloc] initWithFrame:NSMakeRect(0, 23, W, kFindBarH)];
    _findBar.autoresizingMask = NSViewWidthSizable;
    _findBar.delegate = self;
    _findBar.hidden = YES;
    [content addSubview:_findBar];

    // Transparent drop target on top — passes mouse clicks through via hitTest:nil
    _NMDropView *dropView = [[_NMDropView alloc] initWithFrame:content.bounds];
    dropView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    dropView.dropTarget = self;
    [content addSubview:dropView positioned:NSWindowAbove relativeTo:nil];
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
    [appMenu addItemWithTitle:@"Über NotepadMac"
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"NotepadMac ausblenden"
                       action:@selector(hide:)
                keyEquivalent:@"h"];
    NSMenuItem *hideOthers = [appMenu addItemWithTitle:@"Andere ausblenden"
                                                action:@selector(hideOtherApplications:)
                                         keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [appMenu addItemWithTitle:@"Alle einblenden" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"NotepadMac beenden" action:@selector(terminate:) keyEquivalent:@"q"];

    // ── File menu ─────────────────────────────────────────────────────────
    NSMenuItem *fileItem = [[NSMenuItem alloc] initWithTitle:@"Ablage" action:nil keyEquivalent:@""];
    [mainMenu addItem:fileItem];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"Ablage"];
    fileItem.submenu = fileMenu;
    [fileMenu addItemWithTitle:@"Neu"       action:@selector(menuNew:)  keyEquivalent:@"n"].target = self;
    [fileMenu addItemWithTitle:@"Öffnen…"   action:@selector(menuOpen:) keyEquivalent:@"o"].target = self;

    // Zuletzt geöffnet-Untermenü
    NSMenuItem *recentItem = [[NSMenuItem alloc] initWithTitle:@"Zuletzt geöffnet" action:nil keyEquivalent:@""];
    _recentFilesMenu = [[NSMenu alloc] initWithTitle:@"Zuletzt geöffnet"];
    recentItem.submenu = _recentFilesMenu;
    [fileMenu addItem:recentItem];
    [self rebuildRecentFilesMenu];

    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Sichern"         action:@selector(menuSave:) keyEquivalent:@"s"].target = self;
    NSMenuItem *saveAs = [fileMenu addItemWithTitle:@"Sichern unter…"
                                             action:@selector(menuSaveAs:)
                                      keyEquivalent:@"S"];   // ⇧⌘S
    saveAs.target = self;
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Tab schließen"
                        action:@selector(menuCloseTab:)
                 keyEquivalent:@"w"].target = self;

    // ── Edit menu ─────────────────────────────────────────────────────────
    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Bearbeiten" action:nil keyEquivalent:@""];
    [mainMenu addItem:editItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Bearbeiten"];
    editItem.submenu = editMenu;
    // Undo/Redo gehen durch die Responder-Chain (ScintillaView behandelt sie)
    [editMenu addItemWithTitle:@"Widerrufen" action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem *redo = [editMenu addItemWithTitle:@"Wiederholen" action:@selector(redo:) keyEquivalent:@"Z"];
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Ausschneiden" action:@selector(cut:)       keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Kopieren"     action:@selector(copy:)      keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Einsetzen"    action:@selector(paste:)     keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Alles auswählen" action:@selector(selectAll:) keyEquivalent:@"a"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Suchen…"              action:@selector(menuFind:)        keyEquivalent:@"f"].target = self;
    NSMenuItem *fif = [editMenu addItemWithTitle:@"In Dateien suchen…"
                                          action:@selector(menuFindInFiles:)
                                   keyEquivalent:@"F"];  // ⇧⌘F
    fif.target = self;
    [editMenu addItemWithTitle:@"Gehe zu Zeile…" action:@selector(menuGoToLine:) keyEquivalent:@"g"].target = self;

    // ── Format menu ───────────────────────────────────────────────────────
    NSMenuItem *fmtItem = [[NSMenuItem alloc] initWithTitle:@"Format" action:nil keyEquivalent:@""];
    [mainMenu addItem:fmtItem];
    NSMenu *fmtMenu = [[NSMenu alloc] initWithTitle:@"Format"];
    fmtItem.submenu = fmtMenu;

    NSMenuItem *eolParent = [[NSMenuItem alloc] initWithTitle:@"Zeilenenden" action:nil keyEquivalent:@""];
    NSMenu *eolMenu = [[NSMenu alloc] initWithTitle:@"Zeilenenden"];
    eolParent.submenu = eolMenu;
    [fmtMenu addItem:eolParent];
    [[eolMenu addItemWithTitle:@"Unix (LF)"        action:@selector(menuSetEolLF:)   keyEquivalent:@""] setTarget:self];
    [[eolMenu addItemWithTitle:@"Windows (CRLF)"   action:@selector(menuSetEolCRLF:) keyEquivalent:@""] setTarget:self];
    [[eolMenu addItemWithTitle:@"Classic Mac (CR)" action:@selector(menuSetEolCR:)   keyEquivalent:@""] setTarget:self];

    [fmtMenu addItem:[NSMenuItem separatorItem]];

    // Encoding → Convert submenu
    NSMenuItem *encConvParent = [[NSMenuItem alloc] initWithTitle:@"Kodierung konvertieren" action:nil keyEquivalent:@""];
    NSMenu *encConvMenu = [[NSMenu alloc] initWithTitle:@"Kodierung konvertieren"];
    encConvParent.submenu = encConvMenu;
    [fmtMenu addItem:encConvParent];
    [self addEncodingItemsToMenu:encConvMenu action:@selector(menuConvertToEncoding:)];

    // Encoding → Reload submenu
    NSMenuItem *encRldParent = [[NSMenuItem alloc] initWithTitle:@"Neu laden mit Kodierung" action:nil keyEquivalent:@""];
    NSMenu *encRldMenu = [[NSMenu alloc] initWithTitle:@"Neu laden mit Kodierung"];
    encRldParent.submenu = encRldMenu;
    [fmtMenu addItem:encRldParent];
    [self addEncodingItemsToMenu:encRldMenu action:@selector(menuReloadWithEncoding:)];

    // ── View menu ─────────────────────────────────────────────────────────
    NSMenuItem *viewItem = [[NSMenuItem alloc] initWithTitle:@"Darstellung" action:nil keyEquivalent:@""];
    [mainMenu addItem:viewItem];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"Darstellung"];
    viewItem.submenu = viewMenu;
    [viewMenu addItemWithTitle:@"Schrift vergrößern"    action:@selector(menuFontBigger:)  keyEquivalent:@"+"].target = self;
    [viewMenu addItemWithTitle:@"Schrift verkleinern"   action:@selector(menuFontSmaller:) keyEquivalent:@"-"].target = self;
    [viewMenu addItemWithTitle:@"Schriftgröße zurücksetzen" action:@selector(menuFontReset:) keyEquivalent:@"0"].target = self;
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Zeilenumbruch" action:@selector(menuToggleWrap:) keyEquivalent:@""].target = self;
    [viewMenu addItemWithTitle:@"Randspalte bei 80" action:@selector(menuToggleEdgeColumn:) keyEquivalent:@""].target = self;
    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *palette = [viewMenu addItemWithTitle:@"Befehlspalette"
                                              action:@selector(menuCommandPalette:)
                                       keyEquivalent:@"P"];   // ⌘⇧P
    palette.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    palette.target = self;
    [viewMenu addItem:[NSMenuItem separatorItem]];

    // Folding
    [viewMenu addItemWithTitle:@"Falten umschalten"
                        action:@selector(menuToggleFold:)
                 keyEquivalent:@"."].target = self;
    [viewMenu addItemWithTitle:@"Alle falten"
                        action:@selector(menuFoldAll:)
                 keyEquivalent:@""].target = self;
    [viewMenu addItemWithTitle:@"Alle entfalten"
                        action:@selector(menuUnfoldAll:)
                 keyEquivalent:@""].target = self;

    [viewMenu addItem:[NSMenuItem separatorItem]];

    // Column / block selection mode
    NSMenuItem *colMode = [viewMenu addItemWithTitle:@"Spaltenmodus (Blockauswahl)"
                                              action:@selector(menuToggleColumnMode:)
                                       keyEquivalent:@"b"];
    colMode.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    colMode.target = self;

    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Dateien vergleichen…" action:@selector(menuCompare:) keyEquivalent:@""].target = self;

    NSMenuItem *logAnalysis = [viewMenu addItemWithTitle:@"Log-Analyse…"
                                                  action:@selector(menuLogAnalysis:)
                                           keyEquivalent:@"l"];
    logAnalysis.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    logAnalysis.target = self;

    NSMenuItem *configAnalysis = [viewMenu addItemWithTitle:@"Konfig-Analyse…"
                                                     action:@selector(menuConfigAnalysis:)
                                              keyEquivalent:@"k"];
    configAnalysis.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    configAnalysis.target = self;

    // ── Window menu ───────────────────────────────────────────────────────
    NSMenuItem *winItem = [[NSMenuItem alloc] initWithTitle:@"Fenster" action:nil keyEquivalent:@""];
    [mainMenu addItem:winItem];
    NSMenu *winMenu = [[NSMenu alloc] initWithTitle:@"Fenster"];
    winItem.submenu = winMenu;
    [winMenu addItemWithTitle:@"Im Dock ablegen" action:@selector(miniaturize:) keyEquivalent:@"m"];
    [winMenu addItemWithTitle:@"Zoomen"          action:@selector(zoom:)        keyEquivalent:@""];
    [NSApp setWindowsMenu:winMenu];
}

// MARK: – Tab bar sync

- (void)syncTabBar {
    NSInteger count = _tabView.numberOfTabViewItems;
    NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithCapacity:count];
    for (NSInteger i = 0; i < count; i++) {
        NSTabViewItem *item = [_tabView tabViewItemAtIndex:i];
        [titles addObject:item.label ?: @"Unbenannt"];
    }
    _tabBar.tabTitles   = titles;
    NSInteger selIdx = [_tabView indexOfTabViewItem:_tabView.selectedTabViewItem];
    _tabBar.selectedIndex = (selIdx == NSNotFound) ? -1 : selIdx;
}

// MARK: – TabBarViewDelegate

- (void)tabBarView:(TabBarView *)bar didSelectIndex:(NSInteger)index {
    if (index < 0 || index >= _tabView.numberOfTabViewItems) return;
    // selectTabViewItemAtIndex: fires tabView:didSelectTabViewItem: synchronously,
    // which already calls syncTabBar — no second call needed.
    [_tabView selectTabViewItemAtIndex:index];
}

- (void)tabBarView:(TabBarView *)bar didCloseIndex:(NSInteger)index {
    [self closeTabAtIndex:index];
    [self syncTabBar];
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
    [self syncTabBar];
    [self updateTitle];

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
        if (r == NSAlertThirdButtonReturn) return;
        if (r == NSAlertFirstButtonReturn) {
            if (!evc.document.fileURL) {
                // Untitled doc: the close alert has ended, so we can safely run
                // the save panel now without nesting two runModal calls.
                NSSavePanel *panel = [NSSavePanel savePanel];
                panel.nameFieldStringValue = evc.document.displayName;
                if ([panel runModal] != NSModalResponseOK) return;
                evc.document.content = [evc currentContent];
                NSError *saveErr;
                if (![evc.document saveToURL:panel.URL error:&saveErr]) {
                    [[NSAlert alertWithError:saveErr] runModal];
                    return;
                }
            } else {
                evc.document.content = [evc currentContent];
                NSError *saveErr;
                if (![evc.document save:&saveErr]) {
                    [[NSAlert alertWithError:saveErr] runModal];
                    return;
                }
            }
        }
    }

    [_editors removeObject:evc];
    [_tabView removeTabViewItem:item];
    [self syncTabBar];

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
    _findBar.editor = evc;
    [self showFindBar];
    [_findBar focusFindField];
}

// MARK: – Find bar show/hide

- (void)showFindBar {
    if (!_findBar.hidden) return;
    _findBar.hidden = NO;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.15;
        NSRect tvFrame = _tabView.frame;
        tvFrame.size.height -= kFindBarH;
        [[_tabView animator] setFrame:tvFrame];
    }];
}

- (void)hideFindBar {
    if (_findBar.hidden) return;
    [[self currentEditor] clearSearchHighlights];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.15;
        NSRect tvFrame = _tabView.frame;
        tvFrame.size.height += kFindBarH;
        [[_tabView animator] setFrame:tvFrame];
    } completionHandler:^{
        _findBar.hidden = YES;
    }];
}

// MARK: – FindBarViewDelegate

- (void)findBar:(FindBarView *)bar findNext:(BOOL)forward {
    EditorViewController *evc = [self currentEditor];
    if (!evc) return;
    BOOL found = [evc findText:bar.findText options:bar.findOptions forward:forward];
    [bar setMatchCount:found ? [evc countMatches:bar.findText options:bar.findOptions] : 0];
}

- (void)findBar:(FindBarView *)bar replaceCurrent:(NSString *)replacement {
    EditorViewController *evc = [self currentEditor];
    if (!evc) return;
    [evc replaceCurrentAndFindNext:bar.findText replacement:replacement options:bar.findOptions];
    NSInteger count = [evc countMatches:bar.findText options:bar.findOptions];
    [bar setMatchCount:count];
    [self updateCurrentTabTitle];
}

- (void)findBar:(FindBarView *)bar replaceAll:(NSString *)replacement {
    EditorViewController *evc = [self currentEditor];
    if (!evc) return;
    NSInteger n = [evc replaceAll:bar.findText with:replacement options:bar.findOptions];
    dispatch_async(dispatch_get_main_queue(), ^{
        [bar setMatchCount:n > 0 ? n : 0];
    });
    [self updateCurrentTabTitle];
}

- (void)findBar:(FindBarView *)bar highlightAll:(NSString *)text {
    EditorViewController *evc = [self currentEditor];
    if (!evc) return;
    if (text.length == 0) {
        [evc clearSearchHighlights];
        [bar setMatchCount:-1];
        return;
    }
    NSInteger count = [evc countMatches:text options:bar.findOptions];
    [evc highlightAllMatches:text options:bar.findOptions];
    [bar setMatchCount:count];
}

- (void)findBarDidClose:(FindBarView *)bar {
    [self hideFindBar];
    [[self currentEditor] focusEditor];
}

- (IBAction)menuFontBigger:(id)sender  { [[self currentEditor] changeFontSize:+1]; }
- (IBAction)menuFontSmaller:(id)sender { [[self currentEditor] changeFontSize:-1]; }
- (IBAction)menuFontReset:(id)sender   { [[self currentEditor] changeFontSize:0];  }

- (IBAction)menuToggleWrap:(id)sender {
    EditorViewController *evc = [self currentEditor];
    if (!evc) return;
    [evc toggleWordWrap];
    NSMenuItem *item = (NSMenuItem *)sender;
    item.state = evc.wordWrap ? NSControlStateValueOn : NSControlStateValueOff;
}

- (IBAction)menuToggleEdgeColumn:(id)sender {
    EditorViewController *evc = [self currentEditor];
    if (!evc) return;
    BOOL next = !evc.showEdgeColumn;
    [evc setShowEdgeColumn:next column:80];
    NSMenuItem *item = (NSMenuItem *)sender;
    item.state = next ? NSControlStateValueOn : NSControlStateValueOff;
}

- (IBAction)menuSetEolLF:(id)sender   { [[self currentEditor] convertToEolMode:SC_EOL_LF]; }
- (IBAction)menuSetEolCRLF:(id)sender { [[self currentEditor] convertToEolMode:SC_EOL_CRLF]; }
- (IBAction)menuSetEolCR:(id)sender   { [[self currentEditor] convertToEolMode:SC_EOL_CR]; }

- (IBAction)menuFoldAll:(id)sender          { [[self currentEditor] foldAll]; }
- (IBAction)menuUnfoldAll:(id)sender        { [[self currentEditor] unfoldAll]; }
- (IBAction)menuToggleFold:(id)sender       { [[self currentEditor] toggleFoldAtCursor]; }

- (IBAction)menuToggleColumnMode:(id)sender {
    EditorViewController *evc = [self currentEditor];
    if (!evc) return;
    [evc setColumnMode:!evc.columnMode];
}

// Keep text in memory, change encoding for next save.
- (IBAction)menuConvertToEncoding:(NSMenuItem *)sender {
    NSArray *e = sender.representedObject;
    EditorViewController *evc = [self currentEditor];
    if (!evc) return;
    NSStringEncoding enc = [e[1] unsignedIntegerValue];
    BOOL bom = [e[2] boolValue];
    // Test live editor content, not the stale document snapshot.
    // canBeConvertedToEncoding: avoids materialising a full NSData copy.
    if (![[evc currentContent] canBeConvertedToEncoding:enc]) {
        NSAlert *a = [NSAlert new];
        a.messageText = @"Konvertierung nicht möglich";
        a.informativeText = [NSString stringWithFormat:
            @"Der Text enthält Zeichen, die in \"%@\" nicht darstellbar sind.", e[0]];
        [a runModal];
        return;
    }
    [evc.document setEncodingForNextSave:enc hasBOM:bom];
    [self updateCurrentTabTitle];
    [self updateStatusBar];
}

// Re-read the file from disk with the selected encoding.
- (IBAction)menuReloadWithEncoding:(NSMenuItem *)sender {
    NSArray *e = sender.representedObject;
    EditorViewController *evc = [self currentEditor];
    if (!evc) return;
    if (!evc.document.fileURL) {
        NSAlert *a = [NSAlert new];
        a.messageText = @"Kein Dateiname";
        a.informativeText = @"Ungespeicherte Dateien können nicht neu geladen werden.";
        [a runModal];
        return;
    }
    if (evc.document.hasUnsavedChanges) {
        NSAlert *a = [NSAlert new];
        a.messageText = @"Ungespeicherte Änderungen verwerfen?";
        a.informativeText = [NSString stringWithFormat:
            @"Die Datei wird mit der Kodierung \"%@\" neu geladen. Ungespeicherte Änderungen gehen verloren.", e[0]];
        [a addButtonWithTitle:@"Neu laden"];
        [a addButtonWithTitle:@"Abbrechen"];
        if ([a runModal] != NSAlertFirstButtonReturn) return;
    }
    NSStringEncoding enc = [e[1] unsignedIntegerValue];
    BOOL bom = [e[2] boolValue];
    NSError *err;
    if (![evc.document reloadWithEncoding:enc hasBOM:bom error:&err]) {
        [[NSAlert alertWithError:err] runModal];
        return;
    }
    [evc reloadContent];
    [self updateCurrentTabTitle];
    [self updateStatusBar];
}

// Populate a menu with one item per supported encoding. Checkmark and enabled
// state are resolved by validateMenuItem: when the menu is displayed.
- (void)addEncodingItemsToMenu:(NSMenu *)menu action:(SEL)action {
    for (NSArray *e in NMEncodingTable()) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:e[0] action:action keyEquivalent:@""];
        mi.target = self;
        mi.representedObject = e;
        [menu addItem:mi];
    }
}

// Show encoding menu from the status bar button.
- (IBAction)showEncodingMenu:(NSButton *)sender {
    if (![self currentEditor]) return;

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Kodierung"];

    NSMenuItem *convHeader = [[NSMenuItem alloc] initWithTitle:@"Konvertieren zu:" action:nil keyEquivalent:@""];
    convHeader.enabled = NO;
    [menu addItem:convHeader];
    [self addEncodingItemsToMenu:menu action:@selector(menuConvertToEncoding:)];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *rldHeader = [[NSMenuItem alloc] initWithTitle:@"Neu laden mit:" action:nil keyEquivalent:@""];
    rldHeader.enabled = NO;
    [menu addItem:rldHeader];
    [self addEncodingItemsToMenu:menu action:@selector(menuReloadWithEncoding:)];

    [menu popUpMenuPositioningItem:nil
                        atLocation:NSMakePoint(0, sender.bounds.size.height + 4)
                            inView:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL a = item.action;
    EditorViewController *evc = [self currentEditor];

    if (a == @selector(menuToggleEdgeColumn:)) {
        item.state = evc.showEdgeColumn ? NSControlStateValueOn : NSControlStateValueOff;
        return evc != nil;
    }
    if (a == @selector(menuToggleWrap:)) {
        item.state = evc.wordWrap ? NSControlStateValueOn : NSControlStateValueOff;
        return evc != nil;
    }
    if (a == @selector(menuSetEolLF:)) {
        item.state = (evc.eolMode == SC_EOL_LF) ? NSControlStateValueOn : NSControlStateValueOff;
        return evc != nil;
    }
    if (a == @selector(menuSetEolCRLF:)) {
        item.state = (evc.eolMode == SC_EOL_CRLF) ? NSControlStateValueOn : NSControlStateValueOff;
        return evc != nil;
    }
    if (a == @selector(menuSetEolCR:)) {
        item.state = (evc.eolMode == SC_EOL_CR) ? NSControlStateValueOn : NSControlStateValueOff;
        return evc != nil;
    }
    if (a == @selector(menuConvertToEncoding:)) {
        if (!evc) return NO;
        NSArray *e = item.representedObject;
        item.state = ([e[1] unsignedIntegerValue] == evc.document.encoding
                      && [e[2] boolValue] == evc.document.hasBOM)
                     ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if (a == @selector(menuReloadWithEncoding:)) {
        return evc != nil && evc.document.fileURL != nil;
    }
    if (a == @selector(menuToggleFold:) || a == @selector(menuFoldAll:) || a == @selector(menuUnfoldAll:)) {
        return evc != nil;
    }
    if (a == @selector(menuToggleColumnMode:)) {
        if (!evc) return NO;
        item.state = evc.columnMode ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    return YES;
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
        [self updateStatusBar];
    }
}

- (void)updateCurrentTabTitle {
    NSTabViewItem *sel = _tabView.selectedTabViewItem;
    if (!sel) return;
    if (![sel.identifier isKindOfClass:[EditorViewController class]]) return;
    EditorViewController *evc = (EditorViewController *)sel.identifier;
    NSString *name = evc.document.displayName;
    sel.label = evc.document.hasUnsavedChanges ? [name stringByAppendingString:@" •"] : name;
    [self syncTabBar];
}

- (void)updateTitle {
    EditorViewController *evc = [self currentEditor];
    self.window.title = evc ? evc.document.displayName : @"NotepadMac";
}

- (void)updateStatusBar {
    EditorViewController *evc = [self currentEditor];
    if (!evc) return;
    NSString *lang   = [[LexerManager shared] languageNameForExtension:
                        evc.document.fileURL.pathExtension ?: @""];
    NSInteger eol    = [evc eolMode];
    NSString *eolStr = (eol == SC_EOL_CRLF) ? @"CRLF" : (eol == SC_EOL_CR) ? @"CR" : @"LF";
    _statusLabel.stringValue = [NSString stringWithFormat:
        @"Ln %ld, Col %ld  |  %@  |  %@  |  Lines: %ld",
        (long)[evc currentLine], (long)[evc currentColumn],
        lang, eolStr, (long)[evc totalLines]];
    _encodingBtn.title = NMShortEncodingName(evc.document.encoding, evc.document.hasBOM);
}


// MARK: – Session

- (void)saveSession {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSInteger i = 0; i < _tabView.numberOfTabViewItems; i++) {
        NSTabViewItem *item = [_tabView tabViewItemAtIndex:i];
        if (![item.identifier isKindOfClass:[EditorViewController class]]) continue;
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
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"Keine letzten Dateien" action:nil keyEquivalent:@""];
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
    NSMenuItem *clear = [[NSMenuItem alloc] initWithTitle:@"Letzte Dateien löschen" action:@selector(menuClearRecents:) keyEquivalent:@""];
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

- (void)openDroppedURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *url in urls) {
        [self openFileURL:url];
    }
}

// MARK: – NSTabViewDelegate

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    [self syncTabBar];
    [self updateTitle];
    [self updateStatusBar];
    if ([tabViewItem.identifier isKindOfClass:[EditorViewController class]]) {
        EditorViewController *evc = (EditorViewController *)tabViewItem.identifier;
        if (_findPanel.isVisible) _findPanel.editor = evc;
        if (!_findBar.hidden) {
            _findBar.editor = evc;
            [self findBar:_findBar highlightAll:_findBar.findText];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [evc focusEditor];
        });
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

// MARK: – Auto-save

- (void)autoSaveAll {
    for (EditorViewController *evc in _editors) {
        if (!evc.document.fileURL || !evc.document.hasUnsavedChanges) continue;
        evc.document.content = [evc currentContent];
        NSError *err;
        if ([evc.document save:&err]) {
            // Update tab title to remove unsaved-changes marker
            dispatch_async(dispatch_get_main_queue(), ^{
                for (NSInteger i = 0; i < _tabView.numberOfTabViewItems; i++) {
                    NSTabViewItem *item = [_tabView tabViewItemAtIndex:i];
                    if (item.identifier == evc) {
                        item.label = evc.document.displayName;
                        break;
                    }
                }
                [self syncTabBar];
            });
        }
    }
}

// MARK: – Compare Files

- (IBAction)menuCompare:(id)sender {
    if (_tabView.numberOfTabViewItems < 2) {
        NSAlert *a = [NSAlert new];
        a.messageText     = @"Dateien vergleichen";
        a.informativeText = @"Mindestens zwei Dateien öffnen um zu vergleichen.";
        [a runModal];
        return;
    }

    // Build list of tab titles
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (NSInteger i = 0; i < _tabView.numberOfTabViewItems; i++) {
        NSTabViewItem *item = [_tabView tabViewItemAtIndex:i];
        [titles addObject:item.label ?: @"Unbenannt"];
    }

    // Accessory view with two pop-up buttons
    NSView *acc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 340, 60)];

    NSTextField *lbl1 = [NSTextField labelWithString:@"Links:"];
    lbl1.frame = NSMakeRect(0, 36, 50, 18);
    NSTextField *lbl2 = [NSTextField labelWithString:@"Rechts:"];
    lbl2.frame = NSMakeRect(0, 8, 50, 18);

    NSPopUpButton *pop1 = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(58, 32, 280, 26) pullsDown:NO];
    NSPopUpButton *pop2 = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(58, 4, 280, 26) pullsDown:NO];

    for (NSString *t in titles) {
        [pop1 addItemWithTitle:t];
        [pop2 addItemWithTitle:t];
    }
    // Default: left=first, right=second
    [pop1 selectItemAtIndex:0];
    [pop2 selectItemAtIndex:MIN(1, (NSInteger)titles.count - 1)];

    [acc addSubview:lbl1]; [acc addSubview:lbl2];
    [acc addSubview:pop1]; [acc addSubview:pop2];

    NSAlert *alert = [NSAlert new];
    alert.messageText     = @"Dateien vergleichen";
    alert.informativeText = @"Wähle zwei Dateien zum Vergleichen:";
    alert.accessoryView   = acc;
    [alert addButtonWithTitle:@"Vergleichen"];
    [alert addButtonWithTitle:@"Abbrechen"];

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSInteger idxL = pop1.indexOfSelectedItem;
    NSInteger idxR = pop2.indexOfSelectedItem;
    if (idxL == idxR) {
        NSAlert *a = [NSAlert new];
        a.messageText = @"Bitte zwei verschiedene Dateien wählen.";
        [a runModal];
        return;
    }

    NSTabViewItem *itemL = [_tabView tabViewItemAtIndex:idxL];
    NSTabViewItem *itemR = [_tabView tabViewItemAtIndex:idxR];
    EditorViewController *evcL = (EditorViewController *)itemL.identifier;
    EditorViewController *evcR = (EditorViewController *)itemR.identifier;

    NSString *textL  = [evcL currentContent];
    NSString *textR  = [evcR currentContent];
    NSString *titleL = itemL.label;
    NSString *titleR = itemR.label;

    CompareViewController *cv = [[CompareViewController alloc]
        initWithLeftTitle:titleL leftText:textL
               rightTitle:titleR rightText:textR];
    [_compareControllers addObject:cv];
    [cv showWindow:nil];
}

// MARK: – Log-Analyse

- (IBAction)menuLogAnalysis:(id)sender {
    EditorViewController *evc = [self currentEditor];
    NSString *text = evc ? [evc currentContent] : @"";
    NSString *path = evc.document.fileURL.path;
    [[LogAnalysisPanel shared] showWithText:text filePath:path];
}

// MARK: – Konfig-Analyse

- (IBAction)menuConfigAnalysis:(id)sender {
    EditorViewController *evc = [self currentEditor];
    if (!evc) return;

    NSString *text = [evc currentContent];
    NSDictionary *parsed = [[NMConfigParserRegistry shared] parseConfig:text];
    if (!parsed) {
        NSAlert *a = [NSAlert new];
        a.messageText     = @"Konfig-Analyse";
        a.informativeText = @"Der Inhalt wurde von keinem bekannten Vendor-Parser als Konfiguration erkannt.";
        [a runModal];
        return;
    }

    NSError *err = nil;
    NSData *jsonData = NMConfigToJSONData(parsed, &err);
    if (!jsonData) {
        NSAlert *a = [NSAlert alertWithError:err ?: [NSError errorWithDomain:NSCocoaErrorDomain
                                                                        code:0
                                                                    userInfo:nil]];
        [a runModal];
        return;
    }

    NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    // Determine a readable tab title
    NSString *sourceName = evc.document.fileURL.lastPathComponent ?: @"config";
    NSString *tabTitle   = [sourceName stringByDeletingPathExtension];
    tabTitle = [tabTitle stringByAppendingString:@".json"];

    Document *doc = [[Document alloc] initUntitled];
    doc.content   = json;
    [self openDocument:doc];

    // Rename the tab to reflect the source file
    NSTabViewItem *item = _tabView.selectedTabViewItem;
    if (item) {
        item.label = tabTitle;
        [self syncTabBar];
    }
}

@end
