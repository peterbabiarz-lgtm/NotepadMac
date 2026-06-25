#pragma once
#import <Foundation/Foundation.h>

@interface Document : NSObject

@property (nonatomic, copy) NSURL *fileURL;
@property (nonatomic, copy) NSString *content;
@property (nonatomic, assign) NSStringEncoding encoding;
@property (nonatomic, assign) BOOL hasUnsavedChanges;
@property (nonatomic, readonly) NSString *displayName;

- (instancetype)initUntitled;
- (instancetype)initWithURL:(NSURL *)url error:(NSError **)error;
- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error;
- (BOOL)save:(NSError **)error;

@end
