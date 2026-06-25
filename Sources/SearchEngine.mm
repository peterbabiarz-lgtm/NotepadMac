#import "SearchEngine.h"

@implementation SearchOptions
- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _searchText  = @"";
    _fileFilters = @"*";
    _recursive   = YES;
    _wrapAround  = YES;
    return self;
}
@end

@implementation SearchResult
@end

@implementation FileResults
- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (!self) return nil;
    _filePath = [path copy];
    _results  = [NSMutableArray array];
    return self;
}
@end

@implementation SearchEngine

+ (NSRegularExpressionOptions)regexOptionsFor:(SearchOptions *)opts {
    return opts.matchCase ? 0 : NSRegularExpressionCaseInsensitive;
}

// Build NSRegularExpression from options; escapes the term if not regex mode
+ (NSRegularExpression *)regexFor:(SearchOptions *)opts error:(NSError **)err {
    NSString *pattern = opts.searchText;
    if (!opts.useRegex) {
        pattern = [NSRegularExpression escapedPatternForString:pattern];
    }
    if (opts.wholeWord) {
        pattern = [NSString stringWithFormat:@"\\b%@\\b", pattern];
    }
    return [NSRegularExpression regularExpressionWithPattern:pattern
                                                     options:[self regexOptionsFor:opts]
                                                       error:err];
}

+ (NSArray<SearchResult *> *)findAllInText:(NSString *)text
                                  filePath:(NSString *)path
                                   options:(SearchOptions *)opts {
    if (opts.searchText.length == 0) return @[];
    NSError *err;
    NSRegularExpression *regex = [self regexFor:opts error:&err];
    return [self findAllInText:text filePath:path options:opts regex:regex];
}

+ (NSArray<SearchResult *> *)findAllInText:(NSString *)text
                                  filePath:(NSString *)path
                                   options:(SearchOptions *)opts
                                     regex:(NSRegularExpression *)regex {
    if (!regex) return @[];

    NSMutableArray<SearchResult *> *results = [NSMutableArray array];

    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];

    for (NSInteger i = 0; i < (NSInteger)lines.count; i++) {
        NSString *line = lines[i];
        NSArray<NSTextCheckingResult *> *matches =
            [regex matchesInString:line options:0 range:NSMakeRange(0, line.length)];

        for (NSTextCheckingResult *m in matches) {
            SearchResult *r  = [SearchResult new];
            r.filePath       = path;
            r.lineNumber     = i + 1;
            r.lineText       = line;
            r.matchRange     = m.range;
            [results addObject:r];
        }
    }
    return results;
}

+ (NSArray<FileResults *> *)findInDirectory:(NSString *)directory
                                    options:(SearchOptions *)opts
                              progressBlock:(void(^)(NSString *, NSInteger))progress
                                 cancelFlag:(BOOL *)cancelFlag
                          totalFilesScanned:(NSInteger *)outTotal {
    NSMutableArray<FileResults *> *allResults = [NSMutableArray array];
    NSInteger scanned = 0;
    NSInteger totalHits = 0;

    // Build filter set from semicolon-separated globs like "*.mm;*.h;*.py"
    NSArray<NSString *> *filterParts =
        [opts.fileFilters componentsSeparatedByString:@";"];
    NSMutableArray<NSString *> *filters = [NSMutableArray array];
    for (NSString *f in filterParts) {
        NSString *trimmed = [f stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length) [filters addObject:trimmed];
    }

    NSError *err;
    NSRegularExpression *regex = [self regexFor:opts error:&err];
    if (!regex) return @[];

    // Pre-compile glob filter patterns once for the whole directory scan
    NSMutableArray<NSRegularExpression *> *globRegexes = [NSMutableArray array];
    for (NSString *pat in filters) {
        NSString *escaped = [NSRegularExpression escapedPatternForString:pat];
        NSString *regexPat = [escaped stringByReplacingOccurrencesOfString:@"\\*" withString:@".*"];
        NSRegularExpression *re = [NSRegularExpression
            regularExpressionWithPattern:[NSString stringWithFormat:@"^%@$", regexPat]
                                 options:NSRegularExpressionCaseInsensitive
                                   error:nil];
        if (re) [globRegexes addObject:re];
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerationOptions enumOpts = opts.recursive ? 0 : NSDirectoryEnumerationSkipsSubdirectoryDescendants;
    NSDirectoryEnumerator<NSURL *> *enumerator =
        [fm enumeratorAtURL:[NSURL fileURLWithPath:directory]
 includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLIsHiddenKey]
                    options:enumOpts
               errorHandler:nil];

    for (NSURL *url in enumerator) {
        if (cancelFlag && *cancelFlag) break;

        NSNumber *isFile;
        [url getResourceValue:&isFile forKey:NSURLIsRegularFileKey error:nil];
        if (!isFile.boolValue) continue;

        // Skip hidden files
        NSNumber *isHidden;
        [url getResourceValue:&isHidden forKey:NSURLIsHiddenKey error:nil];
        if (isHidden.boolValue) continue;

        // Apply file filter using pre-compiled glob regexes
        NSString *filename = url.lastPathComponent;
        if (filters.count > 0 && ![filters containsObject:@"*"]) {
            BOOL matched = NO;
            for (NSRegularExpression *re in globRegexes) {
                if ([re numberOfMatchesInString:filename options:0
                                          range:NSMakeRange(0, filename.length)] > 0) {
                    matched = YES; break;
                }
            }
            if (!matched) continue;
        }

        scanned++;
        NSString *path = url.path;

        // Read as text; skip binary files.
        // usedEncoding: requires a non-nil pointer — passing nil is undefined behavior.
        NSStringEncoding detectedEncoding;
        NSString *content = [NSString stringWithContentsOfFile:path
                                                  usedEncoding:&detectedEncoding
                                                         error:nil];
        if (!content) continue;

        NSArray<SearchResult *> *hits = [self findAllInText:content
                                                   filePath:path
                                                    options:opts
                                                      regex:regex];
        if (hits.count == 0) continue;

        FileResults *fr = [[FileResults alloc] initWithPath:path];
        [fr.results addObjectsFromArray:hits];
        [allResults addObject:fr];
        totalHits += hits.count;

        if (progress) {
            dispatch_async(dispatch_get_main_queue(), ^{
                progress(path, totalHits);
            });
        }
    }

    if (outTotal) *outTotal = scanned;
    return allResults;
}

@end
