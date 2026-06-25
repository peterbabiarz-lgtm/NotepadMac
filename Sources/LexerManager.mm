#import "LexerManager.h"

@implementation LexerManager {
    NSDictionary<NSString *, NSString *> *_extToLexer;
    NSDictionary<NSString *, NSString *> *_extToLanguage;
    NSDictionary<NSString *, NSArray<NSString *> *> *_lexerKeywords;
}

+ (instancetype)shared {
    static LexerManager *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [LexerManager new]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    _extToLexer = @{
        @"c":    @"cpp",   @"h":    @"cpp",   @"cpp": @"cpp",
        @"cxx":  @"cpp",   @"cc":   @"cpp",   @"hpp": @"cpp",
        @"m":    @"objc",  @"mm":   @"objc",
        @"py":   @"python",@"pyw":  @"python",
        @"js":   @"cpp",   @"ts":   @"cpp",   @"jsx": @"cpp",  @"tsx": @"cpp",
        @"java": @"cpp",
        @"swift":@"cpp",   // closest available
        @"go":   @"cpp",
        @"rs":   @"rust",
        @"rb":   @"ruby",
        @"php":  @"phpscript",
        @"html": @"hypertext", @"htm": @"hypertext",
        @"xml":  @"xml",   @"xsl":  @"xml",   @"svg": @"xml",
        @"css":  @"css",
        @"json": @"json",
        @"sh":   @"bash",  @"bash": @"bash",  @"zsh": @"bash",
        @"mk":   @"makefile", @"makefile": @"makefile",
        @"sql":  @"sql",   @"mysql": @"mysql",
        @"md":   @"markdown", @"markdown": @"markdown",
        @"yaml": @"yaml",  @"yml":  @"yaml",
        @"toml": @"toml",
        @"tex":  @"latex", @"sty":  @"latex",
        @"lua":  @"lua",
        @"pl":   @"perl",  @"pm":   @"perl",
        @"tcl":  @"tcl",
        @"r":    @"r",
        @"zig":  @"zig",
        @"nim":  @"nim",
        @"dart": @"dart",
        @"ps1":  @"powershell",
        @"bat":  @"batch", @"cmd":  @"batch",
        @"vb":   @"vb",    @"vbs":  @"vb",
        @"asm":  @"asm",   @"s":    @"asm",
        @"pas":  @"pascal",@"pp":   @"pascal",
        @"f":    @"fortran",@"f90": @"fortran",@"f95": @"fortran",
        @"cs":   @"cpp",   // C# — use cpp lexer
        @"ini":  @"props", @"cfg":  @"props",  @"conf": @"props",
        @"diff": @"diff",  @"patch":@"diff",
        @"cmake":@"cmake",
        @"proto":@"cpp",
        @"txt":  @"null",  @"log":  @"null",
    };

    _extToLanguage = @{
        @"c":    @"C",          @"h":    @"C/C++ Header",
        @"cpp":  @"C++",        @"cxx":  @"C++",  @"cc": @"C++",  @"hpp": @"C++ Header",
        @"m":    @"Objective-C",@"mm":   @"Objective-C++",
        @"py":   @"Python",     @"pyw":  @"Python",
        @"js":   @"JavaScript", @"ts":   @"TypeScript",
        @"jsx":  @"JSX",        @"tsx":  @"TSX",
        @"java": @"Java",
        @"swift":@"Swift",
        @"go":   @"Go",
        @"rs":   @"Rust",
        @"rb":   @"Ruby",
        @"php":  @"PHP",
        @"html": @"HTML",       @"htm":  @"HTML",
        @"xml":  @"XML",        @"xsl":  @"XSL",  @"svg": @"SVG",
        @"css":  @"CSS",
        @"json": @"JSON",
        @"sh":   @"Shell",      @"bash": @"Bash",  @"zsh": @"Zsh",
        @"mk":   @"Makefile",   @"makefile": @"Makefile",
        @"sql":  @"SQL",        @"mysql": @"MySQL",
        @"md":   @"Markdown",
        @"yaml": @"YAML",       @"yml":  @"YAML",
        @"toml": @"TOML",
        @"tex":  @"LaTeX",
        @"lua":  @"Lua",
        @"pl":   @"Perl",
        @"r":    @"R",
        @"zig":  @"Zig",
        @"nim":  @"Nim",
        @"dart": @"Dart",
        @"ps1":  @"PowerShell",
        @"bat":  @"Batch",
        @"vb":   @"VBScript",
        @"asm":  @"Assembly",
        @"pas":  @"Pascal",
        @"cs":   @"C#",
        @"ini":  @"INI",        @"cfg":  @"Config",
        @"diff": @"Diff",
        @"cmake":@"CMake",
        @"txt":  @"Plain Text", @"log":  @"Log",
    };

    // keyword set index 0 = primary keywords
    _lexerKeywords = @{
        @"cpp": @[
            @"alignas alignof and and_eq asm auto bitand bitor bool break case catch char char8_t "
            @"char16_t char32_t class compl concept const consteval constexpr constinit const_cast "
            @"continue co_await co_return co_yield decltype default delete do double dynamic_cast "
            @"else enum explicit export extern false float for friend goto if inline int long "
            @"mutable namespace new noexcept not not_eq nullptr operator or or_eq private protected "
            @"public register reinterpret_cast requires return short signed sizeof static "
            @"static_assert static_cast struct switch template this thread_local throw true try "
            @"typedef typeid typename union unsigned using virtual void volatile wchar_t while xor xor_eq",
            @"", // index 1 — secondary (types etc, optional)
        ],
        @"python": @[
            @"False None True and as assert async await break class continue def del elif else "
            @"except finally for from global if import in is lambda nonlocal not or pass raise "
            @"return try while with yield",
            @"abs all any ascii bin bool breakpoint bytearray bytes callable chr classmethod "
            @"compile complex delattr dict dir divmod enumerate eval exec filter float format "
            @"frozenset getattr globals hasattr hash help hex id input int isinstance issubclass "
            @"iter len list locals map max memoryview min next object oct open ord pow print "
            @"property range repr reversed round set setattr slice sorted staticmethod str sum "
            @"super tuple type vars zip __import__",
        ],
        @"bash": @[
            @"alias bg bind break builtin caller case cd command compgen complete compopt "
            @"continue declare dirs disown echo enable eval exec exit export false fc fg "
            @"getopts hash help history jobs kill let local logout mapfile popd printf pushd "
            @"pwd read readarray readonly return set shift shopt source suspend test time "
            @"times trap true type typeset ulimit umask unalias unset wait while for if then "
            @"else elif fi do done case esac function in select until",
        ],
        @"ruby": @[
            @"BEGIN END __ENCODING__ __END__ __FILE__ __LINE__ alias and begin break case class "
            @"def defined? do else elsif end ensure false for if in module next nil not or redo "
            @"rescue retry return self super then true undef unless until when while yield",
        ],
        @"lua": @[
            @"and break do else elseif end false for function goto if in local nil not or repeat "
            @"return then true until while",
        ],
        @"sql": @[
            @"ADD ALL ALTER AND ANY AS ASC BACKUP BETWEEN BY CASCADE CASE CHECK COLUMN CONSTRAINT "
            @"CREATE CROSS CURRENT DATABASE DEFAULT DELETE DISTINCT DROP ELSE END EXEC EXISTS "
            @"FOREIGN FROM FULL GROUP HAVING IN INDEX INNER INSERT INTO IS JOIN KEY LEFT LIKE "
            @"LIMIT NOT NULL ON OR ORDER OUTER PRIMARY PROCEDURE RIGHT ROWNUM SELECT SET TABLE "
            @"TOP TRUNCATE UNION UNIQUE UPDATE VALUES VIEW WHERE WITH",
        ],
        @"css": @[
            @"",
        ],
        @"json": @[
            @"",
        ],
        @"markdown": @[
            @"",
        ],
        @"null": @[
            @"",
        ],
    };

    return self;
}

- (NSString *)lexerNameForExtension:(NSString *)ext {
    NSString *lower = [ext lowercaseString];
    return _extToLexer[lower] ?: @"null";
}

- (NSArray<NSString *> *)keywordsForLexer:(NSString *)lexerName {
    NSArray<NSString *> *kws = _lexerKeywords[lexerName];
    if (!kws) kws = @[@""];
    return kws;
}

- (NSString *)languageNameForExtension:(NSString *)ext {
    NSString *lower = [ext lowercaseString];
    return _extToLanguage[lower] ?: @"Plain Text";
}

@end
