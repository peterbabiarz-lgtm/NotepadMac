// NMTest — a tiny Foundation-only test harness.
//
// XCTest lives only inside a full Xcode install; this project builds with the
// Command Line Tools + a hand-written Makefile, so the tests use this minimal
// macro framework instead. It needs nothing but Foundation, compiles into a
// plain CLI executable, and exits non-zero on any failure (CI-friendly).
#pragma once
#import <Foundation/Foundation.h>
#import <stdio.h>

extern int nm_checks;   // total assertions evaluated
extern int nm_failed;   // assertions that failed

// Run one test function; prints ✓/✗ based on whether it added any failures.
#define NM_RUN(fn)  do {                                            \
    int _before = nm_failed;                                        \
    fn();                                                           \
    printf("  %s %s\n", (nm_failed == _before) ? "\xE2\x9C\x93"     \
                                               : "\xE2\x9C\x97", #fn); \
} while (0)

#define NM_FAIL(fmt, ...)  do {                                     \
    nm_failed++;                                                    \
    printf("      FAIL %s:%d  " fmt "\n",                           \
           __FILE__, __LINE__, ##__VA_ARGS__);                      \
} while (0)

#define NM_EXPECT(cond)  do {                                       \
    nm_checks++;                                                    \
    if (!(cond)) NM_FAIL("expected true: %s", #cond);               \
} while (0)

#define NM_EXPECT_TRUE(cond)  NM_EXPECT(cond)
#define NM_EXPECT_FALSE(cond) do { nm_checks++; if (cond) NM_FAIL("expected false: %s", #cond); } while (0)

// %@ is not valid for C printf, so render the objects to C strings first.
#define NM_EXPECT_EQ_OBJ(a, b)  do {                                \
    nm_checks++;                                                    \
    id _a = (a); id _b = (b);                                       \
    if (!((_a == _b) || [_a isEqual:_b]))                           \
        NM_FAIL("%s != %s  (%s  vs  %s)", #a, #b,                   \
                [[_a description] UTF8String] ?: "(nil)",           \
                [[_b description] UTF8String] ?: "(nil)");          \
} while (0)

#define NM_EXPECT_EQ_INT(a, b)  do {                                \
    nm_checks++;                                                    \
    long _a = (long)(a); long _b = (long)(b);                       \
    if (_a != _b) NM_FAIL("%s != %s  (%ld  vs  %ld)", #a, #b, _a, _b); \
} while (0)

#define NM_EXPECT_NIL(a)     do { nm_checks++; if ((a) != nil) NM_FAIL("expected nil: %s", #a); } while (0)
#define NM_EXPECT_NOTNIL(a)  do { nm_checks++; if ((a) == nil) NM_FAIL("expected non-nil: %s", #a); } while (0)
