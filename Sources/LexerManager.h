#pragma once
#import <Foundation/Foundation.h>

// Maps file extensions to Lexilla lexer names and keyword sets.
@interface LexerManager : NSObject

+ (instancetype)shared;

// Returns the Lexilla lexer name for a given file extension (e.g. "cpp" for ".cpp" files).
- (NSString *)lexerNameForExtension:(NSString *)ext;

// Returns keyword sets for a lexer. Index 0..8 correspond to SCI_SETKEYWORDS parameter.
- (NSArray<NSString *> *)keywordsForLexer:(NSString *)lexerName;

// Human-readable language name for display.
- (NSString *)languageNameForExtension:(NSString *)ext;

@end
