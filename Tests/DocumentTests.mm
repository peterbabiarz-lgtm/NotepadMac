#import "NMTest.h"
#import "Document.h"

// Writes a temp file, runs the block, then removes it. Exercises the full
// initWithURL: encoding-detection path against real bytes on disk.
static void withTempFile(NSData *data, void (^block)(NSURL *url)) {
    NSURL *u = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                URLByAppendingPathComponent:
                    [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"txt"]];
    [data writeToURL:u atomically:YES];
    block(u);
    [[NSFileManager defaultManager] removeItemAtURL:u error:nil];
}

static void test_utf8_no_bom_round_trip(void) {
    NSString *text = @"Grüße — 日本語\nZeile 2\n";
    withTempFile([text dataUsingEncoding:NSUTF8StringEncoding], ^(NSURL *u) {
        Document *doc = [[Document alloc] initWithURL:u error:nil];
        NM_EXPECT_NOTNIL(doc);
        NM_EXPECT_EQ_OBJ(doc.content, text);
        NM_EXPECT_EQ_INT(doc.encoding, NSUTF8StringEncoding);
        NM_EXPECT_FALSE(doc.hasBOM);
    });
}

static void test_utf8_bom_detected(void) {
    uint8_t bom[] = {0xEF, 0xBB, 0xBF};
    NSMutableData *d = [NSMutableData dataWithBytes:bom length:3];
    [d appendData:[@"hello" dataUsingEncoding:NSUTF8StringEncoding]];
    withTempFile(d, ^(NSURL *u) {
        Document *doc = [[Document alloc] initWithURL:u error:nil];
        NM_EXPECT_EQ_OBJ(doc.content, @"hello");
        NM_EXPECT_TRUE(doc.hasBOM);
        NM_EXPECT_EQ_INT(doc.encoding, NSUTF8StringEncoding);
    });
}

static void test_utf16le_detected(void) {
    NSString *text = @"héllo wörld";
    uint8_t bom[] = {0xFF, 0xFE};
    NSMutableData *d = [NSMutableData dataWithBytes:bom length:2];
    [d appendData:[text dataUsingEncoding:NSUTF16LittleEndianStringEncoding]];
    withTempFile(d, ^(NSURL *u) {
        Document *doc = [[Document alloc] initWithURL:u error:nil];
        NM_EXPECT_EQ_INT(doc.encoding, NSUTF16LittleEndianStringEncoding);
        NM_EXPECT_TRUE([doc.content containsString:@"héllo wörld"]);
    });
}

static void test_utf16be_detected(void) {
    NSString *text = @"héllo wörld";
    uint8_t bom[] = {0xFE, 0xFF};
    NSMutableData *d = [NSMutableData dataWithBytes:bom length:2];
    [d appendData:[text dataUsingEncoding:NSUTF16BigEndianStringEncoding]];
    withTempFile(d, ^(NSURL *u) {
        Document *doc = [[Document alloc] initWithURL:u error:nil];
        NM_EXPECT_EQ_INT(doc.encoding, NSUTF16BigEndianStringEncoding);
        NM_EXPECT_TRUE([doc.content containsString:@"héllo wörld"]);
    });
}

static void test_save_round_trip(void) {
    withTempFile([@"original\n" dataUsingEncoding:NSUTF8StringEncoding], ^(NSURL *u) {
        Document *doc = [[Document alloc] initWithURL:u error:nil];
        doc.content = @"modified content ✓\n";
        NSError *err = nil;
        NM_EXPECT_TRUE([doc saveToURL:u error:&err]);
        NM_EXPECT_NIL(err);
        Document *reloaded = [[Document alloc] initWithURL:u error:nil];
        NM_EXPECT_EQ_OBJ(reloaded.content, @"modified content ✓\n");
    });
}

void runDocumentTests(void) {
    NM_RUN(test_utf8_no_bom_round_trip);
    NM_RUN(test_utf8_bom_detected);
    NM_RUN(test_utf16le_detected);
    NM_RUN(test_utf16be_detected);
    NM_RUN(test_save_round_trip);
}
