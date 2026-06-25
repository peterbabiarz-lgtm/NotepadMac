#pragma once
#import <Cocoa/Cocoa.h>
#import "Document.h"

@class EditorViewController;

@protocol EditorViewControllerDelegate <NSObject>
- (void)editorDidChangeContent:(EditorViewController *)editor;
@end

@interface EditorViewController : NSViewController

@property (nonatomic, strong) Document *document;
@property (nonatomic, weak) id<EditorViewControllerDelegate> delegate;

- (instancetype)initWithDocument:(Document *)document;
- (void)applyTheme;
- (void)reloadContent;
- (NSString *)currentContent;

// Find & Replace
- (BOOL)findText:(NSString *)text matchCase:(BOOL)matchCase wholeWord:(BOOL)wholeWord forward:(BOOL)forward;
- (NSInteger)replaceAll:(NSString *)search with:(NSString *)replacement matchCase:(BOOL)matchCase wholeWord:(BOOL)wholeWord;

// Editor state
- (NSInteger)currentLine;
- (NSInteger)currentColumn;
- (NSInteger)totalLines;

// Font size: delta=0 resets to default, +1/-1 increase/decrease
- (void)changeFontSize:(int)delta;
- (int)fontSize;

// Word wrap
- (void)toggleWordWrap;
- (BOOL)wordWrap;

// Edge column guide (vertical line at a given column)
- (void)setShowEdgeColumn:(BOOL)show column:(NSInteger)column;
- (BOOL)showEdgeColumn;

// EOL mode: SC_EOL_LF=2, SC_EOL_CR=1, SC_EOL_CRLF=0
- (NSInteger)eolMode;
- (void)convertToEolMode:(NSInteger)mode;

// Navigation
- (void)goToLine:(NSInteger)lineNumber;

// Focus
- (void)focusEditor;

@end
