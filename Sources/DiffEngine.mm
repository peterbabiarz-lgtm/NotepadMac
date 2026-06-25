#import "DiffEngine.h"

@implementation DiffHunk
@end

@implementation DiffEngine

+ (NSArray<DiffHunk *> *)diffLeft:(NSString *)left right:(NSString *)right {
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *leftPath  = [tmpDir stringByAppendingPathComponent:@"_nmdiff_a.txt"];
    NSString *rightPath = [tmpDir stringByAppendingPathComponent:@"_nmdiff_b.txt"];

    [left  writeToFile:leftPath  atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [right writeToFile:rightPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSTask *task  = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/diff"];
    task.arguments     = @[leftPath, rightPath];

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError  = [NSFileHandle fileHandleWithNullDevice];

    NSError *err;
    [task launchAndReturnError:&err];
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];

    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
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
