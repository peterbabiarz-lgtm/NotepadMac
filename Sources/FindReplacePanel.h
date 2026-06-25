#pragma once
#import <Cocoa/Cocoa.h>
#import "EditorViewController.h"

@interface FindReplacePanel : NSPanel

@property (nonatomic, weak) EditorViewController *editor;

- (instancetype)initForEditor:(EditorViewController *)editor;

@end
