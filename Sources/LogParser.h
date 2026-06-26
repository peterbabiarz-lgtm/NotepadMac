#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// ── Parser contract ───────────────────────────────────────────────────────────
// A vendor parser turns one raw log line into a structured dictionary.
@protocol NMLogParser <NSObject>
@property (nonatomic, readonly) NSString *vendorName;
- (BOOL)canParseLine:(NSString *)line;
- (nullable NSDictionary<NSString *, id> *)parseLine:(NSString *)line;
@end

// ── Base parser ───────────────────────────────────────────────────────────────
// Provides a safe key=value tokenizer shared by all vendor parsers. Subclass and
// override parseLine: to add vendor-specific normalization; override canParseLine:
// to advertise a vendor signature.
@interface NMBaseLogParser : NSObject <NMLogParser>

// Tokenizes `key=value key2="quoted value" …`. Never throws; malformed tokens
// (no '=', empty key) are skipped. Returns an empty dictionary for empty input.
- (NSMutableDictionary<NSString *, NSString *> *)parseKeyValuePairs:(NSString *)line;

@end

// ── Registry (plugin-like extension point) ────────────────────────────────────
// Register one parser per vendor; new vendors (Cisco, Palo Alto, …) plug in here
// without touching existing code.
@interface NMLogParserRegistry : NSObject

+ (instancetype)shared;                                  // convenience singleton
- (void)registerParser:(id<NMLogParser>)parser;
@property (nonatomic, readonly) NSArray<id<NMLogParser>> *parsers;

// Auto-detect: first registered parser whose canParseLine: accepts the line.
- (nullable NSDictionary<NSString *, id> *)parseLine:(NSString *)line;
// Force a specific vendor by name (case-insensitive).
- (nullable NSDictionary<NSString *, id> *)parseLine:(NSString *)line
                                              vendor:(NSString *)vendor;

@end

NS_ASSUME_NONNULL_END
