#import "LogParser.h"

NS_ASSUME_NONNULL_BEGIN

// Field separators in key=value logs: space or tab.
static inline BOOL NMLogIsSep(UniChar c) { return c == ' ' || c == '\t'; }

// Resolve \" and \\ escapes inside a quoted value. Only invoked when an escape
// was seen, so the common (escape-free) path allocates nothing.
static NSString *NMLogUnescape(NSString *s) {
    NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
    NSUInteger n = s.length;
    for (NSUInteger j = 0; j < n; j++) {
        unichar c = [s characterAtIndex:j];
        if (c == '\\' && j + 1 < n) [out appendFormat:@"%C", [s characterAtIndex:++j]];
        else                        [out appendFormat:@"%C", c];
    }
    return out;
}

// ── NMBaseLogParser ───────────────────────────────────────────────────────────

@implementation NMBaseLogParser

- (NSString *)vendorName { return @"Base"; }
- (BOOL)canParseLine:(NSString *)line { return NO; }
- (nullable NSDictionary<NSString *, id> *)parseLine:(NSString *)line {
    return [self parseKeyValuePairs:line];
}

- (NSMutableDictionary<NSString *, NSString *> *)parseKeyValuePairs:(NSString *)line {
    NSMutableDictionary<NSString *, NSString *> *result = [NSMutableDictionary dictionary];
    CFIndex len = line ? (CFIndex)line.length : 0;
    if (len == 0) return result;

    // Walk the string with an inline buffer — O(1) char access without the
    // per-call overhead of -characterAtIndex:, and no regex (no ReDoS risk on
    // adversarial input).
    CFStringInlineBuffer buf;
    CFStringInitInlineBuffer((__bridge CFStringRef)line, &buf, CFRangeMake(0, len));
    #define NM_CH(idx) CFStringGetCharacterFromInlineBuffer(&buf, (idx))

    CFIndex i = 0;
    while (i < len) {
        // Skip separators between tokens
        while (i < len && NMLogIsSep(NM_CH(i))) i++;
        if (i >= len) break;

        // Read key up to '=' or whitespace
        CFIndex keyStart = i;
        while (i < len) { UniChar c = NM_CH(i); if (c == '=' || NMLogIsSep(c)) break; i++; }
        if (i >= len || NM_CH(i) != '=') {
            // No '=' — skip the rest of this token
            while (i < len && !NMLogIsSep(NM_CH(i))) i++;
            continue;
        }
        NSString *key = [line substringWithRange:
                         NSMakeRange((NSUInteger)keyStart, (NSUInteger)(i - keyStart))];
        i++; // skip '='

        // Read value — quoted (with \" / \\ escapes) or bare
        NSString *value;
        if (i < len && NM_CH(i) == '"') {
            i++; // opening quote
            CFIndex valStart = i;
            BOOL sawEscape = NO;
            while (i < len) {
                UniChar c = NM_CH(i);
                if (c == '\\' && i + 1 < len) { sawEscape = YES; i += 2; continue; }
                if (c == '"') break;
                i++;
            }
            value = [line substringWithRange:
                     NSMakeRange((NSUInteger)valStart, (NSUInteger)(i - valStart))];
            if (sawEscape) value = NMLogUnescape(value);
            if (i < len) i++; // closing quote
        } else {
            CFIndex valStart = i;
            while (i < len && !NMLogIsSep(NM_CH(i))) i++;
            value = [line substringWithRange:
                     NSMakeRange((NSUInteger)valStart, (NSUInteger)(i - valStart))];
        }

        if (key.length) result[key] = value;  // empty key → value consumed, dropped
    }
    #undef NM_CH
    return result;
}

@end

// ── NMFortiGateLogParser ──────────────────────────────────────────────────────

@interface NMFortiGateLogParser : NMBaseLogParser
@end

@implementation NMFortiGateLogParser

- (NSString *)vendorName { return @"FortiGate"; }

- (BOOL)canParseLine:(NSString *)line {
    // FortiGate lines always carry logid= and devname= (or at least logid=).
    // Use a simple substring check — no regex, O(n) guaranteed.
    return [line rangeOfString:@"logid="].location != NSNotFound &&
           ([line rangeOfString:@"devname="].location != NSNotFound ||
            [line rangeOfString:@"type="].location != NSNotFound);
}

- (nullable NSDictionary<NSString *, id> *)parseLine:(NSString *)line {
    NSMutableDictionary<NSString *, NSString *> *raw = [self parseKeyValuePairs:line];
    if (!raw.count) return nil;

    NSMutableDictionary<NSString *, id> *out = [NSMutableDictionary dictionary];

    // ── Timestamp reconstruction ──────────────────────────────────────────────
    NSString *date = raw[@"date"];
    NSString *time = raw[@"time"];
    if (date && time) {
        out[@"timestamp"] = [NSString stringWithFormat:@"%@ %@", date, time];
        [raw removeObjectForKey:@"date"];
        [raw removeObjectForKey:@"time"];
    } else if (date) {
        out[@"timestamp"] = date;
        [raw removeObjectForKey:@"date"];
    }

    // ── Standard identity fields ──────────────────────────────────────────────
    for (NSString *field in @[@"logid", @"type", @"subtype", @"level",
                               @"devname", @"devid", @"vd", @"action",
                               @"policyid", @"sessionid", @"proto",
                               @"service", @"app", @"appcat",
                               @"msg", @"logdesc"]) {
        NSString *val = raw[field];
        if (val) {
            out[field] = val;
            [raw removeObjectForKey:field];
        }
    }

    // ── Network group (IP/port fields) ────────────────────────────────────────
    NSMutableDictionary<NSString *, NSString *> *net = [NSMutableDictionary dictionary];
    for (NSString *field in @[@"srcip", @"srcport", @"srcintf", @"srcintfrole",
                               @"dstip", @"dstport", @"dstintf", @"dstintfrole",
                               @"tranip", @"tranport", @"transip", @"transport"]) {
        NSString *val = raw[field];
        if (val) {
            net[field] = val;
            [raw removeObjectForKey:field];
        }
    }
    if (net.count) out[@"network"] = [net copy];

    // ── Bytes / counters group ────────────────────────────────────────────────
    NSMutableDictionary<NSString *, NSString *> *counters = [NSMutableDictionary dictionary];
    for (NSString *field in @[@"sentbyte", @"rcvdbyte", @"sentpkt", @"rcvdpkt",
                               @"duration"]) {
        NSString *val = raw[field];
        if (val) {
            counters[field] = val;
            [raw removeObjectForKey:field];
        }
    }
    if (counters.count) out[@"counters"] = [counters copy];

    // ── Remaining fields passed through as-is ─────────────────────────────────
    if (raw.count) out[@"extra"] = [raw copy];

    return [out copy];
}

@end

// ── NMCiscoASALogParser ───────────────────────────────────────────────────────
// Example: %ASA-6-302013: Built inbound TCP connection 12345 for outside:10.1.1.1/55000 ...

@interface NMCiscoASALogParser : NMBaseLogParser
@end

@implementation NMCiscoASALogParser

- (NSString *)vendorName { return @"CiscoASA"; }

- (BOOL)canParseLine:(NSString *)line {
    return [line rangeOfString:@"%ASA-"].location != NSNotFound;
}

- (nullable NSDictionary<NSString *, id> *)parseLine:(NSString *)line {
    if (!line.length) return nil;

    NSMutableDictionary<NSString *, id> *out = [NSMutableDictionary dictionary];

    // Parse %ASA-<severity>-<msgid>: <body>
    NSRange prefixRange = [line rangeOfString:@"%ASA-"];
    if (prefixRange.location == NSNotFound) return nil;

    NSUInteger pos = prefixRange.location + prefixRange.length;
    NSUInteger len = line.length;

    // Severity digit
    if (pos < len && [line characterAtIndex:pos] != '-') {
        out[@"severity"] = [NSString stringWithFormat:@"%C", [line characterAtIndex:pos]];
        pos++;
    }
    if (pos < len && [line characterAtIndex:pos] == '-') pos++;

    // Message ID (up to ':')
    NSUInteger msgStart = pos;
    while (pos < len && [line characterAtIndex:pos] != ':') pos++;
    if (pos > msgStart) out[@"msgid"] = [line substringWithRange:NSMakeRange(msgStart, pos - msgStart)];
    if (pos < len) pos++; // skip ':'
    while (pos < len && [line characterAtIndex:pos] == ' ') pos++;

    if (pos < len) out[@"msg"] = [line substringFromIndex:pos];

    out[@"vendor_raw"] = line;
    return [out copy];
}

@end

// ── NMLogParserRegistry ───────────────────────────────────────────────────────

@implementation NMLogParserRegistry {
    NSMutableArray<id<NMLogParser>> *_parsers;
}

+ (instancetype)shared {
    static NMLogParserRegistry *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[NMLogParserRegistry alloc] init];
        // Register built-in parsers in priority order
        [instance registerParser:[[NMFortiGateLogParser alloc] init]];
        [instance registerParser:[[NMCiscoASALogParser alloc] init]];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) _parsers = [NSMutableArray array];
    return self;
}

- (void)registerParser:(id<NMLogParser>)parser {
    [_parsers addObject:parser];
}

- (NSArray<id<NMLogParser>> *)parsers {
    return [_parsers copy];
}

- (nullable NSDictionary<NSString *, id> *)parseLine:(NSString *)line {
    for (id<NMLogParser> parser in _parsers) {
        if ([parser canParseLine:line]) return [parser parseLine:line];
    }
    return nil;
}

- (nullable NSDictionary<NSString *, id> *)parseLine:(NSString *)line
                                              vendor:(NSString *)vendor {
    NSString *lower = vendor.lowercaseString;
    for (id<NMLogParser> parser in _parsers) {
        if ([parser.vendorName.lowercaseString isEqualToString:lower])
            return [parser parseLine:line];
    }
    return nil;
}

@end

// ── Usage example / smoke test (call from lldb or a unit test) ───────────────

void NMLogParserRunExample(void) {
    NMLogParserRegistry *reg = [NMLogParserRegistry shared];

    NSString *fgLine =
        @"date=2024-01-01 time=12:00:00 logid=0000000013 type=traffic subtype=forward "
        @"level=notice devname=FGT01 devid=FG100 vd=root srcip=10.1.1.1 srcport=54321 "
        @"srcintf=internal dstip=8.8.8.8 dstport=443 dstintf=wan1 "
        @"policyid=5 action=accept service=HTTPS proto=6 "
        @"sentbyte=1024 rcvdbyte=4096 duration=30";
    NSString *asaLine =
        @"%ASA-6-302013: Built inbound TCP connection 54321 for "
        @"outside:203.0.113.1/12345 (203.0.113.1/12345) to "
        @"inside:10.0.0.5/80 (192.168.1.5/80)";
    NSArray<NSString *> *lines = @[fgLine, asaLine, @"some unrecognised log line with no vendor signature"];

    for (NSString *line in lines) {
        NSDictionary<NSString *, id> *parsed = [reg parseLine:line];
        if (parsed) {
            NSLog(@"[LogParser] Parsed: %@", parsed);
        } else {
            NSLog(@"[LogParser] No parser matched: %@", [line substringToIndex:MIN(80u, line.length)]);
        }
    }

    // Force-vendor test
    NSDictionary *fg = [reg parseLine:fgLine vendor:@"FortiGate"];
    NSLog(@"[LogParser] FortiGate network group: %@", fg[@"network"]);
}

NS_ASSUME_NONNULL_END
