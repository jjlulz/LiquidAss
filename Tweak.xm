// Liquid Gl(ass) remake for iOS 12 (v3).
// Class names and view layouts come from a ViewDump of a 6th gen iPod touch on iOS 12.
// Every glass surface is one cached bitmap (tint, top sheen, corner glow, dark hairline, two-tone rim).
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface CCUIContentModuleContainerView : UIView @end
@interface CCUIRoundButton : UIControl @end
@interface SBDockView : UIView @end
@interface SBFolderBackgroundView : UIView @end
@interface SBFolderIconBackgroundView : UIView @end
@interface NCNotificationShortLookView : UIView @end
@interface SBPasscodeNumberPadButton : UIControl @end
@interface SBFLockScreenDateView : UIView @end
@interface SPUITextField : UITextField @end

static UIView *ivarView(id obj, const char *name) {
    Ivar iv = class_getInstanceVariable([obj class], name);
    if (!iv) return nil;
    id v = object_getIvar(obj, iv);
    return [v isKindOfClass:[UIView class]] ? (UIView *)v : nil;
}

// ---------------------------------------------------------------- glass bitmap
static NSCache *gCache;

static UIImage *glassImage(CGSize size, CGFloat radius, CGFloat tint) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gCache = [[NSCache alloc] init];
        gCache.countLimit = 48;
    });
    NSString *key = [NSString stringWithFormat:@"%.1fx%.1f r%.1f t%.2f", size.width, size.height, radius, tint];
    UIImage *cached = [gCache objectForKey:key];
    if (cached) return cached;

    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt];
    UIImage *img = [renderer imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        CGContextRef c = rc.CGContext;
        CGFloat w = size.width, h = size.height;
        CGRect rect = CGRectMake(0, 0, w, h);
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();

        UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];

        // Light tint over the whole surface.
        [[UIColor colorWithWhite:1 alpha:tint] setFill];
        [shape fill];

        // Sheen from the top and glow in the top-left corner.
        CGContextSaveGState(c);
        [shape addClip];
        CGFloat sheen[8] = {1, 1, 1, 0.18, 1, 1, 1, 0.0};
        CGFloat sheenLoc[2] = {0.0, 0.55};
        CGGradientRef g1 = CGGradientCreateWithColorComponents(cs, sheen, sheenLoc, 2);
        CGContextDrawLinearGradient(c, g1, CGPointMake(w / 2, 0), CGPointMake(w / 2, h), 0);
        CGGradientRelease(g1);
        CGFloat glow[8] = {1, 1, 1, 0.22, 1, 1, 1, 0.0};
        CGGradientRef g2 = CGGradientCreateWithColorComponents(cs, glow, NULL, 2);
        CGPoint gc = CGPointMake(w * 0.12, h * 0.08);
        CGContextDrawRadialGradient(c, g2, gc, 0, gc, MAX(w, h) * 0.7, 0);
        CGGradientRelease(g2);
        CGContextRestoreGState(c);

        // Thin dark hairline on the very edge.
        UIBezierPath *hair = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(rect, 0.25, 0.25)
                                                        cornerRadius:MAX(0, radius - 0.25)];
        hair.lineWidth = 0.5;
        [[UIColor colorWithWhite:0 alpha:0.22] setStroke];
        [hair stroke];

        // Bright two-tone rim just inside the hairline.
        CGContextSaveGState(c);
        CGRect inner = CGRectInset(rect, 1.7, 1.7);
        UIBezierPath *ring = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(rect, 0.5, 0.5)
                                                        cornerRadius:MAX(0, radius - 0.5)];
        [ring appendPath:[UIBezierPath bezierPathWithRoundedRect:inner cornerRadius:MAX(0, radius - 1.7)]];
        ring.usesEvenOddFillRule = YES;
        [ring addClip];
        CGFloat rim[16] = {1, 1, 1, 0.85,  1, 1, 1, 0.10,  1, 1, 1, 0.10,  1, 1, 1, 0.55};
        CGFloat rimLoc[4] = {0.0, 0.35, 0.7, 1.0};
        CGGradientRef g3 = CGGradientCreateWithColorComponents(cs, rim, rimLoc, 4);
        CGContextDrawLinearGradient(c, g3, CGPointMake(0, 0), CGPointMake(w, h), 0);
        CGGradientRelease(g3);
        CGContextRestoreGState(c);

        CGColorSpaceRelease(cs);
    }];
    [gCache setObject:img forKey:key];
    return img;
}

static void glassOnLayer(CALayer *host, CGRect rect, CGFloat radius, CGFloat tint) {
    if (rect.size.width < 2 || rect.size.height < 2) return;
    CGFloat r = MIN(radius, MIN(rect.size.width, rect.size.height) / 2.0);
    UIImage *img = glassImage(rect.size, r, tint);

    CALayer *g = nil;
    for (CALayer *l in host.sublayers) {
        if ([l.name isEqualToString:@"lgglass"]) { g = l; break; }
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!g) {
        g = [CALayer layer];
        g.name = @"lgglass";
        g.opaque = NO;
        [host addSublayer:g];
    }
    g.frame = rect;
    g.contents = (__bridge id)img.CGImage;
    g.contentsScale = img.scale;
    // Keep it on top: the system sometimes adds its blur views after us.
    if (host.sublayers.lastObject != g) [host addSublayer:g];
    [CATransaction commit];
}

static void glass(UIView *v, CGFloat radius, CGFloat tint) {
    if (!v || v.bounds.size.width < 2 || v.bounds.size.height < 2) return;
    CGFloat r = MIN(radius, MIN(v.bounds.size.width, v.bounds.size.height) / 2.0);
    v.layer.cornerRadius = r;
    v.layer.masksToBounds = YES;
    glassOnLayer(v.layer, v.bounds, r, tint);
}

// ---------------------------------------------------------------- Control Center
%group CC_TILE
%hook CCUIContentModuleContainerView
- (void)layoutSubviews {
    %orig;
    CGFloat mn = MIN(self.bounds.size.width, self.bounds.size.height);
    // Small tiles become circles or capsules, big ones keep a 30pt corner.
    glass(self, mn <= 70 ? mn / 2.0 : 30.0, 0.10);
}
%end
%end

%group CC_BUTTON
%hook CCUIRoundButton
- (void)layoutSubviews {
    %orig;
    glass(self, 999.0, 0.06);
}
%end
%end

// ---------------------------------------------------------------- Dock
%group DOCK
%hook SBDockView
- (void)layoutSubviews {
    %orig;
    UIView *bg = ivarView(self, "_backgroundView");
    if (bg) {
        bg.frame = CGRectInset(bg.frame, 10, 8);
        glass(bg, 32.0, 0.05);
    }
}
%end
%end

// ---------------------------------------------------------------- Folders
%group FOLDER_ICON
%hook SBFolderIconBackgroundView
- (void)layoutSubviews {
    %orig;
    glass(self, self.bounds.size.width * 0.2237, 0.05);
}
%end
%end

%group FOLDER_BG
%hook SBFolderBackgroundView
- (void)layoutSubviews {
    %orig;
    glass(self, 38.0, 0.05);
}
%end
%end

// ---------------------------------------------------------------- Banners
%group BANNER
%hook NCNotificationShortLookView
- (void)layoutSubviews {
    %orig;
    glass(self, 26.0, 0.05);
}
%end
%end

// ---------------------------------------------------------------- Passcode keypad
%group PASSCODE
%hook SBPasscodeNumberPadButton
- (void)layoutSubviews {
    %orig;
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGFloat side = MIN(w, h) - 13.0;
    if (side < 20) return;
    CGRect rect = CGRectMake((w - side) / 2.0, (h - side) / 2.0, side, side);
    glassOnLayer(self.layer, rect, side / 2.0, 0.06);
}
%end
%end

// ---------------------------------------------------------------- Spotlight search bar
%group SEARCH
%hook SPUITextField
- (void)layoutSubviews {
    %orig;
    glass(self, 999.0, 0.06);
}
%end
%end

// ---------------------------------------------------------------- Lock screen clock
static UIImageView *lastImageView(UIView *v) {
    UIImageView *found = nil;
    for (UIView *s in v.subviews) {
        if ([s isKindOfClass:[UIImageView class]]) found = (UIImageView *)s;
        UIImageView *deeper = lastImageView(s);
        if (deeper) found = deeper;
    }
    return found;
}

// Draws `img` (used as an alpha mask) filled with `color`, shifted by dx/dy, in UIKit coordinates.
static void drawMasked(CGContextRef c, CGImageRef img, CGSize size, CGFloat dx, CGFloat dy,
                       UIColor *color, CGBlendMode mode) {
    CGContextSaveGState(c);
    CGContextSetBlendMode(c, mode);
    CGContextTranslateCTM(c, 0, size.height);
    CGContextScaleCTM(c, 1, -1);
    CGContextClipToMask(c, CGRectMake(dx, -dy, size.width, size.height), img);
    CGContextSetFillColorWithColor(c, color.CGColor);
    CGContextFillRect(c, CGRectMake(-size.width, -size.height, size.width * 3, size.height * 3));
    CGContextRestoreGState(c);
}

static UIGraphicsImageRenderer *rendererFor(UIImage *mask) {
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.opaque = NO;
    fmt.scale = mask.scale;
    return [[UIGraphicsImageRenderer alloc] initWithSize:mask.size format:fmt];
}

// A thin inner edge: the digits minus a copy of themselves shifted by (dx, dy).
static UIImage *edgeImage(UIImage *mask, UIColor *color, CGFloat dx, CGFloat dy) {
    CGSize size = mask.size;
    return [rendererFor(mask) imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        drawMasked(rc.CGContext, mask.CGImage, size, 0, 0, color, kCGBlendModeNormal);
        drawMasked(rc.CGContext, mask.CGImage, size, dx, dy, [UIColor blackColor], kCGBlendModeDestinationOut);
    }];
}

// Turns the white digits into glass: see-through body, bright inner edge top-left, darker edge bottom-right.
static UIImage *glassClockImage(UIImage *mask) {
    CGSize size = mask.size;
    CGFloat d = 1.4;
    UIImage *light = edgeImage(mask, [UIColor colorWithWhite:1 alpha:0.95], d, d);
    UIImage *dark = edgeImage(mask, [UIColor colorWithWhite:0 alpha:0.30], -d, -d);

    return [rendererFor(mask) imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        CGContextRef c = rc.CGContext;

        // Body: translucent white, brighter at the top, clipped to the digit shapes.
        CGContextSaveGState(c);
        CGContextTranslateCTM(c, 0, size.height);
        CGContextScaleCTM(c, 1, -1);
        CGContextClipToMask(c, CGRectMake(0, 0, size.width, size.height), mask.CGImage);
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGFloat comps[8] = {1, 1, 1, 0.50, 1, 1, 1, 0.14};
        CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps, NULL, 2);
        CGContextDrawLinearGradient(c, grad, CGPointMake(size.width / 2, size.height),
                                    CGPointMake(size.width / 2, 0), 0);
        CGGradientRelease(grad);
        CGColorSpaceRelease(cs);
        CGContextRestoreGState(c);

        [dark drawInRect:CGRectMake(0, 0, size.width, size.height)];
        [light drawInRect:CGRectMake(0, 0, size.width, size.height)];
    }];
}

static const void *kClockGlassKey = &kClockGlassKey;
static UIImage *gLastMask = nil;
static UIImage *gLastGlass = nil;

static void applyClockGlass(UIView *view) {
    UIView *label = ivarView(view, "_timeLabel");
    if (!label) return;
    UIImageView *iv = lastImageView(label);
    if (!iv || !iv.image || !iv.image.CGImage) return;

    // Remove the old gradient overlay from the previous version, if it is still there.
    for (CALayer *l in [iv.layer.sublayers copy]) {
        if ([l.name isEqualToString:@"lgclock"]) [l removeFromSuperlayer];
    }
    iv.alpha = 1.0;

    UIImage *current = iv.image;
    UIImage *ours = objc_getAssociatedObject(iv, kClockGlassKey);
    if (current == ours) return;  // already glass

    UIImage *glassImg;
    if (current == gLastMask && gLastGlass) {
        glassImg = gLastGlass;
    } else {
        glassImg = glassClockImage(current);
        gLastMask = current;
        gLastGlass = glassImg;
    }
    objc_setAssociatedObject(iv, kClockGlassKey, glassImg, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    iv.image = glassImg;
}

%group CLOCK
%hook SBFLockScreenDateView
- (void)layoutSubviews {
    %orig;
    applyClockGlass(self);
}
- (void)setDate:(id)date {
    %orig;
    __weak UIView *ws = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (ws) applyClockGlass(ws);
    });
}
%end
%end

// ---------------------------------------------------------------- init
static BOOL gSearchInited = NO;

%ctor {
    if (NSClassFromString(@"CCUIContentModuleContainerView")) { %init(CC_TILE); }
    if (NSClassFromString(@"CCUIRoundButton")) { %init(CC_BUTTON); }
    if (NSClassFromString(@"SBDockView")) { %init(DOCK); }
    if (NSClassFromString(@"SBFolderIconBackgroundView")) { %init(FOLDER_ICON); }
    if (NSClassFromString(@"SBFolderBackgroundView")) { %init(FOLDER_BG); }
    if (NSClassFromString(@"NCNotificationShortLookView")) { %init(BANNER); }
    if (NSClassFromString(@"SBPasscodeNumberPadButton")) { %init(PASSCODE); }
    if (NSClassFromString(@"SBFLockScreenDateView")) { %init(CLOCK); }

    // The Spotlight classes can load a little later than the rest.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!gSearchInited && NSClassFromString(@"SPUITextField")) {
            gSearchInited = YES;
            %init(SEARCH);
        }
    });
}
