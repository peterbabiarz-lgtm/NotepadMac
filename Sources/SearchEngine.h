#pragma once
#import <Cocoa/Cocoa.h>

// Options shared between Find/Replace and Find in Files
@interface SearchOptions : NSObject
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, assign) BOOL matchCase;
@property (nonatomic, assign) BOOL wholeWord;
@property (nonatomic, assign) BOOL useRegex;
@property (nonatomic, assign) BOOL wrapAround;
// Find in Files extras
@property (nonatomic, copy, nullable) NSString *directory;
@property (nonatomic, copy) NSString *fileFilters; // e.g. "*.mm;*.h"
@property (nonatomic, assign) BOOL recursive;
@end

// One match inside a file
@interface SearchResult : NSObject
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, assign) NSInteger lineNumber;   // 1-based
@property (nonatomic, copy) NSString *lineText;
@property (nonatomic, assign) NSRange matchRange;     // range within lineText
@end

// All matches for one file
@interface FileResults : NSObject
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, strong) NSMutableArray<SearchResult *> *results;
- (instancetype)initWithPath:(NSString *)path;
@end

// Stateless search utility
@interface SearchEngine : NSObject

// Search a string in memory — used for open-document search
+ (NSArray<SearchResult *> *)findAllInText:(NSString *)text
                                  filePath:(NSString *)path
                                   options:(SearchOptions *)opts;

// Recursive directory search; runs on caller's thread (call from background)
// cancelFlag: set to YES to abort early
+ (NSArray<FileResults *> *)findInDirectory:(NSString *)directory
                                    options:(SearchOptions *)opts
                              progressBlock:(nullable void(^)(NSString *file, NSInteger hits))progress
                                 cancelFlag:(BOOL *)cancelFlag
                          totalFilesScanned:(nullable NSInteger *)outTotal;

@end
