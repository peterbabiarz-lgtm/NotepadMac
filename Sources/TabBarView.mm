#import "TabBarView.h"

static const CGFloat kTabHeight      = 33.0;
static const CGFloat kTabMinWidth    = 80.0;
static const CGFloat kTabMaxWidth    = 200.0;
static const CGFloat kCloseSize      = 16.0;
static const CGFloat kClosePadRight  = 8.0;

@implementation TabBarView {
    NSInteger        _hoveredIndex;
    NSInteger        _hoveredCloseIndex;
    NSTrackingArea  *_trackingArea;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _hoveredIndex      = -1;
    _hoveredCloseIndex = -1;
    _selectedIndex     = 0;
    _tabTitles         = @[];
    return self;
}

// MARK: – Layout helpers

- (CGFloat)tabWidth {
    NSInteger count = (NSInteger)_tabTitles.count;
    if (count == 0) return kTabMaxWidth;
    CGFloat available = self.bounds.size.width;
    CGFloat natural = available / count;
    if (natural < kTabMinWidth) natural = kTabMinWidth;
    if (natural > kTabMaxWidth) natural = kTabMaxWidth;
    return natural;
}

- (NSRect)rectForTabAtIndex:(NSInteger)i {
    CGFloat w = [self tabWidth];
    return NSMakeRect(i * w, 0, w, kTabHeight);
}

- (NSRect)closeRectForTabAtIndex:(NSInteger)i {
    NSRect tab = [self rectForTabAtIndex:i];
    return NSMakeRect(NSMaxX(tab) - kCloseSize - kClosePadRight,
                      NSMidY(tab) - kCloseSize / 2,
                      kCloseSize, kCloseSize);
}

// MARK: – Drawing

- (BOOL)isDark {
    if (@available(macOS 10.14, *)) {
        NSAppearanceName best = [self.effectiveAppearance
            bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        return [best isEqualToString:NSAppearanceNameDarkAqua];
    }
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    BOOL dark = [self isDark];

    NSColor *barBg       = dark ? [NSColor colorWithWhite:0.17 alpha:1]
                                : [NSColor colorWithWhite:0.89 alpha:1];
    NSColor *tabSel      = dark ? [NSColor colorWithWhite:0.11 alpha:1]
                                : [NSColor colorWithWhite:1.00 alpha:1];
    NSColor *tabHover    = dark ? [NSColor colorWithWhite:0.21 alpha:1]
                                : [NSColor colorWithWhite:0.94 alpha:1];
    NSColor *divider     = dark ? [NSColor colorWithWhite:0.28 alpha:1]
                                : [NSColor colorWithWhite:0.73 alpha:1];
    NSColor *labelSel    = dark ? [NSColor colorWithWhite:0.95 alpha:1]
                                : [NSColor colorWithWhite:0.10 alpha:1];
    NSColor *labelNormal = dark ? [NSColor colorWithWhite:0.55 alpha:1]
                                : [NSColor colorWithWhite:0.40 alpha:1];

    // Bar background
    [barBg setFill];
    NSRectFill(self.bounds);

    // Bottom border
    [divider setFill];
    NSRectFill(NSMakeRect(0, 0, self.bounds.size.width, 1));

    NSInteger count = (NSInteger)_tabTitles.count;
    CGFloat   tabW  = [self tabWidth];

    for (NSInteger i = 0; i < count; i++) {
        NSRect tab     = [self rectForTabAtIndex:i];
        BOOL   sel     = (i == _selectedIndex);
        BOOL   hovered = (i == _hoveredIndex);

        // Tab background
        if (sel || hovered) {
            [(sel ? tabSel : tabHover) setFill];
            NSRectFill(NSMakeRect(tab.origin.x, 1, tabW, kTabHeight - 1));
        }

        // Right divider (skip for selected and the tab just before selected)
        if (!sel && (i + 1) != _selectedIndex) {
            [divider setFill];
            NSRectFill(NSMakeRect(NSMaxX(tab) - 1, 6, 1, kTabHeight - 12));
        }

        // ── Close button ──────────────────────────────────────────────────
        BOOL closeHov = (i == _hoveredCloseIndex);
        // Show × on selected tab, on hovered tab, or when hovering the × itself
        if (sel || hovered || closeHov) {
            NSRect cr = [self closeRectForTabAtIndex:i];

            if (closeHov) {
                // Red circle background on hover
                NSColor *redBg = [NSColor colorWithRed:0.78 green:0.18 blue:0.18 alpha:0.85];
                [redBg setFill];
                [[NSBezierPath bezierPathWithOvalInRect:cr] fill];
            }

            NSColor *xColor = closeHov
                ? [NSColor whiteColor]
                : (dark ? [NSColor colorWithWhite:0.50 alpha:1]
                        : [NSColor colorWithWhite:0.38 alpha:1]);
            NSDictionary *xAttrs = @{
                NSFontAttributeName:            [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
                NSForegroundColorAttributeName: xColor,
            };
            NSString *xStr  = @"✕";
            NSSize    xSz   = [xStr sizeWithAttributes:xAttrs];
            [xStr drawAtPoint:NSMakePoint(NSMidX(cr) - xSz.width / 2,
                                          NSMidY(cr) - xSz.height / 2)
               withAttributes:xAttrs];
        }

        // ── Label ─────────────────────────────────────────────────────────
        NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
        ps.lineBreakMode = NSLineBreakByTruncatingMiddle;
        ps.alignment     = NSTextAlignmentLeft;

        NSDictionary *lblAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:12
                                                   weight:sel ? NSFontWeightMedium : NSFontWeightRegular],
            NSForegroundColorAttributeName: sel ? labelSel : labelNormal,
            NSParagraphStyleAttributeName:  ps,
        };

        // Label rect: from left edge to just before the × area
        CGFloat lblX = tab.origin.x + 10;
        CGFloat lblW = tabW - kCloseSize - kClosePadRight - 14;
        NSRect  lblR = NSMakeRect(lblX, (kTabHeight - 15) / 2, MAX(0, lblW), 15);
        [_tabTitles[i] drawInRect:lblR withAttributes:lblAttrs];
    }
}

// MARK: – Mouse

- (void)mouseDown:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger count = (NSInteger)_tabTitles.count;

    for (NSInteger i = 0; i < count; i++) {
        if (NSPointInRect(loc, [self closeRectForTabAtIndex:i])) {
            [_delegate tabBarView:self didCloseIndex:i];
            return;
        }
        if (NSPointInRect(loc, [self rectForTabAtIndex:i])) {
            [_delegate tabBarView:self didSelectIndex:i];
            return;
        }
    }
}

// MARK: – Tracking areas (hover)

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways
               owner:self
            userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseMoved:(NSEvent *)event {
    [self updateHoverForPoint:[self convertPoint:event.locationInWindow fromView:nil]];
}

- (void)mouseEntered:(NSEvent *)event {
    [self updateHoverForPoint:[self convertPoint:event.locationInWindow fromView:nil]];
}

- (void)mouseExited:(NSEvent *)event {
    _hoveredIndex = _hoveredCloseIndex = -1;
    [self setNeedsDisplay:YES];
}

- (void)updateHoverForPoint:(NSPoint)loc {
    NSInteger newHov = -1, newClose = -1;
    NSInteger count = (NSInteger)_tabTitles.count;
    for (NSInteger i = 0; i < count; i++) {
        if (NSPointInRect(loc, [self closeRectForTabAtIndex:i])) {
            newClose = i; newHov = i; break;
        }
        if (NSPointInRect(loc, [self rectForTabAtIndex:i])) {
            newHov = i; break;
        }
    }
    if (newHov != _hoveredIndex || newClose != _hoveredCloseIndex) {
        _hoveredIndex = newHov;
        _hoveredCloseIndex = newClose;
        [self setNeedsDisplay:YES];
    }
}

// MARK: – Properties

- (void)setTabTitles:(NSArray<NSString *> *)tabTitles {
    _tabTitles = [tabTitles copy];
    NSInteger newCount = (NSInteger)_tabTitles.count;
    if (_hoveredIndex >= newCount)      _hoveredIndex = -1;
    if (_hoveredCloseIndex >= newCount) _hoveredCloseIndex = -1;
    [self setNeedsDisplay:YES];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    _selectedIndex = selectedIndex;
    [self setNeedsDisplay:YES];
}

@end
