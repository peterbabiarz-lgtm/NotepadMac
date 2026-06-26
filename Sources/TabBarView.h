#pragma once
#import <Cocoa/Cocoa.h>

@class TabBarView;

@protocol TabBarViewDelegate <NSObject>
- (void)tabBarView:(TabBarView *)bar didSelectIndex:(NSInteger)index;
- (void)tabBarView:(TabBarView *)bar didCloseIndex:(NSInteger)index;
@end

@interface TabBarView : NSView

@property (nonatomic, weak) id<TabBarViewDelegate> delegate;
@property (nonatomic, copy) NSArray<NSString *> *tabTitles;
@property (nonatomic) NSInteger selectedIndex;

@end
