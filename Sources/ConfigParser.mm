#import "ConfigParser.h"

NS_ASSUME_NONNULL_BEGIN

// ── Tokeniser ─────────────────────────────────────────────────────────────────
// Splits one config line into tokens.  Respects double-quoted strings (with
// \" and \\ escapes) as single tokens; quotes are stripped.  Never throws;
// returns empty array for blank/comment lines.
//
// Uses CFStringInlineBuffer for O(1) char access without the per-call overhead
// of -characterAtIndex:, which matters on large multi-megabyte configs.

static inline BOOL NMCfgIsWS(UniChar c) { return c == ' ' || c == '\t'; }

// Resolve \" and \\ escapes. Only invoked when an escape was actually seen, so
// the common (escape-free) path allocates nothing.
static NSString *NMCfgUnescape(NSString *s) {
    NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
    NSUInteger n = s.length;
    for (NSUInteger j = 0; j < n; j++) {
        unichar c = [s characterAtIndex:j];
        if (c == '\\' && j + 1 < n) [out appendFormat:@"%C", [s characterAtIndex:++j]];
        else                        [out appendFormat:@"%C", c];
    }
    return out;
}

static NSArray<NSString *> *NMTokeniseLine(NSString *line) {
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    CFIndex len = line ? (CFIndex)line.length : 0;
    if (len == 0) return tokens;

    CFStringInlineBuffer buf;
    CFStringInitInlineBuffer((__bridge CFStringRef)line, &buf, CFRangeMake(0, len));
    #define NM_CH(idx) CFStringGetCharacterFromInlineBuffer(&buf, (idx))

    CFIndex i = 0;
    while (i < len) {
        while (i < len && NMCfgIsWS(NM_CH(i))) i++;       // skip whitespace
        if (i >= len) break;

        UniChar c = NM_CH(i);
        if (c == '#') break;                              // comment — ignore rest

        if (c == '"') {                                   // quoted token
            i++;
            CFIndex start = i;
            BOOL sawEscape = NO;
            while (i < len) {
                UniChar d = NM_CH(i);
                if (d == '\\' && i + 1 < len) { sawEscape = YES; i += 2; continue; }
                if (d == '"') break;
                i++;
            }
            NSString *tok = [line substringWithRange:
                             NSMakeRange((NSUInteger)start, (NSUInteger)(i - start))];
            [tokens addObject:sawEscape ? NMCfgUnescape(tok) : tok];
            if (i < len) i++;                             // skip closing quote
        } else {                                          // bare token
            CFIndex start = i;
            while (i < len && !NMCfgIsWS(NM_CH(i))) i++;
            [tokens addObject:[line substringWithRange:
                               NSMakeRange((NSUInteger)start, (NSUInteger)(i - start))]];
        }
    }
    #undef NM_CH
    return tokens;
}

// Joins tokens[1..] into a single value string.
static NSString *NMJoinValues(NSArray<NSString *> *tokens, NSUInteger from) {
    if (from >= tokens.count) return @"";
    if (tokens.count - from == 1) return tokens[from];
    return [[tokens subarrayWithRange:NSMakeRange(from, tokens.count - from)]
            componentsJoinedByString:@" "];
}

// Normalise a section name: lowercase, spaces → underscores.
static NSString *NMNormaliseKey(NSString *s) {
    return [s.lowercaseString stringByReplacingOccurrencesOfString:@" " withString:@"_"];
}

// ── Stack frame ───────────────────────────────────────────────────────────────

typedef NS_ENUM(NSInteger, NMConfigFrameKind) {
    NMConfigFrameKindSection, // inside "config X Y"
    NMConfigFrameKindObject,  // inside "edit <id>"
};

@interface NMConfigFrame : NSObject
@property (nonatomic, assign) NMConfigFrameKind kind;
@property (nonatomic, copy)   NSString *sectionKey;       // normalised, only for Section frames
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *object; // current object/section dict
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *entries;     // edit entries (Section only)
@property (nonatomic, assign) BOOL hasEntries;            // YES if any "edit" was seen
@end
@implementation NMConfigFrame @end

// ── FortiGate parser ──────────────────────────────────────────────────────────

@implementation NMFortiGateConfigParser

- (NSString *)vendorName { return @"FortiGate"; }

- (BOOL)canParseConfig:(NSString *)text {
    if (!text.length) return NO;
    // FortiGate configs open sections with the "config " keyword; require a
    // block delimiter too so we don't claim arbitrary prose containing "config".
    return [text rangeOfString:@"config "].location != NSNotFound &&
           ([text rangeOfString:@"edit "].location != NSNotFound ||
            [text rangeOfString:@"end"].location   != NSNotFound);
}

- (NSDictionary<NSString *, id> *)parseConfig:(NSString *)text {
    NSMutableDictionary<NSString *, id> *result = [NSMutableDictionary dictionary];
    NSMutableArray<NMConfigFrame *> *stack = [NSMutableArray array];
    if (!text.length) return result;

    // Stream lines instead of materialising one big array — bounded memory on
    // large configs, and correct across LF / CRLF / CR line endings.
    [text enumerateLinesUsingBlock:^(NSString *rawLine, BOOL *stop) {
        NSArray<NSString *> *tokens = NMTokeniseLine(rawLine);
        if (!tokens.count) return;

        NSString *cmd = tokens[0].lowercaseString;

        // ── config <section name…> ────────────────────────────────────────────
        if ([cmd isEqual:@"config"] && tokens.count >= 2) {
            NMConfigFrame *frame = [[NMConfigFrame alloc] init];
            frame.kind       = NMConfigFrameKindSection;
            frame.sectionKey = NMNormaliseKey(NMJoinValues(tokens, 1));
            frame.object     = [NSMutableDictionary dictionary];
            frame.entries    = [NSMutableArray array];
            frame.hasEntries = NO;
            [stack addObject:frame];
            return;
        }

        // ── edit <id> ─────────────────────────────────────────────────────────
        if ([cmd isEqual:@"edit"] && tokens.count >= 2) {
            if (![self currentSectionInStack:stack]) return;  // "edit" outside config
            if (stack.lastObject.kind == NMConfigFrameKindObject)
                [self closeObjectFrame:stack intoResult:result]; // implicit missing "next"

            NMConfigFrame *objFrame = [[NMConfigFrame alloc] init];
            objFrame.kind   = NMConfigFrameKindObject;
            objFrame.object = [NSMutableDictionary dictionary];

            // id may be an integer (policies) or a name (interfaces). Keep it a
            // number only if it round-trips exactly, so "007" / "port1" stay strings.
            NSString *idStr = NMJoinValues(tokens, 1);
            NSInteger idInt = idStr.integerValue;
            objFrame.object[@"id"] = [[@(idInt) stringValue] isEqualToString:idStr]
                                     ? @(idInt) : idStr;
            [stack addObject:objFrame];
            return;
        }

        // ── set key value… ────────────────────────────────────────────────────
        if ([cmd isEqual:@"set"] && tokens.count >= 2) {
            NMConfigFrame *top = stack.lastObject;
            if (!top) return;
            top.object[NMNormaliseKey(tokens[1])] = NMJoinValues(tokens, 2);
            return;
        }

        // ── unset key ─────────────────────────────────────────────────────────
        if ([cmd isEqual:@"unset"] && tokens.count >= 2) {
            [stack.lastObject.object removeObjectForKey:NMNormaliseKey(tokens[1])];
            return;
        }

        // ── next ──────────────────────────────────────────────────────────────
        if ([cmd isEqual:@"next"]) {
            if (stack.lastObject.kind == NMConfigFrameKindObject)
                [self closeObjectFrame:stack intoResult:result];
            return; // "next" outside an object frame is a no-op
        }

        // ── end ───────────────────────────────────────────────────────────────
        if ([cmd isEqual:@"end"]) {
            if (stack.lastObject.kind == NMConfigFrameKindObject)
                [self closeObjectFrame:stack intoResult:result];
            // Guard on count: NMConfigFrameKindSection == 0, so nil.kind would
            // otherwise match an empty stack and pop past the end.
            if (stack.count && stack.lastObject.kind == NMConfigFrameKindSection)
                [self closeSectionFrame:stack intoResult:result];
            return;
        }

        // All other commands (append, rename, …) are ignored safely.
    }];

    // Drain remaining open frames (missing "end"s)
    while (stack.count) {
        if (stack.lastObject.kind == NMConfigFrameKindObject)
            [self closeObjectFrame:stack intoResult:result];
        else
            [self closeSectionFrame:stack intoResult:result];
    }

    return [result copy];
}

// MARK: – Frame helpers

- (nullable NMConfigFrame *)currentSectionInStack:(NSArray<NMConfigFrame *> *)stack {
    for (NMConfigFrame *f in stack.reverseObjectEnumerator) {
        if (f.kind == NMConfigFrameKindSection) return f;
    }
    return nil;
}

// Pops the top object frame and appends its object dict to the enclosing
// section's entries list.
- (void)closeObjectFrame:(NSMutableArray<NMConfigFrame *> *)stack
            intoResult:(NSMutableDictionary *)result {
    NMConfigFrame *objFrame = stack.lastObject;
    if (objFrame.kind != NMConfigFrameKindObject) return;
    [stack removeLastObject];

    NMConfigFrame *section = [self currentSectionInStack:stack];
    if (section) {
        section.hasEntries = YES;
        [section.entries addObject:[objFrame.object copy]];
    }
    // If there's no enclosing section (shouldn't happen in valid config) just discard
}

// Pops the top section frame and writes its collected data into result.
- (void)closeSectionFrame:(NSMutableArray<NMConfigFrame *> *)stack
             intoResult:(NSMutableDictionary *)result {
    if (!stack.count) return;  // nil.kind == Section (0); never pop past the end
    NMConfigFrame *section = stack.lastObject;
    if (section.kind != NMConfigFrameKindSection) return;
    [stack removeLastObject];

    id value;
    if (section.hasEntries) {
        // Section had edit/next objects → array
        value = [section.entries copy];
    } else if (section.object.count) {
        // Flat section (only "set" lines, no "edit") → dict
        value = [section.object copy];
    } else {
        // Empty section — omit entirely
        return;
    }

    // Merge into parent section or top-level result
    NMConfigFrame *parent = [self currentSectionInStack:stack];
    if (parent) {
        parent.object[section.sectionKey] = value;
    } else {
        // Check for key collision: merge arrays, wrap conflicting values
        id existing = result[section.sectionKey];
        if (!existing) {
            result[section.sectionKey] = value;
        } else if ([existing isKindOfClass:[NSArray class]] &&
                   [value isKindOfClass:[NSArray class]]) {
            result[section.sectionKey] = [existing arrayByAddingObjectsFromArray:value];
        } else {
            // Wrap both in an array to avoid data loss
            result[section.sectionKey] = @[existing, value];
        }
    }
}

@end

// ── NMConfigParserRegistry ────────────────────────────────────────────────────

@implementation NMConfigParserRegistry {
    NSMutableArray<id<NMConfigParser>> *_parsers;
}

+ (instancetype)shared {
    static NMConfigParserRegistry *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[NMConfigParserRegistry alloc] init];
        [instance registerParser:[[NMFortiGateConfigParser alloc] init]];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) _parsers = [NSMutableArray array];
    return self;
}

- (void)registerParser:(id<NMConfigParser>)parser { [_parsers addObject:parser]; }
- (NSArray<id<NMConfigParser>> *)parsers { return [_parsers copy]; }

- (nullable NSDictionary<NSString *, id> *)parseConfig:(NSString *)text {
    for (id<NMConfigParser> parser in _parsers) {
        if ([parser canParseConfig:text]) return [parser parseConfig:text];
    }
    return nil;
}

@end

// ── Utilities ─────────────────────────────────────────────────────────────────

NSData * _Nullable NMConfigToJSONData(NSDictionary<NSString *, id> *config, NSError **error) {
    if (![NSJSONSerialization isValidJSONObject:config]) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                                code:NSPropertyListWriteInvalidError
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                       @"Config dict is not JSON-serialisable"}];
        return nil;
    }
    return [NSJSONSerialization dataWithJSONObject:config
                                           options:NSJSONWritingPrettyPrinted
                                             error:error];
}

// ── Example / smoke test ──────────────────────────────────────────────────────

void NMConfigParserRunExample(void) {
    NSString *sample =
        @"config firewall policy\n"
        @"    edit 1\n"
        @"        set srcintf \"port1\"\n"
        @"        set dstintf \"port2\"\n"
        @"        set srcaddr \"all\"\n"
        @"        set dstaddr \"all\"\n"
        @"        set action accept\n"
        @"        set schedule \"always\"\n"
        @"        set service \"ALL\"\n"
        @"        set logtraffic all\n"
        @"    next\n"
        @"    edit 2\n"
        @"        set srcintf \"port2\"\n"
        @"        set dstintf \"port1\"\n"
        @"        set action deny\n"
        @"    next\n"          // last "next" with no closing "end" — handled gracefully
        @"end\n"
        @"\n"
        @"config system interface\n"
        @"    edit \"port1\"\n"
        @"        set ip 192.168.1.1 255.255.255.0\n"
        @"        set allowaccess ping https ssh\n"
        @"        set type physical\n"
        @"    next\n"
        @"    edit \"port2\"\n"
        @"        set ip 10.0.0.1 255.255.255.0\n"
        @"        set allowaccess ping\n"
        @"        set type physical\n"
        @"    next\n"
        @"end\n"
        @"\n"
        @"config system global\n"
        @"    set hostname \"FGT-01\"\n"
        @"    set timezone 26\n"
        @"    set admintimeout 30\n"
        @"end\n"
        @"\n"
        // Intentionally malformed: missing "next" before "end"
        @"config firewall address\n"
        @"    edit \"internal-net\"\n"
        @"        set subnet 192.168.1.0 255.255.255.0\n"
        @"        # missing next\n"
        @"end\n";

    NMFortiGateConfigParser *parser = [[NMFortiGateConfigParser alloc] init];
    NSDictionary *result = [parser parseConfig:sample];

    NSError *err = nil;
    NSData *json = NMConfigToJSONData(result, &err);
    if (json) {
        NSString *str = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
        NSLog(@"[ConfigParser] Result:\n%@", str);
    } else {
        NSLog(@"[ConfigParser] JSON error: %@", err);
    }

    // Spot-checks
    NSArray *policies = result[@"firewall_policy"];
    NSLog(@"[ConfigParser] firewall_policy count: %lu", (unsigned long)policies.count);
    NSLog(@"[ConfigParser] policy[0] action: %@", policies[0][@"action"]);
    NSLog(@"[ConfigParser] system_global hostname: %@", [result[@"system_global"] valueForKey:@"hostname"]);
}

NS_ASSUME_NONNULL_END
