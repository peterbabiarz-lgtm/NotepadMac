#import "Document.h"

static int untitledCounter = 0;

@implementation Document {
    NSString *_untitledName;
}

- (instancetype)initUntitled {
    self = [super init];
    if (!self) return nil;
    _content = @"";
    _encoding = NSUTF8StringEncoding;
    _hasUnsavedChanges = NO;
    untitledCounter++;
    _untitledName = [NSString stringWithFormat:@"Untitled %d", untitledCounter];
    return self;
}

- (instancetype)initWithURL:(NSURL *)url error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    _fileURL = url;
    _encoding = NSUTF8StringEncoding;

    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data) return nil;

    // Try UTF-8 first, then let Foundation detect the encoding from the data we already have
    _content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!_content) {
        NSStringEncoding detected;
        _content = [NSString stringWithContentsOfURL:url usedEncoding:&detected error:error];
        if (_content) {
            _encoding = detected;
        } else {
            // Both attempts failed — return nil so callers can show the real error
            return nil;
        }
    }

    _hasUnsavedChanges = NO;
    return self;
}

- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error {
    NSData *data = [_content dataUsingEncoding:_encoding allowLossyConversion:YES];
    if (![data writeToURL:url options:NSDataWritingAtomic error:error]) return NO;
    _fileURL = url;
    _hasUnsavedChanges = NO;
    return YES;
}

- (BOOL)save:(NSError **)error {
    if (!_fileURL) return NO;
    return [self saveToURL:_fileURL error:error];
}

- (NSString *)displayName {
    if (_fileURL) return _fileURL.lastPathComponent;
    return _untitledName;
}

@end
