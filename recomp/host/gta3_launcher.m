/* Grand Theft Auto III launch window, in the manner of the other native ports' launchers: Steam's library art (Catalina
 * against the city) under the game's logo, a strip of Liberty City, a row of tiles (Graphics Options, Saves, Game Files,
 * Updates) and Quit / Play. Graphics Options opens a panel: Display, Notch (on a display with one), Resolution, VSync.
 *
 * main.m calls ds_launcher_run() before the game: it returns 1 to play (the choices are then in the environment and in
 * <data>/launcher.plist; main.m starts the game in a fresh process with DS_NO_LAUNCHER=1), 0 to quit.
 *   DS_DISPLAY=window|fullscreen, DS_NOTCH=around|below   main.m (the game's window)
 *   GTA_MODE=WxH                                        runtime/win32/gta3_mode.c (the game's video mode), d3d9.c modes()
 *   DSR_VSYNC=1|0                                        main.m (the Metal layer)
 * Art: the data folder's art/ (or the app's Resources/art), fetched at install time by tools/gta3_art.py; without it the
 * title is written. Development: DS_LAUNCHER_SHOT=<png> renders the window to an image (DS_LAUNCHER_OPEN=1: the panel
 * open; DS_LAUNCHER_HOVER=<code>: an item lit). */
#import <Cocoa/Cocoa.h>
#include <unistd.h>

static NSColor *accent(void) { return [NSColor colorWithSRGBRed:0.98 green:0.70 blue:0.20 alpha:1]; }       /* the game's menu amber */
static NSColor *accent_dim(void) { return [NSColor colorWithSRGBRed:0.55 green:0.38 blue:0.12 alpha:1]; }
static NSColor *text_c(void) { return [NSColor colorWithSRGBRed:0.97 green:0.95 blue:0.91 alpha:1]; }
static NSColor *dim(void) { return [NSColor colorWithSRGBRed:0.66 green:0.64 blue:0.60 alpha:1]; }
static NSColor *ink(void) { return [NSColor colorWithSRGBRed:0.03 green:0.04 blue:0.06 alpha:1]; }
static NSFont *heavy(CGFloat size) { return [NSFont fontWithName:@"Futura-CondensedExtraBold" size:size] ?: [NSFont systemFontOfSize:size weight:NSFontWeightHeavy]; }
static NSFont *body(CGFloat size, BOOL bold)
{ return [NSFont fontWithName:bold ? @"AvenirNext-DemiBold" : @"AvenirNext-Medium" size:size] ?: [NSFont systemFontOfSize:size weight:bold ? NSFontWeightSemibold : NSFontWeightRegular]; }
static void on_main(dispatch_block_t b) { CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, b); CFRunLoopWakeUp(CFRunLoopGetMain()); }

// ---------------------------------------------------------------- settings tiles
@interface G3Tile : NSObject
@property NSString *title; @property NSArray<NSDictionary *> *choices; @property NSInteger index;
@property (copy) void (^activate)(void);            /* a tile that runs something instead of cycling */
@property (copy) NSString *(^summary)(void);        /* a tile showing others' values (Graphics Options) */
@property BOOL wide;
@end
@implementation G3Tile @end

// ---------------------------------------------------------------- the view
enum { HIT_NONE = -1, HIT_PLAY = 100, HIT_QUIT = 101, HIT_BACK = 102, HIT_TILE = 300, HIT_ROW = 400 };   /* + 10*k + 0 left / 1 value / 2 right */
enum { W = 960, H = 660 };

@interface G3LaunchView : NSView
@property NSArray<G3Tile *> *tiles; @property NSInteger hover, pressed, focus;
@property NSArray<G3Tile *> *rows; @property BOOL open; @property NSInteger rowFocus;   /* the Graphics Options panel */
@property NSImage *hero, *logo; @property NSArray<NSImage *> *shots; @property NSString *hint;
@property (copy) void (^onPlay)(void); @property (copy) void (^onQuit)(void); @property (copy) void (^onChange)(void);
@end

@implementation G3LaunchView
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; }
- (NSRect)shotRect:(NSInteger)i { return NSMakeRect(60 + i * 288, 318, 264, 149); }
- (NSRect)tileRect:(NSInteger)k   /* the tiles in a row (a wide one counts twice) */
{
    NSInteger units = 0, at = 0, n = (NSInteger)self.tiles.count;
    for (NSInteger j = 0; j < n; j++) { if (j == k) at = units; units += self.tiles[j].wide ? 2 : 1; }
    CGFloat u = (840 - 16 * (units - 1)) / (CGFloat)units;
    return NSMakeRect(60 + at * (u + 16), 494, self.tiles[k].wide ? 2 * u + 16 : u, 66);
}
- (NSRect)arrow:(NSInteger)k right:(BOOL)right { NSRect r = [self tileRect:k]; return NSMakeRect(right ? NSMaxX(r) - 22 : r.origin.x + 1, r.origin.y + 26, 21, 34); }
- (NSRect)playRect { return NSMakeRect(W - 60 - 200, H - 66, 200, 46); }
- (NSRect)quitRect { return NSMakeRect(W - 60 - 200 - 20 - 150, H - 66, 150, 46); }
- (NSRect)panelRect { CGFloat h = 86 + 60 * (CGFloat)self.rows.count; return NSMakeRect(130, MAX(40, 486 - h), 700, h); }
- (NSRect)rowRect:(NSInteger)k { NSRect p = self.panelRect; return NSMakeRect(p.origin.x + 30, p.origin.y + 72 + 60 * k, p.size.width - 60, 52); }
- (NSRect)rowArrow:(NSInteger)k right:(BOOL)right { NSRect r = [self rowRect:k]; return NSMakeRect(right ? NSMaxX(r) - 34 : NSMaxX(r) - 330, r.origin.y + 3, 30, 30); }
- (NSRect)rowValue:(NSInteger)k { NSRect r = [self rowRect:k]; return NSMakeRect(NSMaxX(r) - 300, r.origin.y + 4, 262, 28); }
- (void)openPanel { self.open = YES; self.rowFocus = 0; self.hover = HIT_NONE; self.needsDisplay = YES; }
- (void)closePanel { self.open = NO; self.hover = HIT_NONE; self.needsDisplay = YES; }
- (NSInteger)hit:(NSPoint)p
{
    if (NSPointInRect(p, self.playRect)) return HIT_PLAY;
    if (NSPointInRect(p, self.quitRect)) return self.open ? HIT_BACK : HIT_QUIT;
    if (self.open) {
        for (NSInteger k = 0; k < (NSInteger)self.rows.count; k++) {
            if (NSPointInRect(p, [self rowArrow:k right:NO])) return HIT_ROW + 10 * k;
            if (NSPointInRect(p, [self rowArrow:k right:YES])) return HIT_ROW + 10 * k + 2;
            if (NSPointInRect(p, [self rowRect:k])) return HIT_ROW + 10 * k + 1;
        }
        return NSPointInRect(p, self.panelRect) ? HIT_NONE : HIT_BACK;    /* a click outside the panel closes it */
    }
    for (NSInteger k = 0; k < (NSInteger)self.tiles.count; k++) {
        if (!NSPointInRect(p, [self tileRect:k])) continue;
        if (self.tiles[k].activate) return HIT_TILE + 10 * k + 1;
        if (NSPointInRect(p, [self arrow:k right:NO])) return HIT_TILE + 10 * k;
        if (NSPointInRect(p, [self arrow:k right:YES])) return HIT_TILE + 10 * k + 2;
        return HIT_TILE + 10 * k + 1;
    }
    return HIT_NONE;
}
- (void)updateTrackingAreas
{
    for (NSTrackingArea *t in self.trackingAreas) [self removeTrackingArea:t];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseMoved:(NSEvent *)e { NSInteger h = [self hit:[self convertPoint:e.locationInWindow fromView:nil]]; if (h != self.hover) { self.hover = h; self.needsDisplay = YES; } }
- (void)mouseExited:(NSEvent *)e { self.hover = HIT_NONE; self.needsDisplay = YES; }
- (void)mouseDown:(NSEvent *)e { self.pressed = [self hit:[self convertPoint:e.locationInWindow fromView:nil]]; self.needsDisplay = YES; }
- (void)mouseUp:(NSEvent *)e
{
    NSInteger h = [self hit:[self convertPoint:e.locationInWindow fromView:nil]], p = self.pressed; self.pressed = HIT_NONE; self.needsDisplay = YES;
    if (h != p || h == HIT_NONE) return;
    if (h == HIT_PLAY) { if (self.onPlay) self.onPlay(); return; }
    if (h == HIT_QUIT) { if (self.onQuit) self.onQuit(); return; }
    if (h == HIT_BACK) { [self closePanel]; return; }
    if (h >= HIT_ROW) { NSInteger k = (h - HIT_ROW) / 10; self.rowFocus = k; [self stepRow:k by:(h - HIT_ROW) % 10 == 0 ? -1 : 1]; return; }
    NSInteger k = (h - HIT_TILE) / 10, part = (h - HIT_TILE) % 10; self.focus = k;
    [self step:k by:part == 0 ? -1 : 1];
}
- (void)step:(NSInteger)k by:(NSInteger)dir
{
    if (k < 0 || k >= (NSInteger)self.tiles.count) return;
    G3Tile *t = self.tiles[k];
    if (t.activate) { t.activate(); self.needsDisplay = YES; return; }
    NSInteger n = (NSInteger)t.choices.count; t.index = (t.index + dir + n) % n;
    self.needsDisplay = YES; if (self.onChange) self.onChange();
}
- (void)stepRow:(NSInteger)k by:(NSInteger)dir
{
    G3Tile *t = self.rows[k]; NSInteger n = (NSInteger)t.choices.count; t.index = (t.index + dir + n) % n;
    self.needsDisplay = YES; if (self.onChange) self.onChange();
}
- (void)keyDown:(NSEvent *)e
{
    if (self.open) {
        NSInteger rn = (NSInteger)self.rows.count;
        switch (e.keyCode) {
        case 0x24: case 0x4c: case 0x35: [self closePanel]; return;                          /* Return, Escape: back */
        case 0x7b: [self stepRow:self.rowFocus by:-1]; return;
        case 0x7c: [self stepRow:self.rowFocus by:1]; return;
        case 0x7e: self.rowFocus = (self.rowFocus + rn - 1) % rn; self.needsDisplay = YES; return;
        case 0x7d: case 0x30: self.rowFocus = (self.rowFocus + 1) % rn; self.needsDisplay = YES; return;
        }
        [super keyDown:e]; return;
    }
    NSInteger n = (NSInteger)self.tiles.count;
    switch (e.keyCode) {
    case 0x24: case 0x4c: if (self.focus >= 0 && self.tiles[self.focus].activate) { [self step:self.focus by:1]; return; }   /* Return */
                          if (self.onPlay) self.onPlay(); return;
    case 0x35: if (self.onQuit) self.onQuit(); return;                                       /* Escape */
    case 0x7b: [self step:self.focus by:-1]; return;
    case 0x7c: [self step:self.focus by:1]; return;
    case 0x7e: self.focus = self.focus <= 0 ? n - 1 : self.focus - 1; self.needsDisplay = YES; return;
    case 0x7d: case 0x30: self.focus = (self.focus + 1) % n; self.needsDisplay = YES; return;   /* also Tab */
    }
    [super keyDown:e];
}

static void draw_text(NSString *s, NSFont *f, NSColor *c, NSRect r, NSTextAlignment al, NSShadow *sh, CGFloat kern)
{
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.alignment = al; ps.lineBreakMode = NSLineBreakByTruncatingTail;
    NSMutableDictionary *a = [@{NSFontAttributeName: f, NSForegroundColorAttributeName: c, NSParagraphStyleAttributeName: ps, NSKernAttributeName: @(kern)} mutableCopy];
    if (sh) a[NSShadowAttributeName] = sh;
    [s drawInRect:r withAttributes:a];
}
static void fill_over(NSRect r) { NSRectFillUsingOperation(r, NSCompositingOperationSourceOver); }
/* an image filling a rectangle, aspect kept (cropped), focusX/focusY: where the crop sits (0 left/top .. 1 right/bottom) */
static void draw_cover(NSImage *img, NSRect r, CGFloat fraction, CGFloat focusX, CGFloat focusY)
{
    NSSize is = img.size;
    CGFloat sc = MAX(r.size.width / is.width, r.size.height / is.height), w = r.size.width / sc, h = r.size.height / sc;
    NSRect from = NSMakeRect((is.width - w) * focusX, (is.height - h) * (1 - focusY), w, h);   /* NSImage rows: bottom-up */
    [img drawInRect:r fromRect:from operation:NSCompositingOperationSourceOver fraction:fraction respectFlipped:YES hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
}
static void draw_fit(NSImage *img, NSRect r, CGFloat fraction)           /* aspect kept, inside r, left-aligned */
{
    CGFloat sc = MIN(r.size.width / img.size.width, r.size.height / img.size.height), w = img.size.width * sc, h = img.size.height * sc;
    [img drawInRect:NSMakeRect(r.origin.x, NSMidY(r) - h / 2, w, h) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:fraction respectFlipped:YES hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
}
static void stroke_rect(NSRect r, NSColor *c, CGFloat w) { [c setStroke]; NSBezierPath *b = [NSBezierPath bezierPathWithRect:NSInsetRect(r, w / 2, w / 2)]; b.lineWidth = w; [b stroke]; }
- (void)drawButton:(NSRect)r title:(NSString *)title code:(NSInteger)code primary:(BOOL)primary
{
    BOOL hot = self.hover == code, down = self.pressed == code;
    if (primary) {   /* the game's amber bar: solid, black lettering */
        NSShadow *glow = [NSShadow new]; glow.shadowColor = [accent() colorWithAlphaComponent:hot ? 0.75 : 0.4]; glow.shadowBlurRadius = hot ? 22 : 14; glow.shadowOffset = NSZeroSize;
        [NSGraphicsContext saveGraphicsState]; [glow set];
        [(down ? accent_dim() : hot ? [NSColor colorWithSRGBRed:1 green:0.80 blue:0.36 alpha:1] : accent()) setFill]; NSRectFill(r);
        [NSGraphicsContext restoreGraphicsState];
        draw_text(title, heavy(25), ink(), NSMakeRect(r.origin.x, r.origin.y + 7, r.size.width, 34), NSTextAlignmentCenter, nil, 4);
    } else {
        [[NSColor colorWithWhite:0.02 alpha:down ? 0.95 : 0.7] setFill]; fill_over(r);
        stroke_rect(r, hot ? accent() : [text_c() colorWithAlphaComponent:0.35], hot ? 2 : 1);
        draw_text(title, heavy(21), hot ? accent() : text_c(), NSMakeRect(r.origin.x, r.origin.y + 10, r.size.width, 30), NSTextAlignmentCenter, nil, 4);
    }
}
- (void)drawArrow:(NSRect)r right:(BOOL)right lit:(BOOL)lit
{
    NSBezierPath *p = [NSBezierPath bezierPath]; CGFloat x0 = NSMidX(r) - 4, x1 = NSMidX(r) + 4, y0 = NSMidY(r) - 7, y1 = NSMidY(r) + 7, ym = NSMidY(r);
    if (right) { [p moveToPoint:NSMakePoint(x0, y0)]; [p lineToPoint:NSMakePoint(x1, ym)]; [p lineToPoint:NSMakePoint(x0, y1)]; }
    else { [p moveToPoint:NSMakePoint(x1, y0)]; [p lineToPoint:NSMakePoint(x0, ym)]; [p lineToPoint:NSMakePoint(x1, y1)]; }
    p.lineWidth = 2.5; p.lineCapStyle = NSLineCapStyleSquare; p.lineJoinStyle = NSLineJoinStyleMiter;
    [(lit ? NSColor.whiteColor : accent()) setStroke]; [p stroke];
}
- (void)drawTile:(NSInteger)k shadow:(NSShadow *)sh
{
    G3Tile *t = self.tiles[k]; NSRect r = [self tileRect:k]; NSDictionary *c = t.choices[t.index];
    BOOL hot = self.hover >= HIT_TILE + 10 * k && self.hover <= HIT_TILE + 10 * k + 2, foc = self.focus == k, special = [c[@"accent"] boolValue];
    [[NSColor colorWithWhite:0.03 alpha:hot ? 0.92 : 0.78] setFill]; fill_over(r);
    stroke_rect(r, (hot || foc) ? accent() : [text_c() colorWithAlphaComponent:0.16], foc ? 2 : 1);
    [((hot || foc) ? accent() : accent_dim()) setFill]; NSRectFill(NSMakeRect(r.origin.x, r.origin.y, 4, r.size.height));   /* an amber edge */
    draw_text(t.title.uppercaseString, heavy(13), (hot || foc) ? accent() : dim(), NSMakeRect(r.origin.x + 4, r.origin.y + 9, r.size.width - 4, 18), NSTextAlignmentCenter, nil, 2.5);
    NSColor *vc = special ? accent() : self.hover == HIT_TILE + 10 * k + 1 ? NSColor.whiteColor : text_c();
    draw_text(t.summary ? t.summary() : c[@"label"], body(15, YES), vc, NSMakeRect(r.origin.x + 21, r.origin.y + 33, r.size.width - 38, 24), NSTextAlignmentCenter, sh, 0.2);
    if (!t.activate) {
        [self drawArrow:[self arrow:k right:NO] right:NO lit:self.hover == HIT_TILE + 10 * k];
        [self drawArrow:[self arrow:k right:YES] right:YES lit:self.hover == HIT_TILE + 10 * k + 2];
    }
}
- (void)drawPanel:(NSShadow *)sh                        /* Graphics Options: a panel over the window, a row per setting */
{
    [[NSColor colorWithWhite:0 alpha:0.66] setFill]; fill_over(NSMakeRect(0, 0, W, H - 90));
    NSRect p = self.panelRect;
    NSShadow *glow = [NSShadow new]; glow.shadowColor = [NSColor colorWithWhite:0 alpha:0.9]; glow.shadowBlurRadius = 30; glow.shadowOffset = NSMakeSize(0, -8);
    [NSGraphicsContext saveGraphicsState]; [glow set]; [[NSColor colorWithSRGBRed:0.05 green:0.05 blue:0.06 alpha:0.98] setFill]; NSRectFill(p); [NSGraphicsContext restoreGraphicsState];
    [accent() setFill]; NSRectFill(NSMakeRect(p.origin.x, p.origin.y, p.size.width, 50));   /* the game's menu title bar */
    draw_text(@"GRAPHICS OPTIONS", heavy(30), ink(), NSMakeRect(p.origin.x + 30, p.origin.y + 6, p.size.width - 60, 40), NSTextAlignmentRight, nil, 3);
    for (NSInteger k = 0; k < (NSInteger)self.rows.count; k++) {
        G3Tile *t = self.rows[k]; NSRect r = [self rowRect:k]; NSDictionary *c = t.choices[t.index];
        BOOL hot = self.hover >= HIT_ROW + 10 * k && self.hover <= HIT_ROW + 10 * k + 2, foc = self.rowFocus == k;
        if (foc || hot) { [[accent() colorWithAlphaComponent:foc ? 0.16 : 0.08] setFill]; fill_over(NSInsetRect(r, -10, -2));   /* the game's highlight band */
                          if (foc) { [accent() setFill]; NSRectFill(NSMakeRect(r.origin.x - 10, r.origin.y - 2, 4, r.size.height + 4)); } }
        draw_text(t.title.uppercaseString, heavy(21), foc || hot ? accent() : text_c(), NSMakeRect(r.origin.x + 6, r.origin.y + 4, 260, 28), NSTextAlignmentLeft, sh, 2.5);
        [self drawArrow:[self rowArrow:k right:NO] right:NO lit:self.hover == HIT_ROW + 10 * k];
        [self drawArrow:[self rowArrow:k right:YES] right:YES lit:self.hover == HIT_ROW + 10 * k + 2];
        draw_text(c[@"label"], body(18, YES), self.hover == HIT_ROW + 10 * k + 1 ? NSColor.whiteColor : text_c(), [self rowValue:k], NSTextAlignmentCenter, sh, 0.3);
        draw_text(c[@"note"] ?: @"", body(12, NO), dim(), NSMakeRect(r.origin.x + 6, r.origin.y + 32, r.size.width - 12, 18), NSTextAlignmentRight, nil, 0);
        if (k + 1 < (NSInteger)self.rows.count) { [[text_c() colorWithAlphaComponent:0.1] setFill]; fill_over(NSMakeRect(r.origin.x, NSMaxY(r) + 4, r.size.width, 1)); }
    }
}
- (NSString *)currentHint
{
    if (self.open) return @"←/→ change  ·  ↑/↓ move  ·  Return or Esc goes back";
    NSInteger k = -1;
    if (self.hover >= HIT_TILE && self.hover < HIT_ROW) k = (self.hover - HIT_TILE) / 10; else if (self.hover == HIT_NONE && self.focus >= 0) k = self.focus;
    if (k >= 0 && k < (NSInteger)self.tiles.count) { G3Tile *t = self.tiles[k]; return t.choices[t.index][@"note"]; }
    return self.hint;
}
- (void)drawRect:(NSRect)dirty
{
    NSRect b = self.bounds;
    NSShadow *sh = [NSShadow new]; sh.shadowColor = [NSColor colorWithWhite:0 alpha:0.85]; sh.shadowOffset = NSMakeSize(0, -1); sh.shadowBlurRadius = 3;
    [ink() setFill]; NSRectFill(b);
    /* Steam's library art across the top, Catalina on the right; it fades into the dark below and behind the logo */
    NSRect band = NSMakeRect(0, 0, W, 360);
    if (self.hero) draw_cover(self.hero, band, 1, 0.78, 0.3);
    else { [[NSColor colorWithSRGBRed:0.02 green:0.21 blue:0.33 alpha:1] setFill]; NSRectFill(band); }
    NSGradient *left = [[NSGradient alloc] initWithColorsAndLocations:[ink() colorWithAlphaComponent:0.92], 0.0, [ink() colorWithAlphaComponent:0.55], 0.42, [ink() colorWithAlphaComponent:0], 0.7, nil];
    [left drawInRect:band angle:0];
    NSGradient *foot = [[NSGradient alloc] initWithColorsAndLocations:[ink() colorWithAlphaComponent:0], 0.0, [ink() colorWithAlphaComponent:0.7], 0.6, ink(), 1.0, nil];
    [foot drawInRect:NSMakeRect(0, 150, W, 212) angle:90];
    /* the logo and what this is */
    if (self.logo.size.width > 16) {
        NSShadow *ls = [NSShadow new]; ls.shadowColor = [NSColor colorWithWhite:0 alpha:0.9]; ls.shadowOffset = NSMakeSize(0, -4); ls.shadowBlurRadius = 14;
        [NSGraphicsContext saveGraphicsState]; [ls set]; draw_fit(self.logo, NSMakeRect(46, 34, 340, 191), 1); [NSGraphicsContext restoreGraphicsState];
    } else draw_text(@"GRAND THEFT AUTO III", heavy(54), text_c(), NSMakeRect(60, 90, 600, 70), NSTextAlignmentLeft, sh, 2);
    [accent() setFill]; NSRectFill(NSMakeRect(60, 240, 4, 38));
    draw_text(@"NATIVE FOR APPLE SILICON", heavy(19), text_c(), NSMakeRect(74, 238, 420, 24), NSTextAlignmentLeft, sh, 2.5);
    draw_text(@"Liberty City on Metal · your Steam copy, recompiled", body(13, NO), accent(), NSMakeRect(74, 261, 420, 20), NSTextAlignmentLeft, sh, 0.3);
    /* a strip of the city */
    draw_text(@"LIBERTY CITY", heavy(13), dim(), NSMakeRect(60, 296, 300, 18), NSTextAlignmentLeft, nil, 3);
    for (NSInteger i = 0; i < 3; i++) {
        NSRect r = [self shotRect:i];
        [NSColor.blackColor setFill]; NSRectFill(r);
        if (i < (NSInteger)self.shots.count && self.shots[i].size.width > 16) draw_cover(self.shots[i], r, 1, 0.5, 0.5);
        stroke_rect(NSInsetRect(r, -1, -1), [text_c() colorWithAlphaComponent:0.85], 3);   /* a print's white border */
    }
    NSInteger hov = self.hover, foc = self.focus; if (self.open) self.hover = self.focus = HIT_NONE;   /* under the panel: nothing lit */
    for (NSInteger k = 0; k < (NSInteger)self.tiles.count; k++) [self drawTile:k shadow:sh];
    self.hover = hov; self.focus = foc;
    [[text_c() colorWithAlphaComponent:0.12] setFill]; fill_over(NSMakeRect(60, H - 90, 840, 1));
    if (self.open) [self drawPanel:sh];
    NSString *hint = [self currentHint];
    if (hint.length) draw_text(hint, body(12.5, NO), dim(), NSMakeRect(60, H - 58, 400, 36), NSTextAlignmentLeft, sh, 0.2);
    [self drawButton:self.quitRect title:self.open ? @"BACK" : @"QUIT" code:self.open ? HIT_BACK : HIT_QUIT primary:NO];
    [self drawButton:self.playRect title:@"PLAY" code:HIT_PLAY primary:YES];
}
@end

// ---------------------------------------------------------------- updates (the other ports' updater)
enum { UPD_NONE, UPD_CHECKING, UPD_CURRENT, UPD_AVAILABLE, UPD_ERROR };
static NSString *short_commit(NSString *c) { return c.length > 7 ? [c substringToIndex:7] : (c ?: @""); }
static NSString *update_check(NSString *updater)     /* the newest commit of the branch on GitHub; nil if it can't be reached */
{
    NSTask *t = [NSTask new]; t.executableURL = [NSURL fileURLWithPath:@"/bin/bash"]; t.arguments = @[updater, @"--check"];
    NSPipe *p = [NSPipe pipe]; t.standardOutput = p; t.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![t launchAndReturnError:nil]) return nil;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_global_queue(0, 0), ^{ if (t.running) [t terminate]; });
    NSData *d = [p.fileHandleForReading readDataToEndOfFile]; [t waitUntilExit];
    NSString *out = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return t.terminationStatus == 0 && out.length >= 40 ? [out substringToIndex:40] : nil;
}
static NSArray<NSDictionary *> *update_choice(int state, NSString *branch, NSString *built, NSString *latest)
{
    NSString *label = @"Unavailable", *note = @"This copy wasn't installed from the GitHub repository"; BOOL lit = NO;
    switch (state) {
    case UPD_CHECKING: label = @"Checking…"; note = [NSString stringWithFormat:@"Asking GitHub for the newest %@", branch]; break;
    case UPD_CURRENT: label = @"Up to Date"; note = [NSString stringWithFormat:@"%@ %@ · click to check again", branch, short_commit(built)]; break;
    case UPD_AVAILABLE: label = @"Update Ready"; lit = YES; note = [NSString stringWithFormat:@"%@ → %@: click to install", short_commit(built), short_commit(latest)]; break;
    case UPD_ERROR: label = @"Can’t Check"; note = @"GitHub unreachable or not signed in: click to retry"; break;
    }
    return @[@{@"value": @"", @"label": label, @"note": note, @"accent": @(lit)}];
}
static NSString *update_phase(NSString *line, NSString *branch)
{
    if ([line hasPrefix:@"== fetching"]) return @"Downloading the update from GitHub";
    if ([line hasPrefix:[NSString stringWithFormat:@"== %@:", branch]]) return [@"Got " stringByAppendingString:[line substringFromIndex:branch.length + 4]];
    if ([line hasPrefix:@"== recompiling"]) return @"Rebuilding from your game: translating it to native code (1 of 2)";
    if ([line hasPrefix:@"== installing"]) return @"Installing the new app (2 of 2)";
    return nil;
}
@interface G3BlockTarget : NSObject
@property (copy) void (^fire)(void);
- (void)clicked:(id)b;
@end
@implementation G3BlockTarget
- (void)clicked:(id)b { (void)b; if (self.fire) self.fire(); }
@end
static BOOL update_run(NSWindow *parent, NSString *updater, NSString *branch, NSString *logPath)   /* modal progress; YES when rebuilt */
{
    NSPanel *pn = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 520, 170) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    pn.title = @"Updating";
    NSTextField *title = [NSTextField labelWithString:@"Updating to the newest version"]; title.font = [NSFont boldSystemFontOfSize:14]; title.frame = NSMakeRect(20, 128, 480, 22);
    NSTextField *status = [NSTextField wrappingLabelWithString:@"Starting…"]; status.frame = NSMakeRect(20, 64, 480, 56);
    NSProgressIndicator *spin = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 44, 480, 12)]; spin.indeterminate = YES; [spin startAnimation:nil];
    NSTextField *time = [NSTextField labelWithString:@"This takes a few minutes. Your saves and settings are kept."]; time.font = [NSFont systemFontOfSize:11]; time.textColor = NSColor.secondaryLabelColor; time.frame = NSMakeRect(20, 14, 370, 18);
    NSButton *btn = [NSButton buttonWithTitle:@"Close" target:nil action:nil]; btn.frame = NSMakeRect(400, 8, 100, 30); btn.hidden = YES;
    for (NSView *x in @[title, status, spin, time, btn]) [pn.contentView addSubview:x];
    if (parent) [pn setFrameOrigin:NSMakePoint(NSMidX(parent.frame) - 260, NSMidY(parent.frame) - 85)]; else [pn center];
    [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
    NSFileHandle *log = [NSFileHandle fileHandleForWritingAtPath:logPath];
    NSTask *t = [NSTask new]; t.executableURL = [NSURL fileURLWithPath:@"/bin/bash"]; t.arguments = @[updater];
    NSPipe *pipe = [NSPipe pipe]; t.standardOutput = pipe; t.standardError = pipe;
    NSMutableString *pending = [NSMutableString new], *tail = [NSMutableString new];
    pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
        NSData *d = h.availableData; if (!d.length) return;
        [log writeData:d];
        NSString *chunk = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
        @synchronized (pending) {
            [pending appendString:chunk]; NSRange nl;
            while ((nl = [pending rangeOfString:@"\n"]).location != NSNotFound) {
                NSString *line = [pending substringToIndex:nl.location]; [pending deleteCharactersInRange:NSMakeRange(0, nl.location + 1)];
                [tail appendFormat:@"%@\n", line]; if (tail.length > 600) [tail deleteCharactersInRange:NSMakeRange(0, tail.length - 600)];
                NSString *ph = update_phase(line, branch); if (ph) on_main(^{ status.stringValue = ph; });
            }
        }
    };
    __block BOOL ok = NO;
    __attribute__((objc_precise_lifetime)) G3BlockTarget *bt = [G3BlockTarget new];   /* a button's target is weak: kept here */
    bt.fire = ^{ [NSApp stopModal]; }; btn.target = bt; btn.action = @selector(clicked:);
    t.terminationHandler = ^(NSTask *task) {
        int code = task.terminationStatus;
        on_main(^{
            pipe.fileHandleForReading.readabilityHandler = nil; [log closeFile];
            [spin stopAnimation:nil]; spin.hidden = YES; btn.hidden = NO;
            if (code == 0) { ok = YES; title.stringValue = @"Updated"; status.stringValue = @"The new version is installed. The app restarts when you press Restart."; btn.title = @"Restart"; }
            else {
                NSString *last; @synchronized (pending) { last = [[tail componentsSeparatedByString:@"\n"] componentsJoinedByString:@" "]; }
                title.stringValue = @"The update didn't finish";
                status.stringValue = [NSString stringWithFormat:@"Nothing was changed if it stopped before installing. Details: %@  (%@)", logPath, last.length > 160 ? [last substringFromIndex:last.length - 160] : last];
                time.stringValue = @"";
            }
        });
    };
    if (![t launchAndReturnError:nil]) { [log closeFile]; return NO; }
    [pn makeKeyAndOrderFront:nil]; [NSApp runModalForWindow:pn]; [pn orderOut:nil];
    return ok;
}

// ---------------------------------------------------------------- the window
static NSInteger index_of(NSArray<NSDictionary *> *c, id v, NSInteger dflt)
{ for (NSUInteger k = 0; k < c.count; k++) if ([c[k][@"value"] isEqual:v]) return (NSInteger)k; return dflt; }
static NSImage *image_at(NSArray<NSString *> *dirs, NSString *name)
{
    for (NSString *d in dirs) { NSImage *i = [[NSImage alloc] initWithContentsOfFile:[d stringByAppendingPathComponent:name]]; if (i.size.width > 16) return i; }
    return nil;
}
static NSString *val(G3Tile *t) { return t.choices[t.index][@"value"]; }
static void setenv_soft(const char *k, const char *v) { if (!getenv(k)) setenv(k, v, 1); }   /* a terminal's own setting wins */
/* the game's video mode for these choices: 4:3 (the game's picture; the window keeps it, bars at the sides), as tall as
 * the screen (below the notch's band if so), the window, in points or (Retina) pixels; "" = as set in the game */
static NSString *mode_for(NSString *display, NSString *notch, NSString *res)
{
    if ([res isEqualToString:@"game"]) return @"";
    NSScreen *s = NSScreen.mainScreen; CGFloat h = s.frame.size.height;
    if ([display isEqualToString:@"window"]) h = floor(s.visibleFrame.size.height * 0.78) - 28;   /* main.m's window, less its title bar */
    else if (![notch isEqualToString:@"around"]) { if (@available(macOS 12.0, *)) h -= s.safeAreaInsets.top; }
    if ([res isEqualToString:@"retina"]) h *= s.backingScaleFactor;
    int ih = (int)floor(h) & ~1, iw = (int)lround(ih * 4.0 / 3) & ~1;
    if (ih < 480) { ih = 480; iw = 640; }
    return [NSString stringWithFormat:@"%dx%d", iw, ih];
}
static void apply(NSDictionary *c)
{
    setenv_soft("DS_DISPLAY", [c[@"display"] ?: @"fullscreen" UTF8String]);
    setenv_soft("DS_NOTCH", [c[@"notch"] ?: @"below" UTF8String]);
    setenv_soft("DSR_VSYNC", [c[@"vsync"] ?: @"1" UTF8String]);
    NSString *m = mode_for(c[@"display"] ?: @"fullscreen", c[@"notch"] ?: @"below", c[@"resolution"] ?: @"standard");
    if (m.length) setenv_soft("GTA_MODE", m.UTF8String);
}

int ds_launcher_run(const char *game_dir, const char *data_dir)
{
    NSString *game = @(game_dir), *data = @(data_dir), *plistPath = [data stringByAppendingPathComponent:@"launcher.plist"];
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:plistPath] ?: @{};
    const char *shot = getenv("DS_LAUNCHER_SHOT");
    if (getenv("DS_NO_LAUNCHER") && !shot) { apply(saved); return 1; }   /* the game's own process (or a terminal): the saved choices */

    NSScreen *scr = NSScreen.mainScreen;
    CGFloat notchH = 0; if (@available(macOS 12.0, *)) notchH = scr.safeAreaInsets.top;
    G3Tile *display = [G3Tile new], *notch = [G3Tile new], *res = [G3Tile new], *vsync = [G3Tile new];
    display.title = @"Display";
    display.choices = @[@{@"value": @"fullscreen", @"label": @"Full Screen", @"note": @"The whole display, the Dock and menu bar out of the way: Game Mode on"},
                        @{@"value": @"window", @"label": @"Window", @"note": @"A window on the desktop (4:3, resizable); ⌘-Tab and the Dock as usual"}];
    display.index = index_of(display.choices, saved[@"display"], 0);
    notch.title = @"Notch";
    notch.choices = @[@{@"value": @"below", @"label": @"Below It", @"note": @"The picture under the camera housing, the band above it black"},
                      @{@"value": @"around", @"label": @"Around It", @"note": @"The whole display's height: the notch over the top of the picture"}];
    notch.index = index_of(notch.choices, saved[@"notch"], 0);
    CGFloat sc = scr.backingScaleFactor;
    res.title = @"Resolution";
    res.choices = @[@{@"value": @"standard", @"label": @"Standard", @"note": [NSString stringWithFormat:@"Display height in points (%@), scaled up by macOS", mode_for(@"fullscreen", @"around", @"standard")]},
                    @{@"value": @"retina", @"label": @"Retina", @"note": [NSString stringWithFormat:@"Every pixel (%@ full screen): the sharpest picture", mode_for(@"fullscreen", @"around", @"retina")]},
                    @{@"value": @"game", @"label": @"As Set in Game", @"note": @"The game's own Display Setup menu decides (640 × 480 at first)"}];
    if (sc <= 1) res.choices = @[res.choices[0], res.choices[2]];
    res.index = index_of(res.choices, saved[@"resolution"], 0);
    NSInteger hz = scr.maximumFramesPerSecond; if (hz <= 0) hz = 60;
    vsync.title = @"VSync";
    vsync.choices = @[@{@"value": @"1", @"label": @"On", @"short": @"VSync", @"note": [NSString stringWithFormat:@"Frames paced to the display's %ld Hz: no tearing (the game's own limiter keeps 30)", (long)hz]},
                      @{@"value": @"0", @"label": @"Off", @"short": @"No VSync", @"note": @"Frames shown as soon as they're drawn: lowest latency, may tear"}];
    vsync.index = index_of(vsync.choices, saved[@"vsync"], 0);

    G3LaunchView *v = [[G3LaunchView alloc] initWithFrame:NSMakeRect(0, 0, W, H)];
    v.hover = v.pressed = HIT_NONE; v.focus = -1;
    NSArray *artDirs = @[[data stringByAppendingPathComponent:@"art"], [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"art"] ?: @""];
    v.hero = image_at(artDirs, @"hero.jpg"); v.logo = image_at(artDirs, @"logo.png");
    NSMutableArray *shots = [NSMutableArray array];
    for (int i = 1; i <= 3; i++) [shots addObject:image_at(artDirs, [NSString stringWithFormat:@"shot%d.jpg", i]) ?: [NSImage new]];
    v.shots = shots;
    v.hint = @"↑/↓ choose · ←/→ change · Return plays · Esc quits";
    v.rows = notchH > 0 ? @[display, notch, res, vsync] : @[display, res, vsync];
    G3Tile *gfx = [G3Tile new]; gfx.title = @"Graphics Options"; gfx.wide = YES;
    gfx.choices = @[@{@"value": @"", @"label": @"", @"note": notchH > 0 ? @"Display, notch, resolution and VSync" : @"Display, resolution and VSync"}];
    gfx.summary = ^NSString * {
        NSMutableArray *a = [NSMutableArray array];
        for (G3Tile *t in @[display, res, vsync]) [a addObject:t.choices[t.index][@"short"] ?: t.choices[t.index][@"label"]];
        return [a componentsJoinedByString:@"  ·  "];
    };
    __weak G3LaunchView *wv = v; gfx.activate = ^{ [wv openPanel]; };
    NSString *userFiles = [data stringByAppendingPathComponent:@"drive_c/Users/player/Documents/GTA3 User Files"];
    G3Tile *saves = [G3Tile new]; saves.title = @"Saves";
    saves.choices = @[@{@"value": @"", @"label": @"Open", @"note": [@"Saved games and settings: " stringByAppendingString:userFiles.stringByAbbreviatingWithTildeInPath]}];
    saves.activate = ^{ [[NSFileManager defaultManager] createDirectoryAtPath:userFiles withIntermediateDirectories:YES attributes:nil error:nil];
                        [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:userFiles isDirectory:YES]]; };
    G3Tile *files = [G3Tile new]; files.title = @"Game Files";
    files.choices = @[@{@"value": @"", @"label": @"Open", @"note": [@"The game's own folder (models, audio, skins): " stringByAppendingString:game.stringByAbbreviatingWithTildeInPath]}];
    files.activate = ^{ [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:game isDirectory:YES]]; };

    /* Updates: install.sh's updater rebuilds the app from the branch it follows (main.m bundle_launch sets these) */
    NSString *updater = getenv("DS_UPDATER") ? @(getenv("DS_UPDATER")) : nil, *branch = getenv("DS_UPDATE_BRANCH") ? @(getenv("DS_UPDATE_BRANCH")) : @"main";
    NSString *built = getenv("DS_BUILT_COMMIT") ? @(getenv("DS_BUILT_COMMIT")) : @"";
    G3Tile *upd = [G3Tile new]; upd.title = @"Updates";
    __block int state = updater ? UPD_CHECKING : UPD_NONE; __block NSString *latest = nil;
    upd.choices = update_choice(state, branch, built, nil);
    __weak G3Tile *wu = upd;
    void (^check)(void) = ^{
        if (!updater) return;
        state = UPD_CHECKING; wu.choices = update_choice(state, branch, built, nil); wv.needsDisplay = YES;
        void (^done)(NSString *) = ^(NSString *l) {
            latest = l; state = !l ? UPD_ERROR : [l isEqualToString:built] ? UPD_CURRENT : UPD_AVAILABLE;
            wu.choices = update_choice(state, branch, built, l); wv.needsDisplay = YES;
        };
        if (shot) { done(update_check(updater)); return; }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ NSString *l = update_check(updater); on_main(^{ done(l); }); });
    };
    check();
    upd.activate = ^{
        if (state == UPD_CHECKING || state == UPD_NONE) return;
        if (state != UPD_AVAILABLE) { check(); return; }
        NSAlert *a = [NSAlert new];
        a.messageText = [NSString stringWithFormat:@"Update to the newest %@?", [branch isEqualToString:@"nightly"] ? @"Nightly" : @"version"];
        a.informativeText = [NSString stringWithFormat:@"The %@ branch (%@) is downloaded from GitHub and the app is rebuilt from your own copy of the game, "
                             "which takes a few minutes. Your saves and settings are kept. The app restarts when it is done.", branch, short_commit(latest)];
        [a addButtonWithTitle:@"Update"]; [a addButtonWithTitle:@"Cancel"];
        if ([a runModal] != NSAlertFirstButtonReturn) return;
        if (update_run(wv.window, updater, branch, [data stringByAppendingPathComponent:@"update.log"])) {   /* restart: the new app, then this one ends */
            NSString *app = [[[updater stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
            NSTask *o = [NSTask new]; o.executableURL = [NSURL fileURLWithPath:@"/usr/bin/open"]; o.arguments = @[@"-n", app];
            [o launchAndReturnError:nil]; [o waitUntilExit];
            exit(0);
        }
        check();
    };
    v.tiles = @[gfx, saves, files, upd];
    NSDictionary *(^choices)(void) = ^NSDictionary * { return @{@"display": val(display), @"notch": val(notch), @"resolution": val(res), @"vsync": val(vsync)}; };
    v.onChange = ^{ [choices() writeToFile:plistPath atomically:YES]; };

    if (shot) {                                                          /* development: the window as an image */
        if (getenv("DS_LAUNCHER_HOVER")) v.hover = atoi(getenv("DS_LAUNCHER_HOVER"));
        if (getenv("DS_LAUNCHER_OPEN")) v.open = YES;
        NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds]; [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(shot) atomically:YES];
        return 0;
    }
    NSWindow *w = [[NSWindow alloc] initWithContentRect:v.frame styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskFullSizeContentView
                                                backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;   /* ARC owns it */
    w.titlebarAppearsTransparent = YES; w.titleVisibility = NSWindowTitleHidden; w.movableByWindowBackground = YES;
    w.title = @"Grand Theft Auto III"; w.backgroundColor = NSColor.blackColor; w.contentView = v; [w center]; [w makeFirstResponder:v];
    __block int result = 0;
    v.onPlay = ^{ result = 1; [NSApp stopModal]; };
    v.onQuit = ^{ result = 0; [NSApp stopModal]; };
    id obs = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification object:w queue:nil usingBlock:^(NSNotification *n) { (void)n; [NSApp stopModal]; }];
    [NSApp activateIgnoringOtherApps:YES];
    [w makeKeyAndOrderFront:nil];
    [NSApp runModalForWindow:w];
    [[NSNotificationCenter defaultCenter] removeObserver:obs];
    [w orderOut:nil];
    if (!result) return 0;
    NSDictionary *c = choices(); [c writeToFile:plistPath atomically:YES];
    apply(c);
    return 1;
}
