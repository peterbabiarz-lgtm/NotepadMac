#pragma once
#import <Foundation/Foundation.h>

@interface Document : NSObject

@property (nonatomic, copy)   NSURL            *fileURL;
@property (nonatomic, copy)   NSString         *content;
@property (nonatomic, assign) NSStringEncoding  encoding;
@property (nonatomic, assign) BOOL              hasBOM;
@property (nonatomic, assign) BOOL              hasUnsavedChanges;
@property (nonatomic, readonly) NSString        *displayName;

- (instancetype)initUntitled;
- (instancetype)initWithURL:(NSURL *)url error:(NSError **)error;
- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error;
- (BOOL)save:(NSError **)error;

// Re-read the file from disk using a different encoding.
// Returns NO (and sets *error) if the file can't be read or the encoding fails.
- (BOOL)reloadWithEncoding:(NSStringEncoding)enc hasBOM:(BOOL)bom error:(NSError **)error;

// Change encoding/BOM for next save without reloading (text stays as-is).
- (void)setEncodingForNextSave:(NSStringEncoding)enc hasBOM:(BOOL)bom;

@end
