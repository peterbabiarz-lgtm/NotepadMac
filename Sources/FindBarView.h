#pragma once
#import <Cocoa/Cocoa.h>
#import "EditorViewController.h"

@class FindBarView;

@protocol FindBarViewDelegate <NSObject>
- (void)findBar:(FindBarView *)bar findNext:(BOOL)forward;
- (void)findBar:(FindBarView *)bar replaceCurrent:(NSString *)replacement;
- (void)findBar:(FindBarView *)bar replaceAll:(NSString *)replacement;
- (void)findBar:(FindBarView *)bar highlightAll:(NSString *)text;
- (void)findBarDidClose:(FindBarView *)bar;
@end

@interface FindBarView : NSView <NSTextFieldDelegate>

@property (nonatomic, weak) id<FindBarViewDelegate> delegate;
@property (nonatomic, weak) EditorViewController *editor;

@property (nonatomic, readonly) NSString *findText;
@property (nonatomic, readonly) NSString *replaceText;
@property (nonatomic, readonly) NMFindOptions findOptions;

- (void)focusFindField;
- (void)setMatchCount:(NSInteger)count;

@end
