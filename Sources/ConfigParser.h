#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Protocol for vendor-specific config parsers (same plugin pattern as NMLogParser)
@protocol NMConfigParser <NSObject>
@property (nonatomic, readonly) NSString *vendorName;
// Cheap signature check used for auto-detection by the registry.
- (BOOL)canParseConfig:(NSString *)text;
- (NSDictionary<NSString *, id> *)parseConfig:(NSString *)text;
@end

// FortiGate CLI config parser.
// Handles: config/edit/set/next/end blocks, nested config blocks,
// missing "next", unknown commands (ignored), imperfect formatting.
@interface NMFortiGateConfigParser : NSObject <NMConfigParser>

// Parse a FortiGate CLI config string. Returns a dictionary whose keys are
// normalised section names (e.g. "firewall_policy") and whose values are
// arrays of objects (for sections containing "edit" entries) or nested
// dictionaries (for flat sections).
- (NSDictionary<NSString *, id> *)parseConfig:(NSString *)text;

@end

// Registry (plugin-like extension point) — mirrors NMLogParserRegistry so new
// vendors (Cisco IOS, Palo Alto, …) plug in without touching call sites.
@interface NMConfigParserRegistry : NSObject
+ (instancetype)shared;
- (void)registerParser:(id<NMConfigParser>)parser;
@property (nonatomic, readonly) NSArray<id<NMConfigParser>> *parsers;
// Auto-detect vendor and parse; returns nil if no parser recognises the text.
- (nullable NSDictionary<NSString *, id> *)parseConfig:(NSString *)text;
@end

// Convenience: parse and serialise to pretty-printed JSON data.
NSData * _Nullable NMConfigToJSONData(NSDictionary<NSString *, id> *config, NSError **error);

void NMConfigParserRunExample(void);

NS_ASSUME_NONNULL_END
