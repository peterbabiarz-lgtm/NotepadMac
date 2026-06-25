#import "DiffEngine.h"

@implementation DiffHunk
@end

@implementation DiffEngine

+ (NSArray<DiffHunk *> *)diffLeft:(NSString *)left right:(NSString *)right {
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *uid    = [[NSUUID UUID] UUIDString];
    NSString *leftPath  = [tmpDir stringByAppendingPathComponent:[uid stringByAppendingString:@"_a.txt"]];
    NSString *rightPath = [tmpDir stringByAppendingPathComponent:[uid stringByAppendingString:@"_b.txt"]];
    NSString *outPath   = [tmpDir stringByAppendingPathComponent:[uid stringByAppendingString:@"_out.txt"]];

    NSFileManager *fm = [NSFileManager defaultManager];

    [left  writeToFile:leftPath  atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [right writeToFile:rightPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    // Write stdout to a file instead of a pipe so we avoid a pipe-buffer deadlock
    // on large diffs (the child would block writing once the ~64 KB buffer fills).
    [@"" writeToFile:outPath atomically:NO encoding:NSUTF8StringEncoding error:nil];
    NSFileHandle *outHandle = [NSFileHandle fileHandleForWritingAtPath:outPath];

    NSTask *task = [NSTask new];
    task.executableURL  = [NSURL fileURLWithPath:@"/usr/bin/diff"];
    task.arguments      = @[leftPath, rightPath];
    task.standardOutput = outHandle;
    task.standardError  = [NSFileHandle fileHandleWithNullDevice];

    NSError *err;
    BOOL launched = [task launchAndReturnError:&err];
    if (!launched) {
        NSLog(@"DiffEngine: failed to launch /usr/bin/diff: %@", err.localizedDescription);
        [fm removeItemAtPath:leftPath  error:nil];
        [fm removeItemAtPath:rightPath error:nil];
        [fm removeItemAtPath:outPath   error:nil];
        return @[];
    }

    [task waitUntilExit];
    [outHandle closeFile];

    NSString *output = [NSString stringWithContentsOfFile:outPath
                                                 encoding:NSUTF8StringEncoding
                                                    error:nil] ?: @"";
    [fm removeItemAtPath:leftPath  error:nil];
    [fm removeItemAtPath:rightPath error:nil];
    [fm removeItemAtPath:outPath   error:nil];

    return [self parseOutput:output];
}

// Parse normal diff format lines like "1,3c5,7" or "4a8" or "10d2"
+ (NSArray<DiffHunk *> *)parseOutput:(NSString *)diff {
    NSMutableArray<DiffHunk *> *hunks = [NSMutableArray array];

    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression
              regularExpressionWithPattern:@"^(\\d+)(?:,(\\d+))?([adc])(\\d+)(?:,(\\d+))?"
                                   options:NSRegularExpressionAnchorsMatchLines
                                     error:nil];
    });

    for (NSString *line in [diff componentsSeparatedByString:@"\n"]) {
        NSTextCheckingResult *m = [re firstMatchInString:line options:0
                                                   range:NSMakeRange(0, line.length)];
        if (!m) continue;

        NSInteger l1 = [self int:m group:1 in:line];
        NSInteger l2 = ([m rangeAtIndex:2].location != NSNotFound) ? [self int:m group:2 in:line] : l1;
        NSString  *cmd = [line substringWithRange:[m rangeAtIndex:3]];
        NSInteger r1 = [self int:m group:4 in:line];
        NSInteger r2 = ([m rangeAtIndex:5].location != NSNotFound) ? [self int:m group:5 in:line] : r1;

        DiffHunk *h   = [DiffHunk new];
        h.leftStart   = l1;
        h.leftEnd     = l2;
        h.rightStart  = r1;
        h.rightEnd    = r2;

        if ([cmd isEqual:@"a"]) {
            h.type       = DiffHunkTypeAdded;
            h.leftStart  = 0; h.leftEnd = 0;  // no lines removed on left
        } else if ([cmd isEqual:@"d"]) {
            h.type       = DiffHunkTypeDeleted;
            h.rightStart = 0; h.rightEnd = 0; // no lines added on right
        } else {
            h.type = DiffHunkTypeChanged;
        }
        [hunks addObject:h];
    }
    return hunks;
}

+ (NSInteger)int:(NSTextCheckingResult *)m group:(NSUInteger)g in:(NSString *)s {
    NSRange r = [m rangeAtIndex:g];
    return (r.location == NSNotFound) ? 0 : [[s substringWithRange:r] integerValue];
}

@end
