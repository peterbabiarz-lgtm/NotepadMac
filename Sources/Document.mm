#import "Document.h"

static _Atomic int untitledCounter = 0;  // atomic: safe if ever opened from multiple threads

@implementation Document {
    NSString *_untitledName;
}

- (instancetype)initUntitled {
    self = [super init];
    if (!self) return nil;
    _content = @"";
    _encoding = NSUTF8StringEncoding;
    _hasBOM = NO;
    _hasUnsavedChanges = NO;
    _untitledName = [NSString stringWithFormat:@"Untitled %d", ++untitledCounter];
    return self;
}

- (instancetype)initWithURL:(NSURL *)url error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    _fileURL = url;

    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data) return nil;

    [self _detectEncodingFromData:data];
    _hasUnsavedChanges = NO;
    return self;
}

- (void)_detectEncodingFromData:(NSData *)data {
    const uint8_t *b = (const uint8_t *)data.bytes;
    NSUInteger len = data.length;
    _hasBOM = NO;

    // ── BOM detection ──────────────────────────────────────────────────────
    // UTF-32 LE (FF FE 00 00) must be tested before UTF-16 LE (FF FE).
    NSData        *bomBody = nil;
    NSStringEncoding bomEnc = 0;

    if (len >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
        bomEnc  = NSUTF8StringEncoding;
        bomBody = [data subdataWithRange:NSMakeRange(3, len - 3)];
    } else if (len >= 4 && b[0]==0xFF && b[1]==0xFE && b[2]==0x00 && b[3]==0x00) {
        bomEnc  = NSUTF32LittleEndianStringEncoding;
        bomBody = [data subdataWithRange:NSMakeRange(4, len - 4)]; // strip BOM; explicit-endian codec needs it gone
    } else if (len >= 4 && b[0]==0x00 && b[1]==0x00 && b[2]==0xFE && b[3]==0xFF) {
        bomEnc  = NSUTF32BigEndianStringEncoding;
        bomBody = [data subdataWithRange:NSMakeRange(4, len - 4)];
    } else if (len >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
        bomEnc  = NSUTF16LittleEndianStringEncoding;
        bomBody = data; // Foundation's explicit-endian UTF-16 decoder strips the BOM
    } else if (len >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
        bomEnc  = NSUTF16BigEndianStringEncoding;
        bomBody = data;
    }

    if (bomEnc != 0) {
        NSString *str = [[NSString alloc] initWithData:bomBody encoding:bomEnc];
        if (str) {
            _hasBOM = YES;
            _encoding = bomEnc;
            _content = str;
            return;
        }
        // BOM present but body is undecodable with that encoding — fall through
        // without _hasBOM so we try other encodings rather than silently opening empty.
    }

    // ── No BOM (or BOM mismatch): try UTF-8 ───────────────────────────────
    _content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (_content) {
        _encoding = NSUTF8StringEncoding;
        return;
    }

    // ── Foundation's heuristic on already-loaded data (no second disk read) ─
    NSString *heuristic = nil;
    BOOL usedLossy = NO;
    NSStringEncoding detected = [NSString stringEncodingForData:data
                                               encodingOptions:nil
                                               convertedString:&heuristic
                                           usedLossyConversion:&usedLossy];
    if (detected != 0 && heuristic && !usedLossy) {
        _content = heuristic;
        _encoding = detected;
        return;
    }

    // ── Windows-1252 (superset of Latin-1, covers most Western European) ──
    _content = [[NSString alloc] initWithData:data encoding:NSWindowsCP1252StringEncoding];
    if (_content) {
        _encoding = NSWindowsCP1252StringEncoding;
        return;
    }

    // ── Latin-1 last resort (always succeeds for any byte sequence) ───────
    _content = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    _encoding = NSISOLatin1StringEncoding;
    if (!_content) _content = @"";
}

- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error {
    // Encode content; fall back to UTF-8 if the chosen encoding can't represent all chars.
    NSData *body = [_content dataUsingEncoding:_encoding allowLossyConversion:NO];
    if (!body) {
        _encoding = NSUTF8StringEncoding;
        _hasBOM = NO;
        body = [_content dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
    }

    NSData *data = body;

    // Prepend BOM bytes for every encoding that supports one.
    if (_hasBOM && body) {
        uint8_t bom[4] = {0};
        NSUInteger bomLen = 0;
        if (_encoding == NSUTF8StringEncoding) {
            bom[0]=0xEF; bom[1]=0xBB; bom[2]=0xBF; bomLen = 3;
        } else if (_encoding == NSUTF16LittleEndianStringEncoding) {
            bom[0]=0xFF; bom[1]=0xFE; bomLen = 2;
        } else if (_encoding == NSUTF16BigEndianStringEncoding) {
            bom[0]=0xFE; bom[1]=0xFF; bomLen = 2;
        } else if (_encoding == NSUTF32LittleEndianStringEncoding) {
            bom[0]=0xFF; bom[1]=0xFE; bom[2]=0x00; bom[3]=0x00; bomLen = 4;
        } else if (_encoding == NSUTF32BigEndianStringEncoding) {
            bom[0]=0x00; bom[1]=0x00; bom[2]=0xFE; bom[3]=0xFF; bomLen = 4;
        }
        if (bomLen > 0) {
            NSMutableData *md = [NSMutableData dataWithBytes:bom length:bomLen];
            [md appendData:body];
            data = md;
        }
    }

    if (![data writeToURL:url options:NSDataWritingAtomic error:error]) return NO;
    _fileURL = url;
    _hasUnsavedChanges = NO;
    return YES;
}

- (BOOL)save:(NSError **)error {
    if (!_fileURL) return NO;
    return [self saveToURL:_fileURL error:error];
}

- (BOOL)reloadWithEncoding:(NSStringEncoding)enc hasBOM:(BOOL)bom error:(NSError **)error {
    if (!_fileURL) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                                code:NSFileNoSuchFileError
                                            userInfo:@{NSLocalizedDescriptionKey: @"Keine Datei zum Neu laden."}];
        return NO;
    }
    NSData *data = [NSData dataWithContentsOfURL:_fileURL options:0 error:error];
    if (!data) return NO;

    const uint8_t *b = (const uint8_t *)data.bytes;
    NSUInteger len = data.length;

    // Strip BOM bytes so they don't appear as garbled chars in the resulting string.
    // UTF-16 LE/BE: Foundation's explicit-endian decoders handle the BOM themselves.
    NSData *body = data;
    if (enc == NSUTF8StringEncoding && len >= 3 && b[0]==0xEF && b[1]==0xBB && b[2]==0xBF)
        body = [data subdataWithRange:NSMakeRange(3, len - 3)];
    else if (enc == NSUTF32LittleEndianStringEncoding && len >= 4 && b[0]==0xFF && b[1]==0xFE && b[2]==0x00 && b[3]==0x00)
        body = [data subdataWithRange:NSMakeRange(4, len - 4)];
    else if (enc == NSUTF32BigEndianStringEncoding && len >= 4 && b[0]==0x00 && b[1]==0x00 && b[2]==0xFE && b[3]==0xFF)
        body = [data subdataWithRange:NSMakeRange(4, len - 4)];

    NSString *str = [[NSString alloc] initWithData:body encoding:enc];
    if (!str) {
        if (error)
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileReadInapplicableStringEncodingError
                                     userInfo:@{NSLocalizedDescriptionKey:
                          [NSString stringWithFormat:@"Die Datei konnte nicht als \"%@\" gelesen werden.",
                           [NSString localizedNameOfStringEncoding:enc]]}];
        return NO;
    }
    _content = str;
    _encoding = enc;
    _hasBOM = bom;
    _hasUnsavedChanges = NO;
    return YES;
}

- (void)setEncodingForNextSave:(NSStringEncoding)enc hasBOM:(BOOL)bom {
    _encoding = enc;
    _hasBOM = bom;
    _hasUnsavedChanges = YES;
}

- (NSString *)displayName {
    if (_fileURL) return _fileURL.lastPathComponent;
    return _untitledName;
}

@end
