#import "NMTest.h"
#import "LogParser.h"

// ── Base key=value tokenizer ──────────────────────────────────────────────────

static void test_kv_basic(void) {
    NSDictionary *d = [[NMBaseLogParser new] parseKeyValuePairs:@"a=1 b=2 c=hello"];
    NM_EXPECT_EQ_INT(d.count, 3);
    NM_EXPECT_EQ_OBJ(d[@"a"], @"1");
    NM_EXPECT_EQ_OBJ(d[@"b"], @"2");
    NM_EXPECT_EQ_OBJ(d[@"c"], @"hello");
}

static void test_kv_quoted_value(void) {
    NSDictionary *d = [[NMBaseLogParser new] parseKeyValuePairs:@"msg=\"hello world\" k=v"];
    NM_EXPECT_EQ_OBJ(d[@"msg"], @"hello world");
    NM_EXPECT_EQ_OBJ(d[@"k"], @"v");
}

static void test_kv_escaped_quote(void) {
    // value contains an escaped quote: path="a\"b"  → a"b
    NSDictionary *d = [[NMBaseLogParser new] parseKeyValuePairs:@"path=\"a\\\"b\""];
    NM_EXPECT_EQ_OBJ(d[@"path"], @"a\"b");
}

static void test_kv_tab_separator(void) {
    NSDictionary *d = [[NMBaseLogParser new] parseKeyValuePairs:@"a=1\tb=2"];
    NM_EXPECT_EQ_OBJ(d[@"a"], @"1");
    NM_EXPECT_EQ_OBJ(d[@"b"], @"2");
}

static void test_kv_malformed_skipped(void) {
    NSDictionary *d = [[NMBaseLogParser new] parseKeyValuePairs:@"loosetoken noequals a=1"];
    NM_EXPECT_EQ_OBJ(d[@"a"], @"1");
    NM_EXPECT_NIL(d[@"loosetoken"]);
    NM_EXPECT_NIL(d[@"noequals"]);
}

static void test_kv_empty(void) {
    NM_EXPECT_EQ_INT([[NMBaseLogParser new] parseKeyValuePairs:@""].count, 0);
}

// ── FortiGate (via registry auto-detect) ──────────────────────────────────────

static void test_fortigate_groups(void) {
    NSString *line = @"date=2024-01-01 time=12:00:00 logid=0000000013 type=traffic "
                      "devname=FGT01 srcip=10.1.1.1 srcport=54321 dstip=8.8.8.8 "
                      "dstport=443 action=accept sentbyte=1024 rcvdbyte=4096";
    NSDictionary *d = [[NMLogParserRegistry shared] parseLine:line];
    NM_EXPECT_NOTNIL(d);
    NM_EXPECT_EQ_OBJ(d[@"action"], @"accept");
    NM_EXPECT_EQ_OBJ(d[@"timestamp"], @"2024-01-01 12:00:00");
    NM_EXPECT_EQ_OBJ(((NSDictionary *)d[@"network"])[@"srcip"], @"10.1.1.1");
    NM_EXPECT_EQ_OBJ(((NSDictionary *)d[@"network"])[@"dstport"], @"443");
    NM_EXPECT_EQ_OBJ(((NSDictionary *)d[@"counters"])[@"sentbyte"], @"1024");
}

// ── Cisco ASA ─────────────────────────────────────────────────────────────────

static void test_cisco_asa(void) {
    NSDictionary *d = [[NMLogParserRegistry shared]
                       parseLine:@"%ASA-6-302013: Built inbound TCP connection 54321"];
    NM_EXPECT_NOTNIL(d);
    NM_EXPECT_EQ_OBJ(d[@"severity"], @"6");
    NM_EXPECT_EQ_OBJ(d[@"msgid"], @"302013");
}

static void test_unrecognised_returns_nil(void) {
    NM_EXPECT_NIL([[NMLogParserRegistry shared] parseLine:@"just some random text here"]);
}

void runLogParserTests(void) {
    NM_RUN(test_kv_basic);
    NM_RUN(test_kv_quoted_value);
    NM_RUN(test_kv_escaped_quote);
    NM_RUN(test_kv_tab_separator);
    NM_RUN(test_kv_malformed_skipped);
    NM_RUN(test_kv_empty);
    NM_RUN(test_fortigate_groups);
    NM_RUN(test_cisco_asa);
    NM_RUN(test_unrecognised_returns_nil);
}
