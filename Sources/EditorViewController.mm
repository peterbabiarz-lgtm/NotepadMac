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
    BOOL           _showEdgeColumn;
    NSInteger      _edgeColumn;
}

- (instancetype)initWithDocument:(Document *)document {
    self = [super initWithNibName:nil bundle:nil];
    if (!self) return nil;
    _document = document;
    _fontSize = 13;
    _wordWrap = NO;
    _showEdgeColumn = NO;
    _edgeColumn = 80;
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
    [self detectEolMode];

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
    // Use a 2px frame border around the caret line instead of a filled background,
    // so text on the current line stays readable.
    [_editor setGeneralProperty:SCI_SETCARETLINEFRAME value:2];

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
    _currentLexer = [lm lexerNameForExtension:ext];

    // Set lexer via Lexilla static API. Keep the const char* alive via _currentLexer.
    Scintilla::ILexer5 *lexer = CreateLexer(_currentLexer.UTF8String);
    if (lexer) {
        [_editor setReferenceProperty:SCI_SETILEXER parameter:0 value:lexer];
    }

    // Keywords
    NSArray<NSString *> *keywords = [lm keywordsForLexer:_currentLexer];
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
    // SCI_SETCARETLINEBACK takes color as wParam (unlike most color messages that use lParam),
    // so we must pass it as the parameter argument, not via setColorProperty.
    {
        NSColor *c = [t.caretLineBg colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
        if (c) {
            long clr = (long)(c.redComponent * 255)
                     | ((long)(c.greenComponent * 255) << 8)
                     | ((long)(c.blueComponent * 255) << 16);
            [_editor setGeneralProperty:SCI_SETCARETLINEBACK parameter:clr value:0];
        }
    }
    [_editor setColorProperty:SCI_SETSELBACK parameter:1 value:t.selectionBg];

    // Line numbers
    [_editor setColorProperty:SCI_STYLESETBACK parameter:STYLE_LINENUMBER value:t.lineNumberBg];
    [_editor setColorProperty:SCI_STYLESETFORE parameter:STYLE_LINENUMBER value:t.lineNumberFg];

    // Fold margin
    [_editor setColorProperty:SCI_SETFOLDMARGINCOLOUR       parameter:1 value:t.lineNumberBg];
    [_editor setColorProperty:SCI_SETFOLDMARGINHICOLOUR     parameter:1 value:t.lineNumberBg];

    // Brace matching styles: bold + colored foreground on default background
    [_editor setGeneralProperty:SCI_STYLESETBOLD   parameter:STYLE_BRACELIGHT value:1];
    [_editor setColorProperty:SCI_STYLESETFORE     parameter:STYLE_BRACELIGHT value:t.braceMatchFg];
    [_editor setColorProperty:SCI_STYLESETBACK     parameter:STYLE_BRACELIGHT value:t.background];
    [_editor setGeneralProperty:SCI_STYLESETBOLD   parameter:STYLE_BRACEBAD value:1];
    [_editor setColorProperty:SCI_STYLESETFORE     parameter:STYLE_BRACEBAD value:t.braceBadFg];
    [_editor setColorProperty:SCI_STYLESETBACK     parameter:STYLE_BRACEBAD value:t.background];

    // Edge column colour
    {
        NSColor *ec = [t.edgeColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
        if (ec) {
            long clr = (long)(ec.redComponent * 255)
                     | ((long)(ec.greenComponent * 255) << 8)
                     | ((long)(ec.blueComponent * 255) << 16);
            [_editor setGeneralProperty:SCI_SETEDGECOLOUR parameter:clr value:0];
        }
    }

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

// MARK: – Find & Replace (legacy wrappers)

- (BOOL)findText:(NSString *)text matchCase:(BOOL)matchCase wholeWord:(BOOL)wholeWord forward:(BOOL)forward {
    NMFindOptions opts = (matchCase ? NMFindMatchCase : 0) | (wholeWord ? NMFindWholeWord : 0);
    return [self findText:text options:opts forward:forward];
}

- (NSInteger)replaceAll:(NSString *)search with:(NSString *)replacement matchCase:(BOOL)matchCase wholeWord:(BOOL)wholeWord {
    NMFindOptions opts = (matchCase ? NMFindMatchCase : 0) | (wholeWord ? NMFindWholeWord : 0);
    return [self replaceAll:search with:replacement options:opts];
}

// MARK: – Find & Replace (full-featured, Scintilla target API)

static const NSInteger kSearchIndicator = 9;

- (int)_scFlagsForOptions:(NMFindOptions)opts {
    int flags = 0;
    if (opts & NMFindMatchCase) flags |= SCFIND_MATCHCASE;
    if (opts & NMFindWholeWord) flags |= SCFIND_WHOLEWORD;
    if (opts & NMFindRegex)     flags |= SCFIND_REGEXP | SCFIND_POSIX;
    return flags;
}

- (BOOL)findText:(NSString *)text options:(NMFindOptions)opts forward:(BOOL)forward {
    if (!text.length) return NO;
    [_editor setGeneralProperty:SCI_SETSEARCHFLAGS value:[self _scFlagsForOptions:opts]];

    const char *cstr = text.UTF8String;
    long clen = (long)strlen(cstr);
    long docLen   = [_editor getGeneralProperty:SCI_GETLENGTH];
    long selStart = [_editor getGeneralProperty:SCI_GETSELECTIONSTART];
    long selEnd   = [_editor getGeneralProperty:SCI_GETSELECTIONEND];

    long found = -1;
    if (forward) {
        [_editor setGeneralProperty:SCI_SETTARGETSTART value:selEnd];
        [_editor setGeneralProperty:SCI_SETTARGETEND   value:docLen];
        found = [ScintillaView directCall:_editor message:SCI_SEARCHINTARGET wParam:clen lParam:(sptr_t)cstr];
        if (found < 0) { // wrap around
            [_editor setGeneralProperty:SCI_SETTARGETSTART value:0];
            [_editor setGeneralProperty:SCI_SETTARGETEND   value:selStart];
            found = [ScintillaView directCall:_editor message:SCI_SEARCHINTARGET wParam:clen lParam:(sptr_t)cstr];
        }
    } else {
        if (selStart > 0) {
            [_editor setGeneralProperty:SCI_SETTARGETSTART value:selStart];
            [_editor setGeneralProperty:SCI_SETTARGETEND   value:0];
            found = [ScintillaView directCall:_editor message:SCI_SEARCHINTARGET wParam:clen lParam:(sptr_t)cstr];
        }
        if (found < 0) { // wrap around
            [_editor setGeneralProperty:SCI_SETTARGETSTART value:docLen];
            [_editor setGeneralProperty:SCI_SETTARGETEND   value:selEnd];
            found = [ScintillaView directCall:_editor message:SCI_SEARCHINTARGET wParam:clen lParam:(sptr_t)cstr];
        }
    }

    if (found < 0) return NO;
    long matchStart = [_editor getGeneralProperty:SCI_GETTARGETSTART];
    long matchEnd   = [_editor getGeneralProperty:SCI_GETTARGETEND];
    [_editor setGeneralProperty:SCI_SETSEL parameter:matchStart value:matchEnd];
    [_editor setGeneralProperty:SCI_SCROLLCARET value:0];
    return YES;
}

- (NSInteger)replaceAll:(NSString *)search with:(NSString *)replacement options:(NMFindOptions)opts {
    if (!search.length) return 0;
    [_editor setGeneralProperty:SCI_SETSEARCHFLAGS value:[self _scFlagsForOptions:opts]];

    const char *cstr = search.UTF8String;
    long clen = (long)strlen(cstr);
    const char *rstr = replacement.UTF8String;
    long rlen = (long)strlen(rstr);
    NSInteger replaceMsg = (opts & NMFindRegex) ? SCI_REPLACETARGETRE : SCI_REPLACETARGET;

    long docLen = [_editor getGeneralProperty:SCI_GETLENGTH];
    NSInteger count = 0;
    long pos = 0;

    while (pos <= docLen) {
        [_editor setGeneralProperty:SCI_SETTARGETSTART value:pos];
        [_editor setGeneralProperty:SCI_SETTARGETEND   value:docLen];
        long found = [ScintillaView directCall:_editor message:SCI_SEARCHINTARGET wParam:clen lParam:(sptr_t)cstr];
        if (found < 0) break;

        long mEnd = [_editor getGeneralProperty:SCI_GETTARGETEND];
        [ScintillaView directCall:_editor message:replaceMsg wParam:rlen lParam:(sptr_t)rstr];

        // After replacement the doc length changes; get new target end
        long newEnd = [_editor getGeneralProperty:SCI_GETTARGETEND];
        docLen = [_editor getGeneralProperty:SCI_GETLENGTH];
        pos = (mEnd == found) ? found + 1 : newEnd; // guard against zero-length match
        count++;
    }

    if (count > 0) {
        _document.hasUnsavedChanges = YES;
        [_delegate editorDidChangeContent:self];
    }
    return count;
}

- (BOOL)replaceCurrentAndFindNext:(NSString *)search replacement:(NSString *)replacement options:(NMFindOptions)opts {
    if (!search.length) return NO;
    [_editor setGeneralProperty:SCI_SETSEARCHFLAGS value:[self _scFlagsForOptions:opts]];

    long selStart = [_editor getGeneralProperty:SCI_GETSELECTIONSTART];
    long selEnd   = [_editor getGeneralProperty:SCI_GETSELECTIONEND];

    if (selStart < selEnd) {
        const char *cstr = search.UTF8String;
        long clen = (long)strlen(cstr);
        [_editor setGeneralProperty:SCI_SETTARGETSTART value:selStart];
        [_editor setGeneralProperty:SCI_SETTARGETEND   value:selEnd];
        long found = [ScintillaView directCall:_editor message:SCI_SEARCHINTARGET wParam:clen lParam:(sptr_t)cstr];
        if (found == selStart) {
            NSInteger replaceMsg = (opts & NMFindRegex) ? SCI_REPLACETARGETRE : SCI_REPLACETARGET;
            const char *rstr = replacement.UTF8String;
            long rlen = (long)strlen(rstr);
            [ScintillaView directCall:_editor message:replaceMsg wParam:rlen lParam:(sptr_t)rstr];
            _document.hasUnsavedChanges = YES;
            [_delegate editorDidChangeContent:self];
        }
    }
    return [self findText:search options:opts forward:YES];
}

- (NSInteger)countMatches:(NSString *)text options:(NMFindOptions)opts {
    return [self _searchAllMatches:text options:opts highlight:NO];
}

- (void)highlightAllMatches:(NSString *)text options:(NMFindOptions)opts {
    if (!text.length) { [self clearSearchHighlights]; return; }
    [self _searchAllMatches:text options:opts highlight:YES];
}

- (void)clearSearchHighlights {
    long docLen = [_editor getGeneralProperty:SCI_GETLENGTH];
    [_editor setGeneralProperty:SCI_SETINDICATORCURRENT value:kSearchIndicator];
    [ScintillaView directCall:_editor message:SCI_INDICATORCLEARRANGE wParam:0 lParam:docLen];
}

- (NSInteger)_searchAllMatches:(NSString *)text options:(NMFindOptions)opts highlight:(BOOL)highlight {
    [_editor setGeneralProperty:SCI_SETSEARCHFLAGS value:[self _scFlagsForOptions:opts]];

    if (highlight) {
        // Warm yellow (R=255 G=200 B=0 → Scintilla RGB = R|(G<<8)|(B<<16))
        long color = 255 | (200 << 8) | (0 << 16);
        [_editor setGeneralProperty:SCI_INDICSETSTYLE  parameter:kSearchIndicator value:INDIC_ROUNDBOX];
        [_editor setGeneralProperty:SCI_INDICSETFORE   parameter:kSearchIndicator value:color];
        [_editor setGeneralProperty:SCI_INDICSETALPHA  parameter:kSearchIndicator value:120];
        [_editor setGeneralProperty:SCI_SETINDICATORCURRENT value:kSearchIndicator];
        long docLen = [_editor getGeneralProperty:SCI_GETLENGTH];
        [ScintillaView directCall:_editor message:SCI_INDICATORCLEARRANGE wParam:0 lParam:docLen];
    }

    const char *cstr = text.UTF8String;
    long clen = (long)strlen(cstr);
    long docLen = [_editor getGeneralProperty:SCI_GETLENGTH];
    NSInteger count = 0;
    long pos = 0;

    while (pos <= docLen) {
        [_editor setGeneralProperty:SCI_SETTARGETSTART value:pos];
        [_editor setGeneralProperty:SCI_SETTARGETEND   value:docLen];
        long found = [ScintillaView directCall:_editor message:SCI_SEARCHINTARGET wParam:clen lParam:(sptr_t)cstr];
        if (found < 0) break;

        long mEnd = [_editor getGeneralProperty:SCI_GETTARGETEND];
        long mLen = mEnd - found;

        if (highlight && mLen > 0) {
            [ScintillaView directCall:_editor message:SCI_INDICATORFILLRANGE wParam:found lParam:mLen];
        }
        count++;
        pos = (mLen > 0) ? mEnd : found + 1;
    }
    return count;
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
        _document.hasUnsavedChanges = YES;
        [_delegate editorDidChangeContent:self];
    } else if (notification->nmhdr.code == SCN_UPDATEUI &&
               (notification->updated & (SC_UPDATE_SELECTION | SC_UPDATE_V_SCROLL | SC_UPDATE_H_SCROLL))) {
        if (notification->updated & (SC_UPDATE_SELECTION | SC_UPDATE_CONTENT)) {
            [self updateBraceHighlight];
        }
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
    [self.view.window makeFirstResponder:[_editor content]];
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

// MARK: – Brace matching

- (void)updateBraceHighlight {
    long pos = [_editor getGeneralProperty:SCI_GETCURRENTPOS];

    // Check the character at the caret and one position before it
    long checkPos = -1;
    for (long p = pos; p >= MAX(0, pos - 1); p--) {
        int ch = (int)[_editor getGeneralProperty:SCI_GETCHARAT parameter:p];
        if (ch == '{' || ch == '}' || ch == '[' || ch == ']' || ch == '(' || ch == ')') {
            checkPos = p;
            break;
        }
    }

    if (checkPos >= 0) {
        long matchPos = [_editor getGeneralProperty:SCI_BRACEMATCH parameter:checkPos];
        if (matchPos >= 0) {
            [_editor setGeneralProperty:SCI_BRACEHIGHLIGHT parameter:checkPos value:matchPos];
        } else {
            [_editor setGeneralProperty:SCI_BRACEBADLIGHT value:checkPos];
        }
    } else {
        // Clear: INVALID_POSITION = -1
        [_editor setGeneralProperty:SCI_BRACEHIGHLIGHT parameter:-1 value:-1];
    }
}

// MARK: – Edge column guide

- (void)setShowEdgeColumn:(BOOL)show column:(NSInteger)column {
    _showEdgeColumn = show;
    _edgeColumn = column;
    [_editor setGeneralProperty:SCI_SETEDGECOLUMN value:column];
    [_editor setGeneralProperty:SCI_SETEDGEMODE value:show ? EDGE_LINE : EDGE_NONE];
}

- (BOOL)showEdgeColumn {
    return _showEdgeColumn;
}

// MARK: – EOL mode

- (void)detectEolMode {
    NSString *content = _document.content;
    if (!content.length) return;
    NSInteger mode = SC_EOL_LF;
    if ([content rangeOfString:@"\r\n"].location != NSNotFound) {
        mode = SC_EOL_CRLF;
    } else if ([content rangeOfString:@"\r"].location != NSNotFound) {
        mode = SC_EOL_CR;
    }
    [_editor setGeneralProperty:SCI_SETEOLMODE value:mode];
}

- (NSInteger)eolMode {
    return [_editor getGeneralProperty:SCI_GETEOLMODE];
}

- (void)convertToEolMode:(NSInteger)mode {
    [_editor setGeneralProperty:SCI_SETEOLMODE value:mode];
    [_editor setGeneralProperty:SCI_CONVERTEOLS value:mode];
    _document.hasUnsavedChanges = YES;
    [_delegate editorDidChangeContent:self];
}

// MARK: – Code folding

- (void)foldAll {
    [ScintillaView directCall:_editor message:SCI_FOLDALL wParam:SC_FOLDACTION_CONTRACT lParam:0];
}

- (void)unfoldAll {
    [ScintillaView directCall:_editor message:SCI_FOLDALL wParam:SC_FOLDACTION_EXPAND lParam:0];
}

- (void)toggleFoldAtCursor {
    long caret = [_editor getGeneralProperty:SCI_GETCURRENTPOS];
    long line  = [ScintillaView directCall:_editor message:SCI_LINEFROMPOSITION wParam:(uptr_t)caret lParam:0];
    long level = [ScintillaView directCall:_editor message:SCI_GETFOLDLEVEL wParam:(uptr_t)line lParam:0];
    if (level & SC_FOLDLEVELHEADERFLAG) {
        [ScintillaView directCall:_editor message:SCI_TOGGLEFOLD wParam:(uptr_t)line lParam:0];
    }
}

// MARK: – Column / block selection mode

- (void)setColumnMode:(BOOL)on {
    [ScintillaView directCall:_editor message:SCI_SETSELECTIONMODE
                       wParam:on ? SC_SEL_RECTANGLE : SC_SEL_STREAM
                       lParam:0];
    // Virtual space lets rectangular selection extend beyond line ends
    [_editor setGeneralProperty:SCI_SETVIRTUALSPACEOPTIONS
                          value:on ? SCVS_RECTANGULARSELECTION : SCVS_NONE];
}

- (BOOL)columnMode {
    long mode = [ScintillaView directCall:_editor message:SCI_GETSELECTIONMODE wParam:0 lParam:0];
    // SC_SEL_THIN (3) is a collapsed rectangular selection — still column mode.
    return mode == SC_SEL_RECTANGLE || mode == SC_SEL_THIN;
}

// MARK: – Appearance change

- (void)viewDidChangeEffectiveAppearance {
    [self applyTheme];
}

@end
