#pragma once
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, DiffHunkType) {
    DiffHunkTypeAdded,    // lines present only in right
    DiffHunkTypeDeleted,  // lines present only in left
    DiffHunkTypeChanged,  // lines changed between left and right
};

@interface DiffHunk : NSObject
@property (nonatomic, assign) NSInteger leftStart;   // 1-based; 0 = no lines (insertion point only)
@property (nonatomic, assign) NSInteger leftEnd;
@property (nonatomic, assign) NSInteger rightStart;
@property (nonatomic, assign) NSInteger rightEnd;
@property (nonatomic, assign) DiffHunkType type;
@end

@interface DiffEngine : NSObject
// Returns hunks describing differences between left and right text.
+ (NSArray<DiffHunk *> *)diffLeft:(NSString *)left right:(NSString *)right;
@end
