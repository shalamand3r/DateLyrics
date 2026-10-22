#import <UIKit/UIKit.h>

/// a live miniature of the lock-screen lyric line.
///
/// it re-implements, in a self-contained way, what the tweak does to the date label so the
/// preference pane can show the real effect of every setting: gradient progressive fill,
/// word highlighting, marquee scrolling (same hold + smoothstep curve), split long lines,
/// ad-libs, forced lowercase, custom font, and all five line transitions.
///
/// `lines` is an array of dictionaries:
///   @"begin" / @"end"  nsnumber (seconds)
///   @"words"           nsarray of @{ @"text": nsstring, @"begin": nsnumber, @"end": nsnumber,
///                                    @"bg": nsnumber(bool), @"sep": nsstring (optional) }
///
/// `settings` uses the same keys as the tweak's preferences (forcelowercase, wordhighlighting,
/// progressivefill, usecustomfont, customfontname, transitionsenabled, transitionstyle,
/// transitionduration, splitlonglines, marqueeenabled, showadlibs).
@interface DateLyricsPreviewView : UIView

/// yes: header style, with a clock under the lyric line.
/// no: compact lyric line suitable for a navigation bar.
- (instancetype)initWithFrame:(CGRect)frame card:(BOOL)card;

@property (nonatomic, copy) NSArray<NSDictionary *> *lines;

/// text colour for the lyric and clock. defaults to the dynamic system label colour.
@property (nonatomic, strong) UIColor *textColor;

/// when set, the preview follows this song position (seconds) instead of looping its built-in
/// sample. return the live playback position; the view never calls it off the main thread.
@property (nonatomic, copy) double (^timeProvider)(void);
@property (nonatomic, copy) NSDictionary *settings;
@property (nonatomic, assign) NSTimeInterval loopDuration;

/// starts / stops the display link. call from viewwillappear / viewwilldisappear.
- (void)start;
- (void)stop;

/// re-reads `settings` and redraws the current line immediately, without a transition.
- (void)applySettings:(NSDictionary *)settings;

/// replays a line transition on the current line with the current style and duration, so a
/// change to the transition settings is visible right away instead of at the next lyric.
- (void)playTransitionDemo;

@end
