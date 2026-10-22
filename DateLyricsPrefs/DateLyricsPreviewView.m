#import "DateLyricsPreviewView.h"
#import <QuartzCore/QuartzCore.h>

// same constants and curve the tweak uses for its marquee, so what the preview scrolls like is
// what the lock screen scrolls like.
static const NSTimeInterval kPVMarqueeHoldPad   = 0.15;
static const CGFloat        kPVMarqueeMaxSpeed  = 90.0;
static const NSTimeInterval kPVMarqueeMinScroll = 0.60;

// the tweak starts the next line this long before its timestamp so the transition can settle
// (kdatelyricslinetransitionlead), and slides by the date label's real height (26.33 pt measured
// from the stock label on device). matching both keeps the preview's motion identical.
static const NSTimeInterval kPVLineLead = 0.05;
static const CGFloat        kPVLabelHeight = 26.333;
static const CGFloat        kPVDimAlpha = 0.35;

/// the current time the way the lock screen shows it: no am/pm, no leading zero in 12-hour mode.
static NSString *PVClockString(void) {
    static NSDateFormatter *formatter = nil;
    static NSString *currentLocaleID = nil;
    NSString *localeID = NSLocale.currentLocale.localeIdentifier;
    if (!formatter || ![currentLocaleID isEqualToString:localeID]) {
        NSString *template = [NSDateFormatter dateFormatFromTemplate:@"j:mm" options:0 locale:NSLocale.currentLocale] ?: @"h:mm";
        template = [template stringByReplacingOccurrencesOfString:@"a" withString:@""];
        template = [template stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        formatter = [NSDateFormatter new];
        formatter.locale = NSLocale.currentLocale;
        formatter.dateFormat = template;
        currentLocaleID = localeID;
    }
    return [formatter stringFromDate:[NSDate date]];
}

static CGFloat PVWidth(NSString *text, UIFont *font) {
    if (text.length == 0 || !font) return 0.0;
    return ceil([text sizeWithAttributes:@{NSFontAttributeName: font}].width);
}

@class DateLyricsPreviewView;

@interface DateLyricsPreviewView ()
- (void)pv_tick;
@end

// cadisplaylink retains its target; route through a weak box so the view can still dealloc.
@interface PVWeakTarget : NSObject
@property (nonatomic, weak) DateLyricsPreviewView *view;
- (void)tick:(CADisplayLink *)link;
@end

@implementation PVWeakTarget
- (void)tick:(CADisplayLink *)link { [self.view pv_tick]; }
@end

@implementation DateLyricsPreviewView {
    BOOL _card;
    UILabel *_clock;
    CFTimeInterval _lastClockCheck;
    UIView *_viewport;
    UIView *_host;
    // playback-clock smoothing (mirrors the tweak's pause glide / hold / resume ramp).
    double _dispT, _lastSrcT;
    CFTimeInterval _lastTickNow, _modeStart;
    NSInteger _clockMode, _stillFrames;   // 0 follow, 1 glide/paused, 2 hold, 3 ramp
    double _glideBase;
    UIView *_outgoing;
    UILabel *_content;
    NSMutableArray<UILabel *> *_overlays;
    NSMutableArray<CAGradientLayer *> *_masks;
    NSArray<NSNumber *> *_activeIndices;

    CADisplayLink *_link;
    PVWeakTarget *_target;
    CFTimeInterval _t0;
    double _lastT;
    NSInteger _token;
    CGSize _lastSize;

    NSString *_curKey;
    NSString *_stateKey;
    NSInteger _segLine;
    NSInteger _segMono;
    NSDictionary *_model;

    UIFont *_font;
    CGFloat _textWidth;
    CGFloat _avail;
    CGFloat _overflow;
    BOOL _marquee;
    BOOL _fallback;
    NSArray<NSValue *> *_wordRects;
}

#pragma mark - Setup

- (instancetype)initWithFrame:(CGRect)frame card:(BOOL)card {
    // a negative width (a caller computing "container width - inset" before the container has been
    // laid out) makes uikit shift the view's bounds origin to compensate, and that offset stays
    // after the frame becomes valid, pushing all content sideways. never accept one.
    frame.size.width = MAX(frame.size.width, 0.0);
    frame.size.height = MAX(frame.size.height, 0.0);
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _card = card;
    _overlays = [NSMutableArray array];
    _masks = [NSMutableArray array];
    _segLine = -1;
    _loopDuration = 42.0;
    _settings = @{};

    // text only: no card, no gradient, no border. the lyric and clock sit directly on the page
    // in the system label colour, so they follow light and dark mode on their own.
    self.backgroundColor = UIColor.clearColor;
    self.clipsToBounds = NO;
    if (card) {
        // a native-looking card: the same rounded surface the settings rows use, so the preview
        // reads as its own element without any gradient or border.
        self.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        self.layer.cornerRadius = 16.0;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;
    }
    self.userInteractionEnabled = NO;
    _textColor = UIColor.labelColor;
    self.isAccessibilityElement = NO;

    if (card) {
        _clock = [UILabel new];
        _clock.text = PVClockString();
        _clock.textAlignment = NSTextAlignmentCenter;
        _clock.textColor = [UIColor.labelColor colorWithAlphaComponent:0.92];
        _clock.font = [UIFont systemFontOfSize:96.0 weight:UIFontWeightBold];
        _clock.adjustsFontSizeToFitWidth = YES;
        _clock.minimumScaleFactor = 0.5;
        [self addSubview:_clock];
    }

    _viewport = [UIView new];
    // clip sideways only (the marquee must not spill), but let lines slide freely above and below
    // during a transition, as they do on the lock screen. a mask taller than the slot does this.
    _viewport.clipsToBounds = NO;
    _viewport.layer.mask = [CALayer layer];
    _viewport.layer.mask.backgroundColor = UIColor.blackColor.CGColor;
    [self addSubview:_viewport];

    _host = [UIView new];
    [_viewport addSubview:_host];

    _content = [UILabel new];
    _content.numberOfLines = 1;
    _content.backgroundColor = UIColor.clearColor;
    [_host addSubview:_content];
    return self;
}

- (void)dealloc {
    [_link invalidate];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.bounds.origin.x != 0.0 || self.bounds.origin.y != 0.0) {
        CGRect fixed = self.bounds;
        fixed.origin = CGPointZero;
        self.bounds = fixed;
    }
    CGFloat W = CGRectGetWidth(self.bounds), H = CGRectGetHeight(self.bounds);
    if (_card) {
        // the lyric slot is as wide as the lock screen's date view (336 pt on a 375 pt screen:
        // screen width minus 39), so line splitting and the marquee trigger at the same widths.
        CGFloat slot = MIN([UIScreen mainScreen].bounds.size.width - 39.0, W - 36.0);
        slot = MAX(slot, 1.0);
        _viewport.frame = CGRectMake(floor((W - slot) * 0.5), 14.0, slot, kPVLabelHeight);
        // only the top half of the clock shows, fading out toward the card's bottom edge.
        CGFloat clockH = ceil(_clock.font.lineHeight);
        _clock.frame = CGRectMake(0.0, 31.0, W, clockH);
        CGFloat visible = MAX(H - 31.0, 1.0);
        CAGradientLayer *fade = [CAGradientLayer layer];
        fade.frame = _clock.bounds;
        fade.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
        fade.startPoint = CGPointMake(0.5, 0.0);
        fade.endPoint = CGPointMake(0.5, 1.0);
        fade.locations = @[@(MIN(0.45 * visible / clockH, 0.99)), @(MIN(visible / clockH, 1.0))];
        _clock.layer.mask = fade;
    } else {
        _viewport.frame = CGRectMake(0.0, 0.0, MAX(W, 1.0), H);
    }
    _host.frame = _viewport.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _viewport.layer.mask.frame = CGRectMake(0.0, -40.0, CGRectGetWidth(_viewport.bounds), CGRectGetHeight(_viewport.bounds) + 80.0);
    [CATransaction commit];

    if (!CGSizeEqualToSize(_lastSize, self.bounds.size)) {
        _lastSize = self.bounds.size;
        [self finishTransitionNow];
        _curKey = nil;
        _segLine = -1;   // segment boundaries depend on width, so drop the monotonic floor
        [self renderAtTime:_lastT animated:NO];
    }
}

#pragma mark - Public

- (void)setTimeProvider:(double (^)(void))timeProvider {
    _timeProvider = [timeProvider copy];
    _clockMode = 0; _lastSrcT = -1.0; _stillFrames = 0;
    [self finishTransitionNow];
    _curKey = nil;
    _segLine = -1;
}

- (void)setLines:(NSArray<NSDictionary *> *)lines {
    _lines = [lines copy];
    NSDictionary *last = _lines.lastObject;
    double end = [last[@"end"] doubleValue];
    if (end > 1.0) _loopDuration = end + 1.0;
    _curKey = nil;
    _segLine = -1;
    [self renderAtTime:_lastT animated:NO];
}

- (void)start {
    if (_link) return;
    _target = [PVWeakTarget new];
    _target.view = self;
    _t0 = CACurrentMediaTime();
    _link = [CADisplayLink displayLinkWithTarget:_target selector:@selector(tick:)];
    _link.preferredFramesPerSecond = 60;
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

}

- (void)stop {
    [_link invalidate];
    _link = nil;
    _target = nil;
    [self finishTransitionNow];
}

- (void)applySettings:(NSDictionary *)settings {
    _settings = [settings copy] ?: @{};
    [self finishTransitionNow];
    _curKey = nil;
    _segLine = -1;
    [self renderAtTime:_lastT animated:NO];
}

- (void)playTransitionDemo {
    if (!_curKey || ![self transitionsActive]) return;
    UIView *snap = [self captureOutgoing];
    [self runTransitionWithOutgoing:snap];
}

#pragma mark - Settings helpers

- (BOOL)flag:(NSString *)key fallback:(BOOL)fallback {
    id v = _settings[key];
    return v ? [v boolValue] : fallback;
}

- (NSTimeInterval)transitionDuration {
    id v = _settings[@"TransitionDuration"];
    double d = v ? [v doubleValue] : 0.33;
    return MIN(MAX(d, 0.0), 2.0);
}

- (BOOL)transitionsActive {
    return [self flag:@"TransitionsEnabled" fallback:YES] && [self transitionDuration] > 0.02;
}

- (UIFont *)resolveFont {
    // the real date label is 26.33 pt tall, which only a 22 pt system font produces. the header
    // preview is drawn a little larger (24 pt) for readability, so long lines may wrap or scroll
    // marginally earlier than on the lock screen. the compact nav version is a smaller stand-in.
    CGFloat size = _card ? 22.0 : 18.0;
    UIFont *font = [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
    if ([self flag:@"UseCustomFont" fallback:NO]) {
        NSString *name = _settings[@"CustomFontName"];
        if ([name isKindOfClass:NSString.class] && name.length > 0) {
            UIFont *custom = [UIFont fontWithName:name size:size];
            if (custom) font = custom;
        }
    }
    return font;
}

#pragma mark - Time -> what to show

/// live mode only. pausing does not freeze the fill and marquee dead: they coast to a stop over
/// 0.20 s (ease-out). on resume they wait until the real clock has caught up to where they
/// stopped, then ramp back to full speed over 0.18 s, exactly as the lock screen does.
- (double)smoothedClock:(double)src now:(CFTimeInterval)now {
    static const double kGlide = 0.20, kRamp = 0.18;
    double dt = now - _lastTickNow;
    _lastTickNow = now;
    if (dt <= 0.0 || dt > 0.25 || _lastSrcT < 0.0) { _dispT = src; _lastSrcT = src; _clockMode = 0; _stillFrames = 0; return src; }
    BOOL moving = (src - _lastSrcT) > 0.0004;
    BOOL jumped = fabs(src - _lastSrcT) > 0.5;   // scrub or track change
    _lastSrcT = src;
    _stillFrames = moving ? 0 : _stillFrames + 1;
    if (jumped) { _clockMode = 0; _dispT = src; return src; }

    switch (_clockMode) {
        case 0:
            _dispT = src;
            if (_stillFrames >= 2) { _clockMode = 1; _modeStart = now; _glideBase = _dispT; }
            break;
        case 1: {
            if (moving) { _clockMode = 2; break; }
            double tau = MIN((now - _modeStart) / kGlide, 1.0);
            _dispT = _glideBase + kGlide * (tau - tau * tau * 0.5);
            break;
        }
        case 2:
            // held: the display is a little ahead of the restarted clock. wait for it.
            if (!moving && _stillFrames >= 2) { _clockMode = 1; _modeStart = now; _glideBase = _dispT; break; }
            if (src >= _dispT - 0.5 * kRamp) { _clockMode = 3; _modeStart = now; }
            break;
        case 3: {
            if (!moving && _stillFrames >= 2) { _clockMode = 1; _modeStart = now; _glideBase = _dispT; break; }
            double u = (now - _modeStart) / kRamp;
            if (u >= 1.0) { _clockMode = 0; _dispT = src; break; }
            _dispT += dt * u;
            break;
        }
    }
    return _dispT;
}

- (void)pv_tick {
    double loop = MAX(_loopDuration, 8.0);
    // live mode follows the song that is actually playing; otherwise loop the built-in sample.
    double t = _timeProvider ? [self smoothedClock:_timeProvider() now:CACurrentMediaTime()]
                             : fmod(CACurrentMediaTime() - _t0, loop);
    if (_clock && CACurrentMediaTime() - _lastClockCheck > 1.0) {
        _lastClockCheck = CACurrentMediaTime();
        NSString *now = PVClockString();
        if (![now isEqualToString:_clock.text]) _clock.text = now;
    }
    [self renderAtTime:t animated:YES];
}

/// resolves the line and (when split long lines applies) the segment shown at time t,
/// honouring ad-libs, lowercase and the font. mirrors the tweak's per-line planning.
- (NSDictionary *)modelAtTime:(double)t {
    NSArray<NSDictionary *> *lines = _lines;
    if (lines.count == 0) return nil;

    // the tweak advances the line slightly early (the transition needs time to settle) while the
    // syllable fill stays on the true clock; do the same.
    double lineTime = t + ([self transitionsActive] ? kPVLineLead : 0.0);
    NSInteger L = 0;
    for (NSInteger i = 0; i < (NSInteger)lines.count; i++) {
        if (lineTime >= [lines[i][@"begin"] doubleValue]) L = i; else break;
    }
    NSDictionary *line = lines[L];

    BOOL showAdlibs = [self flag:@"ShowAdlibs" fallback:YES];
    BOOL lower = [self flag:@"ForceLowercase" fallback:NO];
    NSMutableArray<NSDictionary *> *words = [NSMutableArray array];
    for (NSDictionary *w in line[@"words"]) {
        if ([w[@"bg"] boolValue] && !showAdlibs) continue;
        [words addObject:w];
    }
    if (words.count == 0) words = [line[@"words"] mutableCopy];

    NSMutableString *full = [NSMutableString string];
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    for (NSDictionary *w in words) {
        NSString *text = w[@"text"] ?: @"";
        if (lower) text = text.lowercaseString;
        // real scores carry each word's own separator (a syllable continues a word with none).
        NSString *sep = w[@"sep"];
        if (full.length > 0) [full appendString:(sep ?: @" ")];
        [ranges addObject:[NSValue valueWithRange:NSMakeRange(full.length, text.length)]];
        [full appendString:text];
    }

    NSInteger n = (NSInteger)words.count;
    CGFloat avail = CGRectGetWidth(_viewport.bounds);
    UIFont *font = _font ?: [self resolveFont];

    // split long lines: greedy word packing, then pick the segment holding the active word.
    NSMutableArray<NSValue *> *segs = [NSMutableArray array];
    if ([self flag:@"SplitLongLines" fallback:NO] && n >= 2 && avail > 1.0 && PVWidth(full, font) > avail) {
        NSInteger start = 0;
        for (NSInteger i = 1; i < n; i++) {
            NSRange first = [ranges[start] rangeValue], cur = [ranges[i] rangeValue];
            NSString *candidate = [full substringWithRange:NSMakeRange(first.location, NSMaxRange(cur) - first.location)];
            if (PVWidth(candidate, font) > avail) {
                [segs addObject:[NSValue valueWithRange:NSMakeRange(start, i - start)]];
                start = i;
            }
        }
        [segs addObject:[NSValue valueWithRange:NSMakeRange(start, n - start)]];
    }
    if (segs.count < 2) {
        segs = [NSMutableArray arrayWithObject:[NSValue valueWithRange:NSMakeRange(0, n)]];
    }

    NSInteger active = -1;
    for (NSInteger i = 0; i < n; i++) {
        if (t >= [words[i][@"begin"] doubleValue]) active = i;
    }
    NSInteger target = 0;
    if (active >= 0) {
        for (NSInteger s = 0; s < (NSInteger)segs.count; s++) {
            NSRange r = [segs[s] rangeValue];
            if (active >= (NSInteger)r.location && active < (NSInteger)NSMaxRange(r)) { target = s; break; }
        }
    }
    // monotonic within a line, so a gap between words never snaps back to segment 0.
    if (L == _segLine) target = MAX(target, _segMono);
    _segLine = L;
    _segMono = target;
    target = MIN(target, (NSInteger)segs.count - 1);

    NSRange wr = [segs[target] rangeValue];
    NSString *segText = @"";
    NSMutableArray<NSDictionary *> *segWords = [NSMutableArray array];
    if (wr.length > 0) {
        NSRange firstR = [ranges[wr.location] rangeValue];
        NSRange lastR = [ranges[NSMaxRange(wr) - 1] rangeValue];
        segText = [full substringWithRange:NSMakeRange(firstR.location, NSMaxRange(lastR) - firstR.location)];
        for (NSUInteger i = wr.location; i < NSMaxRange(wr); i++) {
            NSRange r = [ranges[i] rangeValue];
            [segWords addObject:@{
                @"range": [NSValue valueWithRange:NSMakeRange(r.location - firstR.location, r.length)],
                @"begin": words[i][@"begin"] ?: @0,
                @"end": words[i][@"end"] ?: @0,
            }];
        }
    }

    return @{
        @"line": @(L),
        @"seg": @(target),
        @"text": segText,
        @"words": segWords,
        @"lineBegin": line[@"begin"] ?: @0,
        @"lineEnd": line[@"end"] ?: @0,
        @"split": @(segs.count > 1),
    };
}

#pragma mark - Rendering

- (void)renderAtTime:(double)t animated:(BOOL)animated {
    if (_lines.count == 0 || CGRectGetWidth(_viewport.bounds) < 10.0) return;
    _lastT = t;
    _font = [self resolveFont];
    _avail = CGRectGetWidth(_viewport.bounds);

    NSDictionary *model = [self modelAtTime:t];
    if (!model) return;
    NSString *key = [NSString stringWithFormat:@"%@|%@", model[@"line"], model[@"seg"]];

    if (!_curKey || ![key isEqualToString:_curKey]) {
        BOOL animate = animated && _curKey != nil && [self transitionsActive];
        UIView *snapshot = nil;
        if (animate) snapshot = [self captureOutgoing]; else [self finishTransitionNow];
        _curKey = key;
        _stateKey = nil;
        _model = model;
        [self rebuildContent];
        if (animate) [self runTransitionWithOutgoing:snapshot];
    }
    _model = model;
    [self updateAppearanceAtTime:t];
}

/// lays out the content for the current line/segment: width, overflow mode, glyph rects.
- (void)rebuildContent {
    NSString *text = _model[@"text"];
    CGFloat h = CGRectGetHeight(_viewport.bounds);

    _textWidth = PVWidth(text, _font) + 1.0;
    _overflow = MAX(0.0, _textWidth - _avail);
    BOOL overflowing = _textWidth > _avail + 0.5;
    _marquee = overflowing && [self flag:@"MarqueeEnabled" fallback:YES] && ![_model[@"split"] boolValue];
    // overflowing with no marquee: the tweak shrinks to the minimum scale, then truncates.
    _fallback = overflowing && !_marquee;

    if (_fallback) {
        _content.frame = CGRectMake(0.0, 0.0, _avail, h);
        _content.textAlignment = NSTextAlignmentCenter;
        _content.adjustsFontSizeToFitWidth = YES;
        _content.minimumScaleFactor = 0.55;
        _content.lineBreakMode = NSLineBreakByTruncatingTail;
    } else {
        _content.frame = CGRectMake(0.0, 0.0, _textWidth, h);
        _content.textAlignment = NSTextAlignmentLeft;
        _content.adjustsFontSizeToFitWidth = NO;
        _content.lineBreakMode = NSLineBreakByClipping;
    }

    // per-word glyph rectangles, for the gradient fill windows.
    NSMutableArray<NSValue *> *rects = nil;
    if (!_fallback && text.length > 0) {
        NSTextStorage *storage = [[NSTextStorage alloc] initWithString:text attributes:@{NSFontAttributeName: _font}];
        NSLayoutManager *layout = [NSLayoutManager new];
        NSTextContainer *container = [[NSTextContainer alloc] initWithSize:CGSizeMake(10000.0, h)];
        container.lineFragmentPadding = 0.0;
        container.maximumNumberOfLines = 1;
        [layout addTextContainer:container];
        [storage addLayoutManager:layout];
        rects = [NSMutableArray array];
        for (NSDictionary *w in _model[@"words"]) {
            NSRange r = [w[@"range"] rangeValue];
            NSRange glyphs = [layout glyphRangeForCharacterRange:r actualCharacterRange:NULL];
            CGRect rect = [layout boundingRectForGlyphRange:glyphs inTextContainer:container];
            [rects addObject:[NSValue valueWithCGRect:rect]];
        }
    }
    _wordRects = rects;
    for (UILabel *overlay in _overlays) overlay.hidden = YES;
    _activeIndices = @[];
}

- (void)updateAppearanceAtTime:(double)t {
    NSString *text = _model[@"text"];
    NSArray<NSDictionary *> *words = _model[@"words"];
    BOOL wordHL = [self flag:@"WordHighlighting" fallback:YES];
    BOOL progressive = wordHL && [self flag:@"ProgressiveFill" fallback:YES] && !_fallback &&
                       _wordRects.count == words.count;

    UIColor *bright = _textColor ?: UIColor.labelColor;
    UIColor *dim = [bright colorWithAlphaComponent:kPVDimAlpha];

    // the expensive part (attributed strings, overlay text) only changes when a word starts or
    // ends; between those moments only the gradient edge and marquee offset move.
    NSMutableString *state = [NSMutableString stringWithFormat:@"%d%d%d|", wordHL, progressive, _fallback];
    NSMutableArray<NSNumber *> *active = [NSMutableArray array];
    for (NSUInteger i = 0; i < words.count && wordHL; i++) {
        double b = [words[i][@"begin"] doubleValue], e = [words[i][@"end"] doubleValue];
        if (progressive) {
            if (e <= t) [state appendString:@"c"];
            else if (b <= t) { [state appendString:@"a"]; [active addObject:@(i)]; }
            else [state appendString:@"-"];
        } else {
            [state appendString:(b <= t ? @"b" : @"-")];
        }
    }

    if (![state isEqualToString:_stateKey]) {
        _stateKey = state;
        NSMutableAttributedString *attr = [[NSMutableAttributedString alloc]
            initWithString:text attributes:@{NSFontAttributeName: _font,
                                             NSForegroundColorAttributeName: wordHL ? dim : bright}];
        if (wordHL) {
            for (NSDictionary *w in words) {
                double b = [w[@"begin"] doubleValue], e = [w[@"end"] doubleValue];
                BOOL lit = progressive ? (e <= t) : (b <= t);
                if (lit) {
                    NSRange r = [w[@"range"] rangeValue];
                    if (NSMaxRange(r) <= attr.length) [attr addAttribute:NSForegroundColorAttributeName value:bright range:r];
                }
            }
        }
        _content.attributedText = attr;

        while (_overlays.count < active.count) {
            UILabel *overlay = [UILabel new];
            overlay.numberOfLines = 1;
            overlay.lineBreakMode = NSLineBreakByClipping;
            overlay.backgroundColor = UIColor.clearColor;
            overlay.userInteractionEnabled = NO;
            CAGradientLayer *mask = [CAGradientLayer layer];
            mask.startPoint = CGPointMake(0.0, 0.5);
            mask.endPoint = CGPointMake(1.0, 0.5);
            mask.colors = @[(id)UIColor.whiteColor.CGColor, (id)UIColor.whiteColor.CGColor,
                            (id)UIColor.clearColor.CGColor, (id)UIColor.clearColor.CGColor];
            mask.locations = @[@0.0, @0.0, @0.0, @1.0];
            mask.actions = @{@"locations": NSNull.null, @"bounds": NSNull.null, @"position": NSNull.null};
            overlay.layer.mask = mask;
            [_content addSubview:overlay];
            [_overlays addObject:overlay];
            [_masks addObject:mask];
        }
        for (NSUInteger k = 0; k < _overlays.count; k++) {
            UILabel *overlay = _overlays[k];
            if (k >= active.count) { overlay.hidden = YES; continue; }
            NSRange r = [words[active[k].unsignedIntegerValue][@"range"] rangeValue];
            NSMutableAttributedString *oa = [[NSMutableAttributedString alloc]
                initWithString:text attributes:@{NSFontAttributeName: _font,
                                                 NSForegroundColorAttributeName: UIColor.clearColor}];
            if (NSMaxRange(r) <= oa.length) [oa addAttribute:NSForegroundColorAttributeName value:bright range:r];
            overlay.attributedText = oa;
            overlay.frame = _content.bounds;
            _masks[k].frame = overlay.bounds;
            overlay.hidden = NO;
        }
        _activeIndices = [active copy];
    }

    // gradient fill: a feathered window sweeping across the active word, as in the tweak.
    if (progressive) {
        CGFloat width = MAX(CGRectGetWidth(_content.bounds), 1.0);
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        for (NSUInteger k = 0; k < _activeIndices.count && k < _masks.count; k++) {
            NSUInteger wi = _activeIndices[k].unsignedIntegerValue;
            CGRect glyph = _wordRects[wi].CGRectValue;
            double b = [words[wi][@"begin"] doubleValue], e = [words[wi][@"end"] doubleValue];
            double fraction = e > b ? MIN(MAX((t - b) / (e - b), 0.0), 1.0) : 1.0;
            CGFloat start = MIN(MAX(CGRectGetMinX(glyph) / width, 0.0), 1.0);
            CGFloat span = MIN(MAX(CGRectGetWidth(glyph) / width, 0.0), 1.0 - start);
            CGFloat feather = MIN(8.0 / width, MAX(1.0 / width, span * 0.5));
            CGFloat edge = MIN(1.0, start + (span + feather) * fraction);
            CGFloat soft = MAX(0.0, edge - feather);
            _masks[k].locations = @[@0.0, @(soft), @(edge), @1.0];
        }
        [CATransaction commit];
    }

    // position: centred if it fits, otherwise the marquee's hold + smoothstep scroll.
    CGFloat x = 0.0;
    if (_marquee) {
        double lineBegin = [_model[@"lineBegin"] doubleValue], lineEnd = [_model[@"lineEnd"] doubleValue];
        double timeline = MAX(lineEnd - lineBegin, 0.001);
        double phase = t - lineBegin;
        NSTimeInterval desired = ([self transitionsActive] ? [self transitionDuration] : 0.0) + kPVMarqueeHoldPad;
        NSTimeInterval needScroll = MAX(kPVMarqueeMinScroll, _overflow / kPVMarqueeMaxSpeed);
        NSTimeInterval maxHold = timeline - needScroll;
        NSTimeInterval hold = maxHold <= 0.0 ? 0.0 : MIN(desired, maxHold);
        double scroll = MAX(timeline - hold, 0.001);
        if (phase <= hold) x = 0.0;
        else if (phase >= timeline) x = -_overflow;
        else {
            double u = (phase - hold) / scroll;
            x = -_overflow * (u * u * (3.0 - 2.0 * u));
        }
    } else if (!_fallback) {
        x = (_avail - _textWidth) * 0.5;
    }
    CGRect f = _content.frame;
    if (fabs(f.origin.x - x) > 0.01) { f.origin.x = x; _content.frame = f; }
}

#pragma mark - Transitions

- (void)finishTransitionNow {
    [_host.layer removeAllAnimations];
    _host.transform = CGAffineTransformIdentity;
    _host.alpha = 1.0;
    if (_outgoing) {
        [_outgoing.layer removeAllAnimations];
        [_outgoing removeFromSuperview];
        _outgoing = nil;
    }
    _token++;
}

/// freezes what is on screen as the outgoing line (finishing any transition in flight first).
- (UIView *)captureOutgoing {
    [self finishTransitionNow];
    UIView *snapshot = [_host snapshotViewAfterScreenUpdates:NO];
    if (!snapshot) return nil;
    snapshot.frame = _host.frame;
    snapshot.userInteractionEnabled = NO;
    [_viewport insertSubview:snapshot belowSubview:_host];
    _outgoing = snapshot;
    return snapshot;
}

/// the five styles, matching the tweak's datelyricsanimatelabeltransition. forward direction
/// only: the preview loops forward and never scrubs backwards.
- (void)runTransitionWithOutgoing:(UIView *)out {
    NSTimeInterval d = MAX([self transitionDuration], 0.05);
    NSInteger style = [_settings[@"TransitionStyle"] integerValue];
    if (!_settings[@"TransitionStyle"]) style = 1;
    NSInteger token = ++_token;
    UIView *host = _host;
    // the tweak slides by the date label's own bounds: ~26.3 pt tall, as wide as the date view.
    CGFloat h = kPVLabelHeight, w = CGRectGetWidth(_viewport.bounds);
    UIViewAnimationOptions base = UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;

    switch (style) {
        case 0: { // fade: out, then in
            host.alpha = 0.0;
            [UIView animateKeyframesWithDuration:d delay:0.0 options:UIViewKeyframeAnimationOptionCalculationModeCubic animations:^{
                [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.45 animations:^{ out.alpha = 0.0; }];
                [UIView addKeyframeWithRelativeStartTime:0.55 relativeDuration:0.45 animations:^{ host.alpha = 1.0; }];
            } completion:nil];
            break;
        }
        case 1: case 2: case 3: { // up / down / push
            CGFloat dx = 0.0, dy = 0.0;
            if (style == 1) dy = h; else if (style == 2) dy = -h; else dx = w;
            host.transform = CGAffineTransformMakeTranslation(dx, dy);
            host.alpha = 0.0;
            [UIView animateWithDuration:d delay:0.0 options:base | UIViewAnimationOptionCurveEaseInOut animations:^{
                host.transform = CGAffineTransformIdentity;
                host.alpha = 1.0;
                out.transform = CGAffineTransformMakeTranslation(-dx, -dy);
                out.alpha = 0.0;
            } completion:nil];
            break;
        }
        case 4: { // pop
            host.transform = CGAffineTransformMakeScale(0.9, 0.9);
            host.alpha = 0.0;
            [UIView animateKeyframesWithDuration:d delay:0.0 options:UIViewKeyframeAnimationOptionCalculationModeCubic animations:^{
                [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.42 animations:^{
                    out.transform = CGAffineTransformMakeScale(1.1, 1.1);
                    out.alpha = 0.0;
                }];
                [UIView addKeyframeWithRelativeStartTime:0.5 relativeDuration:0.5 animations:^{
                    host.transform = CGAffineTransformIdentity;
                    host.alpha = 1.0;
                }];
            } completion:nil];
            break;
        }
        default: break;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((d + 0.05) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DateLyricsPreviewView *strongSelf = weakSelf;
        if (strongSelf && strongSelf->_token == token) [strongSelf finishTransitionNow];
    });
}

@end
