#import "EditorViewController.h"
#import "LexerManager.h"
#import "ThemeManager.h"

// Scintilla headers (order matters)
#include "Scintilla.h"
#include "ILexer.h"
#include "Lexilla.h"
#include "SciLexer.h"
#include "ScintillaView.h"

@interface EditorViewController () <ScintillaNotificationProtocol>
@end

@implementation EditorViewController {
    ScintillaView *_editor;
    NSString      *_currentLexer;
    int            _fontSize;
    BOOL           _wordWrap;
}

- (instancetype)initWithDocument:(Document *)document {
    self = [super initWithNibName:nil bundle:nil];
    if (!self) return nil;
    _document = document;
    _fontSize = 13;
    _wordWrap = NO;
    return self;
}

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.view = root;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    _editor = [[ScintillaView alloc] initWithFrame:self.view.bounds];
    _editor.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.view addSubview:_editor];

    [self configureEditorDefaults];
    [self applyLexerForDocument];
    [self applyTheme];
    [self reloadContent];

    // Set delegate last so no notifications fire during initial setup
    _editor.delegate = self;
}

// MARK: – Editor setup

- (void)configureEditorDefaults {
    // Font
    [_editor setFontName:@"Menlo" size:_fontSize bold:NO italic:NO];

    // Tabs & indentation
    [_editor setGeneralProperty:SCI_SETTABWIDTH value:4];
    [_editor setGeneralProperty:SCI_SETUSETABS value:0];         // spaces
    [_editor setGeneralProperty:SCI_SETINDENT value:4];
    [_editor setGeneralProperty:SCI_SETINDENTATIONGUIDES value:SC_IV_LOOKBOTH];

    // Line endings — auto-detect
    [_editor setGeneralProperty:SCI_SETEOLMODE value:SC_EOL_LF];

    // Line numbers (margin 0)
    [_editor setGeneralProperty:SCI_SETMARGINTYPEN parameter:0 value:SC_MARGIN_NUMBER];
    [_editor setGeneralProperty:SCI_SETMARGINWIDTHN parameter:0 value:44];

    // Fold margin (margin 2)
    [_editor setGeneralProperty:SCI_SETMARGINTYPEN   parameter:2 value:SC_MARGIN_SYMBOL];
    [_editor setGeneralProperty:SCI_SETMARGINWIDTHN  parameter:2 value:16];
    [_editor setGeneralProperty:SCI_SETMARGINMASKN   parameter:2 value:SC_MASK_FOLDERS];
    [_editor setGeneralProperty:SCI_SETMARGINSENSITIVEN parameter:2 value:1];

    // Fold markers
    [_editor setGeneralProperty:SCI_MARKERDEFINE parameter:SC_MARKNUM_FOLDER        value:SC_MARK_BOXPLUS];
    [_editor setGeneralProperty:SCI_MARKERDEFINE parameter:SC_MARKNUM_FOLDEROPEN    value:SC_MARK_BOXMINUS];
    [_editor setGeneralProperty:SCI_MARKERDEFINE parameter:SC_MARKNUM_FOLDERSUB     value:SC_MARK_VLINE];
    [_editor setGeneralProperty:SCI_MARKERDEFINE parameter:SC_MARKNUM_FOLDERTAIL    value:SC_MARK_LCORNER];
    [_editor setGeneralProperty:SCI_MARKERDEFINE parameter:SC_MARKNUM_FOLDEREND     value:SC_MARK_BOXPLUSCONNECTED];
    [_editor setGeneralProperty:SCI_MARKERDEFINE parameter:SC_MARKNUM_FOLDEROPENMID value:SC_MARK_BOXMINUSCONNECTED];
    [_editor setGeneralProperty:SCI_MARKERDEFINE parameter:SC_MARKNUM_FOLDERMIDTAIL value:SC_MARK_TCORNER];
    [_editor setGeneralProperty:SCI_SETFOLDFLAGS value:SC_FOLDFLAG_LINEAFTER_CONTRACTED];

    // Auto-fold on click
    [_editor setGeneralProperty:SCI_SETAUTOMATICFOLD
                      parameter:SC_AUTOMATICFOLD_SHOW | SC_AUTOMATICFOLD_CLICK | SC_AUTOMATICFOLD_CHANGE
                          value:0];

    // Caret
    [_editor setGeneralProperty:SCI_SETCARETWIDTH value:2];
    [_editor setGeneralProperty:SCI_SETCARETLINEVISIBLE value:1];

    // Ensure editor is writable
    [_editor setGeneralProperty:SCI_SETREADONLY value:0];

    // Word wrap off by default
    [_editor setGeneralProperty:SCI_SETWRAPMODE value:SC_WRAP_NONE];

    // Auto-close brackets
    [_editor setGeneralProperty:SCI_SETMOUSEDOWNCAPTURES value:1];

    // Scrolling
    [_editor setGeneralProperty:SCI_SETSCROLLWIDTHTRACKING value:1];
    [_editor setGeneralProperty:SCI_SETSCROLLWIDTH value:1];

    // Multiple selections
    [_editor setGeneralProperty:SCI_SETMULTIPLESELECTION value:1];
    [_editor setGeneralProperty:SCI_SETADDITIONALSELECTIONTYPING value:1];

    // Extra ascent/descent for readability
    [_editor setGeneralProperty:SCI_SETEXTRAASCENT  value:1];
    [_editor setGeneralProperty:SCI_SETEXTRADESCENT value:1];
}

- (void)applyLexerForDocument {
    NSString *ext = _document.fileURL.pathExtension ?: @"";
    LexerManager *lm = [LexerManager shared];
    const char *lexerName = [lm lexerNameForExtension:ext];
    _currentLexer = [NSString stringWithUTF8String:lexerName];

    // Set lexer via Lexilla static API
    Scintilla::ILexer5 *lexer = CreateLexer(lexerName);
    if (lexer) {
        [_editor setReferenceProperty:SCI_SETILEXER parameter:0 value:lexer];
    }

    // Keywords
    NSArray<NSString *> *keywords = [lm keywordsForLexer:lexerName];
    for (NSUInteger i = 0; i < keywords.count; i++) {
        const char *kw = [keywords[i] UTF8String];
        [_editor setReferenceProperty:SCI_SETKEYWORDS parameter:(long)i value:kw];
    }

    // Enable folding for supported languages
    [_editor setLexerProperty:@"fold" value:@"1"];
    [_editor setLexerProperty:@"fold.compact" value:@"0"];
    [_editor setLexerProperty:@"fold.comment" value:@"1"];
    [_editor setLexerProperty:@"fold.preprocessor" value:@"1"];
}

// MARK: – Theme

- (void)applyTheme {
    ScintillaTheme t = [[ThemeManager shared] themeForAppearance:NSApp.effectiveAppearance];

    [_editor suspendDrawing:YES];

    // Default style
    [_editor setColorProperty:SCI_STYLESETBACK parameter:STYLE_DEFAULT value:t.background];
    [_editor setColorProperty:SCI_STYLESETFORE parameter:STYLE_DEFAULT value:t.foreground];
    [_editor setGeneralProperty:SCI_STYLECLEARALL value:0];

    // Caret & selection
    [_editor setColorProperty:SCI_SETCARETFORE parameter:0 value:t.caretFg];
    [_editor setColorProperty:SCI_SETCARETLINEBACK parameter:0 value:t.caretLineBg];
    [_editor setColorProperty:SCI_SETSELBACK parameter:1 value:t.selectionBg];

    // Line numbers
    [_editor setColorProperty:SCI_STYLESETBACK parameter:STYLE_LINENUMBER value:t.lineNumberBg];
    [_editor setColorProperty:SCI_STYLESETFORE parameter:STYLE_LINENUMBER value:t.lineNumberFg];

    // Fold margin
    [_editor setColorProperty:SCI_SETFOLDMARGINCOLOUR       parameter:1 value:t.lineNumberBg];
    [_editor setColorProperty:SCI_SETFOLDMARGINHICOLOUR     parameter:1 value:t.lineNumberBg];

    // Apply language-specific colours
    [self applyLanguageColors:t];

    [_editor suspendDrawing:NO];
}

- (void)applyLanguageColors:(ScintillaTheme)t {
    NSString *l = _currentLexer ?: @"";

    if ([l isEqual:@"cpp"]) {
        // C / C++ / Java / JS / C# / Swift (all use SCE_C_*)
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_C_COMMENT      value:t.comment];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_C_COMMENTLINE  value:t.comment];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_C_COMMENTDOC   value:t.comment];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_C_NUMBER       value:t.number];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_C_WORD         value:t.keyword];
        [_editor setGeneralProperty:SCI_STYLESETBOLD parameter:SCE_C_WORD       value:1];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_C_WORD2        value:t.keyword];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_C_STRING       value:t.string];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_C_CHARACTER    value:t.string];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_C_PREPROCESSOR value:t.preprocessor];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_C_OPERATOR     value:t.operator_];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_C_IDENTIFIER   value:t.foreground];
    } else if ([l isEqual:@"python"]) {
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_P_COMMENTLINE  value:t.comment];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_P_COMMENTBLOCK value:t.comment];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_P_NUMBER       value:t.number];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_P_WORD         value:t.keyword];
        [_editor setGeneralProperty:SCI_STYLESETBOLD parameter:SCE_P_WORD       value:1];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_P_WORD2        value:t.identifier];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_P_STRING       value:t.string];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_P_CHARACTER    value:t.string];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_P_TRIPLE       value:t.string];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_P_TRIPLEDOUBLE value:t.string];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_P_DECORATOR    value:t.preprocessor];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_P_OPERATOR     value:t.operator_];
    } else if ([l isEqual:@"bash"]) {
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_SH_COMMENTLINE value:t.comment];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_SH_NUMBER      value:t.number];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_SH_WORD        value:t.keyword];
        [_editor setGeneralProperty:SCI_STYLESETBOLD parameter:SCE_SH_WORD      value:1];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_SH_STRING      value:t.string];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_SH_CHARACTER   value:t.string];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_SH_OPERATOR    value:t.operator_];
    } else if ([l isEqual:@"hypertext"]) {
        // HTML
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_H_COMMENT         value:t.comment];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_H_TAG             value:t.keyword];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_H_ATTRIBUTE       value:t.identifier];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_H_VALUE           value:t.string];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_H_DOUBLESTRING    value:t.string];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_H_SINGLESTRING    value:t.string];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_H_NUMBER          value:t.number];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_H_ENTITY          value:t.preprocessor];
    } else if ([l isEqual:@"css"]) {
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_CSS_COMMENT       value:t.comment];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_CSS_TAG           value:t.keyword];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_CSS_CLASS         value:t.identifier];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_CSS_PSEUDOCLASS   value:t.identifier];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_CSS_ATTRIBUTE     value:t.identifier];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_CSS_PSEUDOELEMENT value:t.identifier];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_CSS_DOUBLESTRING  value:t.string];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_CSS_SINGLESTRING  value:t.string];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_CSS_VALUE         value:t.string];
    } else if ([l isEqual:@"json"]) {
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_JSON_STRING       value:t.string];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_JSON_NUMBER       value:t.number];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_JSON_KEYWORD      value:t.keyword];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_JSON_PROPERTYNAME value:t.identifier];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_JSON_LINECOMMENT  value:t.comment];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_JSON_BLOCKCOMMENT value:t.comment];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_JSON_OPERATOR     value:t.operator_];
    } else if ([l isEqual:@"sql"] || [l isEqual:@"mysql"]) {
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_SQL_COMMENT       value:t.comment];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_SQL_COMMENTLINE   value:t.comment];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_SQL_COMMENTDOC    value:t.comment];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_SQL_NUMBER        value:t.number];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_SQL_WORD          value:t.keyword];
        [_editor setGeneralProperty:SCI_STYLESETBOLD parameter:SCE_SQL_WORD        value:1];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_SQL_STRING        value:t.string];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_SQL_OPERATOR      value:t.operator_];
    } else if ([l isEqual:@"ruby"]) {
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_RB_COMMENTLINE    value:t.comment];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_RB_NUMBER         value:t.number];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_RB_WORD           value:t.keyword];
        [_editor setGeneralProperty:SCI_STYLESETBOLD parameter:SCE_RB_WORD         value:1];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_RB_STRING         value:t.string];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_RB_CHARACTER      value:t.string];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_RB_OPERATOR       value:t.operator_];
    } else if ([l isEqual:@"lua"]) {
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_LUA_COMMENT       value:t.comment];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_LUA_COMMENTLINE   value:t.comment];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_LUA_NUMBER        value:t.number];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_LUA_WORD          value:t.keyword];
        [_editor setGeneralProperty:SCI_STYLESETBOLD parameter:SCE_LUA_WORD        value:1];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_LUA_STRING        value:t.string];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_LUA_CHARACTER     value:t.string];
        [_editor setColorProperty:SCI_STYLESETFORE parameter:SCE_LUA_OPERATOR      value:t.operator_];
    }
    // Other lexers: default colours inherited from STYLE_DEFAULT work fine
}

// MARK: – Content

- (void)reloadContent {
    NSString *content = _document.content ?: @"";
    [_editor setString:content];
    [_editor setGeneralProperty:SCI_SETSAVEPOINT value:0];
    _document.hasUnsavedChanges = NO;
}

- (NSString *)currentContent {
    return [_editor string];
}

// MARK: – Find & Replace

- (BOOL)findText:(NSString *)text matchCase:(BOOL)matchCase wholeWord:(BOOL)wholeWord forward:(BOOL)forward {
    return [_editor findAndHighlightText:text
                               matchCase:matchCase
                               wholeWord:wholeWord
                                scrollTo:YES
                                    wrap:YES
                               backwards:!forward];
}

- (NSInteger)replaceAll:(NSString *)search with:(NSString *)replacement matchCase:(BOOL)matchCase wholeWord:(BOOL)wholeWord {
    return [_editor findAndReplaceText:search
                                byText:replacement
                             matchCase:matchCase
                             wholeWord:wholeWord
                                 doAll:YES];
}

// MARK: – Editor state

- (NSInteger)currentLine {
    long pos = [_editor getGeneralProperty:SCI_GETCURRENTPOS];
    return [_editor getGeneralProperty:SCI_LINEFROMPOSITION parameter:pos] + 1;
}

- (NSInteger)currentColumn {
    long pos = [_editor getGeneralProperty:SCI_GETCURRENTPOS];
    long line = [_editor getGeneralProperty:SCI_LINEFROMPOSITION parameter:pos];
    long lineStart = [_editor getGeneralProperty:SCI_POSITIONFROMLINE parameter:line];
    return (pos - lineStart) + 1;
}

- (NSInteger)totalLines {
    return [_editor getGeneralProperty:SCI_GETLINECOUNT];
}

// MARK: – ScintillaNotificationProtocol

- (void)notification:(SCNotification *)notification {
    if (notification->nmhdr.code == SCN_MODIFIED &&
        (notification->modificationType & (SC_MOD_INSERTTEXT | SC_MOD_DELETETEXT))) {
        // Don't copy the full buffer here — read lazily at save time via [_editor string]
        _document.hasUnsavedChanges = YES;
        [_delegate editorDidChangeContent:self];
    } else if (notification->nmhdr.code == SCN_UPDATEUI &&
               (notification->updated & (SC_UPDATE_SELECTION | SC_UPDATE_V_SCROLL | SC_UPDATE_H_SCROLL))) {
        // Only update status bar when caret/scroll actually changed, not on every paint
        [_delegate editorDidChangeContent:self];
    }
}

// MARK: – Navigation

- (void)focusEditor {
    NSWindow *win = self.view.window;
    if (!win) return;
    [win makeFirstResponder:[_editor content]];
}

- (void)goToLine:(NSInteger)lineNumber {
    NSInteger total = [_editor getGeneralProperty:SCI_GETLINECOUNT];
    NSInteger line  = MAX(1, MIN(lineNumber, total)) - 1; // SCI is 0-based
    [_editor setGeneralProperty:SCI_GOTOLINE parameter:line value:0];
    [self.view.window makeFirstResponder:_editor];
}

// MARK: – Font size

- (void)changeFontSize:(int)delta {
    if (delta == 0) {
        _fontSize = 13;
    } else {
        _fontSize = MAX(6, MIN(72, _fontSize + delta));
    }
    // SCI_STYLESETSIZE takes point size as integer; apply to all styles via STYLE_DEFAULT + clearall
    [_editor setGeneralProperty:SCI_STYLESETSIZE parameter:STYLE_DEFAULT value:_fontSize];
    [_editor setGeneralProperty:SCI_STYLECLEARALL value:0];
    // Re-apply theme colours that were wiped by STYLECLEARALL
    [self applyTheme];
}

- (int)fontSize {
    return _fontSize;
}

// MARK: – Word wrap

- (void)toggleWordWrap {
    _wordWrap = !_wordWrap;
    [_editor setGeneralProperty:SCI_SETWRAPMODE value:_wordWrap ? SC_WRAP_WORD : SC_WRAP_NONE];
}

- (BOOL)wordWrap {
    return _wordWrap;
}

// MARK: – Appearance change

- (void)viewDidChangeEffectiveAppearance {
    [self applyTheme];
}

@end
