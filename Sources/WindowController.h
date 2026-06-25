#pragma once
#import <Cocoa/Cocoa.h>
#import "Document.h"

@interface WindowController : NSWindowController

- (instancetype)init;
- (void)openDocument:(Document *)document;
- (void)newDocument;

// Session restore: open a file URL silently (no duplicate check)
- (void)openFileURL:(NSURL *)url;

// Persist open file URLs to NSUserDefaults for next launch
- (void)saveSession;

@end
