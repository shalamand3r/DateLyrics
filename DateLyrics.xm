@import Darwin;
@import Foundation;
@import QuartzCore;
@import StoreKit;
@import UIKit;
#import <dlfcn.h>
#import <objc/runtime.h>
#import <stdarg.h>
#import <math.h>
#import <float.h>
#import <ctype.h>
#import <notify.h>
#import "DateLyricsStorage.h"
#import "DateLyricsPreferences.h"
#import <stdio.h>
#import "DateLyricsExternalTrack.h"
#import "DateLyricsJSON.h"
#import "DateLyricsProviderOrder.h"
#import "DateLyricsFetchSettings.h"
#import "CoreLyrics/CoreLyrics.h"
#import "CoreLyrics/LyricsText.h"

// native dim aod renders whole lyric lines, independent of the user's awake settings.
static BOOL gDateLyricsAlwaysOnDisplay = NO;
static BOOL gDateLyricsAODEnabled = YES;
static BOOL gDateLyricsAODRefreshRetry = YES;
static BOOL gDateLyricsAODSuppressed = NO;
static void DateLyricsRefreshDisplayState(BOOL fallbackAwake);
@interface SBBacklightPlatformProvider : NSObject
+ (BOOL)deviceSupportsAlwaysOn;
@end

@interface SBScreenSleepCoordinatorBacklightEnvironment : NSObject
- (instancetype)initWithCoordinator:(id)coordinator;
- (void)invalidateContentForReason:(id)reason;
- (NSDate *)presentationDate;
@end
static __weak SBScreenSleepCoordinatorBacklightEnvironment *gDateLyricsBacklightEnvironment;

@interface ICURLResponse : NSObject
@property (nonatomic, readonly) NSData *bodyData;
@end

typedef void (^ICURLSessionCompletionHandler)(ICURLResponse *, NSError *);

@interface MSVLyricsLine : NSObject
@property (assign, nonatomic) NSTimeInterval startTime;
@property (assign, nonatomic) NSTimeInterval endTime;
@property (copy, nonatomic) NSAttributedString *lyricsText;
@end

@interface ICMusicKitRequestContext : NSObject
@end

@interface ICMusicKitURLRequest : NSObject
@property (nonatomic, copy, readonly) ICMusicKitRequestContext *requestContext;
- (instancetype)initWithURL:(NSURL *)arg1 requestContext:(ICMusicKitRequestContext *)arg2;
@end

@interface MRContentItemMetadata : NSObject
@property (assign, nonatomic) NSInteger iTunesStoreIdentifier;
@property (assign, nonatomic) BOOL lyricsAvailable;
@property (assign, nonatomic) NSInteger lyricsAdamID;
@end

@interface MRContentItem : NSObject
@property (nonatomic, copy) MRContentItemMetadata *metadata;
@end



@interface MSVLyricsTTMLParser : NSObject
- (instancetype)initWithTTMLData:(NSData *)data;
- (NSArray<MSVLyricsLine *> *)lyricLines;
- (id)parseWithError:(id*)arg1;
@end

@interface ICURLSession : NSObject
- (void)enqueueDataRequest:(id)arg1 withCompletionHandler:(ICURLSessionCompletionHandler)arg2;
@end

@interface MRNowPlayingPlayerClient : NSObject
@property (nonatomic, readonly) MRContentItem *nowPlayingContentItem;
- (void)sendContentItemChanges:(NSArray<MRContentItem *> *)contentItems;
@end


@interface CSProminentSubtitleDateView : UIView
@end

@interface CSProminentEmptyElementView : UIView
@end

@interface _UIAnimatingLabel : UILabel
@end

@interface _UIAnimatingLabel (DateLyrics)
- (BOOL)_amlApplyCurrentLyric;
@end

@interface LyricsTask : NSObject
@property (nonatomic, assign) NSUInteger selectionGeneration;
@property (nonatomic, assign) CFTimeInterval startedAt;
@property (nonatomic, assign) NSInteger iTunesStoreID;
@property (nonatomic, assign) NSInteger lyricsAdamID;
@property (nonatomic, assign) NSInteger retryCount;
@property (nonatomic, strong) NSURL *lyricURL;
@property (nonatomic, strong) NSString *lyricsFilePath;
@property (nonatomic, copy) NSString *fallbackTitle;
@property (nonatomic, copy) NSString *fallbackArtist;
@property (nonatomic, copy) NSString *fallbackAlbum;
@property (nonatomic, assign) NSTimeInterval fallbackDuration;

@property (nonatomic, assign) NSUInteger cacheGeneration;
@end

typedef NS_ENUM(NSInteger, DateLyricsSyncTier) {
    DateLyricsSyncTierNone = 0,
    DateLyricsSyncTierLine = 1,
    DateLyricsSyncTierWord = 2,
};

@interface DateLyricsMusixmatchTask : NSObject
@property (nonatomic) NSInteger storeID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *album;
@property (nonatomic) NSTimeInterval duration;
@property (nonatomic) DateLyricsSyncTier appleTier;
@property (nonatomic) NSUInteger cacheGeneration;
@property (nonatomic) NSUInteger musixmatchGeneration;
@property (nonatomic, copy) NSString *taskID;
@property (nonatomic) BOOL hasShownLoading;
@property (nonatomic) NSInteger currentProviderIndex;
@property (nonatomic) NSInteger totalProviders;
@property (nonatomic) BOOL hasUsableLines;
@property (nonatomic) BOOL hasWordTiming;
@end

extern BOOL gDateLyricsShowAdlibs;

@interface DateLyricsTimedWord : NSObject
@property (nonatomic, assign) NSTimeInterval begin;
@property (nonatomic, assign) NSTimeInterval end;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *separatorBefore;
@property (nonatomic, assign, getter=isBackground) BOOL background;
@property (nonatomic, assign) NSRange characterRange;
@end

@interface DateLyricsTimedLine : NSObject
@property (nonatomic, assign) NSTimeInterval begin;
@property (nonatomic, assign) NSTimeInterval end;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSArray<DateLyricsTimedWord *> *words;
@property (nonatomic, assign) BOOL canonicalMapped;
// memoised adlib-filtered form of this line. see datelyricsgetfilteredline.
@property (nonatomic, strong) DateLyricsTimedLine *amlCachedFiltered;
@property (nonatomic, assign) BOOL amlCachedFilteredReturnsOriginal;
@property (nonatomic, assign) BOOL amlCachedFilteredValid;
@property (nonatomic, assign) BOOL amlCachedFilteredAdlibs;
@property (nonatomic, assign) BOOL characterRangesValid;
// immutable after range assignment: 0 unknown, 1 safe, 2 complex, 3 unsafe ranges.
@property (nonatomic, assign) NSUInteger amlResolverSuitability;
@end

@implementation LyricsTask
@end

@implementation DateLyricsMusixmatchTask
@end

@implementation DateLyricsTimedWord
@end

@implementation DateLyricsTimedLine
@end

static BOOL gDateLyricsDebugLogging = NO;
static BOOL gDateLyricsNativeTransitionProbe = NO;

static NSString *GetLyricsRootPath(void);
static BOOL DateLyricsIsSpringBoardHost(void);
static BOOL DateLyricsIsMusicHost(void);
static void DateLyricsWriteDebugLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void DateLyricsWriteDebugLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    static dispatch_queue_t queue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.shalamand3r.datelyrics.debuglog", DISPATCH_QUEUE_SERIAL);
    });

    NSString *stamped = [NSString stringWithFormat:@"[DateLyrics %@] %.3f %@", DateLyricsIsSpringBoardHost() ? @"SB" : @"Music", [NSDate timeIntervalSinceReferenceDate], message];

    dispatch_async(queue, ^{
        static NSUInteger lineCount = 0;
        static BOOL countInitialized = NO;
        NSString *dir = DateLyricsIsMusicHost() ? GetLyricsRootPath() : DateLyricsSharedDirectory;
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *path = [dir stringByAppendingPathComponent:@"tweak-debug.log"];

        if (!countInitialized) {
            NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
            lineCount = content ? [[content componentsSeparatedByString:@"\n"] count] : 0;
            countInitialized = YES;
        }

        lineCount++;

        // each [anim:p] etc. event is one entry now, so this is roughly 10+ minutes of
        // playback; the prefs viewer shows the newest 5000 lines of it.
        if (lineCount > 15000) {
            NSString *backup = [path stringByAppendingString:@".1"];
            [[NSFileManager defaultManager] removeItemAtPath:backup error:nil];
            [[NSFileManager defaultManager] moveItemAtPath:path toPath:backup error:nil];
            lineCount = 1;
        }

        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (handle) {
            [handle seekToEndOfFile];
            [handle writeData:[[stamped stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
            [handle closeFile];
        } else {
            [[stamped stringByAppendingString:@"\n"] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    });
}
#define DateLyricsDebugLog(...) do { \
    if (gDateLyricsDebugLogging) DateLyricsWriteDebugLog(__VA_ARGS__); \
} while (0)

// nsarray/nsdictionary descriptions print one element per line, which is why a few
// seconds of playback used to fill hundreds of log lines.  these keep every event to a
// single line so a long log window actually covers a long stretch of playback.
static NSString *DateLyricsFormatNumbers(NSArray *numbers) {
    if (![numbers isKindOfClass:NSArray.class]) return @"none";
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:numbers.count];
    for (id n in numbers) [parts addObject:[NSString stringWithFormat:@"%.3f", [n doubleValue]]];
    return [NSString stringWithFormat:@"[%@]", [parts componentsJoinedByString:@","]];
}

static NSString *DateLyricsFormatSegments(NSArray *segments) {
    if (![segments isKindOfClass:NSArray.class] || segments.count == 0) return @"none";
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:segments.count];
    for (NSDictionary *seg in segments) {
        NSString *lane = [seg[@"lane"] isEqual:@"background"] ? @"bg" : @"fg";
        [parts addObject:[NSString stringWithFormat:@"%@:%@+%@@%.3f-%.3f", lane,
                          seg[@"loc"] ?: @"?", seg[@"len"] ?: @"?",
                          [seg[@"begin"] doubleValue], [seg[@"end"] doubleValue]]];
    }
    return [parts componentsJoinedByString:@" "];
}


static void DateLyricsAssignCharacterRanges(DateLyricsTimedLine *line) {
    if (!line) return;
    line.amlResolverSuitability = 0;
    if (line.words.count == 0) return;

    NSUInteger cursor = 0;
    NSUInteger lineLength = line.text.length;
    NSMutableString *reconstructed = [NSMutableString string];

    for (DateLyricsTimedWord *word in line.words) {
        NSString *separator = word.separatorBefore ?: @"";
        NSString *wordText = word.text ?: @"";

        [reconstructed appendString:separator];
        [reconstructed appendString:wordText];

        if (separator.length > NSUIntegerMax - cursor) {
            word.characterRange = NSMakeRange(NSNotFound, 0);
            continue;
        }

        cursor += separator.length;

        if (cursor <= lineLength && wordText.length <= lineLength - cursor) {
            word.characterRange = NSMakeRange(cursor, wordText.length);
        } else {
            word.characterRange = NSMakeRange(NSNotFound, 0);
        }

        if (wordText.length <= NSUIntegerMax - cursor) {
            cursor += wordText.length;
        }
    }

    if ([reconstructed isEqualToString:line.text ?: @""]) {
        line.characterRangesValid = YES;
    } else {
        line.characterRangesValid = NO;
        DateLyricsDebugLog(@"[Resolver] Unsafe character ranges for line: reconstructed text mismatch");
    }
}

@interface DateLyricsScore : NSObject
@property (nonatomic, assign) NSInteger trackId;
@property (nonatomic, assign) BOOL hasWordTiming;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, copy) NSString *revision;

@property (nonatomic, strong) NSArray<DateLyricsTimedLine *> *lines;
- (instancetype)initWithJSONData:(NSData *)data;
@end

static BOOL DateLyricsIsUnsynchronizedLyricsID(NSInteger lyricsAdamID);



static BOOL DateLyricsSerializedLinesHaveTiming(NSArray *rawLines) {
    if (![rawLines isKindOfClass:NSArray.class] || rawLines.count == 0) return NO;

    BOOL hasTiming = NO;
    for (id rawLine in rawLines) {
        if (![rawLine isKindOfClass:NSDictionary.class]) return NO;
        NSDictionary *line = (NSDictionary *)rawLine;
        NSNumber *begin = line[@"begin"];
        NSNumber *end = line[@"end"];
        if (![begin isKindOfClass:NSNumber.class] || ![end isKindOfClass:NSNumber.class] ||
            !isfinite(begin.doubleValue) || !isfinite(end.doubleValue)) {
            return NO;
        }
        if (end.doubleValue > begin.doubleValue || begin.doubleValue > 0.001) hasTiming = YES;
        // line-synced ttml may expose only a start time; a non-zero start still
        // establishes an actual timeline.  the all-zero transcript score does
        // not pass this check.

        NSArray *rawWords = line[@"words"];
        if (rawWords && ![rawWords isKindOfClass:NSArray.class]) return NO;
        for (id rawWord in rawWords) {
            if (![rawWord isKindOfClass:NSDictionary.class]) return NO;
            NSNumber *wordBegin = rawWord[@"b"];
            NSNumber *wordEnd = rawWord[@"e"];
            if (![wordBegin isKindOfClass:NSNumber.class] || ![wordEnd isKindOfClass:NSNumber.class] ||
                !isfinite(wordBegin.doubleValue) || !isfinite(wordEnd.doubleValue)) {
                return NO;
            }
            if (wordEnd.doubleValue > wordBegin.doubleValue) hasTiming = YES;
        }
    }
    return hasTiming;
}

@implementation DateLyricsScore
- (instancetype)initWithJSONData:(NSData *)data {
    if ((self = [super init])) {
        if (data.length == 0) return nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]] || ![json[@"kind"] isEqual:@"score"]) return nil;
        self.trackId = DateLyricsJSONTrackID(json[@"trackId"]);
        if (self.trackId <= 0) return nil;
        self.hasWordTiming = DateLyricsJSONNumber(json[@"hasWordTiming"]).boolValue;

        self.source = [json[@"source"] isKindOfClass:NSString.class] ? json[@"source"] : nil;
        self.revision = [json[@"revision"] isKindOfClass:NSString.class] ? json[@"revision"] : nil;
        NSArray *rawLines = json[@"lines"];
        if (self.trackId <= 0 || !DateLyricsSerializedLinesHaveTiming(rawLines)) return nil;
        NSMutableArray *parsedLines = [NSMutableArray array];
        for (id rawLine in rawLines) {
            if (![rawLine isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *lineDict = (NSDictionary *)rawLine;
            DateLyricsTimedLine *line = [DateLyricsTimedLine new];
            line.begin = [lineDict[@"begin"] doubleValue];
            line.end = [lineDict[@"end"] doubleValue];
            line.text = [lineDict[@"text"] isKindOfClass:NSString.class] ? lineDict[@"text"] : @"";
            NSMutableArray *parsedWords = [NSMutableArray array];
            id wordsValue = lineDict[@"words"];
            NSArray *rawWords = [wordsValue isKindOfClass:NSArray.class] ? wordsValue : @[];
            for (id rawWord in rawWords) {
                if (![rawWord isKindOfClass:NSDictionary.class]) continue;
                NSDictionary *wordDict = (NSDictionary *)rawWord;
                DateLyricsTimedWord *word = [DateLyricsTimedWord new];
                word.begin = [wordDict[@"b"] doubleValue];
                word.end = [wordDict[@"e"] doubleValue];
                word.text = [wordDict[@"t"] isKindOfClass:NSString.class] ? wordDict[@"t"] : @"";
                word.separatorBefore = [wordDict[@"s"] isKindOfClass:NSString.class] ? wordDict[@"s"] : @"";
                word.background = DateLyricsJSONNumber(wordDict[@"bg"]).boolValue;
                [parsedWords addObject:word];
            }
            line.words = parsedWords;
            DateLyricsAssignCharacterRanges(line);
            [parsedLines addObject:line];
        }
        // older score files predate the explicit haswordtiming flag. infer it
        // from the serialized words so switching from a line-synced track can
        // never leave a cached syllable score rendered as permanently dim.
        if (!self.hasWordTiming) {
            for (DateLyricsTimedLine *line in parsedLines) {
                for (DateLyricsTimedWord *word in line.words) {
                    if (word.end > word.begin) {
                        self.hasWordTiming = YES;
                        break;
                    }
                }
                if (self.hasWordTiming) break;
            }
        }
        self.lines = parsedLines;
    }
    return self;
}
@end

@interface DateLyricsWordResolverState : NSObject
@property (nonatomic, weak) DateLyricsTimedLine *line;
@property (nonatomic, assign) NSInteger trackID;
@property (nonatomic, assign) BOOL showAdlibs;

@property (nonatomic, assign) NSTimeInterval lastElapsed;
@property (nonatomic, assign) NSUInteger nextStartIndex;

@property (nonatomic, strong) NSMutableArray<NSDictionary *> *completedRanges;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *progressSegments;
@property (nonatomic, assign) NSRange activeRange;
@property (nonatomic, assign) NSRange progressiveRange;
@property (nonatomic, assign) NSTimeInterval progressiveBegin;
@property (nonatomic, assign) NSTimeInterval progressiveEnd;
@property (nonatomic, assign) NSTimeInterval activeForegroundWordBegin;
@property (nonatomic, assign) NSUInteger foregroundProgressStart;
@property (nonatomic, assign) NSUInteger foregroundProgressEnd;
@end

@implementation DateLyricsWordResolverState
@end

static DateLyricsWordResolverState *gDateLyricsWordResolverState = nil;

static NSUInteger gDateLyricsSuitabilityScans = 0;
static NSUInteger gDateLyricsSuitabilityCacheHits = 0;

static BOOL DateLyricsIsLineSuitableForOptimizedResolver(DateLyricsTimedLine *line) {
    if (!line) return NO;
    if (line.amlResolverSuitability != 0) {
        gDateLyricsSuitabilityCacheHits++;
        return line.amlResolverSuitability == 1;
    }
    gDateLyricsSuitabilityScans++;
    if (!line.characterRangesValid) {
        line.amlResolverSuitability = 3;
        return NO;
    }
    NSTimeInterval lastBegin = -1.0;
    NSTimeInterval lastEnd = -1.0;
    for (DateLyricsTimedWord *word in line.words) {
        if (word.characterRange.location == NSNotFound || word.isBackground || word.begin < lastBegin || word.end < word.begin || word.begin < lastEnd - 0.05) {
            line.amlResolverSuitability = 2;
            return NO;
        }
        lastBegin = word.begin;
        lastEnd = MAX(lastEnd, word.end);
    }
    line.amlResolverSuitability = 1;
    return YES;
}

static DateLyricsTimedLine *DateLyricsGetFilteredLine(DateLyricsTimedLine *line);
static NSDictionary *DateLyricsMakePayload(NSString *text, NSRange activeRange);
static NSDictionary *DateLyricsMakePayloadWithBackgroundRange(NSString *text, NSRange activeRange, NSRange backgroundRange);
static void DateLyricsSetRangeFields(NSMutableDictionary *payload, NSString *prefix, NSRange range);
static void DateLyricsApplyCurrentLineToAllCoverSheets(void);
static void DateLyricsStopMarquee(_UIAnimatingLabel *label);
static UIView *DateLyricsDetachMarquee(_UIAnimatingLabel *label);
static BOOL DateLyricsStartMarquee(_UIAnimatingLabel *label, CGFloat overflow, NSDictionary *payload, BOOL *didRebuild);
static void DateLyricsRefreshMarqueeContent(_UIAnimatingLabel *label);

// mixed scores can contain word-timed lines and line-timed fallbacks together.
// timing must be decided per line, not from the whole-score haswordtiming flag.
static BOOL DateLyricsLineHasWordTiming(DateLyricsTimedLine *line) {
    if (!line || line.words.count == 0) return NO;

    for (DateLyricsTimedWord *word in line.words) {
        if (word.text.length > 0 &&
            isfinite(word.begin) &&
            isfinite(word.end) &&
            word.end > word.begin) {
            return YES;
        }
    }

    return NO;
}

static NSDictionary *DateLyricsResolveWordPayloadFullScan(DateLyricsTimedLine *line, NSTimeInterval elapsedTime, NSTimeInterval *nextWordStartOut, BOOL *isLineFinishedOut) {
    NSRange activeRange = NSMakeRange(NSNotFound, 0);
    NSRange backgroundActiveRange = NSMakeRange(NSNotFound, 0);
    NSRange previousForegroundWordRange = NSMakeRange(NSNotFound, 0);
    NSRange previousBackgroundWordRange = NSMakeRange(NSNotFound, 0);
    NSTimeInterval previousForegroundWordEnd = -1.0;
    NSTimeInterval previousBackgroundWordEnd = -1.0;
    NSUInteger previousForegroundSegmentStart = NSNotFound;
    NSUInteger previousBackgroundSegmentStart = NSNotFound;
    NSTimeInterval nextForegroundWordStart = -1.0;
    NSTimeInterval nextBackgroundWordStart = -1.0;
    BOOL previousWordWasBackground = NO;
    BOOL hasPreviousWord = NO;
    NSTimeInterval activeForegroundWordBegin = -1.0;
    NSTimeInterval activeBackgroundWordBegin = -1.0;
    NSUInteger foregroundProgressStart = NSNotFound;
    NSUInteger foregroundProgressEnd = 0;
    NSUInteger completedStart = NSNotFound;
    NSUInteger completedEnd = 0;
    NSRange progressiveRange = NSMakeRange(NSNotFound, 0);
    NSTimeInterval progressiveBegin = -1.0;
    NSTimeInterval progressiveEnd = -1.0;
    NSUInteger activeForegroundCount = 0;
    NSMutableArray<NSDictionary *> *progressSegments = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *completedRanges = [NSMutableArray array];
    NSUInteger backgroundProgressStart = NSNotFound;
    NSUInteger backgroundProgressEnd = 0;
    NSUInteger wordCursor = 0;
    BOOL isLineFinished = YES;
    NSTimeInterval minWordBegin = -1.0;

    for (DateLyricsTimedWord *word in line.words) {
        if (word.end > elapsedTime) isLineFinished = NO;
        if (minWordBegin < 0 || word.begin < minWordBegin) minWordBegin = word.begin;

        wordCursor += word.separatorBefore.length;
        NSRange wordRange = NSMakeRange(wordCursor, word.text.length);
        NSUInteger segmentStart = wordRange.location;
        if (hasPreviousWord && previousWordWasBackground == word.isBackground) {
            segmentStart = word.isBackground ? previousBackgroundSegmentStart : previousForegroundSegmentStart;
        }
        BOOL isActive = elapsedTime >= word.begin && elapsedTime < word.end;
        if (word.end <= elapsedTime && word.text.length > 0) {
            [completedRanges addObject:@{@"loc": @(wordRange.location),
                                         @"len": @(wordRange.length),
                                         @"lane": word.isBackground ? @"background" : @"foreground"}];
        } else if (isActive && word.text.length > 0) {
            [progressSegments addObject:@{@"loc": @(wordRange.location),
                                           @"len": @(wordRange.length),
                                           @"begin": @(word.begin),
                                           @"end": @(word.end),
                                           @"lane": word.isBackground ? @"background" : @"foreground"}];
        }
        if (word.isBackground) {
            if (elapsedTime >= word.begin && backgroundProgressStart == NSNotFound) backgroundProgressStart = wordRange.location;
            if (elapsedTime >= word.begin) backgroundProgressEnd = MAX(backgroundProgressEnd, NSMaxRange(wordRange));
            if (isActive && (backgroundActiveRange.location == NSNotFound || word.begin >= activeBackgroundWordBegin)) {
                backgroundActiveRange = wordRange;
                activeBackgroundWordBegin = word.begin;
            }
            if (word.begin > elapsedTime && (nextBackgroundWordStart < 0 || word.begin < nextBackgroundWordStart)) nextBackgroundWordStart = word.begin;
            if (word.end <= elapsedTime && word.end >= previousBackgroundWordEnd) {
                previousBackgroundWordRange = wordRange;
                previousBackgroundWordEnd = word.end;
                previousBackgroundSegmentStart = segmentStart;
            }
        } else {
            if (isActive) activeForegroundCount++;
            if (word.end <= elapsedTime) {
                if (completedStart == NSNotFound) completedStart = wordRange.location;
                completedEnd = MAX(completedEnd, NSMaxRange(wordRange));
            }
            if (isActive && progressiveRange.location == NSNotFound) {
                progressiveRange = wordRange;
                progressiveBegin = word.begin;
                progressiveEnd = word.end;
            }
            if (elapsedTime >= word.begin && foregroundProgressStart == NSNotFound) foregroundProgressStart = wordRange.location;
            if (elapsedTime >= word.begin) foregroundProgressEnd = MAX(foregroundProgressEnd, NSMaxRange(wordRange));
            if (isActive && (activeRange.location == NSNotFound || word.begin >= activeForegroundWordBegin)) {
                activeRange = wordRange;
                activeForegroundWordBegin = word.begin;
            }
            if (word.begin > elapsedTime && (nextForegroundWordStart < 0 || word.begin < nextForegroundWordStart)) nextForegroundWordStart = word.begin;
            if (word.end <= elapsedTime && word.end >= previousForegroundWordEnd) {
                previousForegroundWordRange = wordRange;
                previousForegroundWordEnd = word.end;
                previousForegroundSegmentStart = segmentStart;
            }
        }
        hasPreviousWord = YES;
        previousWordWasBackground = word.isBackground;
        wordCursor += word.text.length;
    }

    if (activeRange.location == NSNotFound && previousForegroundWordRange.location != NSNotFound &&
        elapsedTime >= previousForegroundWordEnd &&
        (nextForegroundWordStart < 0 || elapsedTime < nextForegroundWordStart) && elapsedTime <= line.end) {
        activeRange = previousForegroundWordRange;
    }
    if (backgroundActiveRange.location == NSNotFound && previousBackgroundWordRange.location != NSNotFound &&
        elapsedTime >= previousBackgroundWordEnd &&
        (nextBackgroundWordStart < 0 || elapsedTime < nextBackgroundWordStart) && elapsedTime <= line.end) {
        backgroundActiveRange = previousBackgroundWordRange;
    }

    NSRange focusForegroundRange = activeRange;
    NSRange focusBackgroundRange = backgroundActiveRange;

    if (foregroundProgressStart != NSNotFound && foregroundProgressEnd > foregroundProgressStart) {
        activeRange = NSMakeRange(foregroundProgressStart, foregroundProgressEnd - foregroundProgressStart);
    }
    if (backgroundProgressStart != NSNotFound && backgroundProgressEnd > backgroundProgressStart) {
        backgroundActiveRange = NSMakeRange(backgroundProgressStart, backgroundProgressEnd - backgroundProgressStart);
    }

    NSTimeInterval nextWordStart = -1.0;
    if (nextForegroundWordStart > elapsedTime) nextWordStart = nextForegroundWordStart;
    if (nextBackgroundWordStart > elapsedTime) {
        if (nextWordStart < 0 || nextBackgroundWordStart < nextWordStart) nextWordStart = nextBackgroundWordStart;
    }
    if (nextWordStartOut) *nextWordStartOut = nextWordStart;
    if (isLineFinishedOut) *isLineFinishedOut = isLineFinished;

    BOOL isLineStarted = (minWordBegin < 0) || (elapsedTime >= minWordBegin);

    NSDictionary *baseWordPayload = DateLyricsMakePayloadWithBackgroundRange(line.text, activeRange, backgroundActiveRange);
    NSMutableDictionary *mutableWordPayload = [(baseWordPayload ?: @{}) mutableCopy];
    if (mutableWordPayload.count > 0) {
        if (activeForegroundCount != 1) progressiveRange = NSMakeRange(NSNotFound, 0);
        mutableWordPayload[@"progressSegments"] = [progressSegments copy];
        mutableWordPayload[@"completedRanges"] = [completedRanges copy];
        mutableWordPayload[@"progressActive"] = @(progressSegments.count > 0);
        DateLyricsSetRangeFields(mutableWordPayload, @"focus", focusForegroundRange);
        DateLyricsSetRangeFields(mutableWordPayload, @"focusBg", focusBackgroundRange);
        if (completedStart != NSNotFound && completedEnd > completedStart) {
            mutableWordPayload[@"completedLoc"] = @(completedStart);
            mutableWordPayload[@"completedLen"] = @(completedEnd - completedStart);
        }
        if (progressiveRange.location != NSNotFound && progressiveRange.length > 0) {
            mutableWordPayload[@"progressLoc"] = @(progressiveRange.location);
            mutableWordPayload[@"progressLen"] = @(progressiveRange.length);
            mutableWordPayload[@"progressBegin"] = @(progressiveBegin);
            mutableWordPayload[@"progressEnd"] = @(progressiveEnd);
            mutableWordPayload[@"progressActive"] = @YES;
        }
        mutableWordPayload[@"timed"] = @YES;
        mutableWordPayload[@"wordTimed"] = @YES;
        mutableWordPayload[@"started"] = @(isLineStarted);
        mutableWordPayload[@"finished"] = @(isLineFinished);
        return [mutableWordPayload copy];
    }
    return nil;
}

static NSDictionary *DateLyricsResolveWordPayloadFastPath(DateLyricsWordResolverState *state, NSTimeInterval elapsedTime, NSTimeInterval *nextWordStartOut, BOOL *isLineFinishedOut) {
    DateLyricsTimedLine *line = state.line;
    if (elapsedTime < state.lastElapsed) {
        state.nextStartIndex = 0;
        [state.completedRanges removeAllObjects];
        [state.progressSegments removeAllObjects];
        state.activeRange = NSMakeRange(NSNotFound, 0);
        state.progressiveRange = NSMakeRange(NSNotFound, 0);
        state.progressiveBegin = -1.0;
        state.progressiveEnd = -1.0;
        state.activeForegroundWordBegin = -1.0;
        state.foregroundProgressStart = NSNotFound;
        state.foregroundProgressEnd = 0;
        // simple binary search for the first uncompleted word
        NSUInteger low = 0;
        NSUInteger high = line.words.count;
        while (low < high) {
            NSUInteger mid = low + (high - low) / 2;
            if (line.words[mid].end <= elapsedTime) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        state.nextStartIndex = low;

        // re-add completed ranges for anything before nextstartindex
        for (NSUInteger i = 0; i < state.nextStartIndex; i++) {
            DateLyricsTimedWord *word = line.words[i];
            if (word.text.length > 0) {
                [state.completedRanges addObject:@{@"loc": @(word.characterRange.location),
                                                   @"len": @(word.characterRange.length),
                                                   @"lane": @"foreground"}];
            }
        }
    }

    state.lastElapsed = elapsedTime;
    BOOL isLineFinished = YES;
    NSTimeInterval minWordBegin = -1.0;

    // we only care about words from nextstartindex onwards for progress
    [state.progressSegments removeAllObjects];
    NSUInteger newNextStart = state.nextStartIndex;

    for (NSUInteger i = state.nextStartIndex; i < line.words.count; i++) {
        DateLyricsTimedWord *word = line.words[i];
        if (word.end > elapsedTime) isLineFinished = NO;
        if (minWordBegin < 0 || word.begin < minWordBegin) minWordBegin = word.begin;

        BOOL isActive = elapsedTime >= word.begin && elapsedTime < word.end;
        if (word.end <= elapsedTime) {
            if (word.text.length > 0) {
                [state.completedRanges addObject:@{@"loc": @(word.characterRange.location),
                                                   @"len": @(word.characterRange.length),
                                                   @"lane": @"foreground"}];
            }
            newNextStart = i + 1;
        } else if (isActive && word.text.length > 0) {
            [state.progressSegments addObject:@{@"loc": @(word.characterRange.location),
                                                @"len": @(word.characterRange.length),
                                                @"begin": @(word.begin),
                                                @"end": @(word.end),
                                                @"lane": @"foreground"}];
        }

        if (isActive) {
            if (state.progressiveRange.location == NSNotFound) {
                state.progressiveRange = word.characterRange;
                state.progressiveBegin = word.begin;
                state.progressiveEnd = word.end;
            }
            if (state.activeRange.location == NSNotFound || word.begin >= state.activeForegroundWordBegin) {
                state.activeRange = word.characterRange;
                state.activeForegroundWordBegin = word.begin;
            }
        }
        if (elapsedTime >= word.begin && state.foregroundProgressStart == NSNotFound) {
            state.foregroundProgressStart = word.characterRange.location;
        }
        if (elapsedTime >= word.begin) {
            state.foregroundProgressEnd = MAX(state.foregroundProgressEnd, NSMaxRange(word.characterRange));
        }
    }

    state.nextStartIndex = newNextStart;

    NSTimeInterval nextWordStart = -1.0;
    for (NSUInteger i = state.nextStartIndex; i < line.words.count; i++) {
        if (line.words[i].begin > elapsedTime) {
            nextWordStart = line.words[i].begin;
            break;
        }
    }

    if (nextWordStartOut) *nextWordStartOut = nextWordStart;
    if (isLineFinishedOut) *isLineFinishedOut = isLineFinished;

    NSRange finalActiveRange = state.activeRange;
    if (state.foregroundProgressStart != NSNotFound && state.foregroundProgressEnd > state.foregroundProgressStart) {
        finalActiveRange = NSMakeRange(state.foregroundProgressStart, state.foregroundProgressEnd - state.foregroundProgressStart);
    }

    BOOL isLineStarted = (minWordBegin < 0) || (elapsedTime >= minWordBegin);

    NSDictionary *baseWordPayload = DateLyricsMakePayloadWithBackgroundRange(line.text, finalActiveRange, NSMakeRange(NSNotFound, 0));
    NSMutableDictionary *mutableWordPayload = [(baseWordPayload ?: @{}) mutableCopy];
    if (mutableWordPayload.count > 0) {
        if (state.progressSegments.count != 1) state.progressiveRange = NSMakeRange(NSNotFound, 0);
        mutableWordPayload[@"progressSegments"] = [state.progressSegments copy];
        mutableWordPayload[@"completedRanges"] = [state.completedRanges copy];
        mutableWordPayload[@"progressActive"] = @(state.progressSegments.count > 0);
        DateLyricsSetRangeFields(mutableWordPayload, @"focus", state.activeRange);
        DateLyricsSetRangeFields(mutableWordPayload, @"focusBg", NSMakeRange(NSNotFound, 0));

        if (state.completedRanges.count > 0) {
            NSUInteger start = [state.completedRanges.firstObject[@"loc"] unsignedIntegerValue];
            NSDictionary *last = state.completedRanges.lastObject;
            NSUInteger end = [last[@"loc"] unsignedIntegerValue] + [last[@"len"] unsignedIntegerValue];
            mutableWordPayload[@"completedLoc"] = @(start);
            mutableWordPayload[@"completedLen"] = @(end - start);
        }

        if (state.progressiveRange.location != NSNotFound && state.progressiveRange.length > 0) {
            mutableWordPayload[@"progressLoc"] = @(state.progressiveRange.location);
            mutableWordPayload[@"progressLen"] = @(state.progressiveRange.length);
            mutableWordPayload[@"progressBegin"] = @(state.progressiveBegin);
            mutableWordPayload[@"progressEnd"] = @(state.progressiveEnd);
            mutableWordPayload[@"progressActive"] = @YES;
        }
        mutableWordPayload[@"timed"] = @YES;
        mutableWordPayload[@"wordTimed"] = @YES;
        mutableWordPayload[@"started"] = @(isLineStarted);
        mutableWordPayload[@"finished"] = @(isLineFinished);
        return [mutableWordPayload copy];
    }
    return nil;
}

static NSDictionary *DateLyricsResolvePayload(DateLyricsScore *score, NSTimeInterval elapsedTime, NSInteger *cursorInOut, NSTimeInterval *nextTriggerOut, NSTimeInterval *nextLineTriggerOut, BOOL isPreview) {
    if (!score || score.lines.count == 0) {
        if (nextTriggerOut) *nextTriggerOut = -1.0;
        if (nextLineTriggerOut) *nextLineTriggerOut = -1.0;
        return nil;
    }

    id selectedLineID = nil;
    NSTimeInterval nextWordStart = -1.0;
    NSDictionary *wordPayload = nil;

    NSInteger cursorIndex = cursorInOut ? *cursorInOut : -1;
    NSInteger resolvedLineIndex = -1;
    NSArray<DateLyricsTimedLine *> *lines = score.lines;

    // the date owns the slot only before the first lyric. once a line has
    // started, keep the most recent line selected through any later
    // instrumental gap; allowing the resolver to expire it is what made the
    // stock date slip back into the lyric slot mid-song.

    if (cursorIndex >= 0 && cursorIndex < (NSInteger)lines.count) {
        for (NSInteger i = cursorIndex; i < (NSInteger)lines.count; i++) {
            DateLyricsTimedLine *line = DateLyricsGetFilteredLine(lines[i]);
            if (!line) continue;
            if (line.begin > elapsedTime) break;
            resolvedLineIndex = i;
        }
    }

    if (resolvedLineIndex < 0) {
        for (NSInteger i = (NSInteger)lines.count - 1; i >= 0; i--) {
            DateLyricsTimedLine *line = DateLyricsGetFilteredLine(lines[i]);
            if (!line) continue;
            if (elapsedTime >= line.begin) {
                resolvedLineIndex = i;
                break;
            }
        }
    }

    if (cursorInOut) *cursorInOut = resolvedLineIndex;

    if (resolvedLineIndex >= 0) {
        DateLyricsTimedLine *line = DateLyricsGetFilteredLine(lines[resolvedLineIndex]);
        if (line && elapsedTime >= line.begin) {

            selectedLineID = @(line.begin);

            if (!gDateLyricsAlwaysOnDisplay && DateLyricsLineHasWordTiming(line)) {
                BOOL isLineFinished = YES;

                if (!isPreview && DateLyricsIsLineSuitableForOptimizedResolver(line)) {
                    if (!gDateLyricsWordResolverState) gDateLyricsWordResolverState = [DateLyricsWordResolverState new];
                    if (gDateLyricsWordResolverState.line != line ||
                        gDateLyricsWordResolverState.trackID != score.trackId ||
                        gDateLyricsWordResolverState.showAdlibs != gDateLyricsShowAdlibs) {

                        gDateLyricsWordResolverState.line = line;
                        gDateLyricsWordResolverState.trackID = score.trackId;
                        gDateLyricsWordResolverState.showAdlibs = gDateLyricsShowAdlibs;
                        gDateLyricsWordResolverState.lastElapsed = -1.0;
                        gDateLyricsWordResolverState.nextStartIndex = 0;
                        gDateLyricsWordResolverState.completedRanges = [NSMutableArray array];
                        gDateLyricsWordResolverState.progressSegments = [NSMutableArray array];
                        gDateLyricsWordResolverState.activeRange = NSMakeRange(NSNotFound, 0);
                        gDateLyricsWordResolverState.progressiveRange = NSMakeRange(NSNotFound, 0);
                        gDateLyricsWordResolverState.progressiveBegin = -1.0;
                        gDateLyricsWordResolverState.progressiveEnd = -1.0;
                        gDateLyricsWordResolverState.activeForegroundWordBegin = -1.0;
                        gDateLyricsWordResolverState.foregroundProgressStart = NSNotFound;
                        gDateLyricsWordResolverState.foregroundProgressEnd = 0;
                    }

                    wordPayload = DateLyricsResolveWordPayloadFastPath(gDateLyricsWordResolverState, elapsedTime, &nextWordStart, &isLineFinished);
                } else {
                    wordPayload = DateLyricsResolveWordPayloadFullScan(line, elapsedTime, &nextWordStart, &isLineFinished);
                }

                if (wordPayload) {
                    NSMutableDictionary *mutableWordPayload = [wordPayload mutableCopy];
                    mutableWordPayload[@"lineId"] = selectedLineID;
                    mutableWordPayload[@"lineBegin"] = @(line.begin);
                    mutableWordPayload[@"lineEnd"] = @(line.end);
                    if (line.end > line.begin) mutableWordPayload[@"lineDuration"] = @(line.end - line.begin);
                    wordPayload = [mutableWordPayload copy];
                }
            } else {
                // no word timing. just basic line payload.
                wordPayload = DateLyricsMakePayload(line.text, NSMakeRange(NSNotFound, 0));
                if (wordPayload) {
                    NSMutableDictionary *m = [wordPayload mutableCopy];
                    m[@"timed"] = @YES;
                    m[@"lineId"] = selectedLineID;
                    m[@"lineBegin"] = @(line.begin);
                    m[@"lineEnd"] = @(line.end);
                    if (line.end > line.begin) m[@"lineDuration"] = @(line.end - line.begin);
                    wordPayload = [m copy];
                }
            }
        }
    }

    NSTimeInterval upcomingLineBegin = -1.0;
    NSInteger scanStartIndex = (resolvedLineIndex >= 0) ? (resolvedLineIndex + 1) : 0;
    for (NSInteger i = scanStartIndex; i < (NSInteger)lines.count; i++) {
        DateLyricsTimedLine *upcomingLine = DateLyricsGetFilteredLine(lines[i]);
        if (upcomingLine && upcomingLine.begin > elapsedTime) {
            upcomingLineBegin = upcomingLine.begin;
            break;
        }
    }

    if (upcomingLineBegin >= 0.0 && (nextWordStart < 0 || upcomingLineBegin < nextWordStart)) {
        nextWordStart = upcomingLineBegin;
    }

    NSTimeInterval nextTrigger = -1.0;
    if (nextWordStart > elapsedTime) nextTrigger = nextWordStart;

    // hold internal gaps, but do not leave the final lyric on screen forever
    // after playback stops or the mediaremote session disappears.
    if (resolvedLineIndex >= 0) {
        DateLyricsTimedLine *resolvedLine = DateLyricsGetFilteredLine(lines[resolvedLineIndex]);
        BOOL hasUpcoming = upcomingLineBegin >= 0.0;
        if (resolvedLine && !hasUpcoming) {
            NSTimeInterval effectiveEnd = resolvedLine.end;
            for (DateLyricsTimedWord *word in resolvedLine.words) effectiveEnd = MAX(effectiveEnd, word.end);
            static const NSTimeInterval kFinalLineGrace = 2.0;
            if (effectiveEnd > resolvedLine.begin) {
                NSTimeInterval expiry = effectiveEnd + kFinalLineGrace;
                if (elapsedTime < expiry) {
                    if (nextTrigger < 0.0 || expiry < nextTrigger) nextTrigger = expiry;
                } else {
                    wordPayload = nil;
                    nextTrigger = -1.0;
                }
            }
        }
    }

    if (nextTriggerOut) *nextTriggerOut = nextTrigger;
    if (nextLineTriggerOut) *nextLineTriggerOut = upcomingLineBegin;

    return wordPayload;
}


@interface DateLyricsWeakBox : NSObject
@property (nonatomic, weak) id object;
@end

@implementation DateLyricsWeakBox
@end

// cached word-wrap result for one lyric line, held on the label it was computed for.
// segments == nil means "measured, does not need splitting".
@interface DateLyricsSplitPlan : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) id lineId;
@property (nonatomic, assign) NSInteger trackId;
@property (nonatomic, assign) CGFloat width;
@property (nonatomic, copy) NSString *fontKey;
@property (nonatomic, strong) NSArray<NSValue *> *segments;
@property (nonatomic, assign) NSUInteger lastIndex;
@end

@implementation DateLyricsSplitPlan
@end

static dispatch_queue_t gLyricsQueue = nil;
static ICURLSession *gSession = nil;
static ICMusicKitRequestContext *gRequestContext = nil;
static NSMutableArray<LyricsTask *> *gLyricsTaskQueue = nil;
static NSMutableSet<NSNumber *> *gPendingLyricsIDs = nil;
// at most two apple requests: a new song can bypass one old download.
static NSMutableSet<LyricsTask *> *gActiveLyricsTasks = nil;
static NSInteger gDateLyricsSelectedStoreID = 0;
static NSInteger gDateLyricsSelectedAdamID = 0;
static NSUInteger gDateLyricsSelectionGeneration = 0;
static NSMutableDictionary<NSNumber *, NSArray<MSVLyricsLine *> *> *gLyricsCache = nil;
static NSMutableDictionary<NSNumber *, NSArray<DateLyricsTimedLine *> *> *gWordLyricsCache = nil;
static NSMutableArray<NSNumber *> *gLyricsCacheOrder = nil;
// transcript-only files are a valid apple response, but they are not useful to
// datelyrics.  remember rejected adam ids for this music process so every
// now-playing update does not refetch the same unsynchronised document.
static NSMutableSet<NSNumber *> *gUnsynchronizedLyricsIDs = nil;
// datelyrics owns score publication; corelyrics owns online requests and tokens.
static NSMutableDictionary<NSNumber *, NSString *> *gMusixmatchPendingTaskIDs = nil;
static NSMutableDictionary<NSNumber *, NSNumber *> *gMusixmatchFailureRetryAfter = nil;
static pthread_mutex_t gLyricsCacheMutex = PTHREAD_MUTEX_INITIALIZER;

// now-playing update dedupe: checked on glyricsqueue before any metadata work.
static NSInteger gLastHandledStoreID = 0;
static NSInteger gLastHandledAdamID = 0;
static BOOL gLastHandledLyricsAvailable = NO;
static NSUInteger gDateLyricsCacheGeneration = 0;
static NSUInteger gDateLyricsMusixmatchGeneration = 0;
static NSUInteger gDateLyricsStyleGeneration = 1;
static const void *kDateLyricsAppliedStyleGenerationKey = &kDateLyricsAppliedStyleGenerationKey;

static NSUInteger gDateLyricsScoreGeneration = 0;
static NSUInteger gDateLyricsLastResolvedScoreGeneration = 0;

static __weak MRNowPlayingPlayerClient *gActivePlayerClient = nil;

static BOOL DateLyricsIsUnsynchronizedLyricsID(NSInteger lyricsAdamID) {
    if (lyricsAdamID <= 0) return NO;
    NSNumber *key = @(lyricsAdamID);
    pthread_mutex_lock(&gLyricsCacheMutex);
    BOOL known = [gUnsynchronizedLyricsIDs containsObject:key];
    pthread_mutex_unlock(&gLyricsCacheMutex);
    return known;
}

static void DateLyricsSetUnsynchronizedLyricsID(NSInteger lyricsAdamID, BOOL unsynchronized) {
    if (lyricsAdamID <= 0) return;
    NSNumber *key = @(lyricsAdamID);
    pthread_mutex_lock(&gLyricsCacheMutex);
    if (unsynchronized) {
        [gUnsynchronizedLyricsIDs addObject:key];
    } else {
        [gUnsynchronizedLyricsIDs removeObject:key];
    }
    pthread_mutex_unlock(&gLyricsCacheMutex);
}

static BOOL gDateLyricsEnabled = YES;
static BOOL gDateLyricsScreenIsOn = YES;
// presentation is independent of backlight power: the date views can remain
// attached while springboard is showing an app underneath the coversheet.
static BOOL gDateLyricsCoverSheetVisible = YES;
static BOOL DateLyricsRenderingActive(void) {
    return gDateLyricsScreenIsOn && (gDateLyricsCoverSheetVisible || gDateLyricsAlwaysOnDisplay);
}
static void DateLyricsSetCoverSheetVisible(BOOL visible, NSString *reason);
static BOOL gDateLyricsDisplayWakeInProgress = NO;
static NSUInteger gDateLyricsDisplayModeRequestGeneration = 0;
static BOOL gDateLyricsForceLowercase = NO;
static BOOL gDateLyricsWordHighlighting = YES;
static BOOL gDateLyricsProgressiveFill = YES;
static NSInteger gDateLyricsActiveMarqueeCount = 0;
static NSUInteger gDateLyricsAnchorGeneration = 0;
static NSUInteger gDateLyricsLastResolvedAnchorGeneration = 0;
static BOOL gDateLyricsUseCustomFont = NO;
static NSString *gDateLyricsCustomFontName = @"AvenirNext-Regular";
static BOOL gDateLyricsTransitionsEnabled = YES;
static NSInteger gDateLyricsTransitionStyle = 1;
static NSTimeInterval gDateLyricsTransitionDuration = 0.33;
static BOOL gDateLyricsSplitLongLines = NO;
static BOOL gDateLyricsMarqueeEnabled = YES;
BOOL gDateLyricsShowAdlibs = YES;

static NSTimeInterval gDateLyricsPauseTimeout = 5.0;
static BOOL gDateLyricsMusixmatchEnabled = YES;
static BOOL gDateLyricsLRCLIBEnabled = YES;
static BOOL gDateLyricsMegalobizEnabled = YES;
static BOOL gDateLyricsQQMusicEnabled = YES;
static BOOL gDateLyricsNetEaseEnabled = YES;
static NSArray<NSString *> *gDateLyricsProviderOrder = nil;
static BOOL gDateLyricsRelaxedMatching = NO;
static NSInteger gDateLyricsRequestTimeout = DateLyricsDefaultRequestTimeout;
// owned by glyricsqueue, including completions and cancellation barriers.
static BOOL gDateLyricsExternalAppsEnabled = YES;
// owned by the provider queue; external lookups never require music injection.
static NSInteger gDateLyricsSelectedExternalTrack = 0;
static BOOL DateLyricsMusixmatchServiceEnabled(void) {
    return gDateLyricsMusixmatchEnabled &&
           (gDateLyricsProviderOrder == nil || [gDateLyricsProviderOrder containsObject:@"musixmatch"]);
}
static BOOL DateLyricsLRCLIBServiceEnabled(void) {
    return gDateLyricsMusixmatchEnabled &&
           gDateLyricsLRCLIBEnabled &&
           (gDateLyricsProviderOrder == nil || [gDateLyricsProviderOrder containsObject:@"lrclib"]);
}
static BOOL DateLyricsMegalobizServiceEnabled(void) {
    return gDateLyricsMusixmatchEnabled &&
           gDateLyricsMegalobizEnabled &&
           (gDateLyricsProviderOrder == nil || [gDateLyricsProviderOrder containsObject:@"megalobiz"]);
}
static BOOL DateLyricsNetEaseServiceEnabled(void) {
    return gDateLyricsMusixmatchEnabled &&
           gDateLyricsNetEaseEnabled &&
           (gDateLyricsProviderOrder == nil || [gDateLyricsProviderOrder containsObject:@"netease"]);
}
static BOOL DateLyricsQQMusicServiceEnabled(void) {
    return gDateLyricsMusixmatchEnabled &&
           gDateLyricsQQMusicEnabled &&
           (gDateLyricsProviderOrder == nil || [gDateLyricsProviderOrder containsObject:@"qqmusic"]);
}
static NSArray<NSString *> *DateLyricsActiveProviders(void) {
    NSArray<NSString *> *order = gDateLyricsProviderOrder ?: DateLyricsDefaultProviderOrder();
    NSMutableArray<NSString *> *active = [NSMutableArray array];
    for (NSString *key in order) {
        if ([key isEqualToString:@"musixmatch"] && DateLyricsMusixmatchServiceEnabled()) {
            [active addObject:key];
        } else if ([key isEqualToString:@"lrclib"] && DateLyricsLRCLIBServiceEnabled()) {
            [active addObject:key];
        } else if ([key isEqualToString:@"megalobiz"] && DateLyricsMegalobizServiceEnabled()) {
            [active addObject:key];
        } else if ([key isEqualToString:@"netease"] && DateLyricsNetEaseServiceEnabled()) {
            [active addObject:key];
        } else if ([key isEqualToString:@"qqmusic"] && DateLyricsQQMusicServiceEnabled()) {
            [active addObject:key];
        }
    }
    return active;
}
static BOOL DateLyricsMusixmatchAllowedForTrack(NSInteger trackID) {
    return gDateLyricsMusixmatchEnabled && (!DateLyricsIsExternalTrack(trackID) || gDateLyricsExternalAppsEnabled);
}

static BOOL DateLyricsProgressiveFillAvailable(void) {
    return !gDateLyricsAlwaysOnDisplay && gDateLyricsProgressiveFill && gDateLyricsWordHighlighting;
}

static BOOL DateLyricsMarqueeAvailable(void) {
    return !gDateLyricsAlwaysOnDisplay && gDateLyricsMarqueeEnabled;
}

static BOOL DateLyricsTransitionsAvailable(void) {
    return !gDateLyricsAlwaysOnDisplay && gDateLyricsTransitionsEnabled;
}

static NSHashTable<CSProminentSubtitleDateView *> *gDateLyricsDateViews = nil;
static NSHashTable<UIView *> *gDateLyricsWidgetSlots = nil;
static NSDictionary *gDateLyricsCurrentPayload = nil;
static id gDateLyricsAODTailLine = nil;
static NSInteger gDateLyricsAODTailTrack = 0;

// springboard playback clock
static DateLyricsScore *gDateLyricsCurrentScore = nil;
static NSUInteger gDateLyricsScoreLoadGeneration = 0;
static NSUInteger gDateLyricsScoreLoadAttemptGeneration = NSUIntegerMax;
static void DateLyricsInvalidateScoreLoad(void) {
    ++gDateLyricsScoreLoadGeneration;
    gDateLyricsScoreLoadAttemptGeneration = NSUIntegerMax;
}
static void DateLyricsRequestScoreLoad(void);
static NSDictionary *gDateLyricsLocalAnchor = nil; // { elapsed, rate, athosttime, trackid }
static NSDictionary *gDateLyricsStagedAnchor = nil;
static dispatch_source_t gDateLyricsTicker = nil;
static NSUInteger gDateLyricsTickerGeneration = 0;
static NSTimeInterval gDateLyricsTickerDeadline = 0.0;
static NSUInteger gDateLyricsTickerCreates = 0;
static NSUInteger gDateLyricsTickerRearms = 0;
static NSUInteger gDateLyricsTickerFires = 0;
static dispatch_source_t gDateLyricsPauseHideTimer = nil;
static NSTimeInterval gDateLyricsPauseHideDeadline = 0.0;
static NSInteger gDateLyricsResolverCursor = -1;
// bumped when a render-affecting payload, track, or preference changes. labels
// use it to avoid rebuilding the same attributed string on every uikit layout.
static NSUInteger gDateLyricsRenderGeneration = 1;
// mediaremote's authoritative clock can arrive a few milliseconds behind our
// extrapolated anchor. keep only the lyric-resolution clock monotonic within one
// track; the anchor itself remains untouched so playback and real seeks stay true.
static NSInteger gDateLyricsLastResolvedTrackId = 0;
static NSTimeInterval gDateLyricsLastResolvedElapsed = -1.0;

static BOOL gDateLyricsLastResolutionWasBackwardSeek = NO;
// start a forward line transition slightly before its score timestamp.  this
// is deliberately fixed rather than exposed as another preference: 50 ms is
// small enough to preserve the score's timing while hiding timer/notification
// latency on the lock screen.  syllable updates themselves remain on time.
static const NSTimeInterval kDateLyricsLineTransitionLead = 0.05;
static NSDictionary *gDateLyricsEarlyLinePayload = nil;
static NSTimeInterval gDateLyricsEarlyLineBegin = -1.0;
static NSTimeInterval gDateLyricsEarlyLineNextTrigger = -1.0;
static NSInteger gDateLyricsEarlyLineTrackId = 0;
static void DateLyricsClearEarlyLinePreview(void) {
    gDateLyricsEarlyLinePayload = nil;
    gDateLyricsEarlyLineBegin = -1.0;
    gDateLyricsEarlyLineNextTrigger = -1.0;
    gDateLyricsEarlyLineTrackId = 0;
}
static void DateLyricsScheduleTicker(void);
static void DateLyricsLogCacheStats(void);
static void DateLyricsCancelPauseHideTimer(void);
static void DateLyricsSchedulePauseHideTimer(void);
static void DateLyricsRequestNowPlayingInfo(void);
static void DateLyricsRequestAODRefresh(NSString *reason);
static void DateLyricsScheduleAODRefreshRetry(double nextBoundary, double elapsed, double rate);
static void DateLyricsClearFrozenMarquee(_UIAnimatingLabel *label);

static NSTimeInterval DateLyricsMonotonicTime(void) {
    return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) / 1e9;
}



static NSTimeInterval DateLyricsCurrentRenderElapsed(void) {
    NSDictionary *anchor = gDateLyricsLocalAnchor;
    if (!anchor) return -1.0;
    NSTimeInterval elapsed = [anchor[@"elapsed"] doubleValue];
    NSTimeInterval host = [anchor[@"atHostTime"] doubleValue];
    double rate = MAX(0.0, [anchor[@"rate"] doubleValue]);
    NSTimeInterval current = elapsed + MAX(0.0, DateLyricsMonotonicTime() - host) * rate;
    NSInteger trackID = [anchor[@"trackId"] integerValue];
    if (rate > 0.0 && !gDateLyricsLastResolutionWasBackwardSeek &&
        trackID == gDateLyricsLastResolvedTrackId && gDateLyricsLastResolvedElapsed >= 0.0 &&
        current < gDateLyricsLastResolvedElapsed &&
        gDateLyricsLastResolvedElapsed - current <= 0.15) {
        current = gDateLyricsLastResolvedElapsed;
    }
    return current;
}



static BOOL DateLyricsAODTailMatchesCurrentLine(void) {
    return gDateLyricsAODTailLine && [gDateLyricsAODTailLine isEqual:gDateLyricsCurrentPayload[@"lineId"]] &&
        gDateLyricsAODTailTrack == [gDateLyricsLocalAnchor[@"trackId"] integerValue];
}
static void DateLyricsUpdateAODTailMode(BOOL awake, BOOL alwaysOn) {
    if (!awake) { gDateLyricsAODTailLine = nil; gDateLyricsAODTailTrack = 0; }
    else if (alwaysOn && !gDateLyricsAlwaysOnDisplay) {
        gDateLyricsAODTailLine = gDateLyricsMarqueeEnabled && !gDateLyricsSplitLongLines ? gDateLyricsCurrentPayload[@"lineId"] : nil;
        gDateLyricsAODTailTrack = [gDateLyricsLocalAnchor[@"trackId"] integerValue];
    }
}

static void DateLyricsSuspendPauseHideTimer(void) {
    if (gDateLyricsPauseHideTimer) {
        dispatch_source_cancel(gDateLyricsPauseHideTimer);
        gDateLyricsPauseHideTimer = nil;
    }
}

static void DateLyricsCancelPauseHideTimer(void) {
    DateLyricsSuspendPauseHideTimer();
    gDateLyricsPauseHideDeadline = 0.0;
}

static void DateLyricsSchedulePauseHideTimer(void) {
    NSDictionary *payload = gDateLyricsCurrentPayload;
    if (![payload[@"text"] isKindOfClass:NSString.class] || [payload[@"text"] length] == 0) {
        // expiry removes the payload. retain its deadline so later display or
        // aod mode changes cannot start a fresh pause interval and reveal it.
        DateLyricsSuspendPauseHideTimer();
        return;
    }

    // repeated paused anchors are expected; do not reset the delay every time
    // mediaremote refreshes the same zero-rate position.
    if (gDateLyricsPauseHideTimer) return;

    NSTimeInterval now = DateLyricsMonotonicTime();
    if (gDateLyricsPauseHideDeadline <= 0.0)
        gDateLyricsPauseHideDeadline = now + MAX(0.0, gDateLyricsPauseTimeout);
    // remember expiry while asleep, but never wake the process to hide text on
    // a black display. the resolver checks this same deadline on wake.
    if (!DateLyricsRenderingActive()) return;
    NSTimeInterval delay = MAX(0.0, gDateLyricsPauseHideDeadline - now);
    if (delay <= 0.0) {
        gDateLyricsCurrentPayload = nil;
        gDateLyricsRenderGeneration++;
        DateLyricsApplyCurrentLineToAllCoverSheets();
        if (gDateLyricsAlwaysOnDisplay) DateLyricsRequestAODRefresh(@"pause timeout");
        return;
    }

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    gDateLyricsPauseHideTimer = timer;
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), DISPATCH_TIME_FOREVER, 0);
    dispatch_source_set_event_handler(timer, ^{
        if (gDateLyricsPauseHideTimer != timer) return;
        gDateLyricsPauseHideTimer = nil;
        dispatch_source_cancel(timer);

        if ([gDateLyricsLocalAnchor[@"rate"] floatValue] <= 0.0f &&
            [gDateLyricsCurrentPayload[@"text"] isKindOfClass:NSString.class]) {
            gDateLyricsCurrentPayload = nil;
            gDateLyricsRenderGeneration++;
            DateLyricsApplyCurrentLineToAllCoverSheets();
            if (gDateLyricsAlwaysOnDisplay) DateLyricsRequestAODRefresh(@"pause timeout");
        }
    });
    dispatch_resume(timer);
}

static void DateLyricsClearNowPlaying(void);

static void DateLyricsCancelTicker(void) {
    if (gDateLyricsTicker) {
        dispatch_source_cancel(gDateLyricsTicker);
        gDateLyricsTicker = nil;
    }
    gDateLyricsTickerDeadline = 0.0;
}

// publishes what is playing (track, position, rate) to a tiny file so the preferences pane can
// show the current lyric for the song you are listening to, in step with the lock screen.  only
// written when the anchor actually changes (play / pause / seek / track change), never per tick;
// the reader extrapolates the position from the wall-clock time it was written.
static NSUInteger gDateLyricsLastPublishedGeneration = NSUIntegerMax;
static BOOL gDateLyricsLastPublishedHadAnchor = NO;
static void DateLyricsPublishNowPlayingState(void) {
    NSDictionary *anchor = gDateLyricsLocalAnchor;
    BOOL hasAnchor = anchor != nil;
    if (hasAnchor == gDateLyricsLastPublishedHadAnchor &&
        gDateLyricsAnchorGeneration == gDateLyricsLastPublishedGeneration) return;
    gDateLyricsLastPublishedHadAnchor = hasAnchor;
    gDateLyricsLastPublishedGeneration = gDateLyricsAnchorGeneration;

    NSDictionary *state;
    NSTimeInterval wall = [[NSDate date] timeIntervalSince1970];
    if (hasAnchor) {
        double rate = MAX(0.0, [anchor[@"rate"] doubleValue]);
        double elapsedNow = [anchor[@"elapsed"] doubleValue] +
            MAX(0.0, DateLyricsMonotonicTime() - [anchor[@"atHostTime"] doubleValue]) * rate;
        state = @{@"trackId": anchor[@"trackId"] ?: @0, @"elapsed": @(elapsedNow), @"rate": @(rate), @"wall": @(wall)};
    } else {
        state = @{@"trackId": @0, @"elapsed": @0, @"rate": @0, @"wall": @(wall)};
    }
    static dispatch_queue_t queue = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.shalamand3r.datelyrics.nowplaying", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(queue, ^{
        NSString *dir = DateLyricsSharedDirectory;
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSData *data = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
        [data writeToFile:[dir stringByAppendingPathComponent:@"nowplaying.json"] atomically:YES];
    });
}

static void DateLyricsScheduleTicker(void) {
    // metadata updates still drive the settings preview while an app is open.
    // this bridge is generation-deduplicated and never needs a hidden-view timer.
    if (gDateLyricsScreenIsOn) DateLyricsPublishNowPlayingState();
    if (!DateLyricsRenderingActive()) {
        DateLyricsCancelTicker();
        DateLyricsSuspendPauseHideTimer();
        // preserve the pause deadline without an off-screen timer.
        if (!gDateLyricsEnabled || !gDateLyricsCurrentScore || !gDateLyricsLocalAnchor ||
            [gDateLyricsLocalAnchor[@"rate"] floatValue] > 0.0f) DateLyricsCancelPauseHideTimer();
        else DateLyricsSchedulePauseHideTimer();
        return;
    }
    DateLyricsRequestScoreLoad();

    if (!gDateLyricsEnabled || !gDateLyricsCurrentScore || !gDateLyricsLocalAnchor) {
        DateLyricsCancelTicker();
        DateLyricsCancelPauseHideTimer();
        return;
    }

    if (gDateLyricsDateViews.count == 0 && gDateLyricsWidgetSlots.count == 0) {
        DateLyricsCancelTicker();
        DateLyricsSuspendPauseHideTimer();
        return;
    }

    float rate = MAX(0.0f, [gDateLyricsLocalAnchor[@"rate"] floatValue]);
    BOOL anchorChanged = gDateLyricsAnchorGeneration != gDateLyricsLastResolvedAnchorGeneration;
    gDateLyricsLastResolvedAnchorGeneration = gDateLyricsAnchorGeneration;

    NSTimeInterval anchorElapsed = [gDateLyricsLocalAnchor[@"elapsed"] doubleValue];
    NSTimeInterval atHostTime = [gDateLyricsLocalAnchor[@"atHostTime"] doubleValue];
    NSTimeInterval nowHost = DateLyricsMonotonicTime();

    // a zero-rate anchor is a pause. resolve it once so the lock screen cannot
    // keep displaying a payload selected by the old, running anchor, then stop.
    NSTimeInterval rawCurrentElapsed = anchorElapsed + ((nowHost - atHostTime) * rate);
    NSTimeInterval currentElapsed = rawCurrentElapsed;
    if (!isfinite(currentElapsed) || !isfinite(rate)) {
        DateLyricsCancelTicker();
        DateLyricsCancelPauseHideTimer();
        return;
    }

    // ignore small backward anchor corrections at line boundaries to avoid
    // flashing the previous line. larger backward moves remain real seeks.
    NSInteger trackId = [gDateLyricsLocalAnchor[@"trackId"] integerValue];
    BOOL isExplicitSeek = [gDateLyricsLocalAnchor[@"seek"] boolValue];
    if (isExplicitSeek) {
        // one resolution only. the anchor now lives for minutes at a time, so a
        // sticky flag makes every later tick look like a seek: no early line
        // transitions, and jitter resetting split segments to the first one.
        NSMutableDictionary *consumed = [gDateLyricsLocalAnchor mutableCopy];
        consumed[@"seek"] = @NO;
        gDateLyricsLocalAnchor = [consumed copy];
    }
    BOOL movedBackwardBySeek = NO;
    BOOL trackChanged = trackId != gDateLyricsLastResolvedTrackId;
    BOOL scoreChanged = gDateLyricsScoreGeneration != gDateLyricsLastResolvedScoreGeneration;
    if (trackChanged || scoreChanged) {
        if (trackChanged) {
            gDateLyricsLastResolvedTrackId = trackId;
        }
        gDateLyricsLastResolvedScoreGeneration = gDateLyricsScoreGeneration;
        gDateLyricsLastResolvedElapsed = -1.0;
        gDateLyricsRenderGeneration++;
    }
    if (gDateLyricsLastResolvedElapsed >= 0.0) {
        NSTimeInterval backwards = gDateLyricsLastResolvedElapsed - currentElapsed;
        movedBackwardBySeek = isExplicitSeek && backwards > 0.001;

        if (!trackChanged && !scoreChanged && !isExplicitSeek && backwards > 0.0 && backwards <= 0.35) {
            currentElapsed = gDateLyricsLastResolvedElapsed;
        }
    }
    gDateLyricsLastResolvedElapsed = currentElapsed;
    gDateLyricsLastResolutionWasBackwardSeek = movedBackwardBySeek;

    // a seek, pause, track swap, or score replacement invalidates a pending
    // early line.  in particular, never carry an early forward payload across
    // a backward scrub: the normal resolver must be allowed to produce the
    // reverse transition immediately.
    if (trackChanged ||
        scoreChanged ||
        isExplicitSeek ||
        movedBackwardBySeek ||
        rate <= 0.0f) {
        DateLyricsClearEarlyLinePreview();

        if (rate <= 0.0f && !isExplicitSeek && !movedBackwardBySeek && !trackChanged && !scoreChanged) {
            NSDictionary *displayed = gDateLyricsCurrentPayload;
            NSTimeInterval lineBegin = [displayed[@"lineBegin"] doubleValue];
            if (displayed[@"lineId"] && lineBegin > rawCurrentElapsed &&
                (lineBegin - rawCurrentElapsed) <= 0.35) {
                NSMutableDictionary *held = [displayed mutableCopy];
                for (NSString *k in @[@"loc",@"len",@"bgLoc",@"bgLen",@"focusLoc",@"focusLen",
                                      @"focusBgLoc",@"focusBgLen",@"completedLoc",@"completedLen",
                                      @"progressLoc",@"progressLen",@"progressBegin",@"progressEnd",
                                      @"progressSegments",@"completedRanges"]) {
                    [held removeObjectForKey:k];
                }
                held[@"progressActive"] = @NO;
                held[@"started"] = @NO;
                held[@"finished"] = @NO;
                gDateLyricsEarlyLinePayload = [held copy];
                gDateLyricsEarlyLineBegin = lineBegin;
                gDateLyricsEarlyLineNextTrigger = lineBegin;
                gDateLyricsEarlyLineTrackId = trackId;
            }
        }
    }

    NSTimeInterval nextTrigger = -1.0;
    NSTimeInterval nextLineTrigger = -1.0;
    NSDictionary *payload = nil;
    BOOL usingEarlyLine = NO;

    // hold the previewed line until its real timestamp.  without this small
    // state machine, the next scheduled word tick would resolve against the
    // actual clock and briefly snap back to the previous line during the
    // 50 ms lead window.
    if (gDateLyricsEarlyLinePayload && gDateLyricsEarlyLineTrackId == trackId &&
        gDateLyricsEarlyLineBegin > currentElapsed && rate > 0.0f && !isExplicitSeek) {
        payload = gDateLyricsEarlyLinePayload;
        nextTrigger = gDateLyricsEarlyLineNextTrigger;
        usingEarlyLine = YES;
    } else {
        if (gDateLyricsEarlyLinePayload && currentElapsed >= gDateLyricsEarlyLineBegin) {
            DateLyricsClearEarlyLinePreview();
        }

        payload = DateLyricsResolvePayload(gDateLyricsCurrentScore, currentElapsed,
                                           &gDateLyricsResolverCursor, &nextTrigger, &nextLineTrigger, NO);

        // only advance a *line* early.  syllable/word highlights continue to
        // resolve against the real elapsed time, so the 50 ms lead cannot make
        // the karaoke highlight itself run ahead of the source score.
        NSTimeInterval leadWindow = rate * kDateLyricsLineTransitionLead;
        if (DateLyricsTransitionsAvailable() && rate > 0.0f && !isExplicitSeek && !movedBackwardBySeek &&
            nextLineTrigger > currentElapsed &&
            (nextLineTrigger - currentElapsed) <= leadWindow + 0.002) {
            NSInteger previewCursor = gDateLyricsResolverCursor;
            NSTimeInterval ignoredNextLineTrigger = -1.0;
            NSDictionary *previewPayload = DateLyricsResolvePayload(gDateLyricsCurrentScore,
                                                                      nextLineTrigger + 0.001,
                                                                      &previewCursor,
                                                                      NULL,
                                                                      &ignoredNextLineTrigger, YES);
            id currentLineID = payload[@"lineId"];
            id previewLineID = previewPayload[@"lineId"];
            if (previewPayload && previewLineID && ![previewLineID isEqual:currentLineID]) {
                NSMutableDictionary *earlyPayload = [previewPayload mutableCopy];
                // resolve the line identity at its real boundary, but keep
                // word highlighting on the real clock.  the preview therefore
                // enters as an upcoming/dim line and the first syllable is
                // applied by the normal tick at the exact timestamp.
                if ([earlyPayload[@"timed"] boolValue]) {
                    [earlyPayload removeObjectForKey:@"loc"];
                    [earlyPayload removeObjectForKey:@"len"];
                    [earlyPayload removeObjectForKey:@"bgLoc"];
                    [earlyPayload removeObjectForKey:@"bgLen"];
                    [earlyPayload removeObjectForKey:@"focusLoc"];
                    [earlyPayload removeObjectForKey:@"focusLen"];
                    [earlyPayload removeObjectForKey:@"focusBgLoc"];
                    [earlyPayload removeObjectForKey:@"focusBgLen"];
                    [earlyPayload removeObjectForKey:@"completedLoc"];
                    [earlyPayload removeObjectForKey:@"completedLen"];
                    [earlyPayload removeObjectForKey:@"progressLoc"];
                    [earlyPayload removeObjectForKey:@"progressLen"];
                    [earlyPayload removeObjectForKey:@"progressBegin"];
                    [earlyPayload removeObjectForKey:@"progressEnd"];
                    [earlyPayload removeObjectForKey:@"progressSegments"];
                    [earlyPayload removeObjectForKey:@"completedRanges"];
                    earlyPayload[@"progressActive"] = @NO;
                    earlyPayload[@"started"] = @NO;
                    earlyPayload[@"finished"] = @NO;
                }
                gDateLyricsEarlyLinePayload = [earlyPayload copy];
                gDateLyricsEarlyLineBegin = nextLineTrigger;
                // always wake at the true boundary. resolving the preview 1 ms
                // into the line can already consume a first syllable whose
                // begin time equals line.begin; scheduling its reported next
                // trigger would then skip straight to syllable two.
                gDateLyricsEarlyLineNextTrigger = nextLineTrigger;
                gDateLyricsEarlyLineTrackId = trackId;
                gDateLyricsResolverCursor = previewCursor;
                payload = gDateLyricsEarlyLinePayload;
                nextTrigger = gDateLyricsEarlyLineNextTrigger;
                usingEarlyLine = YES;
                DateLyricsDebugLog(@"[Ticker] starting line %.3f %.0fms early (actual=%.3f)",
                                   nextLineTrigger, kDateLyricsLineTransitionLead * 1000.0, currentElapsed);
            }
        }
    }

    DateLyricsDebugLog(@"[Ticker] elapsed=%.2f text='%@' range=[%@, %@] nextTrigger=%.3f nextLine=%.3f early=%d",
                       currentElapsed, payload[@"text"] ?: @"", payload[@"loc"], payload[@"len"],
                       nextTrigger, nextLineTrigger, usingEarlyLine);

    if (rate <= 0.0f && gDateLyricsPauseHideDeadline > 0.0 &&
        DateLyricsMonotonicTime() >= gDateLyricsPauseHideDeadline) payload = nil;
    BOOL payloadChanged = ![gDateLyricsCurrentPayload isEqual:payload];
    if (payloadChanged ||
        trackChanged ||
        scoreChanged ||
        movedBackwardBySeek ||
        (anchorChanged && (DateLyricsProgressiveFillAvailable() || gDateLyricsActiveMarqueeCount > 0))) {
        gDateLyricsCurrentPayload = [payload copy];
        if (!DateLyricsAODTailMatchesCurrentLine()) gDateLyricsAODTailLine = nil;
        gDateLyricsRenderGeneration++;
        DateLyricsApplyCurrentLineToAllCoverSheets();
        DateLyricsLogCacheStats();
        if (gDateLyricsAlwaysOnDisplay && payloadChanged &&
            [gDateLyricsBacklightEnvironment respondsToSelector:@selector(invalidateContentForReason:)]) {
            // ask the native aod scheduler for a new snapshot only when the
            // displayed line changes. never hold a continuous-render assertion.
            DateLyricsRequestAODRefresh(@"line changed");
            DateLyricsScheduleAODRefreshRetry(nextTrigger, currentElapsed, rate);
        }
    }

    if (rate <= 0.0f) {
        DateLyricsCancelTicker();
        DateLyricsSchedulePauseHideTimer();
        DateLyricsDebugLog(@"[Ticker] paused at %.2f", currentElapsed);
        return;
    }

    DateLyricsCancelPauseHideTimer();

    // a completed score has no future edge. anchors/score notifications restart us.
    if (nextTrigger < 0.0) {
        DateLyricsCancelTicker();
        return;
    }

    NSTimeInterval delay = 100.0;
    if (nextTrigger >= 0.0) {
        delay = MAX(0.0, (nextTrigger - currentElapsed) / rate);
        // when the next trigger is the actual beginning of a new line, fire
        // the ticker 50 ms early so the transition animation has a little time
        // to settle before the source timestamp.  do not advance word/syllable
        // triggers, and do not subtract the lead twice while a preview is held.
        if (DateLyricsTransitionsAvailable() && !usingEarlyLine && nextLineTrigger >= 0.0 &&
            fabs(nextTrigger - nextLineTrigger) < 0.001 &&
            delay > kDateLyricsLineTransitionLead) {
            delay -= kDateLyricsLineTransitionLead;
        }
    }
    if (!isfinite(delay)) { DateLyricsCancelTicker(); return; }
    // bound the nanosecond conversion even for a malformed far-future score.
    delay = MIN(86400.0, MAX(0.008, delay));
    if (!gDateLyricsTicker) {
        gDateLyricsTicker = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        NSUInteger generation = ++gDateLyricsTickerGeneration;
        gDateLyricsTickerCreates++;
        dispatch_source_set_event_handler(gDateLyricsTicker, ^{
            // ignore events queued by a source cancelled on pause/detach. an anchor can
            // also rearm this source before an old event runs; honour the new deadline.
            if (!gDateLyricsTicker || generation != gDateLyricsTickerGeneration) return;
            NSTimeInterval remaining = gDateLyricsTickerDeadline - DateLyricsMonotonicTime();
            if (remaining > 0.001) {
                dispatch_source_set_timer(gDateLyricsTicker,
                    dispatch_time(DISPATCH_TIME_NOW, (int64_t)(remaining * NSEC_PER_SEC)),
                    DISPATCH_TIME_FOREVER, 0);
                return;
            }
            gDateLyricsTickerFires++;
            DateLyricsScheduleTicker();
        });
        // arm before resuming the initially suspended source.
        gDateLyricsTickerDeadline = DateLyricsMonotonicTime() + delay;
        dispatch_source_set_timer(gDateLyricsTicker,
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), DISPATCH_TIME_FOREVER, 0);
        dispatch_resume(gDateLyricsTicker);
        return;
    }
    gDateLyricsTickerRearms++;
    gDateLyricsTickerDeadline = DateLyricsMonotonicTime() + delay;
    dispatch_source_set_timer(gDateLyricsTicker,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER, 0);
}

static void DateLyricsUpdateWidgetDateView(UIView *widgetSlot);
static _UIAnimatingLabel *DateLyricsFindAnimatingLabel(UIView *view);

typedef NS_ENUM(NSUInteger, DateLyricsCacheInvalidationReason) {
    DateLyricsCacheInvalidationReasonInitialAttach,
    DateLyricsCacheInvalidationReasonStockRestore,
    DateLyricsCacheInvalidationReasonTransitionCompletion,
    DateLyricsCacheInvalidationReasonExternalContentChanged,
};

static NSUInteger gDateLyricsCacheHits = 0;
static NSUInteger gDateLyricsCacheMisses = 0;
static NSUInteger gDateLyricsCacheForced = 0;

static NSUInteger gDateLyricsCacheLayoutApplies = 0;

static NSUInteger gDateLyricsCacheReasonInitialAttach = 0;
static NSUInteger gDateLyricsCacheReasonStockRestore = 0;
static NSUInteger gDateLyricsCacheReasonTransitionCompletion = 0;
static NSUInteger gDateLyricsCacheReasonExternal = 0;

// the render-cache accounting above is diagnostic only.  it exists to answer
// "who keeps throwing the cache away", so it has to be readable from the log;
// see datelyricslogcachestats, which the ticker drains on a 5 s throttle.
static NSUInteger gDateLyricsAODRefreshSequence = 0;
// always-on specifiers can use distantpast as a marker, not a clock frame date.
// keep both timestamps: the requested specifier and the environment's currently
// staged presentation can differ while ios renders cached future frames.
static NSString *DateLyricsAODDateDescription(id value) {
    if (![value isKindOfClass:NSDate.class]) return @"missing";
    NSDate *date = value;
    if ([date compare:NSDate.distantPast] != NSOrderedDescending) return @"distant-past-marker";
    if ([date compare:NSDate.distantFuture] != NSOrderedAscending) return @"distant-future-marker";
    double wall = date.timeIntervalSince1970;
    if (!isfinite(wall)) return @"invalid";
    return [NSString stringWithFormat:@"unix:%.3f,minute:%.0f", wall, floor(wall / 60.0)];
}

static void DateLyricsRequestAODRefresh(NSString *reason) {
    if (!DateLyricsRenderingActive() || !gDateLyricsAlwaysOnDisplay || ![gDateLyricsBacklightEnvironment respondsToSelector:@selector(invalidateContentForReason:)]) return;
    NSUInteger sequence = ++gDateLyricsAODRefreshSequence;
    DateLyricsDebugLog(@"[AOD:REQUEST] seq=%lu reason=%@ track=%@ line=%@ elapsed=%.3f wall=%@ presentation=%@", (unsigned long)sequence, reason,
        gDateLyricsLocalAnchor[@"trackId"] ?: @0, gDateLyricsCurrentPayload[@"lineId"] ?: @"-", DateLyricsCurrentRenderElapsed(),
        DateLyricsAODDateDescription(NSDate.date), DateLyricsAODDateDescription(
            [gDateLyricsBacklightEnvironment respondsToSelector:@selector(presentationDate)] ? gDateLyricsBacklightEnvironment.presentationDate : nil));
    [gDateLyricsBacklightEnvironment invalidateContentForReason:[@"DateLyrics " stringByAppendingString:reason]];
}

static void DateLyricsScheduleAODRefreshRetry(double nextBoundary, double elapsed, double rate) {
    if (!gDateLyricsAODRefreshRetry || !gDateLyricsAODEnabled || !gDateLyricsAlwaysOnDisplay ||
        !DateLyricsRenderingActive() || !gDateLyricsEnabled || !gDateLyricsCurrentPayload ||
        rate <= 0 || nextBoundary <= elapsed) return;
    double remaining = (nextBoundary - elapsed) / rate;
    // target 10% of the visible line interval, not 10% after attaching midway.
    NSNumber *beginValue = gDateLyricsCurrentPayload[@"lineBegin"];
    double begin = [beginValue isKindOfClass:NSNumber.class] ? beginValue.doubleValue : elapsed;
    if (!isfinite(begin) || begin > elapsed) begin = elapsed;
    double retryElapsed = begin + (nextBoundary - begin) * 0.10;
    double delay = (retryElapsed - elapsed) / rate;
    if (delay < 0.01) return;
    // drop delayed callbacks in the final tenth, before the next line arrives.
    NSTimeInterval deadline = DateLyricsMonotonicTime() + remaining * 0.9;
    NSUInteger anchorGeneration = gDateLyricsAnchorGeneration;
    NSUInteger renderGeneration = gDateLyricsRenderGeneration;
    NSUInteger modeGeneration = gDateLyricsDisplayModeRequestGeneration;
    NSNumber *track = gDateLyricsLocalAnchor[@"trackId"];
    id line = gDateLyricsCurrentPayload[@"lineId"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!gDateLyricsAODRefreshRetry || !gDateLyricsAODEnabled || !gDateLyricsAlwaysOnDisplay ||
            !DateLyricsRenderingActive() || !gDateLyricsEnabled ||
            DateLyricsMonotonicTime() >= deadline || DateLyricsCurrentRenderElapsed() >= nextBoundary ||
            [gDateLyricsLocalAnchor[@"rate"] doubleValue] <= 0 ||
            anchorGeneration != gDateLyricsAnchorGeneration || renderGeneration != gDateLyricsRenderGeneration ||
            modeGeneration != gDateLyricsDisplayModeRequestGeneration ||
            ![track isEqual:gDateLyricsLocalAnchor[@"trackId"]] || ![line isEqual:gDateLyricsCurrentPayload[@"lineId"]]) return;
        DateLyricsRequestAODRefresh(@"line retry");
    });
}

static void DateLyricsLogAODRender(id environment, NSString *event, id specifier) {
    if (!gDateLyricsDebugLogging) return;
    NSDate *date = nil;
    if ([specifier respondsToSelector:@selector(date)]) date = [specifier performSelector:@selector(date)];
    NSDate *presentation = nil;
    if ([environment respondsToSelector:@selector(presentationDate)])
        presentation = [environment performSelector:@selector(presentationDate)];
    DateLyricsDebugLog(@"[AOD:RENDER] event=%@ seq=%lu aod=%d wall=%@ requested=%@ presentation=%@ line=%@ elapsed=%.3f specifier=%@",
        event, (unsigned long)gDateLyricsAODRefreshSequence, gDateLyricsAlwaysOnDisplay,
        DateLyricsAODDateDescription(NSDate.date), DateLyricsAODDateDescription(date), DateLyricsAODDateDescription(presentation),
        gDateLyricsCurrentPayload[@"lineId"] ?: @"-", DateLyricsCurrentRenderElapsed(), specifier ? NSStringFromClass([specifier class]) : @"-");
}

static void DateLyricsLogCacheStats(void) {
    if (!gDateLyricsDebugLogging) return;
    static NSTimeInterval lastLogged = 0.0;
    NSTimeInterval now = DateLyricsMonotonicTime();
    if (lastLogged > 0.0 && (now - lastLogged) < 5.0) return;
    lastLogged = now;

    NSUInteger total = gDateLyricsCacheHits + gDateLyricsCacheMisses;
    DateLyricsDebugLog(@"[CACHE] stats hits=%lu misses=%lu hitRate=%.1f%% layoutApplies=%lu "
                        "forced=%lu (attach=%lu stockRestore=%lu transition=%lu external=%lu)",
        (unsigned long)gDateLyricsCacheHits,
        (unsigned long)gDateLyricsCacheMisses,
        total ? (gDateLyricsCacheHits * 100.0 / (double)total) : 0.0,
        (unsigned long)gDateLyricsCacheLayoutApplies,
        (unsigned long)gDateLyricsCacheForced,
        (unsigned long)gDateLyricsCacheReasonInitialAttach,
        (unsigned long)gDateLyricsCacheReasonStockRestore,
        (unsigned long)gDateLyricsCacheReasonTransitionCompletion,
        (unsigned long)gDateLyricsCacheReasonExternal);
    DateLyricsDebugLog(@"[PERF] ticker creates=%lu rearms=%lu fires=%lu suitability scans=%lu hits=%lu",
        (unsigned long)gDateLyricsTickerCreates, (unsigned long)gDateLyricsTickerRearms,
        (unsigned long)gDateLyricsTickerFires, (unsigned long)gDateLyricsSuitabilityScans,
        (unsigned long)gDateLyricsSuitabilityCacheHits);
}

static BOOL DateLyricsForceApplyDateLabel(_UIAnimatingLabel *label, DateLyricsCacheInvalidationReason reason);
static BOOL DateLyricsApplyDateLabel(_UIAnimatingLabel *label);
static void DateLyricsRestoreSystemDateLabel(_UIAnimatingLabel *label);
static void DateLyricsInvalidateLabelRenderCache(_UIAnimatingLabel *label, DateLyricsCacheInvalidationReason reason);
static BOOL DateLyricsHasRenderableLyricPayload(void);
static const void *kDateLyricsForcedWidgetDateVisibleKey = &kDateLyricsForcedWidgetDateVisibleKey;
static const void *kDateLyricsOriginalHiddenKey = &kDateLyricsOriginalHiddenKey;
static const void *kDateLyricsRestoringStockDateKey = &kDateLyricsRestoringStockDateKey;
static const void *kDateLyricsLabelShowingLyricKey = &kDateLyricsLabelShowingLyricKey;
static const void *kDateLyricsLastRenderedAttrTextKey = &kDateLyricsLastRenderedAttrTextKey;
static const void *kDateLyricsLastRenderedTextKey = &kDateLyricsLastRenderedTextKey;
static const void *kDateLyricsRenderCacheKey = &kDateLyricsRenderCacheKey;
static const void *kDateLyricsAnimatingTransitionKey = &kDateLyricsAnimatingTransitionKey;
static const void *kDateLyricsMarqueeActiveKey = &kDateLyricsMarqueeActiveKey;
static const void *kDateLyricsMarqueeLineIdKey = &kDateLyricsMarqueeLineIdKey;
static const void *kDateLyricsMarqueeSkippedLineIdKey = &kDateLyricsMarqueeSkippedLineIdKey;
static const void *kDateLyricsMarqueeContainerKey = &kDateLyricsMarqueeContainerKey;
static const void *kDateLyricsMarqueeContentLabelKey = &kDateLyricsMarqueeContentLabelKey;
static const void *kDateLyricsMarqueeTrackKey = &kDateLyricsMarqueeTrackKey;
static const void *kDateLyricsMarqueeFrozenKey = &kDateLyricsMarqueeFrozenKey;
static const void *kDateLyricsMarqueeOriginKey = &kDateLyricsMarqueeOriginKey;
static const void *kDateLyricsMarqueeDurationKey = &kDateLyricsMarqueeDurationKey;
static const void *kDateLyricsMarqueeHoldKey = &kDateLyricsMarqueeHoldKey;

static const void *kDateLyricsMarqueeAnchorGenerationKey = &kDateLyricsMarqueeAnchorGenerationKey;
static const void *kDateLyricsTransitionGenerationKey = &kDateLyricsTransitionGenerationKey;
static const void *kDateLyricsOriginalClipsToBoundsKey = &kDateLyricsOriginalClipsToBoundsKey;
static const void *kDateLyricsOriginalFontKey = &kDateLyricsOriginalFontKey;
static const void *kDateLyricsOriginalTextColorKey = &kDateLyricsOriginalTextColorKey;
static const void *kDateLyricsOriginalNumberOfLinesKey = &kDateLyricsOriginalNumberOfLinesKey;
static const void *kDateLyricsOriginalAdjustsFontSizeKey = &kDateLyricsOriginalAdjustsFontSizeKey;

static const void *kDateLyricsOriginalLineBreakModeKey = &kDateLyricsOriginalLineBreakModeKey;
static const void *kDateLyricsOriginalTextAlignmentKey = &kDateLyricsOriginalTextAlignmentKey;
static const void *kDateLyricsOriginalAttributedTextKey = &kDateLyricsOriginalAttributedTextKey;
static const void *kDateLyricsOriginalTextKey = &kDateLyricsOriginalTextKey;
// set once on the specific label we drive, so the _uianimatinglabel setter hooks
// can early-out with a single lookup instead of walking the superview chain on
// every text assignment in springboard.
static const void *kDateLyricsIsDateLabelKey = &kDateLyricsIsDateLabelKey;
// weak-boxed cache of the label a date view owns, so we stop re-running a
// recursive subview search on every layout pass.
static const void *kDateLyricsCachedLabelKey = &kDateLyricsCachedLabelKey;
// cached widget host view. widget containers can lay out many times per second;
// retain the positive recursive lookup while the host remains in the subtree.
static const void *kDateLyricsCachedWidgetHostKey = &kDateLyricsCachedWidgetHostKey;
// cached datelyricssplitplan for the line currently on the label.
static const void *kDateLyricsSplitPlanKey = &kDateLyricsSplitPlanKey;
// latched (grow-only) wrap width for the label. see datelyricssplitavailablewidth.
static const void *kDateLyricsSplitWidthKey = &kDateLyricsSplitWidthKey;
// frame the label is pinned to for the duration of a line transition.
static const void *kDateLyricsFrozenFrameKey = &kDateLyricsFrozenFrameKey;
static const void *kDateLyricsGlyphCacheKey = &kDateLyricsGlyphCacheKey;
static const void *kDateLyricsProgressSlotPoolKey = &kDateLyricsProgressSlotPoolKey;
static const void *kDateLyricsProgressFrozenKey = &kDateLyricsProgressFrozenKey;
static const void *kDateLyricsDisplayMorphKey = &kDateLyricsDisplayMorphKey;
static const void *kDateLyricsMarqueeWakeRejoinKey = &kDateLyricsMarqueeWakeRejoinKey;

static const void *kDateLyricsMarqueeFrozenSettledXKey = &kDateLyricsMarqueeFrozenSettledXKey;
static const void *kDateLyricsMarqueeFrozenSettledPhaseKey = &kDateLyricsMarqueeFrozenSettledPhaseKey;
// static copy of the outgoing line. keeping the real label live allows
// syllable colours to update while the line transition is still running.
static const void *kDateLyricsOutgoingSnapshotKey = &kDateLyricsOutgoingSnapshotKey;
// distinguishes our own lyric content writes from springboard's stock date
// updates. the latter must not replace an active lyric during wake/layout.
static const void *kDateLyricsApplyingLyricContentKey = &kDateLyricsApplyingLyricContentKey;

static CGFloat DateLyricsDebugLayerX(CALayer *layer) {
    if (!layer) return NAN;
    id value = [layer valueForKeyPath:@"transform.translation.x"];
    return [value respondsToSelector:@selector(doubleValue)]
        ? [value doubleValue] : NAN;
}



static void DateLyricsDebugMarqueeState(_UIAnimatingLabel *label,
                                         NSString *event,
                                         NSDictionary *payload) {
    if (!gDateLyricsDebugLogging || !label) return;

    payload = payload ?: gDateLyricsCurrentPayload;

    UIView *container = objc_getAssociatedObject(label, kDateLyricsMarqueeContainerKey);
    UIView *track = objc_getAssociatedObject(label, kDateLyricsMarqueeTrackKey);
    if (!track) return;
    CALayer *presentation = track.layer.presentationLayer;
    CAAnimation *animation = [track.layer animationForKey:@"DateLyricsMarquee"];

    DateLyricsDebugLog(
        @"[ANIM:M] event=%@ gen=%lu line=%@ rate=%.2f elapsed=%.3f "
         "lineBegin=%.3f lineEnd=%.3f frozen=%d active=%d count=%ld "
         "viewport=%.1f trackW=%.1f modelX=%.2f presentationX=%.2f "
         "animation=%@ duration=%.3f speed=%.2f offset=%.3f localNow=%.3f",
        event ?: @"?",
        (unsigned long)gDateLyricsAnchorGeneration,
        payload[@"lineId"] ?: objc_getAssociatedObject(label, kDateLyricsMarqueeLineIdKey) ?: @"-",
        [gDateLyricsLocalAnchor[@"rate"] doubleValue],
        DateLyricsCurrentRenderElapsed(),
        [payload[@"lineBegin"] doubleValue],
        [payload[@"lineEnd"] doubleValue],
        [objc_getAssociatedObject(label, kDateLyricsMarqueeFrozenKey) boolValue],
        [objc_getAssociatedObject(label, kDateLyricsMarqueeActiveKey) boolValue],
        (long)gDateLyricsActiveMarqueeCount,
        CGRectGetWidth(container.bounds),
        CGRectGetWidth(track.bounds),
        DateLyricsDebugLayerX(track.layer),
        DateLyricsDebugLayerX(presentation),
        animation ? NSStringFromClass(animation.class) : @"none",
        animation.duration,
        animation.speed,
        animation.timeOffset,
        track ? [track.layer convertTime:CACurrentMediaTime() fromLayer:nil] : NAN
    );
}

static const void *kDateLyricsMarqueeRunGenerationKey = &kDateLyricsMarqueeRunGenerationKey;

static void DateLyricsScheduleMarqueeProbe(_UIAnimatingLabel *label,
                                            UIView *track,
                                            NSDictionary *payload,
                                            NSTimeInterval delay,
                                            NSString *event,
                                            NSUInteger gen) {
    if (!gDateLyricsDebugLogging || delay < 0.0) return;

    __weak _UIAnimatingLabel *weakLabel = label;
    __weak UIView *weakTrack = track;
    NSDictionary *payloadCopy = [payload copy];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
        (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        _UIAnimatingLabel *strongLabel = weakLabel;
        UIView *strongTrack = weakTrack;
        if (!strongLabel || !strongTrack) return;

        BOOL stillCurrent =
            objc_getAssociatedObject(strongLabel, kDateLyricsMarqueeTrackKey) == strongTrack;
        NSUInteger currentGen = [objc_getAssociatedObject(strongLabel, kDateLyricsMarqueeRunGenerationKey) unsignedIntegerValue];
        BOOL sameGen = currentGen == gen;
        if (!sameGen) return;

        DateLyricsDebugMarqueeState(
            strongLabel,
            [NSString stringWithFormat:@"probe-%@%@ sameGen=%d",
             event, stillCurrent ? @"" : @" (orphaned)", sameGen],
            payloadCopy
        );
    });
}

static const NSUInteger kDateLyricsMaxMemoryCacheEntries = 40;
static const NSUInteger kDateLyricsMaxDiskCacheEntries = 100;

typedef NS_ENUM(NSInteger, DateLyricsTransitionStyle) {
    DateLyricsTransitionStyleFade = 0,
    DateLyricsTransitionStyleSlideUp = 1,
    DateLyricsTransitionStyleSlideDown = 2,
    DateLyricsTransitionStylePush = 3,
    DateLyricsTransitionStylePop = 4,
};

static BOOL DateLyricsIsSpringBoardHost(void) {
    static BOOL isSpringBoard = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *bundleIdentifier = [NSBundle mainBundle].bundleIdentifier;
        NSString *processName = [NSProcessInfo processInfo].processName;
        isSpringBoard = [bundleIdentifier isEqualToString:@"com.apple.springboard"] ||
                        [processName isEqualToString:@"SpringBoard"];
    });
    return isSpringBoard;
}

static BOOL DateLyricsIsMusicHost(void) {
    static BOOL isMusic = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *bundleIdentifier = [NSBundle mainBundle].bundleIdentifier;
        NSString *processName = [NSProcessInfo processInfo].processName;
        isMusic = [bundleIdentifier isEqualToString:@"com.apple.Music"] ||
                  [processName isEqualToString:@"Music"];
    });
    return isMusic;
}

static NSString *gDateLyricsStorefrontCountryCode = nil;
static id gDateLyricsStorefrontController = nil;  // must outlive the async call

static void DateLyricsRefreshStorefront(void) {
    Class cls = NSClassFromString(@"SKCloudServiceController");
    if (!cls) return;
    if (!gDateLyricsStorefrontController) gDateLyricsStorefrontController = [[cls alloc] init];
    [gDateLyricsStorefrontController requestStorefrontCountryCodeWithCompletionHandler:^(NSString *code, NSError *error) {
        NSString *normalized = (code.length == 2) ? code.lowercaseString : nil;
        if (!normalized || !gLyricsQueue) return;
        dispatch_async(gLyricsQueue, ^{
            if ([normalized isEqualToString:gDateLyricsStorefrontCountryCode]) return;
            DateLyricsDebugLog(@"[Storefront] resolved %@ (was %@)", normalized, gDateLyricsStorefrontCountryCode ?: @"device region");
            gDateLyricsStorefrontCountryCode = normalized;
            gLastHandledStoreID = 0;  // force a refetch on the right storefront
        });
    }];
}

static NSString *DateLyricsStorefront(void) {
    if (gDateLyricsStorefrontCountryCode.length == 2) return gDateLyricsStorefrontCountryCode;
    NSString *countryCode = [NSLocale currentLocale].countryCode;
    return (countryCode.length == 2) ? countryCode.lowercaseString : @"us";
}

static NSString *DateLyricsPreferredLocale(void) {
    NSString *locale = [NSLocale preferredLanguages].firstObject;
    if (![locale isKindOfClass:NSString.class] || locale.length == 0) return @"en-US";
    return [locale stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: @"en-US";
}

static NSTimeInterval DateLyricsParseTimeString(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0) return 0;
    NSArray<NSString *> *parts = [value componentsSeparatedByString:@":"];
    if (parts.count == 1) return value.doubleValue;
    if (parts.count == 2) return (parts[0].doubleValue * 60.0) + parts[1].doubleValue;
    if (parts.count == 3) return (parts[0].doubleValue * 3600.0) + (parts[1].doubleValue * 60.0) + parts[2].doubleValue;
    return 0;
}


static NSDictionary *DateLyricsMakePayload(NSString *text, NSRange activeRange) {
    if (![text isKindOfClass:NSString.class] || text.length == 0) return nil;
    NSMutableDictionary *payload = [@{ @"text": text } mutableCopy];
    if (activeRange.location != NSNotFound && NSMaxRange(activeRange) <= text.length) {
        payload[@"loc"] = @(activeRange.location);
        payload[@"len"] = @(activeRange.length);
    }

    return payload;
}

static NSDictionary *DateLyricsMakePayloadWithBackgroundRange(NSString *text, NSRange activeRange, NSRange backgroundRange) {
    NSDictionary *basePayload = DateLyricsMakePayload(text, activeRange);
    NSMutableDictionary *payload = nil;
    if (basePayload) {
        payload = [basePayload mutableCopy];
    }
    if (payload.count == 0) return nil;
    if (backgroundRange.location != NSNotFound && NSMaxRange(backgroundRange) <= text.length) {
        payload[@"bgLoc"] = @(backgroundRange.location);
        payload[@"bgLen"] = @(backgroundRange.length);
    }

    return payload;
}

static void DateLyricsSetRangeFields(NSMutableDictionary *payload, NSString *prefix, NSRange range) {
    if (![payload isKindOfClass:NSMutableDictionary.class] || prefix.length == 0) return;

    NSString *locKey = [prefix stringByAppendingString:@"Loc"];
    NSString *lenKey = [prefix stringByAppendingString:@"Len"];
    if (range.location != NSNotFound && range.length > 0) {
        payload[locKey] = @(range.location);
        payload[lenKey] = @(range.length);
    } else {
        [payload removeObjectForKey:locKey];
        [payload removeObjectForKey:lenKey];
    }
}

static NSRange DateLyricsRangeFromPayload(NSDictionary *payload, NSString *prefix, NSUInteger textLength) {
    if (![payload isKindOfClass:NSDictionary.class] || ![prefix isKindOfClass:NSString.class]) return NSMakeRange(NSNotFound, 0);
    NSString *locKey = nil;
    NSString *lenKey = nil;
    if ([prefix isEqualToString:@""]) {
        locKey = @"loc";
        lenKey = @"len";
    } else {
        locKey = [prefix stringByAppendingString:@"Loc"];
        lenKey = [prefix stringByAppendingString:@"Len"];
    }

    NSNumber *locNum = payload[locKey];
    NSNumber *lenNum = payload[lenKey];
    if (![locNum isKindOfClass:NSNumber.class] || ![lenNum isKindOfClass:NSNumber.class]) {
        return NSMakeRange(NSNotFound, 0);
    }

    NSUInteger loc = locNum.unsignedIntegerValue;
    NSUInteger len = lenNum.unsignedIntegerValue;
    NSRange range = NSMakeRange(loc, len);
    if (loc == NSNotFound || len == 0 || NSMaxRange(range) > textLength) {
        return NSMakeRange(NSNotFound, 0);
    }
    return range;
}



static void DateLyricsApplyCurrentLineToAllCoverSheets(void) {
    if (!DateLyricsRenderingActive()) return;
    if (gDateLyricsDateViews) {
        for (CSProminentSubtitleDateView *dateView in gDateLyricsDateViews) {
            if (![dateView isKindOfClass:UIView.class]) continue;
            DateLyricsApplyDateLabel(DateLyricsFindAnimatingLabel(dateView));
            [dateView setNeedsLayout];
        }
    }
    if (gDateLyricsWidgetSlots) {
        for (UIView *widgetSlot in gDateLyricsWidgetSlots) {
            if (![widgetSlot isKindOfClass:UIView.class]) continue;
            DateLyricsUpdateWidgetDateView(widgetSlot);
        }
    }
}




static NSDictionary *DateLyricsCurrentRenderablePayload(void) {
    return gDateLyricsCurrentPayload;
}

static UIColor *DateLyricsBaseTextColorForLabel(_UIAnimatingLabel *label) {
    // _uianimatinglabel can adopt the first foreground colour from an
    // attributed string as its textcolor. a fully-dim incoming lyric would
    // therefore poison the base colour for every later syllable on that line.
    // always derive filled/dimmed colours from the stock colour captured before
    // datelyrics first took ownership of the label.
    UIColor *textColor = objc_getAssociatedObject(label, kDateLyricsOriginalTextColorKey);
    if (![textColor isKindOfClass:UIColor.class]) textColor = label.textColor;
    if (![textColor isKindOfClass:UIColor.class]) textColor = UIColor.whiteColor;
    if ([textColor respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
        textColor = [textColor resolvedColorWithTraitCollection:label.traitCollection];
    }
    return textColor;
}


static void DateLyricsApplyLabelContent(_UIAnimatingLabel *label, NSString *displayText, NSAttributedString *attrDisplayText, BOOL layoutNeeded) {
    if (![label isKindOfClass:UILabel.class]) return;

    NSAttributedString *content = attrDisplayText;
    if (!content) {
        UIColor *textColor = DateLyricsBaseTextColorForLabel(label);
        NSMutableAttributedString *cleanStr = [[NSMutableAttributedString alloc] initWithString:displayText ?: @""];
        [cleanStr addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, cleanStr.length)];
        [cleanStr addAttribute:NSForegroundColorAttributeName value:textColor range:NSMakeRange(0, cleanStr.length)];
        content = cleanStr;
    }
    // equal letters can still carry the old karaoke colours. aod needs the
    // clean, fully filled attributes even when its current line stays the same.
    if ([label.attributedText isEqualToAttributedString:content]) return;

    BOOL wasApplying = [objc_getAssociatedObject(label, kDateLyricsApplyingLyricContentKey) boolValue];
    objc_setAssociatedObject(label, kDateLyricsApplyingLyricContentKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    label.attributedText = content;

    objc_setAssociatedObject(label, kDateLyricsApplyingLyricContentKey, @(wasApplying), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [label setNeedsDisplay];
    if (layoutNeeded) {
        [label setNeedsLayout];
    }
}

static UIFont *DateLyricsConfiguredFontForLabel(_UIAnimatingLabel *label) {
    UIFont *originalFont = objc_getAssociatedObject(label, kDateLyricsOriginalFontKey);
    UIFont *baseFont = originalFont ?: label.font ?: [UIFont systemFontOfSize:34.0 weight:UIFontWeightSemibold];
    if (!gDateLyricsUseCustomFont || gDateLyricsCustomFontName.length == 0) {
        return baseFont;
    }

    UIFont *customFont = [UIFont fontWithName:gDateLyricsCustomFontName size:baseFont.pointSize];
    return customFont ?: baseFont;
}

static CGFloat DateLyricsMeasuredLineWidth(NSString *text, UIFont *font) {
    if (![text isKindOfClass:NSString.class] || text.length == 0 || ![font isKindOfClass:UIFont.class]) return 0.0;
    NSString *measureText = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (measureText.length == 0) return 0.0;

    CGRect rect = [measureText boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)
                                            options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                         attributes:@{ NSFontAttributeName: font }
                                            context:nil];
    return ceil(CGRectGetWidth(rect));
}

// only complete, balanced groups are annotations. a regex cannot handle nested
// groups, and an unmatched opener must not hide the rest of a lyric or title.
static NSArray<NSValue *> *DateLyricsBracketedRanges(NSString *text, BOOL includeBraces) {
    NSMutableArray<NSNumber *> *stack = [NSMutableArray array];
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        if (character == '(' || character == '[' || (includeBraces && character == '{')) {
            [stack addObject:@(index)];
            continue;
        }
        unichar opener = character == ')' ? '(' : character == ']' ? '[' : (includeBraces && character == '}') ? '{' : 0;
        if (opener == 0 || stack.count == 0) continue;
        NSUInteger start = stack.lastObject.unsignedIntegerValue;
        if ([text characterAtIndex:start] != opener) {
            [stack removeAllObjects];
            continue;
        }
        [stack removeLastObject];
        if (stack.count == 0) [ranges addObject:[NSValue valueWithRange:NSMakeRange(start, index - start + 1)]];
    }
    return ranges;
}

static NSString *DateLyricsCollapseWhitespace(NSString *text) {
    static NSRegularExpression *spaces;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        spaces = [NSRegularExpression regularExpressionWithPattern:@"\\s+" options:0 error:nil];
    });
    NSString *collapsed = [spaces stringByReplacingMatchesInString:text options:0
        range:NSMakeRange(0, text.length) withTemplate:@" "];
    return [collapsed stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *DateLyricsTextExcludingIndexes(NSString *text, NSRange range, NSIndexSet *excluded) {
    NSMutableString *result = [NSMutableString string];
    __block NSUInteger cursor = range.location;
    [excluded enumerateRangesInRange:range options:0 usingBlock:^(NSRange removed, __unused BOOL *stop) {
        [result appendString:[text substringWithRange:NSMakeRange(cursor, removed.location - cursor)]];
        cursor = NSMaxRange(removed);
    }];
    [result appendString:[text substringWithRange:NSMakeRange(cursor, NSMaxRange(range) - cursor)]];
    return result;
}

static DateLyricsTimedLine *DateLyricsComputeFilteredLine(DateLyricsTimedLine *origLine) {
    if (!origLine) return nil;
    if (gDateLyricsShowAdlibs) return origLine;

    NSMutableString *source = [NSMutableString string];
    BOOL hasBackground = NO;
    for (DateLyricsTimedWord *word in origLine.words) {
        [source appendString:word.separatorBefore ?: @""];
        [source appendString:word.text ?: @""];
        hasBackground |= word.isBackground;
    }
    if (origLine.words.count == 0) [source appendString:origLine.text ?: @""];
    NSMutableIndexSet *excluded = [NSMutableIndexSet indexSet];
    for (NSValue *value in DateLyricsBracketedRanges(source, NO)) {
        [excluded addIndexesInRange:value.rangeValue];
    }
    if (excluded.count == 0 && !hasBackground) return origLine;

    DateLyricsTimedLine *filteredLine = [DateLyricsTimedLine new];
    filteredLine.begin = origLine.begin;
    filteredLine.end = origLine.end;
    if (origLine.words.count == 0) {
        filteredLine.text = DateLyricsCollapseWhitespace(DateLyricsTextExcludingIndexes(source, NSMakeRange(0, source.length), excluded));
        filteredLine.words = @[];
        return filteredLine.text.length > 0 ? filteredLine : nil;
    }
    NSMutableArray<DateLyricsTimedWord *> *filteredWords = [NSMutableArray array];
    NSMutableString *newText = [NSMutableString string];
    NSMutableString *pendingSeparator = [NSMutableString string];
    NSUInteger cursor = 0;
    for (DateLyricsTimedWord *word in origLine.words) {
        NSRange separatorRange = NSMakeRange(cursor, word.separatorBefore.length);
        cursor = NSMaxRange(separatorRange);
        NSRange wordRange = NSMakeRange(cursor, word.text.length);
        cursor = NSMaxRange(wordRange);
        [pendingSeparator appendString:DateLyricsTextExcludingIndexes(source, separatorRange, excluded)];
        if (word.isBackground) continue;
        NSString *wordText = DateLyricsTextExcludingIndexes(source, wordRange, excluded);
        if (wordText.length == 0) continue;
        DateLyricsTimedWord *newWord = [DateLyricsTimedWord new];
        newWord.begin = word.begin;
        newWord.end = word.end;
        newWord.text = wordText;
        if (filteredWords.count == 0) {
            NSUInteger start = 0;
            while (start < pendingSeparator.length && [NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:[pendingSeparator characterAtIndex:start]]) start++;
            newWord.separatorBefore = [pendingSeparator substringFromIndex:start];
        } else {
            BOOL onlyWhitespace = [pendingSeparator stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0;
            newWord.separatorBefore = onlyWhitespace && pendingSeparator.length > 0 ? @" " : [pendingSeparator copy];
        }
        [pendingSeparator setString:@""];
        [filteredWords addObject:newWord];
        [newText appendString:newWord.separatorBefore];
        [newText appendString:newWord.text];
    }
    NSString *tail = [pendingSeparator stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (tail.length > 0 && filteredWords.count > 0) {
        filteredWords.lastObject.text = [filteredWords.lastObject.text stringByAppendingString:tail];
        [newText appendString:tail];
    }
    if ([newText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0 || filteredWords.count == 0) return nil;
    filteredLine.words = filteredWords;
    filteredLine.text = newText;
    filteredLine.begin = filteredWords.firstObject.begin;
    filteredLine.end = filteredWords.lastObject.end;
    DateLyricsAssignCharacterRanges(filteredLine);
    return filteredLine;
}

// scores are immutable after loading. cache the filtered result because line
// selection visits it on every tick; changing showadlibs invalidates the cache.
// store an identity flag instead of retaining the original line through itself.
static DateLyricsTimedLine *DateLyricsGetFilteredLine(DateLyricsTimedLine *origLine) {
    if (!origLine) return nil;
    if (origLine.amlCachedFilteredValid && origLine.amlCachedFilteredAdlibs == gDateLyricsShowAdlibs) {
        return origLine.amlCachedFilteredReturnsOriginal ? origLine : origLine.amlCachedFiltered;
    }

    DateLyricsTimedLine *filtered = DateLyricsComputeFilteredLine(origLine);
    BOOL returnsOriginal = filtered == origLine;
    if (!returnsOriginal) {
        DateLyricsDebugLog(@"[Adlibs] filtered sourceWords=%lu keptWords=%lu sourceCharacters=%lu keptCharacters=%lu hidden=%d",
            (unsigned long)origLine.words.count, (unsigned long)filtered.words.count,
            (unsigned long)origLine.text.length, (unsigned long)filtered.text.length, filtered == nil);
    }
    origLine.amlCachedFiltered = returnsOriginal ? nil : filtered;
    origLine.amlCachedFilteredReturnsOriginal = returnsOriginal;
    origLine.amlCachedFilteredAdlibs = gDateLyricsShowAdlibs;
    origLine.amlCachedFilteredValid = YES;
    return filtered;
}

static NSString *DateLyricsStripParentheses(NSString *text) {
    if (!text) return nil;
    if (gDateLyricsShowAdlibs) return text;
    NSMutableString *stripped = [text mutableCopy];
    for (NSValue *value in [DateLyricsBracketedRanges(text, NO) reverseObjectEnumerator]) {
        [stripped deleteCharactersInRange:value.rangeValue];
    }
    [stripped setString:DateLyricsCollapseWhitespace(stripped)];
    return stripped.length > 0 ? stripped : nil;
}

// latch a stable wrapping width: labels and date views shrink with their text.
// only allow growth (such as rotation or a wider host) so short segments cannot
// trigger repeated rewraps. a conservative width may split a line earlier.
static CGFloat DateLyricsSplitAvailableWidth(UILabel *label) {
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;

    // only the date view is latched. a bogus reading from some other ancestor could
    // poison the latch permanently, and since the latch never shrinks, too wide
    // would mean lines silently stop splitting at all.
    CGFloat measured = 0.0;
    Class dateClass = NSClassFromString(@"CSProminentSubtitleDateView");
    if (dateClass) {
        UIView *view = label.superview;
        while ([view isKindOfClass:UIView.class]) {
            if ([view isKindOfClass:dateClass]) {
                measured = CGRectGetWidth(view.bounds);
                break;
            }
            view = view.superview;
        }
    }

    if (measured > 1.0) {
        if (measured > screenWidth) measured = screenWidth;
        NSNumber *latched = objc_getAssociatedObject(label, kDateLyricsSplitWidthKey);
        CGFloat width = latched ? (CGFloat)latched.doubleValue : 0.0;
        if (measured > width + 0.5) {
            width = measured;
            objc_setAssociatedObject(label, kDateLyricsSplitWidthKey, @(width), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (width > 1.0) return width;
    }

    // date view not found yet (label not installed, or class renamed on a newer os).
    // fall back without latching so a transient bad value is not made permanent.
    NSNumber *latched = objc_getAssociatedObject(label, kDateLyricsSplitWidthKey);
    if (latched.doubleValue > 1.0) return (CGFloat)latched.doubleValue;
    return screenWidth - 60.0;
}

// greedy word wrap. returns nil when the text fits on one line or cannot be split
// (a single word wider than the available width).
static NSArray<NSValue *> *DateLyricsComputeSegments(NSString *text, UIFont *font, CGFloat maxWidth) {
    if (DateLyricsMeasuredLineWidth(text, font) <= maxWidth) return nil;

    NSMutableArray<NSValue *> *wordRanges = [NSMutableArray array];
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                             options:NSStringEnumerationByWords
                          usingBlock:^(__unused NSString *substring, NSRange substringRange, __unused NSRange enclosingRange, __unused BOOL *stop) {
        [wordRanges addObject:[NSValue valueWithRange:substringRange]];
    }];
    if (wordRanges.count < 2) return nil;

    NSMutableArray<NSValue *> *segmentRanges = [NSMutableArray array];
    NSUInteger segmentStart = 0;
    BOOL hasWordsInCurrentLine = NO;

    for (NSValue *value in wordRanges) {
        NSRange wordRange = value.rangeValue;
        if (!hasWordsInCurrentLine) {
            hasWordsInCurrentLine = YES;
            continue;
        }

        NSUInteger candidateEnd = NSMaxRange(wordRange);
        NSString *candidateLine = [text substringWithRange:NSMakeRange(segmentStart, candidateEnd - segmentStart)];
        if (DateLyricsMeasuredLineWidth(candidateLine, font) <= maxWidth) {
            continue;
        }

        NSUInteger breakLocation = wordRange.location;
        NSString *committedLine = [text substringWithRange:NSMakeRange(segmentStart, breakLocation - segmentStart)];
        if (DateLyricsMeasuredLineWidth(committedLine, font) > maxWidth) {
            return nil;
        }

        [segmentRanges addObject:[NSValue valueWithRange:NSMakeRange(segmentStart, breakLocation - segmentStart)]];
        segmentStart = breakLocation;
        hasWordsInCurrentLine = YES;
    }

    NSString *finalLine = [text substringFromIndex:segmentStart];
    if (DateLyricsMeasuredLineWidth(finalLine, font) > maxWidth) return nil;
    [segmentRanges addObject:[NSValue valueWithRange:NSMakeRange(segmentStart, text.length - segmentStart)]];
    if (segmentRanges.count < 2) return nil;

    // segments break at the *start* of the next word, so every one but the last
    // carries a trailing space ("break down the door like a "), which throws the
    // centring off by a space width. only the length shrinks, never the location,
    // so highlight offsets — measured from range.location — are unaffected.
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSMutableArray<NSValue *> *trimmed = [NSMutableArray arrayWithCapacity:segmentRanges.count];
    for (NSValue *value in segmentRanges) {
        NSRange range = value.rangeValue;
        while (range.length > 0 && [whitespace characterIsMember:[text characterAtIndex:NSMaxRange(range) - 1]]) {
            range.length -= 1;
        }
        if (range.length > 0) [trimmed addObject:[NSValue valueWithRange:range]];
    }
    if (trimmed.count < 2) return nil;

    return trimmed;
}

static NSDictionary *DateLyricsSplitPayloadForLabel(NSDictionary *payload, UILabel *label, UIFont *baseFont) {
    if (gDateLyricsAlwaysOnDisplay || !gDateLyricsSplitLongLines) return nil;
    // artificial segments follow syllable focus. a line-synced-only score has
    // no word focus to choose the active segment, so keep it as one line and
    // let uilabel scale down to the configured minimum, then truncate its tail.
    if (![payload[@"wordTimed"] boolValue]) return nil;

    NSString *text = payload[@"text"];
    if (![text isKindOfClass:NSString.class] || text.length == 0) return nil;

    UIFont *measureFont = [baseFont isKindOfClass:UIFont.class] ? baseFont : nil;
    if (!measureFont) return nil;

    CGFloat maxWidth = DateLyricsSplitAvailableWidth(label);
    if (maxWidth <= 1.0) return nil;

    id lineId = payload[@"lineId"];
    NSString *fontKey = [NSString stringWithFormat:@"%@|%.2f", measureFont.fontName, measureFont.pointSize];

    // the segmentation is computed once per line and then reused verbatim for the
    // rest of that line. recomputing it every syllable tick meant any jitter in the
    // measured width silently produced a different set of segments mid-line, which
    // read as a spurious line change and fired another transition.
    DateLyricsSplitPlan *plan = objc_getAssociatedObject(label, kDateLyricsSplitPlanKey);
    NSInteger trackId = [gDateLyricsLocalAnchor[@"trackId"] integerValue];
    BOOL planMatches = plan
        && [plan.text isEqualToString:text]
        && [plan.fontKey isEqualToString:fontKey]
        && plan.trackId == trackId
        && fabs(plan.width - maxWidth) < 0.5
        && (plan.lineId == lineId || [plan.lineId isEqual:lineId]);

    if (!planMatches) {
        plan = [DateLyricsSplitPlan new];
        plan.text = text;
        plan.lineId = lineId;
        plan.trackId = trackId;
        plan.width = maxWidth;
        plan.fontKey = fontKey;
        plan.segments = DateLyricsComputeSegments(text, measureFont, maxWidth);
        plan.lastIndex = 0;
        objc_setAssociatedObject(label, kDateLyricsSplitPlanKey, plan, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DateLyricsDebugLog(@"PLAN w=%.1f segs=%lu font=%@ text='%@'",
                           maxWidth, (unsigned long)plan.segments.count, fontKey, text);
    }

    // segments == nil is a cached "this line does not need splitting", so we do not
    // re-measure it on every tick either.
    NSArray<NSValue *> *segmentRanges = plan.segments;
    if (segmentRanges.count < 2) return nil;

    NSRange highlightRange = DateLyricsRangeFromPayload(payload, @"", text.length);
    NSRange backgroundRange = DateLyricsRangeFromPayload(payload, @"bg", text.length);
    NSRange focusRange = DateLyricsRangeFromPayload(payload, @"focus", text.length);
    NSRange focusBackgroundRange = DateLyricsRangeFromPayload(payload, @"focusBg", text.length);

    NSUInteger targetIndex = plan.lastIndex;
    for (NSUInteger idx = 0; idx < segmentRanges.count; idx++) {
        NSRange segmentRange = [segmentRanges[idx] rangeValue];
        BOOL containsHighlight = focusRange.location != NSNotFound && NSIntersectionRange(segmentRange, focusRange).length > 0;
        BOOL containsBackground = focusBackgroundRange.location != NSNotFound && NSIntersectionRange(segmentRange, focusBackgroundRange).length > 0;
        if (containsHighlight || containsBackground) {
            targetIndex = idx;
            break;
        }
    }

    // keep the split segment monotonic through word-timing gaps.
    // allow a real backward seek to select an earlier segment; before the
    // first word, segment zero is the only unambiguous choice.
    if (gDateLyricsLastResolutionWasBackwardSeek &&
        focusRange.location == NSNotFound && focusBackgroundRange.location == NSNotFound) {
        targetIndex = 0;
    } else if (!gDateLyricsLastResolutionWasBackwardSeek && targetIndex < plan.lastIndex) {
        targetIndex = plan.lastIndex;
    }
    if (targetIndex >= segmentRanges.count) targetIndex = segmentRanges.count - 1;
    plan.lastIndex = targetIndex;

    NSRange targetRange = [segmentRanges[targetIndex] rangeValue];
    NSString *segmentText = [text substringWithRange:targetRange];
    if (segmentText.length == 0) return nil;

    NSMutableDictionary *splitPayload = [payload mutableCopy];
    splitPayload[@"text"] = segmentText;
    splitPayload[@"splitApplied"] = @YES;
    // each segment is presented as its own line, so give it its own identity.
    // line-change detection otherwise falls back to comparing the rendered text,
    // which treats two consecutive segments with identical wording (a repeated
    // "na na na") as unchanged and skips the transition between them.
    splitPayload[@"lineId"] = [NSString stringWithFormat:@"%@#%lu", lineId ?: @"", (unsigned long)targetIndex];

    if (highlightRange.location != NSNotFound) {
        NSRange intersection = NSIntersectionRange(targetRange, highlightRange);
        if (intersection.length > 0) {
            splitPayload[@"loc"] = @(intersection.location - targetRange.location);
            splitPayload[@"len"] = @(intersection.length);
        } else {
            [splitPayload removeObjectForKey:@"loc"];
            [splitPayload removeObjectForKey:@"len"];
        }
    }

    if (backgroundRange.location != NSNotFound) {
        NSRange intersection = NSIntersectionRange(targetRange, backgroundRange);
        if (intersection.length > 0) {
            splitPayload[@"bgLoc"] = @(intersection.location - targetRange.location);
            splitPayload[@"bgLen"] = @(intersection.length);
        } else {
            [splitPayload removeObjectForKey:@"bgLoc"];
            [splitPayload removeObjectForKey:@"bgLen"];
        }
    }

    NSRange completedRange = DateLyricsRangeFromPayload(payload, @"completed", text.length);
    if (completedRange.location != NSNotFound) {
        NSRange intersection = NSIntersectionRange(targetRange, completedRange);
        if (intersection.length > 0) {
            splitPayload[@"completedLoc"] = @(intersection.location - targetRange.location);
            splitPayload[@"completedLen"] = @(intersection.length);
        } else {
            [splitPayload removeObjectForKey:@"completedLoc"];
            [splitPayload removeObjectForKey:@"completedLen"];
        }
    }

    NSRange progressRange = DateLyricsRangeFromPayload(payload, @"progress", text.length);
    if (progressRange.location != NSNotFound) {
        NSRange intersection = NSIntersectionRange(targetRange, progressRange);
        if (intersection.length > 0) {
            splitPayload[@"progressLoc"] = @(intersection.location - targetRange.location);
            splitPayload[@"progressLen"] = @(intersection.length);
        } else {
            [splitPayload removeObjectForKey:@"progressLoc"];
            [splitPayload removeObjectForKey:@"progressLen"];
            splitPayload[@"progressActive"] = @NO;
        }
    }

    NSArray *completedRanges = payload[@"completedRanges"];
    if ([completedRanges isKindOfClass:NSArray.class]) {
        NSMutableArray *remapped = [NSMutableArray array];
        for (NSDictionary *entry in completedRanges) {
            NSRange sourceRange = NSMakeRange([entry[@"loc"] unsignedIntegerValue], [entry[@"len"] unsignedIntegerValue]);
            NSRange intersection = NSIntersectionRange(targetRange, sourceRange);
            if (intersection.length > 0) {
                [remapped addObject:@{@"loc": @(intersection.location - targetRange.location),
                                      @"len": @(intersection.length)}];
            }
        }
        splitPayload[@"completedRanges"] = remapped;
    }

    NSArray *progressSegments = payload[@"progressSegments"];
    if ([progressSegments isKindOfClass:NSArray.class]) {
        NSMutableArray *remapped = [NSMutableArray array];
        for (NSDictionary *entry in progressSegments) {
            NSRange sourceRange = NSMakeRange([entry[@"loc"] unsignedIntegerValue], [entry[@"len"] unsignedIntegerValue]);
            NSRange intersection = NSIntersectionRange(targetRange, sourceRange);
            if (intersection.length > 0) {
                NSMutableDictionary *mapped = [entry mutableCopy];
                mapped[@"loc"] = @(intersection.location - targetRange.location);
                mapped[@"len"] = @(intersection.length);
                [remapped addObject:mapped];
            }
        }
        splitPayload[@"progressSegments"] = remapped;
    }

    return splitPayload;
}

static NSDictionary *DateLyricsPayloadByApplyingLowercaseSafely(NSDictionary *payload) {
    NSString *text = payload[@"text"];
    if (![text isKindOfClass:NSString.class]) return payload;
    NSString *lowercase = text.lowercaseString;
    if ([lowercase isEqualToString:text] || lowercase.length != text.length) {
        if (lowercase.length != text.length) DateLyricsDebugLog(@"[Render] Skipping lowercase because length changed");
        return payload;
    }
    NSMutableDictionary *result = [payload mutableCopy];
    result[@"text"] = lowercase;
    return result;
}

@interface DateLyricsProgressOverlaySlot : NSObject
@property (nonatomic, strong) UILabel *overlayLabel;
@property (nonatomic, strong) CAGradientLayer *maskLayer;
@property (nonatomic, copy) NSString *lane;
@property (nonatomic, assign) NSUInteger laneIndex;
@property (nonatomic, copy) NSString *segmentIdentity;
@property (nonatomic, weak) UIView *renderTarget;
@property (nonatomic, assign) BOOL inUse;
@end

@implementation DateLyricsProgressOverlaySlot
@end

static void DateLyricsRemoveProgressOverlay(UILabel *label) {
    // only the slot pool owns progressive overlays. legacy single-overlay and
    // dictionary stores are never populated by this renderer.
    id pool = objc_getAssociatedObject(label, kDateLyricsProgressSlotPoolKey);
    if ([pool isKindOfClass:NSArray.class]) {
        for (id item in pool) {
            if (![item isKindOfClass:DateLyricsProgressOverlaySlot.class]) continue;
            DateLyricsProgressOverlaySlot *slot = item;
            CAGradientLayer *mask = slot.maskLayer;
            UILabel *overlay = slot.overlayLabel;
            if ([mask isKindOfClass:CAGradientLayer.class]) [mask removeAllAnimations];
            if ([overlay isKindOfClass:UIView.class]) {
                [overlay.layer removeAllAnimations];
                overlay.layer.mask = nil;
                [overlay removeFromSuperview];
            }
            slot.segmentIdentity = nil;
            slot.renderTarget = nil;
            slot.inUse = NO;
            slot.overlayLabel = nil;
            slot.maskLayer = nil;
        }
    }
    objc_setAssociatedObject(label, kDateLyricsProgressSlotPoolKey, nil, OBJC_ASSOCIATION_ASSIGN);
}


@interface DateLyricsGlyphLayoutCache : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIFont *font;
@property (nonatomic, assign) CGSize boundsSize;
@property (nonatomic, assign) NSTextAlignment alignment;
@property (nonatomic, assign) NSLineBreakMode lineBreakMode;
@property (nonatomic, strong) NSTextStorage *textStorage;
@property (nonatomic, strong) NSLayoutManager *layoutManager;
@property (nonatomic, strong) NSTextContainer *textContainer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *rects;
@end
@implementation DateLyricsGlyphLayoutCache
@end

static CGRect DateLyricsProgressGlyphRect(NSString *text, UIFont *font, NSRange range, UILabel *label) {
    if (range.location == NSNotFound || range.length == 0 || range.location + range.length > text.length) return CGRectZero;

    DateLyricsGlyphLayoutCache *cache = objc_getAssociatedObject(label, kDateLyricsGlyphCacheKey);
    BOOL match = cache != nil &&
                 [cache.text isEqualToString:text] &&
                 [cache.font isEqual:font] &&
                 CGSizeEqualToSize(cache.boundsSize, label.bounds.size) &&
                 cache.alignment == label.textAlignment &&
                 cache.lineBreakMode == label.lineBreakMode;

    if (!match) {
        cache = [DateLyricsGlyphLayoutCache new];
        cache.text = [text copy];
        cache.font = font;
        cache.boundsSize = label.bounds.size;
        cache.alignment = label.textAlignment;
        cache.lineBreakMode = label.lineBreakMode;
        cache.rects = [NSMutableDictionary dictionary];

        NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
        paragraph.alignment = label.textAlignment;
        paragraph.lineBreakMode = label.lineBreakMode;
        cache.textStorage = [[NSTextStorage alloc] initWithString:text attributes:@{
            NSFontAttributeName: font,
            NSParagraphStyleAttributeName: paragraph
        }];
        cache.layoutManager = [NSLayoutManager new];
        cache.textContainer = [[NSTextContainer alloc] initWithSize:label.bounds.size];
        cache.textContainer.lineFragmentPadding = 0.0;
        cache.textContainer.maximumNumberOfLines = 1;
        cache.textContainer.lineBreakMode = label.lineBreakMode;

        [cache.layoutManager addTextContainer:cache.textContainer];
        [cache.textStorage addLayoutManager:cache.layoutManager];

        objc_setAssociatedObject(label, kDateLyricsGlyphCacheKey, cache, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    NSString *rangeKey = NSStringFromRange(range);
    NSValue *cachedValue = cache.rects[rangeKey];
    if (cachedValue) {
        return [cachedValue CGRectValue];
    }

    NSRange glyphRange = [cache.layoutManager glyphRangeForCharacterRange:range actualCharacterRange:NULL];
    CGRect rect = [cache.layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:cache.textContainer];
    cache.rects[rangeKey] = [NSValue valueWithCGRect:rect];
    return rect;
}


static void DateLyricsHideProgressOverlays(UILabel *ownerLabel) {
    NSMutableArray<DateLyricsProgressOverlaySlot *> *pool = objc_getAssociatedObject(ownerLabel, kDateLyricsProgressSlotPoolKey);
    for (DateLyricsProgressOverlaySlot *slot in pool) {
        slot.inUse = NO;
        slot.overlayLabel.hidden = YES;
    }
}


// shared inertia constants: pause decelerates, resume accelerates, for the fill and the
// marquee alike, so a transport change never reads as a hard edge on either.
static const NSTimeInterval kDateLyricsPauseSettleDuration = 0.20;
static const NSTimeInterval kDateLyricsResumeRampDuration  = 0.18;

// fraction of the remaining travel covered after fraction u of the remaining time when
// velocity ramps linearly 0 -> v over the first `ramp` of the time, then stays constant,
// and the total still lands exactly on 1.  u in [0,1], ramp in [0,1].
static double DateLyricsEaseInProfile(double u, double ramp) {
    u = MIN(MAX(u, 0.0), 1.0);
    if (ramp <= 0.0) return u;
    ramp = MIN(ramp, 1.0);
    double v = 1.0 / (1.0 - ramp * 0.5);
    if (u < ramp) return v * u * u / (2.0 * ramp);
    return v * (ramp * 0.5 + (u - ramp));
}

// resume from the actual coast speed when play is pressed before settling.
// integrate a short linear velocity ramp and normalise to the word deadline.
static double DateLyricsResumeProgress(double u, double ramp, double initialSpeed) {
    u = MIN(1.0, MAX(0.0, u)); ramp = MIN(1.0, MAX(0.0, ramp));
    if (ramp <= 0) return u;
    initialSpeed = MIN(2.0, MAX(0.0, initialSpeed));
    double steady = (1.0 - initialSpeed*ramp*0.5) / (1.0-ramp*0.5);
    if (u < ramp) return initialSpeed*u + (steady-initialSpeed)*u*u/(2*ramp);
    return (initialSpeed+steady)*ramp*0.5 + steady*(u-ramp);
}

static NSArray *DateLyricsCaptureFillMotion(CAGradientLayer *mask, NSString *key, CGFloat *velocity);

// exact quadratic ease-out as a bezier timing function (y = 1-(1-t)^2).
static CAMediaTimingFunction *DateLyricsQuadEaseOut(void) {
    return [CAMediaTimingFunction functionWithControlPoints:1.0f/3.0f :2.0f/3.0f :2.0f/3.0f :1.0f];
}

// the fill animation carries its target and steady edge velocity as tags so pause and reuse
// logic never have to reverse-engineer them from cabasic- vs cakeyframeanimation internals.
static id DateLyricsAnimTag(CAAnimation *anim, NSString *key) {
    if (!anim) return nil;
    @try { return [anim valueForKey:key]; } @catch (__unused NSException *e) { return nil; }
}

static NSArray *DateLyricsShiftedLocations(NSArray *locations, CGFloat delta) {
    if (locations.count != 4) return locations;
    CGFloat edge = MIN(1.0, (CGFloat)[locations[2] doubleValue] + delta);
    CGFloat soft = MAX(0.0, MIN(edge, (CGFloat)[locations[1] doubleValue] + delta));
    return @[locations[0], @(soft), @(edge), locations[3]];
}

static void DateLyricsUpdateProgressOverlay(_UIAnimatingLabel *ownerLabel, UILabel *renderTargetLabel,
                                            NSDictionary *payload, NSString *text, UIFont *font, UIColor *textColor,
                                            BOOL progressiveEligible) {
    if (!progressiveEligible || ![text isKindOfClass:NSString.class] || text.length == 0) {
        DateLyricsHideProgressOverlays(ownerLabel);
        return;
    }

    NSArray *segments = payload[@"progressSegments"];
    if (![segments isKindOfClass:NSArray.class] || segments.count == 0) {
        NSNumber *loc = payload[@"progressLoc"], *len = payload[@"progressLen"];
        if (loc && len && [payload[@"progressActive"] boolValue]) {
            segments = @[@{@"loc": loc, @"len": len,
                            @"begin": payload[@"progressBegin"] ?: @0,
                            @"end": payload[@"progressEnd"] ?: @0,
                            @"lane": @"foreground"}];
        } else {
            DateLyricsHideProgressOverlays(ownerLabel);
            return;
        }
    }

    NSMutableArray<DateLyricsProgressOverlaySlot *> *pool = objc_getAssociatedObject(ownerLabel, kDateLyricsProgressSlotPoolKey);
    if (!pool) {
        pool = [NSMutableArray array];
        objc_setAssociatedObject(ownerLabel, kDateLyricsProgressSlotPoolKey, pool, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // check if overlays belong to another superview (e.g., from old marquee)
    for (DateLyricsProgressOverlaySlot *slot in pool) {
        if (slot.inUse && slot.overlayLabel.superview && slot.overlayLabel.superview != renderTargetLabel) {
            DateLyricsRemoveProgressOverlay(ownerLabel);
            pool = [NSMutableArray array];
            objc_setAssociatedObject(ownerLabel, kDateLyricsProgressSlotPoolKey, pool, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            break;
        }
    }

    NSTimeInterval elapsed = DateLyricsCurrentRenderElapsed();
    double rate = MAX(0.0, [gDateLyricsLocalAnchor[@"rate"] doubleValue]);

    // every gradient stop below is a fraction of this width.  before the render
    // target has been laid out it is 0, which would clamp start to 1.0 and span
    // to 0 -- a mask that reveals nothing -- and, worse, would still record a
    // segment identity, so the next tick would treat that garbage as continuous
    // state.  leave the overlays alone and retry on the next tick instead.
    CGFloat width = CGRectGetWidth(renderTargetLabel.bounds);
    if (width < 1.0) {
        DateLyricsDebugLog(@"[ANIM:P] skip line=%@ reason=target-not-laid-out target=%@",
                           payload[@"lineId"] ?: @"-",
                           renderTargetLabel == ownerLabel ? @"label" : @"marquee");
        return;
    }

    // mark all slots unused
    for (DateLyricsProgressOverlaySlot *slot in pool) {
        slot.inUse = NO;
    }

    NSMutableDictionary *laneCounts = [NSMutableDictionary dictionary];

    for (NSUInteger index = 0; index < segments.count; index++) {
        NSDictionary *segment = segments[index];
        NSRange range = NSMakeRange([segment[@"loc"] unsignedIntegerValue], [segment[@"len"] unsignedIntegerValue]);
        if (range.length == 0 || NSMaxRange(range) > text.length) continue;

        NSString *lane = segment[@"lane"] ?: @"foreground";
        NSUInteger laneIndex = [laneCounts[lane] unsignedIntegerValue];
        laneCounts[lane] = @(laneIndex + 1);

        DateLyricsProgressOverlaySlot *slot = nil;
        for (DateLyricsProgressOverlaySlot *s in pool) {
            if ([s.lane isEqualToString:lane] && s.laneIndex == laneIndex) {
                slot = s;
                break;
            }
        }
        if (!slot) {
            for (DateLyricsProgressOverlaySlot *s in pool) {
                if (!s.inUse) {
                    slot = s;
                    break;
                }
            }
        }
        if (!slot) {
            slot = [DateLyricsProgressOverlaySlot new];
            slot.overlayLabel = [UILabel new];
            slot.overlayLabel.userInteractionEnabled = NO;
            slot.overlayLabel.backgroundColor = UIColor.clearColor;
            slot.overlayLabel.numberOfLines = 1;
            slot.overlayLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

            slot.maskLayer = [CAGradientLayer layer];
            slot.maskLayer.startPoint = CGPointMake(0.0, 0.5);
            slot.maskLayer.endPoint = CGPointMake(1.0, 0.5);
            slot.maskLayer.colors = @[(id)UIColor.whiteColor.CGColor, (id)UIColor.whiteColor.CGColor,
                                      (id)UIColor.clearColor.CGColor, (id)UIColor.clearColor.CGColor];
            slot.maskLayer.locations = @[@0.0, @0.0, @0.0, @1.0];
            slot.maskLayer.actions = @{ @"locations": [NSNull null],
                                        @"bounds":    [NSNull null],
                                        @"position":  [NSNull null] };

            slot.overlayLabel.layer.mask = slot.maskLayer;
            [pool addObject:slot];
        }

        slot.inUse = YES;
        slot.lane = lane;
        slot.laneIndex = laneIndex;
        slot.renderTarget = renderTargetLabel;
        slot.overlayLabel.hidden = NO;

        UILabel *overlay = slot.overlayLabel;
        CAGradientLayer *mask = slot.maskLayer;

        overlay.frame = renderTargetLabel.bounds;
        overlay.font = font;
        overlay.textAlignment = renderTargetLabel.textAlignment;
        overlay.lineBreakMode = renderTargetLabel.lineBreakMode;
        NSMutableAttributedString *overlayText = [[NSMutableAttributedString alloc] initWithString:text];
        // must match the font datelyricsprogressglyphrect measured with, explicitly.
        // leaving it to uilabel's attributed-text font fallback lets the overlay
        // render at different metrics than the mask window was computed for.
        [overlayText addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, text.length)];
        [overlayText addAttribute:NSForegroundColorAttributeName value:UIColor.clearColor range:NSMakeRange(0, text.length)];
        [overlayText addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, text.length)];
        [overlayText addAttribute:NSForegroundColorAttributeName value:textColor range:range];
        overlay.attributedText = overlayText;

        CGRect glyphRect = DateLyricsProgressGlyphRect(text, font, range, renderTargetLabel);
        if (CGRectIsEmpty(glyphRect)) {
            overlay.hidden = YES;
            slot.inUse = NO;
            continue;
        }

        CGFloat start = MIN(MAX(CGRectGetMinX(glyphRect) / width, 0.0), 1.0);
        CGFloat span = MIN(MAX(CGRectGetWidth(glyphRect) / width, 0.0), 1.0 - start);
        NSTimeInterval begin = [segment[@"begin"] doubleValue];
        NSTimeInterval end = [segment[@"end"] doubleValue];
        double fraction = end > begin ? MIN(MAX((elapsed - begin) / (end - begin), 0.0), 1.0) : 1.0;
        CGFloat feather = MIN(8.0 / width, MAX(1.0 / width, span * 0.5));
        CGFloat revealTravel = span + feather;
        CGFloat edge = MIN(1.0, start + revealTravel * fraction);
        CGFloat softStart = MAX(0.0, edge - feather);

        NSArray *from = @[@0.0, @(softStart), @(edge), @1.0];

        CGFloat finalSolidEnd = MIN(1.0, start + span);
        CGFloat finalEdge = MIN(1.0, finalSolidEnd + feather);

        NSArray *to = @[@0.0, @(finalSolidEnd), @(finalEdge), @1.0];

        mask.frame = overlay.bounds;

        if (overlay.superview != renderTargetLabel) {
            [renderTargetLabel addSubview:overlay];
        }

        CAGradientLayer *maskPresentation = (CAGradientLayer *)mask.presentationLayer;
        NSArray *modelBefore = [mask.locations copy];
        NSArray *presentationBefore = [maskPresentation.locations copy];
        BOOL animationBefore = [mask animationForKey:@"DateLyricsProgressFill"] != nil;

        NSString *segmentID = [NSString stringWithFormat:@"%@|%@|%@|%.3f|%.3f",
                               payload[@"lineId"] ?: @"-", segment[@"loc"] ?: @0, segment[@"len"] ?: @0, begin, end];
        NSString *oldSegmentID = slot.segmentIdentity;

        BOOL sameSegment = [oldSegmentID isEqualToString:segmentID];
        BOOL isFrozen = [objc_getAssociatedObject(mask, kDateLyricsProgressFrozenKey) boolValue];

        // pause: hold where the pixels are, easing to a stop instead of cutting dead.
        // lane-agnostic on purpose: foreground syllables and ad-libs go through the same code.
        if (sameSegment && rate <= 0.0) {
            if (!isFrozen) {
                CAAnimation *running = [mask animationForKey:@"DateLyricsProgressFill"];
                CGFloat velocity = 0;
                NSArray *held = DateLyricsCaptureFillMotion(mask, @"DateLyricsProgressFill", &velocity);
                if (held.count != 4) held = from;

                // glide: an ease-out whose initial speed equals the fill's current speed
                // travels velocity*t/2, never past the end of the word.
                NSArray *settled = held;
                NSTimeInterval glide = 0.0;
                CGFloat finalEdgeLimit = (CGFloat)[to[2] doubleValue];
                CGFloat heldEdge = (CGFloat)[held[2] doubleValue];
                if (running && velocity > 0.0 && held.count == 4) {
                    CGFloat distance = MIN(finalEdgeLimit - heldEdge, velocity * kDateLyricsPauseSettleDuration * 0.5);
                    if (distance > 0.0005) {
                        settled = DateLyricsShiftedLocations(held, distance);
                        glide = MIN(kDateLyricsPauseSettleDuration, 2 * distance / velocity);
                    }
                }

                [CATransaction begin];
                [CATransaction setDisableActions:YES];
                [mask removeAnimationForKey:@"DateLyricsProgressFill"];
                [mask removeAnimationForKey:@"DateLyricsProgressSettle"];
                mask.locations = settled;
                if (glide > 0.0) {
                    CABasicAnimation *stop = [CABasicAnimation animationWithKeyPath:@"locations"];
                    stop.fromValue = held;
                    stop.toValue = settled;
                    stop.duration = glide;
                    stop.beginTime = [mask convertTime:CACurrentMediaTime() fromLayer:nil];
                    stop.timingFunction = DateLyricsQuadEaseOut();
                    [mask addAnimation:stop forKey:@"DateLyricsProgressSettle"];
                }
                [CATransaction commit];
                objc_setAssociatedObject(mask, kDateLyricsProgressFrozenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                DateLyricsDebugLog(@"[PAUSE:P] line=%@ lane=%@ seg=%@ held=%@ settled=%@ glide=%.2f v=%.3f/s",
                                   payload[@"lineId"] ?: @"-", lane, segmentID,
                                   DateLyricsFormatNumbers(held), DateLyricsFormatNumbers(settled), glide, velocity);
            }
            continue;
        }

        BOOL resumingFromPause = sameSegment && isFrozen;
        objc_setAssociatedObject(mask, kDateLyricsProgressFrozenKey, nil, OBJC_ASSOCIATION_ASSIGN);

        // how far the held edge sits ahead of where the clock says it should be.  after a
        // pause glide this is the ~0.1 s of travel the coast overshot by.
        CGFloat leadEdge = 0.0, resumeVelocity = 0.0;

        // never un-light a glyph inside one segment. absorbs clock jitter at a
        // transport boundary and the ~0.0007 geometry wobble.
        if (sameSegment) {
            CGFloat visibleVelocity = 0;
            NSArray *held = DateLyricsCaptureFillMotion(mask, @"DateLyricsProgressFill", &visibleVelocity);
            if (resumingFromPause) resumeVelocity = MAX(0.0, visibleVelocity);
            // with no presentation layer yet (an overlay whose animation was added in this
            // very run-loop turn, e.g. the second apply right after a scrub lands mid-word)
            // the model value is the animation's end state, not where the fill is.  using it
            // as the "never un-light" floor jumped the whole word to fully lit and cancelled
            // its animation.  only trust the model when nothing is animating.
            if (held.count != 4 && !animationBefore) held = mask.locations;
            if (held.count == 4) {
                CGFloat heldEdge = (CGFloat)[held[2] doubleValue];
                if (heldEdge > edge && heldEdge <= finalEdge + 0.0001) {
                    leadEdge = heldEdge - edge;
                    edge = heldEdge;
                    softStart = MAX(0.0, edge - feather);
                    from = @[@0.0, @(softStart), @(edge), @1.0];
                }
            }
        }

        BOOL animate = rate > 0.0 && edge < finalEdge - 0.0001 && (end - elapsed) / rate > 1.0 / 60.0;
        BOOL reusedAnimation = NO;

        if (sameSegment && animationBefore && animate) {
            CAAnimation *existing = [mask animationForKey:@"DateLyricsProgressFill"];
            // if the target gradient is the same, reuse the animation in flight
            NSArray *existingTarget = DateLyricsAnimTag(existing, @"dlTarget");
            if (existingTarget && [existingTarget isEqual:to]) {
                reusedAnimation = YES;
            }
        }

        if (!reusedAnimation) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            [mask removeAnimationForKey:@"DateLyricsProgressFill"];
            [mask removeAnimationForKey:@"DateLyricsProgressSettle"];
            mask.locations = animate ? to : from;
            if (animate) {
                NSTimeInterval duration = MAX(0.0, (end - elapsed) / rate);
                CGFloat travel = (CGFloat)([to[2] doubleValue] - [from[2] doubleValue]);
                CAAnimation *fill = nil;
                double rampFraction = 0.0, initialSpeed = 0.0;

                // resume accelerates from rest over a short ramp, then holds a constant speed
                // that still lands exactly on the word's end.  anything else starts the fill at
                // full speed on the very first frame after a pause.
                NSTimeInterval holdTime = 0.0;
                if (resumingFromPause && duration > 0.15) {
                    // the pause glide left the edge slightly ahead of the song.  hold still for
                    // exactly as long as the clock needs to reach it (at the word's natural
                    // speed), then accelerate from rest and still land on the word's end.
                    CGFloat naturalVelocity = duration > 0.0
                        ? (CGFloat)([to[2] doubleValue] - ([from[2] doubleValue] - leadEdge)) / duration : 0.0;
                    if (resumeVelocity <= 0.0001 && leadEdge > 0.0005 && naturalVelocity > 0.0) {
                        holdTime = MIN(MIN((NSTimeInterval)(leadEdge / naturalVelocity), 0.30), duration * 0.5);
                    }
                    NSTimeInterval active = duration - holdTime;
                    NSTimeInterval ramp = MIN(kDateLyricsResumeRampDuration, active * 0.5);
                    rampFraction = active > 0.0 ? ramp / active : 0.0;
                    initialSpeed = travel > 0.0001 ? MIN(2.0, resumeVelocity * active / travel) : 0.0;
                    NSInteger steps = (NSInteger)MIN(120.0, MAX(12.0, ceil(duration / 0.016)));
                    NSMutableArray *values = [NSMutableArray arrayWithCapacity:(NSUInteger)steps + 1];
                    for (NSInteger i = 0; i <= steps; i++) {
                        NSTimeInterval t = duration * ((double)i / (double)steps);
                        double progress = t <= holdTime ? 0.0
                            : DateLyricsResumeProgress((t - holdTime) / active, rampFraction, initialSpeed);
                        NSMutableArray *stops = [NSMutableArray arrayWithCapacity:4];
                        for (NSUInteger k = 0; k < 4; k++) {
                            double f = [from[k] doubleValue], tt = [to[k] doubleValue];
                            [stops addObject:@(f + (tt - f) * progress)];
                        }
                        [values addObject:stops];
                    }
                    CAKeyframeAnimation *keyed = [CAKeyframeAnimation animationWithKeyPath:@"locations"];
                    keyed.values = values;
                    keyed.calculationMode = kCAAnimationLinear;
                    keyed.duration = duration;
                    fill = keyed;
                } else {
                    CABasicAnimation *basic = [CABasicAnimation animationWithKeyPath:@"locations"];
                    basic.fromValue = from;
                    basic.toValue = to;
                    basic.duration = duration;
                    basic.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
                    fill = basic;
                }
                fill.removedOnCompletion = NO;
                fill.fillMode = kCAFillModeBoth;
                // steady-state edge velocity, tagged so a later pause can derive its glide.
                NSTimeInterval activeTime = duration - holdTime;
                double steadyVelocity = activeTime > 0.0 ? travel * (1.0 - initialSpeed*rampFraction*0.5) / (activeTime * (1.0 - rampFraction * 0.5)) : 0.0;
                [fill setValue:to forKey:@"dlTarget"];
                [fill setValue:@(steadyVelocity) forKey:@"dlEdgeVelocity"];
                // when this fill reaches the word's end (media time), so a line that is being
                // transitioned out can keep filling to that same finish.
                CFTimeInterval fillStart = CACurrentMediaTime();
                fill.beginTime = [mask convertTime:fillStart fromLayer:nil];
                [fill setValue:@(fillStart + duration) forKey:@"dlEndMedia"];
                // a pause that lands during the hold must not glide: nothing is moving yet.
                [fill setValue:@(fillStart + holdTime) forKey:@"dlHoldUntil"];
                [mask addAnimation:fill forKey:@"DateLyricsProgressFill"];
                if (resumingFromPause) {
                    DateLyricsDebugLog(@"[RESUME:P] line=%@ lane=%@ seg=%@ from=%@ to=%@ dur=%.3f hold=%.3f ramp=%.2f",
                                       payload[@"lineId"] ?: @"-", lane, segmentID,
                                       DateLyricsFormatNumbers(from), DateLyricsFormatNumbers(to),
                                       duration, holdTime, rampFraction);
                }
            }
            [CATransaction commit];
        }

        slot.segmentIdentity = segmentID;

        DateLyricsDebugLog(
            @"[ANIM:P] gen=%lu line=%@ oldSegment=%@ newSegment=%@ "
             "rate=%.2f elapsed=%.3f wordBegin=%.3f wordEnd=%.3f fraction=%.3f "
             "modelBefore=%@ presentationBefore=%@ modelAfter=%@ "
             "animation=%d->%d%s target=%@",
            (unsigned long)gDateLyricsAnchorGeneration,
            payload[@"lineId"] ?: @"-",
            oldSegmentID ?: @"none",
            segmentID,
            rate,
            elapsed,
            begin,
            end,
            fraction,
            DateLyricsFormatNumbers(modelBefore),
            DateLyricsFormatNumbers(presentationBefore),
            DateLyricsFormatNumbers(mask.locations),
            animationBefore,
            [mask animationForKey:@"DateLyricsProgressFill"] != nil,
            reusedAnimation ? " (reused)" : "",
            renderTargetLabel == ownerLabel ? @"label" : @"marquee"
        );
    }

    for (DateLyricsProgressOverlaySlot *slot in pool) {
        if (!slot.inUse) slot.overlayLabel.hidden = YES;
    }

    DateLyricsDebugLog(@"PROGRESS_STATE line=%@ elapsed=%.3f completed=%lu active=%@ target=%@",
                       payload[@"lineId"] ?: @"-",
                       elapsed,
                       (unsigned long)[payload[@"completedRanges"] count],
                       DateLyricsFormatSegments(payload[@"progressSegments"]),
                       renderTargetLabel == ownerLabel ? @"label" : @"marquee");
}


// a brief visual bridge between the live karaoke label and the fully lit aod
// line. the underlying lyric clock/renderer continues to own the actual content.
static NSTimeInterval DateLyricsMarqueeHoldForLine(NSTimeInterval timelineDuration, CGFloat overflow);
static CGFloat DateLyricsMarqueeHandoffWakeX(NSTimeInterval phase, NSTimeInterval entryPhase, NSTimeInterval timelineDuration, NSTimeInterval holdDuration, CGFloat overflow, double rate, CGFloat startX, NSTimeInterval duration);
static CGFloat DateLyricsMarqueeHandoffWakeMotionX(NSTimeInterval phase, NSTimeInterval entryPhase, NSTimeInterval timelineDuration, NSTimeInterval holdDuration, CGFloat overflow, double rate, CGFloat startX, CGFloat startVelocity, NSTimeInterval duration);
static CGFloat DateLyricsMarqueeWakePhaseX(double phase, double entryPhase, double timeline, double hold, CGFloat overflow, double rate, CGFloat start, CGFloat velocity, double duration);

// measure the live foreground fill in full-line coordinates for a scrolling
// wake bridge. the stock label's truncated/right-aligned viewport cannot do it.
static CGFloat DateLyricsWakeTrackFillEdge(UILabel *target, NSDictionary *payload, double elapsed) {
    CGFloat width = CGRectGetWidth(target.bounds);
    NSString *text = target.attributedText.string ?: target.text;
    if (width <= 1 || !text.length) return 0;
    CGFloat edge = 0;
    for (NSDictionary *range in payload[@"completedRanges"]) {
        if ([range[@"lane"] isEqual:@"background"]) continue;
        NSRange r = NSMakeRange([range[@"loc"] unsignedIntegerValue], [range[@"len"] unsignedIntegerValue]);
        if (!r.length || r.location > text.length || r.length > text.length-r.location) continue;
        CGRect rect = DateLyricsProgressGlyphRect(text, target.font, r, target);
        edge = MAX(edge, CGRectGetMaxX(rect)/width);
    }
    for (NSDictionary *segment in payload[@"progressSegments"]) {
        if ([segment[@"lane"] isEqual:@"background"]) continue;
        NSRange r = NSMakeRange([segment[@"loc"] unsignedIntegerValue], [segment[@"len"] unsignedIntegerValue]);
        if (!r.length || r.location > text.length || r.length > text.length-r.location) continue;
        CGRect rect = DateLyricsProgressGlyphRect(text, target.font, r, target);
        if (CGRectIsEmpty(rect)) continue;
        double begin = [segment[@"begin"] doubleValue], end = [segment[@"end"] doubleValue];
        double fraction = end > begin ? MIN(1.0, MAX(0.0, (elapsed-begin)/(end-begin))) : 1.0;
        CGFloat start = MIN(1.0, MAX(0.0, CGRectGetMinX(rect)/width));
        CGFloat span = MIN(1.0-start, MAX(0.0, CGRectGetWidth(rect)/width));
        CGFloat feather = MIN(8.0/width, MAX(1.0/width, span*0.5));
        edge = MAX(edge, start + (span+feather)*fraction);
    }
    return MIN(1.0, MAX(0.0, edge));
}

// forecast only the line already on screen. the stateless word resolver can
// cross syllable boundaries without advancing the live cursor or split plan.
static NSDictionary *DateLyricsWakeFillPayload(UILabel *target, double elapsed) {
    NSDictionary *payload = gDateLyricsCurrentPayload;
    if (gDateLyricsCurrentScore.trackId == [gDateLyricsLocalAnchor[@"trackId"] integerValue]) {
        for (DateLyricsTimedLine *source in gDateLyricsCurrentScore.lines) {
            DateLyricsTimedLine *line = DateLyricsGetFilteredLine(source);
            if (!line || ![payload[@"lineId"] isEqual:@(line.begin)]) continue;
            payload = DateLyricsResolveWordPayloadFullScan(line, elapsed, NULL, NULL) ?: payload;
            break;
        }
    }
    if (gDateLyricsForceLowercase) payload = DateLyricsPayloadByApplyingLowercaseSafely(payload);
    NSString *text = payload[@"text"];
    NSString *visibleText = target.attributedText.string ?: target.text;
    if ([text isEqualToString:visibleText]) return payload;

    DateLyricsSplitPlan *plan = objc_getAssociatedObject(target, kDateLyricsSplitPlanKey);
    if (!gDateLyricsSplitLongLines || ![plan.text isEqualToString:text] ||
        plan.trackId != [gDateLyricsLocalAnchor[@"trackId"] integerValue] ||
        plan.lastIndex >= plan.segments.count) return nil;
    NSRange visible = [plan.segments[plan.lastIndex] rangeValue];
    if (visible.location > text.length || visible.length > text.length - visible.location ||
        ![[text substringWithRange:visible] isEqualToString:visibleText]) return nil;
    NSMutableDictionary *mapped = [payload mutableCopy];
    mapped[@"text"] = visibleText;
    for (NSString *key in @[@"completedRanges", @"progressSegments"]) {
        NSMutableArray *ranges = [NSMutableArray array];
        for (NSDictionary *entry in payload[key]) {
            NSRange range = NSMakeRange([entry[@"loc"] unsignedIntegerValue], [entry[@"len"] unsignedIntegerValue]);
            if (range.location > text.length || range.length > text.length - range.location) continue;
            NSRange intersection = NSIntersectionRange(visible, range);
            if (!intersection.length) continue;
            NSMutableDictionary *part = [entry mutableCopy];
            part[@"loc"] = @(intersection.location - visible.location);
            part[@"len"] = @(intersection.length);
            [ranges addObject:part];
        }
        mapped[key] = ranges;
    }
    return mapped;
}

static CGFloat DateLyricsPredictedWakeFillEdge(UILabel *target, double startElapsed, NSTimeInterval duration) {
    double rate = MAX(0.0, [gDateLyricsLocalAnchor[@"rate"] doubleValue]);
    double elapsed = startElapsed + MAX(0.0, duration) * rate;
    NSDictionary *payload = DateLyricsWakeFillPayload(target, elapsed);
    return payload ? DateLyricsWakeTrackFillEdge(target, payload, elapsed) : 1.0;
}

// one display transition owns one window. new lyrics inherit its remaining
// time instead of making the outgoing line race a predicted lyric boundary.
static NSTimeInterval DateLyricsDisplayHandoffDuration(CFTimeInterval deadline, CFTimeInterval now) {
    return deadline > 0 ? MIN(0.85, MAX(0.0, deadline - now)) : 0.85;
}

@interface DateLyricsDisplayMorph : NSObject
@property (nonatomic, weak) _UIAnimatingLabel *label;
@property (nonatomic, strong) UIView *snapshot;
@property (nonatomic, strong) id lineID;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) CGFloat edge;
@property (nonatomic, assign) BOOL canSweep;
@property (nonatomic, assign) BOOL wordTimed;
@property (nonatomic, strong) UIView *marqueeTrack;
@property (nonatomic, strong) UILabel *marqueeFill;
@property (nonatomic, assign) CGFloat marqueeX;
@property (nonatomic, assign) CGFloat marqueeVelocity;
@property (nonatomic, assign) BOOL capturedMarquee;
@property (nonatomic, assign) BOOL interrupted;
@property (nonatomic, assign) BOOL enteringAOD;
@property (nonatomic, assign) NSInteger trackID;
@property (nonatomic, assign) CFTimeInterval deadline;
@property (nonatomic, strong) CAGradientLayer *fillMask;
@property (nonatomic, copy) NSDictionary<NSString *, NSDictionary *> *laneStarts;
@property (nonatomic, copy) NSDictionary<NSString *, CAGradientLayer *> *laneMasks;
@end
@implementation DateLyricsDisplayMorph
@end

static BOOL DateLyricsDisplayMorphCanContinue(DateLyricsDisplayMorph *morph) {
    return morph && DateLyricsRenderingActive() && gDateLyricsEnabled &&
        morph.enteringAOD == gDateLyricsAlwaysOnDisplay &&
        morph.trackID == [gDateLyricsLocalAnchor[@"trackId"] integerValue] &&
        morph.deadline > CACurrentMediaTime();
}

static void DateLyricsCancelDisplayMorph(_UIAnimatingLabel *label) {
    DateLyricsDisplayMorph *morph = objc_getAssociatedObject(label, kDateLyricsDisplayMorphKey);
    [morph.snapshot.layer removeAllAnimations];
    [morph.marqueeTrack.layer removeAllAnimations];
    [morph.fillMask removeAllAnimations];
    for (CAGradientLayer *mask in morph.laneMasks.allValues) [mask removeAllAnimations];
    [morph.snapshot removeFromSuperview];
    if (morph.marqueeTrack) label.alpha = objc_getAssociatedObject(label, kDateLyricsMarqueeContainerKey) ? 0.0 : 1.0;
    UIView *parked = objc_getAssociatedObject(label, kDateLyricsMarqueeContainerKey);
    parked.hidden = NO;
    objc_setAssociatedObject(label, kDateLyricsDisplayMorphKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static BOOL DateLyricsMarqueeAvailableForLabel(_UIAnimatingLabel *label) {
    return DateLyricsMarqueeAvailable() && !objc_getAssociatedObject(label, kDateLyricsDisplayMorphKey);
}

// aod payloads deliberately omit word timing. check the filtered source line
// so mixed scores and lines reached while already dim retain the right policy.
static BOOL DateLyricsCurrentLineSupportsFillHandoff(void) {
    if (!gDateLyricsProgressiveFill || !gDateLyricsWordHighlighting) return NO;
    if ([gDateLyricsCurrentPayload[@"wordTimed"] boolValue]) return YES;
    id lineID = gDateLyricsCurrentPayload[@"lineId"];
    for (DateLyricsTimedLine *source in gDateLyricsCurrentScore.lines) {
        if ([lineID isEqual:@(source.begin)])
            return DateLyricsLineHasWordTiming(DateLyricsGetFilteredLine(source));
    }
    return NO;
}

// use the same visible mask for the frozen glyph copy and its fill endpoint.
// before the first display commit, the model already holds the future target.
static NSArray *DateLyricsDisplayedProgressLocations(CAGradientLayer *mask) {
    CAGradientLayer *presentation = (CAGradientLayer *)mask.presentationLayer;
    NSArray *locations = presentation.locations;
    if (locations.count != 4) {
        CAAnimation *animation = [mask animationForKey:@"DateLyricsProgressFill"];
        if ([animation isKindOfClass:CABasicAnimation.class]) locations = [(CABasicAnimation *)animation fromValue];
        else if ([animation isKindOfClass:CAKeyframeAnimation.class]) locations = [(CAKeyframeAnimation *)animation values].firstObject;
        if (locations.count != 4) locations = mask.locations;
    }
    return locations;
}

// read the pixels currently revealed, not a mask's model value (which already
// holds its eventual target while core animation is animating toward it).
static CGFloat DateLyricsDisplayedFillEdgeInTarget(_UIAnimatingLabel *label, UILabel *target) {
    CGFloat edge = 0.0;
    CGFloat width = CGRectGetWidth(target.bounds);
    if (width < 1.0) return 0.0;
    NSArray<DateLyricsProgressOverlaySlot *> *pool = objc_getAssociatedObject(label, kDateLyricsProgressSlotPoolKey);
    for (DateLyricsProgressOverlaySlot *slot in pool) {
        if (!slot.inUse || slot.overlayLabel.hidden || slot.renderTarget != target ||
            ![slot.lane isEqualToString:@"foreground"]) continue;
        NSArray *locations = DateLyricsDisplayedProgressLocations(slot.maskLayer);
        if (locations.count == 4) edge = MAX(edge, [locations[2] doubleValue]);
    }
    NSDictionary *payload = gDateLyricsCurrentPayload;
    NSString *text = target.attributedText.string ?: target.text;
    for (NSDictionary *range in payload[@"completedRanges"]) {
        if ([range[@"lane"] isEqual:@"background"]) continue;
        NSRange r = NSMakeRange([range[@"loc"] unsignedIntegerValue], [range[@"len"] unsignedIntegerValue]);
        if (!r.length || r.location > text.length || r.length > text.length - r.location) continue;
        CGRect rect = DateLyricsProgressGlyphRect(text, target.font, r, target);
        if (!CGRectIsEmpty(rect)) edge = MAX(edge, CGRectGetMaxX(rect) / width);
    }
    return MIN(MAX(edge, 0.0), 1.0);
}

static CGFloat DateLyricsDisplayedFillEdge(_UIAnimatingLabel *label) {
    UILabel *content = objc_getAssociatedObject(label, kDateLyricsMarqueeContentLabelKey);
    UIView *track = objc_getAssociatedObject(label, kDateLyricsMarqueeTrackKey);
    if (content && track && CGRectGetWidth(label.bounds) > 1.0) {
        CGFloat edge = DateLyricsDisplayedFillEdgeInTarget(label, content) * CGRectGetWidth(content.bounds);
        CGFloat x = [[(track.layer.presentationLayer ?: track.layer) valueForKeyPath:@"transform.translation.x"] doubleValue];
        return MIN(1.0, MAX(0.0, (edge + x) / CGRectGetWidth(label.bounds)));
    }
    return DateLyricsDisplayedFillEdgeInTarget(label, label);
}

static UILabel *DateLyricsCopyHandoffLabel(UILabel *source) {
    UILabel *copy = [[UILabel alloc] initWithFrame:source.frame];
    copy.font = source.font; copy.textAlignment = source.textAlignment;
    copy.numberOfLines = source.numberOfLines; copy.lineBreakMode = source.lineBreakMode;
    copy.adjustsFontSizeToFitWidth = source.adjustsFontSizeToFitWidth;
    copy.textColor = source.textColor; copy.backgroundColor = UIColor.clearColor;
    copy.attributedText = source.attributedText;
    if (!copy.attributedText) copy.text = source.text;
    DateLyricsSplitPlan *plan = objc_getAssociatedObject(source, kDateLyricsSplitPlanKey);
    if (plan) objc_setAssociatedObject(copy, kDateLyricsSplitPlanKey, plan, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return copy;
}

// substitute layouts with complementary clips. crossfading text briefly draws
// both glyph runs in the same pixels, especially when aod truncates a split line.
static void DateLyricsReplaceHandoffLayout(UIView *outgoing, UIView *incoming, NSTimeInterval duration, CFTimeInterval start) {
    CGFloat viewportWidth = CGRectGetWidth(incoming.bounds);
    CGFloat outgoingWidth = CGRectGetWidth(outgoing.bounds);
    CGFloat height = CGRectGetHeight(incoming.bounds);
    CAShapeLayer *incomingClip = [CAShapeLayer layer]; incomingClip.frame = incoming.bounds;
    CAShapeLayer *outgoingClip = [CAShapeLayer layer]; outgoingClip.frame = outgoing.bounds;
    CGPathRef incomingFrom = CGPathCreateCopy([UIBezierPath bezierPathWithRect:CGRectMake(0, 0, 0, height)].CGPath);
    CGPathRef incomingTo = CGPathCreateCopy([UIBezierPath bezierPathWithRect:CGRectMake(0, 0, viewportWidth, height)].CGPath);
    CGPathRef outgoingFrom = CGPathCreateCopy([UIBezierPath bezierPathWithRect:CGRectMake(0, 0, outgoingWidth, height)].CGPath);
    CGPathRef outgoingTo = CGPathCreateCopy([UIBezierPath bezierPathWithRect:CGRectMake(viewportWidth, 0, MAX(0, outgoingWidth - viewportWidth), height)].CGPath);
    incomingClip.path = incomingTo; incoming.layer.mask = incomingClip;
    outgoingClip.path = outgoingTo; outgoing.layer.mask = outgoingClip;
    CABasicAnimation *replace = [CABasicAnimation animationWithKeyPath:@"path"];
    replace.fromValue = (__bridge id)incomingFrom; replace.toValue = (__bridge id)incomingTo;
    replace.beginTime = [incomingClip convertTime:start fromLayer:nil]; replace.duration = duration;
    replace.fillMode = kCAFillModeBackwards;
    replace.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [incomingClip addAnimation:replace forKey:@"DateLyricsAODLanding"];
    CABasicAnimation *remove = [replace copy];
    remove.fromValue = (__bridge id)outgoingFrom; remove.toValue = (__bridge id)outgoingTo;
    remove.beginTime = [outgoingClip convertTime:start fromLayer:nil];
    [outgoingClip addAnimation:remove forKey:@"DateLyricsAODLanding"];
    CGPathRelease(incomingFrom); CGPathRelease(incomingTo);
    CGPathRelease(outgoingFrom); CGPathRelease(outgoingTo);
}

// sample the same linear keyframes used by the live marquee. if core
// animation has no presentation layer yet, its model is the eventual endpoint
// and is not a usable handoff position.
static CGFloat DateLyricsLinearMarqueeSample(NSArray<NSNumber *> *values, NSArray<NSNumber *> *times, double phase, CGFloat *slope) {
    if (slope) *slope = 0;
    if (!values.count) return 0;
    if (values.count == 1) return values.firstObject.doubleValue;
    if (phase >= 1) return values.lastObject.doubleValue;
    phase = MAX(0.0, phase);
    BOOL explicitTimes = times.count == values.count;
    for (NSUInteger i = 1; i < values.count; i++) {
        double begin = explicitTimes ? times[i-1].doubleValue : (double)(i-1)/(values.count-1);
        double end = explicitTimes ? times[i].doubleValue : (double)i/(values.count-1);
        if (phase > end && i+1 < values.count) continue;
        if (end <= begin) return values[i].doubleValue;
        double delta = values[i].doubleValue - values[i-1].doubleValue;
        if (slope) *slope = delta/(end-begin);
        return values[i-1].doubleValue + delta*MIN(1.0, MAX(0.0, (phase-begin)/(end-begin)));
    }
    return values.lastObject.doubleValue;
}

static void DateLyricsCaptureMarqueeMotion(CALayer *layer, CGFloat *position, CGFloat *velocity) {
    *position = [[layer valueForKeyPath:@"transform.translation.x"] doubleValue]; *velocity = 0;
    CAAnimation *animation = [layer animationForKey:@"DateLyricsMarquee"] ?: [layer animationForKey:@"DateLyricsMarqueeToEnd"];
    BOOL settling = NO;
    if (!animation) { animation = [layer animationForKey:@"DateLyricsMarqueeSettle"]; settling = animation != nil; }
    if (animation.duration > 0) {
        double local = [layer convertTime:CACurrentMediaTime() fromLayer:nil];
        double phase = ((local-animation.beginTime)*animation.speed + animation.timeOffset)/animation.duration;
        double t = MIN(1.0, MAX(0.0, phase));
        NSArray *values = nil, *times = nil;
        if ([animation isKindOfClass:CAKeyframeAnimation.class]) {
            values = [(CAKeyframeAnimation *)animation values]; times = [(CAKeyframeAnimation *)animation keyTimes];
        } else if ([animation isKindOfClass:CABasicAnimation.class]) {
            values = @[([(CABasicAnimation *)animation fromValue] ?: @(*position)), ([(CABasicAnimation *)animation toValue] ?: @(*position))];
        }
        if (values.count) {
            CGFloat slope = 0;
            *position = DateLyricsLinearMarqueeSample(values, times, settling ? 1-(1-t)*(1-t) : phase, &slope);
            *velocity = phase >= 0 && phase < 1 ? slope*animation.speed*layer.speed/animation.duration*(settling ? 2*(1-t) : 1) : 0;
        }
    }
    CALayer *visible = layer.presentationLayer;
    if (visible) *position = [[visible valueForKeyPath:@"transform.translation.x"] doubleValue];
}

// a cubic continuation inherits the live speed and comes to rest at the aod
// endpoint. limit only speeds that would overshoot the remaining distance.
static CGFloat DateLyricsMarqueeContinuationX(CGFloat start, CGFloat end, CGFloat velocity, double duration, double phase) {
    double t = MIN(1.0, MAX(0.0, phase));
    double distance = end-start;
    if (fabs(distance) < 0.001 || duration <= 0) return end;
    double tangent = velocity*duration/distance;
    tangent = MIN(3.0, MAX(0.0, tangent));
    double eased = (-2*t*t*t+3*t*t) + tangent*(t*t*t-2*t*t+t);
    return start + distance*eased;
}

// a fill can reverse direction mid-handoff. retain its signed speed through
// the turn and meet the live fill's speed at the predicted wake destination.
static CGFloat DateLyricsFillHandoffEdge(CGFloat start, CGFloat end, CGFloat startVelocity, CGFloat endVelocity, double duration, double phase) {
    double t = MIN(1.0, MAX(0.0, phase));
    if (duration <= 0) return end;
    double t2 = t*t, t3 = t2*t;
    double edge = (2*t3-3*t2+1)*start + (-2*t3+3*t2)*end +
        (t3-2*t2+t)*startVelocity*duration + (t3-t2)*endVelocity*duration;
    return MIN(1.0, MAX(0.0, edge));
}

// if a wake is interrupted while scrolling right, retain that motion briefly
// and turn toward the aod tail continuously, within the real viewport bounds.
static CGFloat DateLyricsMarqueeLockX(CGFloat start, CGFloat end, CGFloat velocity, double duration, double phase, CGFloat overflow) {
    if (velocity <= 0 || end >= start || duration <= 0)
        return DateLyricsMarqueeContinuationX(start, end, velocity, duration, phase);
    double t = MIN(1.0, MAX(0.0, phase));
    double distance = end-start;
    double tangent = MAX(-3.0, velocity*duration/distance);
    double eased = (-2*t*t*t+3*t*t) + tangent*(t*t*t-2*t*t+t);
    return MAX(-overflow, MIN(0.0, start+distance*eased));
}

// presentation owns the visible position. when unavailable, sample the running
// linear/keyframed fill at its current time instead of rewinding to fromvalue.
static NSArray *DateLyricsCaptureFillMotion(CAGradientLayer *mask, NSString *key, CGFloat *velocity) {
    *velocity = 0;
    CAAnimation *animation = [mask animationForKey:key];
    BOOL settling = NO;
    if (!animation && [key isEqual:@"DateLyricsProgressFill"]) {
        animation = [mask animationForKey:@"DateLyricsProgressSettle"];
        settling = animation != nil;
    }
    NSArray *locations = mask.locations;
    if (animation.duration > 0) {
        double local = [mask convertTime:CACurrentMediaTime() fromLayer:nil];
        double phase = ((local - animation.beginTime) * animation.speed + animation.timeOffset) / animation.duration;
        double samplePhase = settling ? 1.0 - pow(1.0 - MIN(1.0, MAX(0.0, phase)), 2) : phase;
        NSArray *values = nil, *times = nil;
        if ([animation isKindOfClass:CAKeyframeAnimation.class]) {
            values = [(CAKeyframeAnimation *)animation values]; times = [(CAKeyframeAnimation *)animation keyTimes];
        } else if ([animation isKindOfClass:CABasicAnimation.class]) {
            id from = [(CABasicAnimation *)animation fromValue], to = [(CABasicAnimation *)animation toValue];
            if ([from isKindOfClass:NSArray.class] && [to isKindOfClass:NSArray.class]) values = @[from,to];
        }
        if ([values.firstObject count] == 4 && [values.lastObject count] == 4) {
            NSMutableArray *sampled = [NSMutableArray array];
            for (NSUInteger stop = 0; stop < 4; stop++) {
                NSMutableArray *points = [NSMutableArray array];
                for (NSArray *frame in values) [points addObject:frame[stop]];
                CGFloat slope = 0;
                [sampled addObject:@(DateLyricsLinearMarqueeSample(points, times, samplePhase, &slope))];
                if (stop == 2 && phase >= 0 && phase < 1)
                    *velocity = slope * animation.speed * mask.speed / animation.duration * (settling ? 2 * (1 - phase) : 1);
            }
            locations = sampled;
        }
    }
    NSArray *visible = [(CAGradientLayer *)mask.presentationLayer locations];
    // a recycled word slot can still expose its previous presentation frame.
    // reject that stale frame instead of dragging the new word's edge backward.
    BOOL plausible = visible.count == 4 && (locations.count != 4 || !animation ||
        fabs([visible[2] doubleValue] - [locations[2] doubleValue]) <= MAX(0.02, fabs(*velocity) * 0.05));
    return plausible ? visible : locations;
}

static NSDictionary *DateLyricsCaptureLaneStart(_UIAnimatingLabel *owner, UILabel *target, NSString *lane) {
    CGFloat edge = 0, soft = 0, velocity = 0;
    CGFloat width = CGRectGetWidth(target.bounds);
    NSDictionary *payload = DateLyricsWakeFillPayload(target, DateLyricsCurrentRenderElapsed());
    NSString *text = target.attributedText.string ?: target.text;
    for (NSDictionary *range in payload[@"completedRanges"]) {
        if (![(range[@"lane"] ?: @"foreground") isEqual:lane]) continue;
        NSRange r = NSMakeRange([range[@"loc"] unsignedIntegerValue], [range[@"len"] unsignedIntegerValue]);
        if (!r.length || r.location > text.length || r.length > text.length - r.location || width <= 1) continue;
        CGRect rect = DateLyricsProgressGlyphRect(text, target.font, r, target);
        if (!CGRectIsEmpty(rect)) edge = MAX(edge, CGRectGetMaxX(rect) / width);
    }
    soft = edge;
    for (DateLyricsProgressOverlaySlot *slot in objc_getAssociatedObject(owner, kDateLyricsProgressSlotPoolKey)) {
        if (!slot.inUse || slot.overlayLabel.hidden || slot.renderTarget != target || ![slot.lane isEqual:lane]) continue;
        CGFloat speed = 0;
        NSArray *locations = DateLyricsCaptureFillMotion(slot.maskLayer, @"DateLyricsProgressFill", &speed);
        if (locations.count == 4 && [locations[2] doubleValue] >= edge) {
            edge = [locations[2] doubleValue]; soft = [locations[1] doubleValue]; velocity = speed;
        }
    }
    return @{@"edge": @(MIN(1.0, MAX(0.0, edge))), @"soft": @(MIN(edge, MAX(0.0, soft))), @"velocity": @(velocity)};
}

// resolve each stream independently; an ad-lib further along the glyph run
// must never pull the foreground's edge forward (or the reverse).
static CGFloat DateLyricsPredictedLaneEdge(UILabel *target, NSString *lane, double elapsed, double duration) {
    elapsed += duration * MAX(0.0, [gDateLyricsLocalAnchor[@"rate"] doubleValue]);
    NSDictionary *payload = DateLyricsWakeFillPayload(target, elapsed);
    if (!payload) return 1;
    NSMutableDictionary *onlyLane = [payload mutableCopy];
    for (NSString *key in @[@"completedRanges", @"progressSegments"]) {
        NSMutableArray *ranges = [NSMutableArray array];
        for (NSDictionary *range in payload[key]) {
            if (![(range[@"lane"] ?: @"foreground") isEqual:lane]) continue;
            NSMutableDictionary *entry = [range mutableCopy]; entry[@"lane"] = @"foreground";
            [ranges addObject:entry];
        }
        onlyLane[key] = ranges;
    }
    return DateLyricsWakeTrackFillEdge(target, onlyLane, elapsed);
}

static void DateLyricsCaptureFillHandoff(DateLyricsDisplayMorph *morph, _UIAnimatingLabel *label) {
    UIView *sourceTrack = objc_getAssociatedObject(label, kDateLyricsMarqueeTrackKey);
    UILabel *sourceText = objc_getAssociatedObject(label, kDateLyricsMarqueeContentLabelKey);
    BOOL scrolling = sourceTrack && sourceText;
    morph.capturedMarquee = scrolling;
    if (!scrolling) sourceText = label;
    if (CGRectGetWidth(sourceText.bounds) < 1.0) return;
    morph.laneStarts = @{@"foreground": DateLyricsCaptureLaneStart(label, sourceText, @"foreground"),
                         @"background": DateLyricsCaptureLaneStart(label, sourceText, @"background")};
    UIView *container = [[UIView alloc] initWithFrame:label.frame]; container.clipsToBounds = YES;
    // uiview.frame includes the live marquee transform. copy untransformed
    // geometry so the captured translation is applied exactly once.
    UIView *track = [[UIView alloc] initWithFrame:CGRectZero];
    track.bounds = scrolling ? sourceTrack.bounds : sourceText.bounds;
    track.center = scrolling ? sourceTrack.center : CGPointMake(CGRectGetMidX(container.bounds), CGRectGetMidY(container.bounds));
    UILabel *base = DateLyricsCopyHandoffLabel(sourceText);
    if (!scrolling) base.frame = sourceText.bounds;
    if (gDateLyricsAlwaysOnDisplay && morph.wordTimed) {
        NSMutableAttributedString *dim = [base.attributedText mutableCopy];
        [dim addAttribute:NSForegroundColorAttributeName value:[DateLyricsBaseTextColorForLabel(label) colorWithAlphaComponent:0.35] range:NSMakeRange(0, dim.length)];
        base.attributedText = dim;
        morph.laneStarts = nil; // aod starts both streams fully revealed.
    }
    [track addSubview:base];
    // the lane masks recreate the captured active fills. keeping extra frozen
    // overlays underneath would double their translucent feather pixels.
    morph.edge = morph.wordTimed ? [morph.laneStarts[@"foreground"][@"edge"] doubleValue] : 1.0;
    if (gDateLyricsAlwaysOnDisplay) morph.edge = 1.0;
    if (scrolling) {
        CGFloat x = 0, velocity = 0;
        DateLyricsCaptureMarqueeMotion(sourceTrack.layer, &x, &velocity);
        morph.marqueeX = x; morph.marqueeVelocity = velocity;
    }
    track.layer.transform = CATransform3DMakeTranslation(morph.marqueeX, 0, 0);
    [container addSubview:track];
    UILabel *filled = DateLyricsCopyHandoffLabel(sourceText);
    if (!scrolling) filled.frame = sourceText.bounds;
    NSMutableAttributedString *bright = [filled.attributedText mutableCopy];
    if (!bright) bright = [[NSMutableAttributedString alloc] initWithString:sourceText.text ?: @""];
    [bright addAttribute:NSForegroundColorAttributeName value:DateLyricsBaseTextColorForLabel(label) range:NSMakeRange(0, bright.length)];
    filled.attributedText = bright;
    morph.snapshot = container; morph.marqueeTrack = track; morph.marqueeFill = filled;
}

// the model already contains its endpoint. reversals must use the visible
// presentation mask, or the animation's start before its first rendered frame.
static CGFloat DateLyricsDisplayedMorphEdge(CAGradientLayer *mask) {
    CAGradientLayer *presentation = (CAGradientLayer *)mask.presentationLayer;
    NSArray *locations = presentation.locations;
    if (locations.count != 4) {
        CABasicAnimation *animation = (CABasicAnimation *)([mask animationForKey:@"DateLyricsMarqueeFinishFill"] ?: [mask animationForKey:@"DateLyricsDisplayMorph"]);
        locations = [animation isKindOfClass:CABasicAnimation.class] ? animation.fromValue : nil;
        if (locations.count != 4) locations = mask.locations;
    }
    return locations.count == 4 ? MIN(1.0, MAX(0.0, [locations[2] doubleValue])) : 0.0;
}

static DateLyricsDisplayMorph *DateLyricsCaptureInterruptedMorph(_UIAnimatingLabel *label, DateLyricsDisplayMorph *old) {
    NSString *text = label.attributedText.string ?: label.text;
    if (!old.fillMask || ![old.lineID isEqual:gDateLyricsCurrentPayload[@"lineId"]] ||
        (![old.text isEqualToString:text] && !gDateLyricsSplitLongLines)) return nil;
    DateLyricsDisplayMorph *morph = [DateLyricsDisplayMorph new];
    morph.label = label; morph.lineID = old.lineID; morph.text = text; morph.interrupted = YES;
    morph.wordTimed = old.wordTimed;
    morph.edge = DateLyricsDisplayedMorphEdge(old.fillMask);
    NSMutableDictionary *laneStarts = [NSMutableDictionary dictionary];
    for (NSString *lane in old.laneMasks) {
        CGFloat velocity = 0;
        NSArray *locations = DateLyricsCaptureFillMotion(old.laneMasks[lane], @"DateLyricsMarqueeFinishFill", &velocity);
        if (locations.count == 4) laneStarts[lane] = @{@"edge":locations[2], @"soft":locations[1], @"velocity":@(velocity)};
    }
    morph.laneStarts = laneStarts.count ? laneStarts : nil;
    if (laneStarts[@"foreground"]) morph.edge = [laneStarts[@"foreground"][@"edge"] doubleValue];
    UIView *container = [[UIView alloc] initWithFrame:label.frame]; container.clipsToBounds = YES;
    CGRect bounds = old.marqueeTrack ? old.marqueeTrack.bounds : label.bounds;
    UIView *track = [[UIView alloc] initWithFrame:bounds];
    UILabel *source = old.marqueeFill ?: label;
    UILabel *base = DateLyricsCopyHandoffLabel(source); base.frame = bounds;
    NSMutableAttributedString *dim = [base.attributedText mutableCopy];
    UIColor *baseColor = DateLyricsBaseTextColorForLabel(label);
    [dim addAttribute:NSForegroundColorAttributeName value:(morph.wordTimed ? [baseColor colorWithAlphaComponent:0.35] : baseColor) range:NSMakeRange(0, dim.length)];
    base.attributedText = dim; [track addSubview:base];
    UILabel *filled = DateLyricsCopyHandoffLabel(source); filled.frame = bounds;
    NSMutableAttributedString *bright = [filled.attributedText mutableCopy];
    [bright addAttribute:NSForegroundColorAttributeName value:DateLyricsBaseTextColorForLabel(label) range:NSMakeRange(0, bright.length)];
    filled.attributedText = bright;
    CGFloat x = 0, velocity = 0;
    DateLyricsCaptureMarqueeMotion(old.marqueeTrack.layer, &x, &velocity);
    morph.marqueeX = x; morph.marqueeVelocity = velocity;
    CGFloat maskWidth = CGRectGetWidth(old.fillMask.frame);
    CGFloat trackWidth = CGRectGetWidth(bounds);
    if (trackWidth > 1.0 && fabs(maskWidth - trackWidth) > 0.5)
        morph.edge = MIN(1.0, MAX(0.0, (morph.edge * maskWidth - morph.marqueeX) / trackWidth));
    track.layer.transform = CATransform3DMakeTranslation(morph.marqueeX, 0, 0);
    [container addSubview:track]; morph.snapshot = container;
    morph.marqueeTrack = track; morph.marqueeFill = filled; morph.capturedMarquee = old.capturedMarquee;
    DateLyricsDebugLog(@"[DISPLAY:MORPH] reverse-from edge=%.3f x=%.1f", morph.edge, morph.marqueeX);
    return morph;
}

static DateLyricsDisplayMorph *DateLyricsCaptureDisplayMorph(_UIAnimatingLabel *label) {
    DateLyricsDisplayMorph *old = objc_getAssociatedObject(label, kDateLyricsDisplayMorphKey);
    DateLyricsDisplayMorph *interrupted = old ? DateLyricsCaptureInterruptedMorph(label, old) : nil;
    DateLyricsCancelDisplayMorph(label);
    if (interrupted) {
        objc_setAssociatedObject(label, kDateLyricsDisplayMorphKey, interrupted, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return interrupted;
    }
    if (!label.window || !label.superview ||
        ![objc_getAssociatedObject(label, kDateLyricsLabelShowingLyricKey) boolValue] ||
        [objc_getAssociatedObject(label, kDateLyricsAnimatingTransitionKey) boolValue]) return nil;
    BOOL wordTimed = DateLyricsCurrentLineSupportsFillHandoff();
    UIView *source = objc_getAssociatedObject(label, kDateLyricsMarqueeContainerKey) ?: label;
    // plain line-timed lyrics have no fill to finish or withdraw. marquees
    // still need their current position captured for the viewport handoff.
    BOOL wakeMarquee = gDateLyricsAlwaysOnDisplay && gDateLyricsMarqueeEnabled && !gDateLyricsSplitLongLines &&
        DateLyricsMeasuredLineWidth(label.attributedText.string ?: label.text, label.font) > CGRectGetWidth(label.bounds) + 0.5;
    if (!wordTimed && source == label && !wakeMarquee) return nil;
    DateLyricsDisplayMorph *morph = [DateLyricsDisplayMorph new];
    morph.label = label;
    morph.lineID = gDateLyricsCurrentPayload[@"lineId"];
    morph.text = label.attributedText.string ?: label.text;
    morph.wordTimed = wordTimed;
    morph.canSweep = wordTimed && label.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionLeftToRight &&
        !objc_getAssociatedObject(label, kDateLyricsMarqueeContainerKey);
    morph.edge = DateLyricsDisplayedFillEdge(label);
    // freeze the marquee's current glyphs and masks in a separate track.
    // its return translation and finish-fill mask run independently.
    // on lock, a translucent uikit snapshot would let the fully bright aod
    // label shine through unfilled glyphs. hide the live label and finish-fill
    // an explicit frozen glyph copy instead. keep the verified wake path.
    if (source != label || (wordTimed && label.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionLeftToRight))
        DateLyricsCaptureFillHandoff(morph, label);
    else morph.snapshot = [source snapshotViewAfterScreenUpdates:NO];
    if (!morph.snapshot) return nil;
    morph.snapshot.userInteractionEnabled = NO;
    morph.snapshot.frame = label.frame;
    objc_setAssociatedObject(label, kDateLyricsDisplayMorphKey, morph, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return morph;
}

static void DateLyricsAnimateHandoffLanes(DateLyricsDisplayMorph *morph, _UIAnimatingLabel *owner,
    BOOL enteringAOD, double elapsed, NSTimeInterval duration, CFTimeInterval start) {
    UILabel *foreground = morph.marqueeFill;
    NSDictionary *complete = DateLyricsWakeFillPayload(foreground, DBL_MAX);
    NSMutableArray<NSValue *> *backgroundRanges = [NSMutableArray array];
    NSString *text = foreground.attributedText.string ?: foreground.text;
    for (NSDictionary *entry in complete[@"completedRanges"]) {
        if (![entry[@"lane"] isEqual:@"background"]) continue;
        NSRange range = NSMakeRange([entry[@"loc"] unsignedIntegerValue], [entry[@"len"] unsignedIntegerValue]);
        if (range.length && range.location <= text.length && range.length <= text.length - range.location)
            [backgroundRanges addObject:[NSValue valueWithRange:range]];
    }
    NSMutableDictionary *masks = [NSMutableDictionary dictionary];
    UIColor *color = DateLyricsBaseTextColorForLabel(owner);
    for (NSString *lane in backgroundRanges.count ? @[@"foreground",@"background"] : @[@"foreground"]) {
        BOOL background = [lane isEqual:@"background"];
        UILabel *filled = background ? DateLyricsCopyHandoffLabel(foreground) : foreground;
        NSMutableAttributedString *bright = [foreground.attributedText mutableCopy];
        [bright addAttribute:NSForegroundColorAttributeName value:background ? UIColor.clearColor : color range:NSMakeRange(0, bright.length)];
        for (NSValue *value in backgroundRanges)
            [bright addAttribute:NSForegroundColorAttributeName value:background ? color : UIColor.clearColor range:value.rangeValue];
        filled.attributedText = bright;
        NSDictionary *captured = morph.laneStarts[lane];
        CGFloat edge = captured ? [captured[@"edge"] doubleValue] : (enteringAOD ? morph.edge : 1.0);
        CGFloat soft = captured ? [captured[@"soft"] doubleValue] : edge;
        CGFloat velocity = captured ? [captured[@"velocity"] doubleValue] : 0;
        if (background && enteringAOD) {
            // an unstarted ad-lib begins at its own first glyph immediately,
            // not after the foreground sweep reaches its place in the string.
            CGFloat beginning = 1.0, width = CGRectGetWidth(filled.bounds);
            for (NSValue *value in backgroundRanges) {
                CGRect rect = DateLyricsProgressGlyphRect(text, filled.font, value.rangeValue, filled);
                if (width > 1 && !CGRectIsEmpty(rect)) beginning = MIN(beginning, CGRectGetMinX(rect) / width);
            }
            if (edge < beginning) { edge = beginning; soft = beginning; velocity = 0; }
        }
        CGFloat end = enteringAOD ? 1.0 : DateLyricsPredictedLaneEdge(filled, lane, elapsed, duration);
        CGFloat endVelocity = enteringAOD ? 0.0 : MAX(0.0,
            (DateLyricsPredictedLaneEdge(filled, lane, elapsed, duration + 0.01) - end) / 0.01);
        CGFloat feather = MIN(8.0 / MAX(1.0, CGRectGetWidth(filled.bounds)), 0.08);
        CGFloat endSoft = enteringAOD ? 1.0 : MAX(0.0, end - feather);
        CAGradientLayer *mask = [CAGradientLayer layer]; mask.frame = filled.bounds;
        mask.startPoint = CGPointMake(0,0.5); mask.endPoint = CGPointMake(1,0.5);
        mask.colors = @[(id)UIColor.whiteColor.CGColor,(id)UIColor.whiteColor.CGColor,(id)UIColor.clearColor.CGColor,(id)UIColor.clearColor.CGColor];
        NSMutableArray *values = [NSMutableArray array];
        for (NSUInteger i = 0; i <= 90; i++) {
            double phase = (double)i / 90;
            CGFloat next = DateLyricsFillHandoffEdge(edge, end, velocity, endVelocity, duration, phase);
            double blend = phase * phase * (3 - 2 * phase);
            CGFloat softness = (edge - soft) * (1 - blend) + (end - endSoft) * blend;
            [values addObject:@[@0,@(MAX(0.0, next - softness)),@(next),@1]];
        }
        mask.locations = values.lastObject; filled.layer.mask = mask; filled.hidden = NO;
        [morph.marqueeTrack addSubview:filled];
        CAKeyframeAnimation *fill = [CAKeyframeAnimation animationWithKeyPath:@"locations"];
        fill.values = values; fill.duration = duration; fill.calculationMode = kCAAnimationLinear;
        fill.beginTime = [mask convertTime:start fromLayer:nil];
        [mask addAnimation:fill forKey:@"DateLyricsMarqueeFinishFill"];
        masks[lane] = mask;
        if (!background) morph.fillMask = mask;
        DateLyricsDebugLog(@"[DISPLAY:FILL] lane=%@ direction=%@ start=%.4f soft=%.4f speed=%.4f end=%.4f duration=%.3f",
            lane, enteringAOD ? @"fill" : @"backfill", edge, soft, velocity, end, duration);
    }
    morph.laneMasks = masks;
}

static void DateLyricsStartDisplayMorph(DateLyricsDisplayMorph *morph, BOOL enteringAOD) {
    _UIAnimatingLabel *label = morph.label;
    if (!label || objc_getAssociatedObject(label, kDateLyricsDisplayMorphKey) != morph) return;
    if (!label.window || !label.superview) { DateLyricsCancelDisplayMorph(label); return; }
    id lineID = gDateLyricsCurrentPayload[@"lineId"];
    NSString *text = label.attributedText.string ?: label.text;
    BOOL splitGeometryChanged = gDateLyricsSplitLongLines && ![morph.text isEqualToString:text];
    if (![morph.lineID isEqual:lineID] || (![morph.text isEqualToString:text] && !splitGeometryChanged)) {
        DateLyricsCancelDisplayMorph(label);
        objc_setAssociatedObject(label, kDateLyricsRenderCacheKey, nil, OBJC_ASSOCIATION_ASSIGN);
        [label _amlApplyCurrentLyric]; return;
    }
    if (!morph.interrupted && !enteringAOD && !splitGeometryChanged &&
        gDateLyricsMarqueeEnabled && !gDateLyricsSplitLongLines &&
        DateLyricsMeasuredLineWidth(text, label.font) > CGRectGetWidth(label.bounds) + 0.5) {
        // wake uses one full-width track, so scrolling and word backfill share
        // glyph coordinates. start at the parked tail or the new line's prefix.
        CGFloat fullWidth = DateLyricsMeasuredLineWidth(text, label.font);
        UIView *bridge = [[UIView alloc] initWithFrame:label.frame]; bridge.clipsToBounds = YES;
        UIView *track = [[UIView alloc] initWithFrame:CGRectMake(0, 0, fullWidth, CGRectGetHeight(label.bounds))];
        UILabel *base = DateLyricsCopyHandoffLabel(label); base.frame = track.bounds;
        base.textAlignment = NSTextAlignmentLeft; base.lineBreakMode = NSLineBreakByClipping;
        UIColor *baseColor = DateLyricsBaseTextColorForLabel(label);
        NSMutableAttributedString *dim = [base.attributedText mutableCopy];
        [dim addAttribute:NSForegroundColorAttributeName value:(morph.wordTimed ? [baseColor colorWithAlphaComponent:0.35] : baseColor) range:NSMakeRange(0, dim.length)];
        base.attributedText = dim; [track addSubview:base];
        UILabel *filled = DateLyricsCopyHandoffLabel(base); filled.frame = track.bounds;
        NSMutableAttributedString *bright = [filled.attributedText mutableCopy];
        [bright addAttribute:NSForegroundColorAttributeName value:baseColor range:NSMakeRange(0, bright.length)];
        filled.attributedText = bright;
        morph.marqueeX = DateLyricsAODTailMatchesCurrentLine() ? -MAX(0, fullWidth - CGRectGetWidth(label.bounds)) : 0;
        track.layer.transform = CATransform3DMakeTranslation(morph.marqueeX, 0, 0);
        [bridge addSubview:track]; morph.snapshot = bridge;
        morph.marqueeTrack = track; morph.marqueeFill = filled;
        morph.capturedMarquee = YES; morph.edge = 1.0;
    }
    UIView *splitOutgoing = nil, *splitIncoming = nil;
    if (!morph.interrupted && !enteringAOD && splitGeometryChanged) {
        // aod owns the whole line; awake owns the live split segment. bridge
        // those layouts, then withdraw the full segment to its current word.
        UIView *old = morph.snapshot;
        [morph.marqueeTrack addSubview:morph.marqueeFill];
        UIView *bridge = [[UIView alloc] initWithFrame:label.frame];
        UILabel *segment = DateLyricsCopyHandoffLabel(label);
        segment.frame = bridge.bounds;
        NSMutableAttributedString *bright = [segment.attributedText mutableCopy];
        [bright addAttribute:NSForegroundColorAttributeName value:DateLyricsBaseTextColorForLabel(label) range:NSMakeRange(0, bright.length)];
        segment.attributedText = bright;
        UIView *track = [[UIView alloc] initWithFrame:bridge.bounds];
        UILabel *base = DateLyricsCopyHandoffLabel(segment);
        NSMutableAttributedString *dim = [bright mutableCopy];
        [dim addAttribute:NSForegroundColorAttributeName value:[DateLyricsBaseTextColorForLabel(label) colorWithAlphaComponent:0.35] range:NSMakeRange(0, dim.length)];
        base.attributedText = dim; [track addSubview:base];
        [bridge addSubview:track];
        old.frame = bridge.bounds; [bridge addSubview:old];
        splitOutgoing = old; splitIncoming = track;
        morph.snapshot = bridge;
        morph.marqueeTrack = track; morph.marqueeFill = segment;
        morph.capturedMarquee = NO; morph.marqueeX = 0; morph.marqueeVelocity = 0;
        morph.laneStarts = nil;
        morph.canSweep = morph.wordTimed;
        morph.text = text;
    }
    CGFloat width = CGRectGetWidth(label.bounds);
    BOOL sweep = morph.canSweep && width > 1.0 &&
        fabs(CGRectGetWidth(morph.snapshot.bounds) - width) < 0.5;
    CFTimeInterval handoffStart = CACurrentMediaTime();
    NSTimeInterval duration = DateLyricsDisplayHandoffDuration(morph.deadline, handoffStart);
    double startElapsed = DateLyricsCurrentRenderElapsed();
    if (duration <= 0.0) {
        DateLyricsCancelDisplayMorph(label);
        objc_setAssociatedObject(label, kDateLyricsRenderCacheKey, nil, OBJC_ASSOCIATION_ASSIGN);
        [label _amlApplyCurrentLyric];
        DateLyricsRequestAODRefresh(@"display handoff window expired");
        return;
    }
    morph.deadline = handoffStart + duration;
    morph.trackID = [gDateLyricsLocalAnchor[@"trackId"] integerValue];
    morph.enteringAOD = enteringAOD;
    if (splitOutgoing) DateLyricsReplaceHandoffLayout(splitOutgoing, splitIncoming, MIN(0.15, duration), handoffStart);
    morph.snapshot.frame = label.frame;
    [label.superview insertSubview:morph.snapshot aboveSubview:label];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (morph.marqueeTrack) {
        label.alpha = 0.0;
        // move and fill the same frozen glyph track through the full handoff.
        // aod holds the ending viewport, so no ellipsis landing is needed.
        CGFloat endX = enteringAOD && morph.capturedMarquee
            ? -MAX(0.0, CGRectGetWidth(morph.marqueeTrack.bounds) - CGRectGetWidth(morph.snapshot.bounds)) : morph.marqueeX;
        // fill and marquee forecast using the same display-transition window.
        NSTimeInterval returnDuration = duration;
        double rate = MAX(0.0, [gDateLyricsLocalAnchor[@"rate"] doubleValue]);
        double lineBegin = [gDateLyricsCurrentPayload[@"lineBegin"] doubleValue];
        double timeline = MAX(0.0, [gDateLyricsCurrentPayload[@"lineEnd"] doubleValue] - lineBegin);
        double entryPhase = startElapsed - lineBegin;
        CGFloat overflow = MAX(0, CGRectGetWidth(morph.marqueeTrack.bounds) - CGRectGetWidth(morph.snapshot.bounds));
        double hold = DateLyricsMarqueeHoldForLine(timeline, overflow);
        BOOL wakeScroll = !enteringAOD && morph.capturedMarquee && timeline > 0;
        UIView *parked = objc_getAssociatedObject(label, kDateLyricsMarqueeContainerKey); parked.hidden = YES;
        CAKeyframeAnimation *scroll = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
        NSMutableArray *positions = [NSMutableArray array];
        for (NSUInteger i = 0; i <= 90; i++) {
            double phase = (double)i/90;
            CGFloat x = wakeScroll ? DateLyricsMarqueeWakePhaseX(phase, entryPhase, timeline, hold, overflow, rate, morph.marqueeX, morph.marqueeVelocity, returnDuration)
                : (enteringAOD
                    ? DateLyricsMarqueeLockX(morph.marqueeX, endX, morph.marqueeVelocity, returnDuration, phase, overflow)
                    : DateLyricsMarqueeContinuationX(morph.marqueeX, endX, 0, returnDuration, phase));
            [positions addObject:@(x)];
        }
        endX = [positions.lastObject doubleValue];
        scroll.values = positions; scroll.duration = returnDuration; scroll.calculationMode = kCAAnimationLinear;
        scroll.beginTime = [morph.marqueeTrack.layer convertTime:handoffStart fromLayer:nil];
        morph.marqueeTrack.layer.transform = CATransform3DMakeTranslation(endX, 0, 0);
        [morph.marqueeTrack.layer addAnimation:scroll forKey:@"DateLyricsMarqueeToEnd"];
        DateLyricsDebugLog(@"[DISPLAY:MARQUEE] continue x=%.2f velocity=%.2f end=%.2f", morph.marqueeX, morph.marqueeVelocity, endX);
        if (morph.wordTimed) DateLyricsAnimateHandoffLanes(morph, label, enteringAOD, startElapsed, duration, handoffStart);
        else morph.marqueeFill.hidden = YES;
        if (enteringAOD && splitGeometryChanged) {
            // use the actual post-mode-switch uilabel layout: its width,
            // alignment and native tail ellipsis exactly match the final aod
            // label. replace via complementary clips before revealing it,
            // rather than fading two overlapping text layouts.
            UILabel *landing = DateLyricsCopyHandoffLabel(label);
            landing.frame = morph.snapshot.bounds;
            [morph.snapshot addSubview:landing];
            NSTimeInterval settleDuration = MIN(0.25, duration);
            CFTimeInterval settleStart = handoffStart + duration - settleDuration;
            DateLyricsReplaceHandoffLayout(morph.marqueeTrack, landing, settleDuration, settleStart);

        }
    } else if (sweep) {
        CGFloat feather = MIN(8.0 / width, 0.08);
        CGFloat start = enteringAOD ? morph.edge : 1.0;
        CGFloat end = enteringAOD ? 1.0 : DateLyricsPredictedWakeFillEdge(label, startElapsed, duration);
        CAGradientLayer *mask = [CAGradientLayer layer];
        mask.frame = morph.snapshot.bounds;
        mask.startPoint = CGPointMake(0.0, 0.5); mask.endPoint = CGPointMake(1.0, 0.5);
        mask.colors = enteringAOD
            ? @[(id)UIColor.clearColor.CGColor, (id)UIColor.clearColor.CGColor, (id)UIColor.whiteColor.CGColor, (id)UIColor.whiteColor.CGColor]
            : @[(id)UIColor.whiteColor.CGColor, (id)UIColor.whiteColor.CGColor, (id)UIColor.clearColor.CGColor, (id)UIColor.clearColor.CGColor];
        NSArray *from = @[@0, @(MAX(0.0, start - feather)), @(start), @1];
        NSArray *to = @[@0, @(MAX(0.0, end - feather)), @(end), @1];
        mask.locations = to; morph.snapshot.layer.mask = mask; morph.fillMask = mask;
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"locations"];
        animation.fromValue = from; animation.toValue = to; animation.duration = duration;
        animation.beginTime = [mask convertTime:handoffStart fromLayer:nil];
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [mask addAnimation:animation forKey:@"DateLyricsDisplayMorph"];
    } else if (morph.wordTimed) {
        morph.snapshot.layer.opacity = 0.0;
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
        animation.fromValue = @1; animation.toValue = @0; animation.duration = duration;
        animation.beginTime = [morph.snapshot.layer convertTime:handoffStart fromLayer:nil];
        [morph.snapshot.layer addAnimation:animation forKey:@"DateLyricsDisplayMorph"];
    } else {
        // a line-timed marquee holds its captured viewport through wake;
        // showing the owner below it would double the fully bright glyphs.
        label.alpha = 0.0;
        UIView *parked = objc_getAssociatedObject(label, kDateLyricsMarqueeContainerKey);
        parked.hidden = YES;
    }
    [CATransaction commit];
    DateLyricsDebugLog(@"[DISPLAY:MORPH] direction=%@ sweep=%d duration=%.2f marqueeReturn=%d", enteringAOD ? @"fill" : @"unfill", sweep, duration, morph.marqueeTrack != nil);
    __weak _UIAnimatingLabel *weakLabel = label;
    NSTimeInterval completionDelay = MAX(0.0, handoffStart + duration - CACurrentMediaTime());
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(completionDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        _UIAnimatingLabel *current = weakLabel;
        if (!current || objc_getAssociatedObject(current, kDateLyricsDisplayMorphKey) != morph) return;
        CGFloat rejoinX = morph.marqueeX, rejoinVelocity = 0;
        if (morph.marqueeTrack) DateLyricsCaptureMarqueeMotion(morph.marqueeTrack.layer, &rejoinX, &rejoinVelocity);
        if (!gDateLyricsAlwaysOnDisplay) DateLyricsStopMarquee(current);
        DateLyricsCancelDisplayMorph(current);
        objc_setAssociatedObject(current, kDateLyricsRenderCacheKey, nil, OBJC_ASSOCIATION_ASSIGN);
        if (!gDateLyricsAlwaysOnDisplay && [gDateLyricsLocalAnchor[@"rate"] doubleValue] > 0.0 &&
            DateLyricsMeasuredLineWidth(current.attributedText.string ?: current.text, current.font) > CGRectGetWidth(current.bounds))
            objc_setAssociatedObject(current, kDateLyricsMarqueeWakeRejoinKey, @{@"line": morph.lineID, @"startX": @(rejoinX), @"velocity": @(rejoinVelocity), @"predicted": @YES}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [current _amlApplyCurrentLyric];
        DateLyricsRequestAODRefresh(@"display handoff finished");
    });
}

// a new lyric has different glyphs, so never reuse the outgoing snapshot.
// give it its own live fill/marquee within the original lock/wake window.
static void DateLyricsCancelLabelTransition(_UIAnimatingLabel *label);

static void DateLyricsContinueDisplayMorph(_UIAnimatingLabel *label, CFTimeInterval deadline) {
    if (deadline <= CACurrentMediaTime() || !label.window || !label.superview ||
        objc_getAssociatedObject(label, kDateLyricsDisplayMorphKey)) return;
    BOOL wordTimed = DateLyricsCurrentLineSupportsFillHandoff();
    NSString *text = label.attributedText.string ?: label.text;
    CGFloat viewport = CGRectGetWidth(label.bounds);
    BOOL scrolling = gDateLyricsMarqueeEnabled && !gDateLyricsSplitLongLines &&
        label.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionLeftToRight &&
        DateLyricsMeasuredLineWidth(text, label.font) > viewport + 0.5;
    if (!text.length || viewport <= 1 || (!wordTimed && !scrolling) ||
        label.effectiveUserInterfaceLayoutDirection != UIUserInterfaceLayoutDirectionLeftToRight) return;
    DateLyricsCancelLabelTransition(label);
    DateLyricsDisplayMorph *morph = [DateLyricsDisplayMorph new];
    morph.label = label; morph.lineID = gDateLyricsCurrentPayload[@"lineId"];
    morph.text = text; morph.wordTimed = wordTimed; morph.interrupted = YES;
    morph.deadline = deadline; morph.capturedMarquee = scrolling;
    UIView *bridge = [[UIView alloc] initWithFrame:label.frame]; bridge.clipsToBounds = YES;
    CGRect bounds = label.bounds;
    if (scrolling) bounds.size.width = DateLyricsMeasuredLineWidth(text, label.font);
    UIView *track = [[UIView alloc] initWithFrame:bounds];
    UILabel *base = DateLyricsCopyHandoffLabel(label); base.frame = track.bounds;
    if (scrolling) { base.textAlignment = NSTextAlignmentLeft; base.lineBreakMode = NSLineBreakByClipping; }
    UIColor *color = DateLyricsBaseTextColorForLabel(label);
    NSMutableAttributedString *dim = [base.attributedText mutableCopy];
    if (!dim) dim = [[NSMutableAttributedString alloc] initWithString:text];
    [dim addAttribute:NSForegroundColorAttributeName value:(wordTimed ? [color colorWithAlphaComponent:0.35] : color) range:NSMakeRange(0, dim.length)];
    base.attributedText = dim; [track addSubview:base];
    UILabel *filled = DateLyricsCopyHandoffLabel(base); filled.frame = track.bounds;
    NSMutableAttributedString *bright = [dim mutableCopy];
    [bright addAttribute:NSForegroundColorAttributeName value:color range:NSMakeRange(0, bright.length)];
    filled.attributedText = bright;
    [bridge addSubview:track]; morph.snapshot = bridge;
    morph.marqueeTrack = track; morph.marqueeFill = filled;
    morph.edge = 1;
    if (gDateLyricsAlwaysOnDisplay && wordTimed) {
        double elapsed = DateLyricsCurrentRenderElapsed();
        NSMutableDictionary *lanes = [NSMutableDictionary dictionary];
        for (NSString *lane in @[@"foreground", @"background"]) {
            CGFloat edge = DateLyricsPredictedLaneEdge(filled, lane, elapsed, 0);
            lanes[lane] = @{@"edge": @(edge), @"soft": @(edge), @"velocity": @0};
        }
        morph.laneStarts = lanes;
        morph.edge = [lanes[@"foreground"][@"edge"] doubleValue];
    }
    if (gDateLyricsAlwaysOnDisplay && scrolling) {
        // this line now completes its own journey to the tail. later, ordinary
        // aod lines still start at the prefix as before.
        gDateLyricsAODTailLine = morph.lineID;
        gDateLyricsAODTailTrack = [gDateLyricsLocalAnchor[@"trackId"] integerValue];
    }
    objc_setAssociatedObject(label, kDateLyricsDisplayMorphKey, morph, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DateLyricsRemoveProgressOverlay(label);
    DateLyricsStartDisplayMorph(morph, gDateLyricsAlwaysOnDisplay);
}

static NSUInteger DateLyricsBeginLabelTransition(_UIAnimatingLabel *label) {
    NSUInteger generation = [objc_getAssociatedObject(label, kDateLyricsTransitionGenerationKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(label, kDateLyricsTransitionGenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(label, kDateLyricsAnimatingTransitionKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // freeze a centered, stable-width frame until the transition completes.
    // changing backing-store geometry mid-crossfade produces overlapping text;
    // layoutsubviews reasserts this frame while the transition is active.
    CGRect frozen = label.frame;
    CGFloat stableWidth = DateLyricsSplitAvailableWidth(label);
    if (stableWidth > frozen.size.width) {
        frozen.origin.x -= (stableWidth - frozen.size.width) / 2.0;
        frozen.size.width = stableWidth;
    }
    if (!CGRectIsEmpty(frozen)) {
        objc_setAssociatedObject(label, kDateLyricsFrozenFrameKey, [NSValue valueWithCGRect:frozen], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        label.frame = frozen;
    }

    [label.layer removeAllAnimations];
    label.alpha = 1.0;
    label.transform = CGAffineTransformIdentity;
    label.clipsToBounds = YES;
    return generation;
}

static void DateLyricsSynchronizeOwnerVisibility(_UIAnimatingLabel *label) {
    if (![label isKindOfClass:UILabel.class]) return;
    UIView *container = objc_getAssociatedObject(label, kDateLyricsMarqueeContainerKey);
    DateLyricsDisplayMorph *handoff = objc_getAssociatedObject(label, kDateLyricsDisplayMorphKey);
    label.alpha = [container isKindOfClass:UIView.class] || handoff.marqueeTrack ? 0.0 : 1.0;
}

static void DateLyricsCancelLabelTransition(_UIAnimatingLabel *label) {
    UIView *outgoing = objc_getAssociatedObject(label, kDateLyricsOutgoingSnapshotKey);
    BOOL active = [objc_getAssociatedObject(label, kDateLyricsAnimatingTransitionKey) boolValue];
    if (!active && !outgoing && !objc_getAssociatedObject(label, kDateLyricsFrozenFrameKey)) return;
    NSUInteger generation = [objc_getAssociatedObject(label, kDateLyricsTransitionGenerationKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(label, kDateLyricsTransitionGenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [outgoing.layer removeAllAnimations]; [outgoing removeFromSuperview];
    objc_setAssociatedObject(label, kDateLyricsOutgoingSnapshotKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsAnimatingTransitionKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsFrozenFrameKey, nil, OBJC_ASSOCIATION_ASSIGN);
    [label.layer removeAllAnimations];
    UIView *marquee = objc_getAssociatedObject(label, kDateLyricsMarqueeContainerKey);
    [marquee.layer removeAllAnimations];
    marquee.transform = CGAffineTransformIdentity; marquee.alpha = 1.0;
    label.transform = CGAffineTransformIdentity;
    DateLyricsSynchronizeOwnerVisibility(label);
    objc_setAssociatedObject(label, kDateLyricsRenderCacheKey, nil, OBJC_ASSOCIATION_ASSIGN);
    [label setNeedsLayout];
}

static void DateLyricsFinishLabelTransitionAfterDelay(_UIAnimatingLabel *label, NSUInteger generation, NSTimeInterval duration) {
    __weak _UIAnimatingLabel *weakLabel = label;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        _UIAnimatingLabel *strongLabel = weakLabel;
        if (!strongLabel) return;
        NSUInteger currentGeneration = [objc_getAssociatedObject(strongLabel, kDateLyricsTransitionGenerationKey) unsignedIntegerValue];
        if (currentGeneration != generation) return;
        UIView *outgoingSnapshot = objc_getAssociatedObject(strongLabel, kDateLyricsOutgoingSnapshotKey);
        [outgoingSnapshot removeFromSuperview];
        objc_setAssociatedObject(strongLabel, kDateLyricsOutgoingSnapshotKey, nil, OBJC_ASSOCIATION_ASSIGN);
        [strongLabel.layer removeAnimationForKey:@"DateLyricsLineTransition"];

        strongLabel.transform = CGAffineTransformIdentity;
        objc_setAssociatedObject(strongLabel, kDateLyricsAnimatingTransitionKey, nil, OBJC_ASSOCIATION_ASSIGN);
        // release the pinned geometry; normal layout resumes on the next pass.
        objc_setAssociatedObject(strongLabel, kDateLyricsFrozenFrameKey, nil, OBJC_ASSOCIATION_ASSIGN);
        [strongLabel setNeedsLayout];
        if ([strongLabel respondsToSelector:@selector(_amlApplyCurrentLyric)]) {
            DateLyricsForceApplyDateLabel(strongLabel, DateLyricsCacheInvalidationReasonTransitionCompletion);
        }

        DateLyricsSynchronizeOwnerVisibility(strongLabel);
    });
}

// lineid is either a numeric line-start time or "line-start#split-segment".
// compare both pieces so scrubbing backwards within a split line also reverses
// the visual direction.
static NSComparisonResult DateLyricsCompareLineIdentity(id leftIdentity, id rightIdentity) {
    NSString *left = [leftIdentity description] ?: @"";
    NSString *right = [rightIdentity description] ?: @"";
    NSArray<NSString *> *leftParts = [left componentsSeparatedByString:@"#"];
    NSArray<NSString *> *rightParts = [right componentsSeparatedByString:@"#"];
    double leftTime = leftParts.firstObject.doubleValue;
    double rightTime = rightParts.firstObject.doubleValue;
    if (fabs(leftTime - rightTime) > 0.0001) {
        return leftTime < rightTime ? NSOrderedAscending : NSOrderedDescending;
    }
    NSInteger leftSegment = leftParts.count > 1 ? leftParts[1].integerValue : 0;
    NSInteger rightSegment = rightParts.count > 1 ? rightParts[1].integerValue : 0;
    if (leftSegment == rightSegment) return NSOrderedSame;
    return leftSegment < rightSegment ? NSOrderedAscending : NSOrderedDescending;
}

// a live stand-in for the outgoing line, used instead of a still snapshot whenever a progressive
// fill is mid-sweep: a copy of the label text plus a copy of each active overlay and mask, with
// every mask carried on to the end of its word. covers foreground syllables and ad-lib lanes
// alike (each lane is its own overlay slot). returns nil when there is nothing mid-fill, in
// which case the plain snapshot is exactly right.
static UIView *DateLyricsBuildOutgoingFillReplica(_UIAnimatingLabel *label) {
    NSArray<DateLyricsProgressOverlaySlot *> *pool = objc_getAssociatedObject(label, kDateLyricsProgressSlotPoolKey);
    NSMutableArray<DateLyricsProgressOverlaySlot *> *live = [NSMutableArray array];
    for (DateLyricsProgressOverlaySlot *slot in pool) {
        if (slot.inUse && !slot.overlayLabel.hidden && slot.overlayLabel.superview == label && slot.maskLayer) {
            [live addObject:slot];
        }
    }
    if (live.count == 0 || CGRectGetWidth(label.bounds) < 1.0) return nil;

    UIView *container = [[UIView alloc] initWithFrame:label.frame];
    container.userInteractionEnabled = NO;

    UILabel *base = [[UILabel alloc] initWithFrame:label.bounds];
    base.numberOfLines = label.numberOfLines;
    base.lineBreakMode = label.lineBreakMode;
    base.textAlignment = label.textAlignment;
    base.adjustsFontSizeToFitWidth = label.adjustsFontSizeToFitWidth;
    base.minimumScaleFactor = label.minimumScaleFactor;
    base.font = label.font;
    base.textColor = label.textColor;
    base.backgroundColor = UIColor.clearColor;
    if (label.attributedText) base.attributedText = label.attributedText; else base.text = label.text;
    [container addSubview:base];

    CFTimeInterval now = CACurrentMediaTime();
    for (DateLyricsProgressOverlaySlot *slot in live) {
        UILabel *source = slot.overlayLabel;
        UILabel *overlay = [[UILabel alloc] initWithFrame:source.frame];
        overlay.numberOfLines = source.numberOfLines;
        overlay.lineBreakMode = source.lineBreakMode;
        overlay.textAlignment = source.textAlignment;
        overlay.font = source.font;
        overlay.backgroundColor = UIColor.clearColor;
        overlay.attributedText = source.attributedText;

        CAGradientLayer *src = slot.maskLayer;
        CAGradientLayer *presentation = (CAGradientLayer *)src.presentationLayer;
        NSArray *from = presentation.locations.count == 4 ? presentation.locations : src.locations;

        CAGradientLayer *mask = [CAGradientLayer layer];
        mask.startPoint = src.startPoint;
        mask.endPoint = src.endPoint;
        mask.colors = src.colors;
        mask.frame = overlay.bounds;
        mask.actions = @{ @"locations": NSNull.null, @"bounds": NSNull.null, @"position": NSNull.null };
        mask.locations = from;
        overlay.layer.mask = mask;
        [container addSubview:overlay];

        CAAnimation *running = [src animationForKey:@"DateLyricsProgressFill"];
        NSArray *target = DateLyricsAnimTag(running, @"dlTarget");
        double remaining = [DateLyricsAnimTag(running, @"dlEndMedia") doubleValue] - now;
        if (target.count == 4 && from.count == 4 && remaining > 0.01) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            mask.locations = target;
            [CATransaction commit];
            CABasicAnimation *finish = [CABasicAnimation animationWithKeyPath:@"locations"];
            finish.fromValue = from;
            finish.toValue = target;
            finish.duration = remaining;
            finish.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
            finish.fillMode = kCAFillModeBoth;
            finish.removedOnCompletion = NO;
            [mask addAnimation:finish forKey:@"DateLyricsOutgoingFill"];
        }
    }
    return container;
}

static void DateLyricsAnimateLabelTransition(_UIAnimatingLabel *label, NSString *previousDisplayText, NSString *displayText, NSAttributedString *attrDisplayText, BOOL reverseDirection, BOOL willMarquee, CGFloat marqueeOverflow, NSDictionary *marqueePayload, id marqueeLineId) {
    if (![label isKindOfClass:UILabel.class]) {
        DateLyricsStopMarquee(label);
        DateLyricsApplyLabelContent(label, displayText, attrDisplayText, YES);
        return;
    }

    NSTimeInterval duration = MAX(0.0, gDateLyricsTransitionDuration);
    if (!DateLyricsTransitionsAvailable() || gDateLyricsDisplayWakeInProgress ||
        objc_getAssociatedObject(label, kDateLyricsDisplayMorphKey) || duration <= 0.0 || previousDisplayText.length == 0) {
        DateLyricsCancelLabelTransition(label);
        DateLyricsStopMarquee(label);
        [label.layer removeAllAnimations];
        label.alpha = 1.0;
        label.transform = CGAffineTransformIdentity;
        objc_setAssociatedObject(label, kDateLyricsAnimatingTransitionKey, nil, OBJC_ASSOCIATION_ASSIGN);
        DateLyricsApplyLabelContent(label, displayText, attrDisplayText, YES);
        if (willMarquee) {
            BOOL didRebuild = NO;
            if (DateLyricsStartMarquee(label, marqueeOverflow, marqueePayload, &didRebuild)) {
                objc_setAssociatedObject(label, kDateLyricsMarqueeLineIdKey, marqueeLineId, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(label, kDateLyricsMarqueeAnchorGenerationKey, @(gDateLyricsAnchorGeneration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        DateLyricsSynchronizeOwnerVisibility(label);
        return;
    }

    UIView *oldSnapshot = objc_getAssociatedObject(label, kDateLyricsOutgoingSnapshotKey);
    [oldSnapshot removeFromSuperview];
    // 1. capture the outgoing visual (existing marquee or plain label snapshot).
    UIView *outgoingSnapshot = DateLyricsDetachMarquee(label);
    NSUInteger generation = DateLyricsBeginLabelTransition(label);

    if (!outgoingSnapshot) {
        // a mid-fill line is carried on by a live copy so its fill keeps sweeping to the end of
        // the word as it leaves; otherwise a plain still snapshot is exactly right.
        outgoingSnapshot = DateLyricsBuildOutgoingFillReplica(label);
        if (!outgoingSnapshot) {
            outgoingSnapshot = [label snapshotViewAfterScreenUpdates:NO];
            outgoingSnapshot.frame = label.frame;
        }
    }

    DateLyricsApplyLabelContent(label, displayText, attrDisplayText, YES);
    [label layoutIfNeeded];

    if (outgoingSnapshot && label.superview) {
        outgoingSnapshot.userInteractionEnabled = NO;
        [label.superview insertSubview:outgoingSnapshot belowSubview:label];
        objc_setAssociatedObject(label, kDateLyricsOutgoingSnapshotKey, outgoingSnapshot, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // 2. apply the new line content to the label so the marquee is seeded correctly.
    [UIView performWithoutAnimation:^{
        [label layoutIfNeeded];
    }];

    // 3. build the incoming marquee (now using the new line's text).
    if (willMarquee) {
        BOOL didRebuild = NO;
        if (DateLyricsStartMarquee(label, marqueeOverflow, marqueePayload, &didRebuild)) {
            objc_setAssociatedObject(label, kDateLyricsMarqueeLineIdKey, marqueeLineId, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(label, kDateLyricsMarqueeAnchorGenerationKey, @(gDateLyricsAnchorGeneration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    // 4. animate the live incoming visual (container when marquee was built, otherwise the label).
    UIView *incomingContainer = objc_getAssociatedObject(label, kDateLyricsMarqueeContainerKey);
    UIView *targetView = incomingContainer ?: label;

    UIViewAnimationOptions options = UIViewAnimationOptionBeginFromCurrentState |
                                     UIViewAnimationOptionAllowUserInteraction |
                                     UIViewAnimationOptionCurveEaseInOut;

    switch (gDateLyricsTransitionStyle) {
        case DateLyricsTransitionStyleFade: {
            targetView.alpha = 0.0;
            if (incomingContainer) label.alpha = 0.0;
            [UIView animateKeyframesWithDuration:duration delay:0.0 options:UIViewKeyframeAnimationOptionCalculationModeCubic animations:^{
                [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.45 animations:^{
                    outgoingSnapshot.alpha = 0.0;
                }];
                [UIView addKeyframeWithRelativeStartTime:0.55 relativeDuration:0.45 animations:^{
                    targetView.alpha = 1.0;
                }];
            } completion:nil];
            break;
        }
        case DateLyricsTransitionStyleSlideUp:
        case DateLyricsTransitionStyleSlideDown:
        case DateLyricsTransitionStylePush: {
            CGFloat dx = 0.0;
            CGFloat dy = 0.0;
            if (gDateLyricsTransitionStyle == DateLyricsTransitionStyleSlideUp) {
                dy = reverseDirection ? -CGRectGetHeight(label.bounds) : CGRectGetHeight(label.bounds);
            } else if (gDateLyricsTransitionStyle == DateLyricsTransitionStylePush) {
                dx = reverseDirection ? -CGRectGetWidth(label.bounds) : CGRectGetWidth(label.bounds);
            } else {
                dy = reverseDirection ? CGRectGetHeight(label.bounds) : -CGRectGetHeight(label.bounds);
            }
            targetView.transform = CGAffineTransformMakeTranslation(dx, dy);
            targetView.alpha = 0.0;
            if (incomingContainer) label.alpha = 0.0;
            [UIView animateWithDuration:duration delay:0.0 options:options animations:^{
                targetView.transform = CGAffineTransformIdentity;
                targetView.alpha = 1.0;
                outgoingSnapshot.transform = CGAffineTransformMakeTranslation(-dx, -dy);
                outgoingSnapshot.alpha = 0.0;
            } completion:nil];
            break;
        }
        case DateLyricsTransitionStylePop: {
            CGFloat incomingScale = reverseDirection ? 1.1 : 0.9;
            CGFloat outgoingScale = reverseDirection ? 0.9 : 1.1;
            targetView.transform = CGAffineTransformMakeScale(incomingScale, incomingScale);
            targetView.alpha = 0.0;
            if (incomingContainer) label.alpha = 0.0;
            [UIView animateKeyframesWithDuration:duration delay:0.0 options:UIViewKeyframeAnimationOptionCalculationModeCubic animations:^{
                [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.42 animations:^{
                    outgoingSnapshot.transform = CGAffineTransformMakeScale(outgoingScale, outgoingScale);
                    outgoingSnapshot.alpha = 0.0;
                }];
                [UIView addKeyframeWithRelativeStartTime:0.5 relativeDuration:0.5 animations:^{
                    targetView.transform = CGAffineTransformIdentity;
                    targetView.alpha = 1.0;
                }];
            } completion:nil];
            break;
        }
        default: {
            break;
        }
    }
    DateLyricsFinishLabelTransitionAfterDelay(label, generation, duration);
}

static UIView *DateLyricsDetachMarquee(_UIAnimatingLabel *label) {
    if (![label isKindOfClass:UILabel.class]) return nil;

    UIView *container = objc_getAssociatedObject(label, kDateLyricsMarqueeContainerKey);
    UIView *track = objc_getAssociatedObject(label, kDateLyricsMarqueeTrackKey);
    if (![track isKindOfClass:UIView.class]) track = objc_getAssociatedObject(label, kDateLyricsMarqueeContentLabelKey);

    if (!container && !track &&
        ![objc_getAssociatedObject(label, kDateLyricsMarqueeActiveKey) boolValue]) {
        return nil;
    }

    DateLyricsDebugMarqueeState(label, @"detach-before", nil);
    // the track's scroll animation is left running: the detached container is the outgoing line
    // for the length of the transition, so it keeps scrolling (and its fills keep sweeping)
    // while the new line comes in. the animation carries fillmode both and the model already
    // rests at the end of the scroll, so nothing snaps when it finishes.

    // the gradient masks are deliberately left running. the detached container is the outgoing
    // line for the length of the transition, and its fills keep sweeping to the end of their
    // words while the new line comes in, instead of stopping dead mid-syllable.
    NSMutableArray<DateLyricsProgressOverlaySlot *> *pool = objc_getAssociatedObject(label, kDateLyricsProgressSlotPoolKey);

    // if the overlays live inside the detaching container, disown them from
    // the label associations without removing them – the container keeps them
    // alive until the whole outgoing snapshot is dismissed.
    BOOL overlaysInContainer = NO;
    for (DateLyricsProgressOverlaySlot *slot in pool) {
        if (slot.inUse && container && [slot.overlayLabel isDescendantOfView:container]) {
            overlaysInContainer = YES;
            break;
        }
    }
    if (overlaysInContainer) {
        objc_setAssociatedObject(label, kDateLyricsProgressSlotPoolKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }

    objc_setAssociatedObject(label, kDateLyricsMarqueeContainerKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsMarqueeContentLabelKey, nil, OBJC_ASSOCIATION_ASSIGN);
    if (track) {
        NSUInteger gen = [objc_getAssociatedObject(label, kDateLyricsMarqueeRunGenerationKey) unsignedIntegerValue] + 1;
        objc_setAssociatedObject(label, kDateLyricsMarqueeRunGenerationKey, @(gen), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    objc_setAssociatedObject(label, kDateLyricsMarqueeTrackKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsMarqueeLineIdKey, nil, OBJC_ASSOCIATION_ASSIGN);
    if ([objc_getAssociatedObject(label, kDateLyricsMarqueeActiveKey) boolValue]) {
        objc_setAssociatedObject(label, kDateLyricsMarqueeActiveKey, nil, OBJC_ASSOCIATION_ASSIGN);
        gDateLyricsActiveMarqueeCount = MAX(0, gDateLyricsActiveMarqueeCount - 1);
    }
    objc_setAssociatedObject(label, kDateLyricsMarqueeSkippedLineIdKey, nil, OBJC_ASSOCIATION_ASSIGN);
    DateLyricsClearFrozenMarquee(label);
    DateLyricsSynchronizeOwnerVisibility(label);
    return container;
}

static void DateLyricsStopMarquee(_UIAnimatingLabel *label) {
    UIView *container = DateLyricsDetachMarquee(label);
    [container removeFromSuperview];
}

static const NSTimeInterval kDateLyricsMarqueeHoldPad   = 0.15;
static const CGFloat        kDateLyricsMarqueeMaxSpeed  = 90.0;
static const NSTimeInterval kDateLyricsMarqueeMinScroll = 0.60;

static NSTimeInterval DateLyricsMarqueeHoldForLine(NSTimeInterval timelineDuration, CGFloat overflow) {
    NSTimeInterval desired = MAX(0.0, gDateLyricsTransitionDuration) + kDateLyricsMarqueeHoldPad;
    if (timelineDuration <= 0.0) return desired;

    NSTimeInterval needScroll = MAX(kDateLyricsMarqueeMinScroll,
                                    (NSTimeInterval)(MAX(0.0, overflow) / kDateLyricsMarqueeMaxSpeed));
    NSTimeInterval maxHold = timelineDuration - needScroll;
    // the window is already too tight to scroll at kdatelyricsmarqueemaxspeed.
    // holding half of it and racing the rest is strictly worse than simply
    // using the whole window, which halves the speed the scroll has to run at.
    if (maxHold <= 0.0) return 0.0;
    return MIN(desired, maxHold);
}

static CGFloat DateLyricsMarqueeXForPhase(NSTimeInterval phase, NSTimeInterval timelineDuration, NSTimeInterval holdDuration, CGFloat overflow) {
    NSTimeInterval scroll = timelineDuration - holdDuration;
    if (scroll <= 0.0001) return 0.0;
    if (phase <= holdDuration) return 0.0;
    if (phase >= timelineDuration) return -overflow;
    double t = (phase - holdDuration) / scroll;
    double ease = t * t * (3.0 - 2.0 * t);
    return -overflow * ease;
}

static CGFloat DateLyricsMarqueeVelocityForPhase(NSTimeInterval phase, NSTimeInterval timelineDuration, NSTimeInterval holdDuration, CGFloat overflow, double rate) {
    double scroll = timelineDuration - holdDuration;
    if (scroll <= 0.0001 || phase <= holdDuration || phase >= timelineDuration) return 0;
    double t = (phase - holdDuration) / scroll;
    return -overflow * 6 * t * (1 - t) * MAX(0.0, rate) / scroll;
}

// correct the running curve rather than starting a second independent ease.
// the correction matches captured position/speed at entry and disappears with
// zero slope at completion, joining the live position and speed together.
static CGFloat DateLyricsMarqueeHandoffWakeMotionX(NSTimeInterval phase, NSTimeInterval entryPhase, NSTimeInterval timelineDuration, NSTimeInterval holdDuration, CGFloat overflow, double rate, CGFloat startX, CGFloat startVelocity, NSTimeInterval duration) {
    CGFloat target = DateLyricsMarqueeXForPhase(phase, timelineDuration, holdDuration, overflow);
    double wallTime = MAX(0.0, (phase - entryPhase) / MAX(0.01, rate));
    double window = MAX(0.001, duration);
    double t = MIN(1.0, wallTime / window);
    CGFloat start = MAX(-overflow, MIN(0.0, startX));
    CGFloat liveStart = DateLyricsMarqueeXForPhase(entryPhase, timelineDuration, holdDuration, overflow);
    CGFloat liveVelocity = DateLyricsMarqueeVelocityForPhase(entryPhase, timelineDuration, holdDuration, overflow, rate);
    double positionWeight = 1 - t*t*(3 - 2*t);
    double velocityWeight = t*(1-t)*(1-t);
    CGFloat x = target + (start-liveStart)*positionWeight + (startVelocity-liveVelocity)*window*velocityWeight;
    return MAX(-overflow, MIN(0.0, x));
}

// the display animation keeps advancing while playback is paused. its target
// remains at the paused lyric time; only playing songs forecast a future phase.
static CGFloat DateLyricsMarqueeWakePhaseX(double phase, double entryPhase, double timeline, double hold, CGFloat overflow, double rate, CGFloat start, CGFloat velocity, double duration) {
    if (rate > 0)
        return DateLyricsMarqueeHandoffWakeMotionX(entryPhase + phase * duration * rate, entryPhase, timeline, hold, overflow, rate, start, velocity, duration);
    CGFloat end = DateLyricsMarqueeXForPhase(entryPhase, timeline, hold, overflow);
    return DateLyricsMarqueeContinuationX(start, end, velocity, duration, phase);
}

static CGFloat DateLyricsMarqueeHandoffWakeX(NSTimeInterval phase, NSTimeInterval entryPhase, NSTimeInterval timelineDuration, NSTimeInterval holdDuration, CGFloat overflow, double rate, CGFloat startX, NSTimeInterval duration) {
    NSTimeInterval remaining = (timelineDuration - entryPhase) / MAX(0.01, rate);
    return DateLyricsMarqueeHandoffWakeMotionX(phase, entryPhase, timelineDuration, holdDuration, overflow, rate, startX, 0, MIN(duration, MAX(0.001, remaining)));
}

static CGFloat DateLyricsMarqueeWakeX(NSTimeInterval phase, NSTimeInterval entryPhase, NSTimeInterval timelineDuration, NSTimeInterval holdDuration, CGFloat overflow, double rate, CGFloat startX) {
    return DateLyricsMarqueeHandoffWakeX(phase, entryPhase, timelineDuration, holdDuration, overflow, rate, startX, 0.35);
}

static NSTimeInterval DateLyricsMarqueePhaseForX(CGFloat x, NSTimeInterval timelineDuration, NSTimeInterval holdDuration, CGFloat overflow) {
    if (x >= 0.0) return 0.0;
    if (x <= -overflow) return timelineDuration;
    if (timelineDuration <= holdDuration) return 0.0;

    NSTimeInterval low = holdDuration;
    NSTimeInterval high = timelineDuration;
    for (int i = 0; i < 20; i++) {
        NSTimeInterval mid = (low + high) * 0.5;
        CGFloat midX = DateLyricsMarqueeXForPhase(mid, timelineDuration, holdDuration, overflow);
        if (midX > x) {
            low = mid;
        } else {
            high = mid;
        }
    }
    return (low + high) * 0.5;
}

static void DateLyricsFreezeMarquee(_UIAnimatingLabel *label) {
    if (![label isKindOfClass:UILabel.class]) return;

    DateLyricsDebugMarqueeState(label, @"freeze-before", nil);

    UIView *track = objc_getAssociatedObject(label, kDateLyricsMarqueeTrackKey);
    if (![track isKindOfClass:UIView.class]) track = objc_getAssociatedObject(label, kDateLyricsMarqueeContentLabelKey);
    if ([track isKindOfClass:UIView.class]) {
        CALayer *layer = track.layer;
        CGFloat xNow = 0, velocity = 0;
        DateLyricsCaptureMarqueeMotion(layer, &xNow, &velocity);
        UIView *container = objc_getAssociatedObject(label, kDateLyricsMarqueeContainerKey);
        CGFloat overflow = container ? CGRectGetWidth(track.bounds) - CGRectGetWidth(container.bounds) : 0.0;

        static const NSTimeInterval kMarqueeSettleDuration = 0.20;

        NSTimeInterval timelineDuration = [objc_getAssociatedObject(label, kDateLyricsMarqueeDurationKey) doubleValue];
        NSTimeInterval holdDuration     = [objc_getAssociatedObject(label, kDateLyricsMarqueeHoldKey) doubleValue];

        BOOL canGlide = overflow > 0.5 && timelineDuration > 0.0 && fabs(velocity) > 0.01;
        NSTimeInterval glideDuration = kMarqueeSettleDuration;
        CGFloat xSettled = MAX(-overflow, MIN(0.0, xNow + velocity * glideDuration * 0.5));
        if (!canGlide) xSettled = xNow;
        else glideDuration = MIN(glideDuration, 2 * fabs(xSettled - xNow) / fabs(velocity));
        NSTimeInterval settledPhase = DateLyricsMarqueePhaseForX(xSettled, timelineDuration, holdDuration, overflow);

        NSUInteger gen = [objc_getAssociatedObject(label, kDateLyricsMarqueeRunGenerationKey) unsignedIntegerValue] + 1;
        objc_setAssociatedObject(label, kDateLyricsMarqueeRunGenerationKey, @(gen), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        [CATransaction begin]; [CATransaction setDisableActions:YES];
        [layer removeAnimationForKey:@"DateLyricsMarquee"];
        [layer removeAnimationForKey:@"DateLyricsMarqueeSettle"];
        layer.transform = CATransform3DMakeTranslation(xSettled, 0, 0);
        [CATransaction commit];

        if (canGlide && glideDuration > 0.001 && fabs(xSettled - xNow) > 0.01) {
            CABasicAnimation *stop = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
            stop.fromValue = @(xNow);
            stop.toValue = @(xSettled);
            stop.duration = glideDuration;
            stop.beginTime = [layer convertTime:CACurrentMediaTime() fromLayer:nil];
            stop.timingFunction = DateLyricsQuadEaseOut();
            [layer addAnimation:stop forKey:@"DateLyricsMarqueeSettle"];
        }

        // store settled position for resume.
        objc_setAssociatedObject(label, kDateLyricsMarqueeFrozenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        objc_setAssociatedObject(label, kDateLyricsMarqueeFrozenSettledXKey, @(xSettled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(label, kDateLyricsMarqueeFrozenSettledPhaseKey, @(settledPhase), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        DateLyricsDebugLog(@"MARQUEE freeze label=%@ xNow=%.2f xSettled=%.2f settledPhase=%.3f",
                           objc_getAssociatedObject(label, kDateLyricsMarqueeLineIdKey) ?: @"-", xNow, xSettled, settledPhase);
    }

    DateLyricsDebugMarqueeState(label, @"freeze-after", nil);
}

static void DateLyricsFreezeAllMarquees(void) {
    for (CSProminentSubtitleDateView *dateView in gDateLyricsDateViews) {
        if ([dateView isKindOfClass:UIView.class]) DateLyricsFreezeMarquee(DateLyricsFindAnimatingLabel(dateView));
    }
    for (UIView *slot in gDateLyricsWidgetSlots) {
        if ([slot isKindOfClass:UIView.class]) DateLyricsFreezeMarquee(DateLyricsFindAnimatingLabel(slot));
    }
}

static void DateLyricsClearFrozenMarquee(_UIAnimatingLabel *label) {
    if (![label isKindOfClass:UILabel.class]) return;

    objc_setAssociatedObject(label, kDateLyricsMarqueeFrozenKey, nil, OBJC_ASSOCIATION_ASSIGN);

    objc_setAssociatedObject(label, kDateLyricsMarqueeFrozenSettledXKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsMarqueeFrozenSettledPhaseKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static void DateLyricsClearAllFrozenMarquees(void) {
    for (CSProminentSubtitleDateView *dateView in gDateLyricsDateViews) {
        _UIAnimatingLabel *label = [dateView isKindOfClass:UIView.class] ? DateLyricsFindAnimatingLabel(dateView) : nil;
        if (label) DateLyricsClearFrozenMarquee(label);
    }
    for (UIView *slot in gDateLyricsWidgetSlots) {
        _UIAnimatingLabel *label = [slot isKindOfClass:UIView.class] ? DateLyricsFindAnimatingLabel(slot) : nil;
        if (label) DateLyricsClearFrozenMarquee(label);
    }
}


static void DateLyricsRefreshMarqueeContent(_UIAnimatingLabel *label) {
    UILabel *contentLabel = objc_getAssociatedObject(label, kDateLyricsMarqueeContentLabelKey);
    if (![contentLabel isKindOfClass:UILabel.class]) return;

    if (![contentLabel.font isEqual:label.font]) contentLabel.font = label.font;
    contentLabel.textColor = label.textColor;
    if (label.attributedText) {
        if (![contentLabel.attributedText isEqualToAttributedString:label.attributedText])
            contentLabel.attributedText = label.attributedText;
    } else if (![contentLabel.text isEqualToString:label.text]) {
        contentLabel.text = label.text;
    }
}

// a static viewport uses the same full-width geometry as the lock animation.
// no core animation motion, active marquee count or ticking is started here.
static BOOL DateLyricsHoldAODTail(_UIAnimatingLabel *label) {
    CGFloat width = CGRectGetWidth(label.bounds);
    CGFloat textWidth = DateLyricsMeasuredLineWidth(label.attributedText.string ?: label.text, label.font);
    if (!label.superview || textWidth <= width + 0.5 || width <= 1.0) return NO;
    UIView *container = objc_getAssociatedObject(label, kDateLyricsMarqueeContainerKey);
    UIView *track = objc_getAssociatedObject(label, kDateLyricsMarqueeTrackKey);
    UILabel *content = objc_getAssociatedObject(label, kDateLyricsMarqueeContentLabelKey);
    if (!container || !track || !content) {
        container = [[UIView alloc] initWithFrame:label.frame]; container.clipsToBounds = YES; container.userInteractionEnabled = NO;
        track = [UIView new]; content = DateLyricsCopyHandoffLabel(label);
        content.textAlignment = NSTextAlignmentLeft; content.lineBreakMode = NSLineBreakByClipping;
        [track addSubview:content]; [container addSubview:track];
        [label.superview insertSubview:container aboveSubview:label];
        objc_setAssociatedObject(label, kDateLyricsMarqueeContainerKey, container, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(label, kDateLyricsMarqueeTrackKey, track, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(label, kDateLyricsMarqueeContentLabelKey, content, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    container.frame = label.frame;
    track.bounds = CGRectMake(0, 0, textWidth, CGRectGetHeight(label.bounds));
    track.center = CGPointMake(textWidth * 0.5, CGRectGetHeight(label.bounds) * 0.5);
    content.frame = track.bounds;
    track.layer.transform = CATransform3DMakeTranslation(-(textWidth - width), 0, 0);
    [CATransaction commit];
    DateLyricsDisplayMorph *handoff = objc_getAssociatedObject(label, kDateLyricsDisplayMorphKey);
    // regular lyric ticks may refresh this parked tail during wake. keep it
    // hidden until the moving handoff releases ownership of the glyphs.
    container.hidden = handoff != nil;
    DateLyricsRefreshMarqueeContent(label); DateLyricsSynchronizeOwnerVisibility(label);
    return YES;
}

// render the full line in an isolated clipped overlay. the stock label remains
// available for vertical/scale transitions, so marquee and line animations never
// compete for the same transform.

static BOOL DateLyricsStartMarquee(_UIAnimatingLabel *label, CGFloat overflow, NSDictionary *payload, BOOL *didRebuild) {
    if (didRebuild) *didRebuild = NO;
    if (![label isKindOfClass:UILabel.class] || !label.superview) return NO;
    if (overflow <= 0.5) return NO;

    DateLyricsDebugMarqueeState(label, @"start-enter", payload);

    BOOL wasFrozen = [objc_getAssociatedObject(label, kDateLyricsMarqueeFrozenKey) boolValue];
    UIView *existingTrack = objc_getAssociatedObject(label, kDateLyricsMarqueeTrackKey);
    if ([existingTrack isKindOfClass:UIView.class]) {
        id existingLineId = objc_getAssociatedObject(label, kDateLyricsMarqueeLineIdKey);
        id payloadLineId = payload[@"lineId"];
        UIView *existingContainer = objc_getAssociatedObject(label, kDateLyricsMarqueeContainerKey);
        CGFloat existingViewportWidth = CGRectGetWidth(existingContainer.bounds);
        CGFloat existingOverflow = CGRectGetWidth(existingTrack.bounds) - existingViewportWidth;
        BOOL sameLine = existingLineId && payloadLineId && (existingLineId == payloadLineId || [existingLineId isEqual:payloadLineId]);

        UILabel *existingContentLabel = objc_getAssociatedObject(label, kDateLyricsMarqueeContentLabelKey);
        NSString *existingText = existingContentLabel.text ?: existingContentLabel.attributedText.string;
        NSString *payloadText = payload[@"text"];
        BOOL sameText = (!existingText && !payloadText) || (existingText && payloadText && [existingText isEqualToString:payloadText]);

        BOOL identityOK = sameLine && sameText &&
                          fabs(existingViewportWidth - CGRectGetWidth(label.bounds)) < 0.5 &&
                          fabs(existingOverflow - overflow) < 0.5;
        if (!identityOK) {
            DateLyricsDebugMarqueeState(label, @"identity-failed", payload);
            DateLyricsStopMarquee(label);
            // fall through to rebuild below.
        } else if (!wasFrozen) {
            DateLyricsDebugMarqueeState(label, @"reuse-existing", payload);
            return YES;
        } else {
            double rate = MAX(0.0, [gDateLyricsLocalAnchor[@"rate"] doubleValue]);
            if (rate <= 0.0) {
                DateLyricsDebugMarqueeState(label, @"paused-hold", payload);
                return YES;
            }
            DateLyricsDebugMarqueeState(label, @"resume-before", payload);

            NSTimeInterval elapsed = DateLyricsCurrentRenderElapsed();
            NSTimeInterval marqueeOrigin = [objc_getAssociatedObject(label, kDateLyricsMarqueeOriginKey) doubleValue];
            NSTimeInterval timelineDuration = [objc_getAssociatedObject(label, kDateLyricsMarqueeDurationKey) doubleValue];
            NSTimeInterval holdDuration = [objc_getAssociatedObject(label, kDateLyricsMarqueeHoldKey) doubleValue];

            CGFloat settledX = [objc_getAssociatedObject(label, kDateLyricsMarqueeFrozenSettledXKey) doubleValue];
            CGFloat resumeOverflow = CGRectGetWidth(existingTrack.bounds) - CGRectGetWidth(existingContainer.bounds);

            NSNumber *storedPhase = objc_getAssociatedObject(label, kDateLyricsMarqueeFrozenSettledPhaseKey);
            NSTimeInterval settledPhase = storedPhase
                ? storedPhase.doubleValue
                : MIN(timelineDuration, MAX(0.0, elapsed - marqueeOrigin));

            NSTimeInterval mediaPhase = MAX(0.0, elapsed - marqueeOrigin);
            NSTimeInterval wallRemaining = MAX(0.0, (timelineDuration - mediaPhase) / rate);

            NSUInteger gen = [objc_getAssociatedObject(label, kDateLyricsMarqueeRunGenerationKey) unsignedIntegerValue] + 1;
            objc_setAssociatedObject(label, kDateLyricsMarqueeRunGenerationKey, @(gen), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            DateLyricsClearFrozenMarquee(label);

            NSTimeInterval settleRemaining = 0.0;
            CAAnimation *settle = [existingTrack.layer animationForKey:@"DateLyricsMarqueeSettle"];
            if (settle) {
                CFTimeInterval localNow = [existingTrack.layer convertTime:CACurrentMediaTime() fromLayer:nil];
                settleRemaining = MAX(0.0, settle.duration - (localNow - settle.beginTime));
            }

            __weak _UIAnimatingLabel *weakLabel = label;
            __weak UIView *weakTrack = existingTrack;
            void (^launch)(void) = ^{
                _UIAnimatingLabel *strongLabel = weakLabel;
                UIView *strongTrack = weakTrack;
                if (!strongLabel || !strongTrack) return;
                if ([objc_getAssociatedObject(strongLabel, kDateLyricsMarqueeRunGenerationKey) unsignedIntegerValue] != gen) return;
                NSTimeInterval launchPhase = MAX(0.0, DateLyricsCurrentRenderElapsed() - marqueeOrigin);
                NSTimeInterval remaining = MAX(0.0, (timelineDuration - launchPhase) / rate);
                [strongTrack.layer removeAnimationForKey:@"DateLyricsMarqueeSettle"];
                [CATransaction begin]; [CATransaction setDisableActions:YES];
                strongTrack.layer.transform = CATransform3DMakeTranslation(-resumeOverflow, 0, 0);
                [CATransaction commit];
                if (remaining > 1.0 / 60.0) {
                    NSMutableArray *vals = [NSMutableArray array];
                    const NSInteger kSteps = 60;
                    // accelerate out of the pause: warp the sampled time so speed ramps up from
                    // rest over a short window, then continues at the line's own pace and still
                    // lands on the line's end.  mirrors the decelerating glide on pause.
                    // the pause glide parked the track slightly ahead of the line's clock.  hold
                    // still until the clock reaches it, then accelerate from rest.
                    NSTimeInterval holdTime = MIN(MIN(MAX(0.0, (settledPhase - launchPhase) / rate), 0.30),
                                                  remaining * 0.5);
                    NSTimeInterval activeTime = remaining - holdTime;
                    double rampFraction = activeTime > 0.15
                        ? MIN(kDateLyricsResumeRampDuration, activeTime * 0.5) / activeTime : 0.0;
                    for (NSInteger i = 0; i <= kSteps; i++) {
                        NSTimeInterval t = remaining * ((double)i / kSteps);
                        double warped = t <= holdTime ? 0.0
                            : DateLyricsEaseInProfile((t - holdTime) / activeTime, rampFraction);
                        NSTimeInterval p = settledPhase + (timelineDuration - settledPhase) * warped;
                        [vals addObject:@(DateLyricsMarqueeXForPhase(p, timelineDuration, holdDuration, resumeOverflow))];
                    }
                    CAKeyframeAnimation *go = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
                    go.values = vals;
                    go.calculationMode = kCAAnimationLinear;
                    go.duration = remaining;
                    go.beginTime = [strongTrack.layer convertTime:CACurrentMediaTime() fromLayer:nil];
                    go.removedOnCompletion = NO;
                    go.fillMode = kCAFillModeBoth;
                    [strongTrack.layer addAnimation:go forKey:@"DateLyricsMarquee"];
                    DateLyricsScheduleMarqueeProbe(strongLabel, strongTrack, payload, remaining + 0.05, @"resume-end+50ms", gen);
                }
            };

            NSTimeInterval totalDelay = settleRemaining;
            if (totalDelay > 0.001) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(totalDelay * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), launch);
            } else {
                launch();
            }

            DateLyricsDebugLog(@"MARQUEE resume settledX=%.1f settledPhase=%.3f settleWait=%.3f wallRemaining=%.3f", settledX, settledPhase, settleRemaining, wallRemaining);
            DateLyricsDebugMarqueeState(label, @"resume-started", payload);
            return YES;
        }
    }
    DateLyricsClearFrozenMarquee(label);
    DateLyricsStopMarquee(label);

    CGRect viewportFrame = label.frame;
    CGFloat viewportWidth = CGRectGetWidth(viewportFrame);
    if (viewportWidth <= 1.0) return NO;

    NSTimeInterval lineBegin = [payload[@"lineBegin"] doubleValue];
    NSTimeInterval lineEnd = [payload[@"lineEnd"] doubleValue];
    NSTimeInterval nowElapsed = MAX(0.0, DateLyricsCurrentRenderElapsed());

    // anchor scrolling to the lyric timeline so seeks and late attachments
    // join the current phase instead of racing from the beginning.
    BOOL lineWindowUsable = payload[@"lineBegin"] != nil && lineEnd > lineBegin;
    NSTimeInterval marqueeOrigin = lineWindowUsable ? lineBegin : nowElapsed;
    NSTimeInterval timelineDuration = MAX(0.0, lineEnd - marqueeOrigin);
    // the ticker fires ~50 ms ahead of a line's timestamp so the transition can
    // settle.  let the entry phase go slightly negative for that window: the
    // extra time simply lengthens the initial hold, and the scroll still lands
    // exactly on the line's end instead of finishing 50 ms late.
    NSTimeInterval entryPhase = MIN(timelineDuration, MAX(-0.15, nowElapsed - marqueeOrigin));

    static const NSTimeInterval kDateLyricsMinMarqueeWindow = 0.30;
    if (timelineDuration < kDateLyricsMinMarqueeWindow) {
        DateLyricsDebugLog(@"[ANIM:M] skip-late line=%@ timelineDuration=%.3f overflow=%.1f",
                           payload[@"lineId"] ?: @"-", timelineDuration, overflow);
        objc_setAssociatedObject(label, kDateLyricsMarqueeSkippedLineIdKey,
                                 payload[@"lineId"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(label, kDateLyricsMarqueeActiveKey, nil, OBJC_ASSOCIATION_ASSIGN);
        return YES;
    }

    if (didRebuild) *didRebuild = YES;

    DateLyricsDebugLog(@"[ANIM:M] origin-lineBegin=%.3f timelineDuration=%.3f entryPhase=%.3f lineDur=%.3f transition=%.3f",
                       marqueeOrigin - lineBegin, timelineDuration, entryPhase, lineEnd - lineBegin, gDateLyricsTransitionDuration);

    UIView *container = [[UIView alloc] initWithFrame:viewportFrame];
    container.userInteractionEnabled = NO;
    container.clipsToBounds = YES;
    container.backgroundColor = UIColor.clearColor;

    UIView *track = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0,
                                                             viewportWidth + overflow,
                                                             CGRectGetHeight(container.bounds))];
    track.userInteractionEnabled = NO;
    track.backgroundColor = UIColor.clearColor;
    UILabel *contentLabel = [[UILabel alloc] initWithFrame:track.bounds];
    contentLabel.numberOfLines = 1;
    contentLabel.adjustsFontSizeToFitWidth = NO;
    contentLabel.lineBreakMode = NSLineBreakByClipping;
    contentLabel.textAlignment = NSTextAlignmentLeft;
    contentLabel.font = label.font;
    contentLabel.textColor = label.textColor;
    contentLabel.backgroundColor = UIColor.clearColor;
    contentLabel.attributedText = label.attributedText;
    if (!contentLabel.attributedText) contentLabel.text = label.text;
    [track addSubview:contentLabel];
    [container addSubview:track];

    [label.superview insertSubview:container aboveSubview:label];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    track.layer.transform = CATransform3DMakeTranslation(-overflow, 0.0, 0.0);
    [CATransaction commit];

    NSTimeInterval holdDuration = DateLyricsMarqueeHoldForLine(timelineDuration, overflow);
    objc_setAssociatedObject(label, kDateLyricsMarqueeOriginKey, @(marqueeOrigin), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(label, kDateLyricsMarqueeDurationKey, @(timelineDuration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(label, kDateLyricsMarqueeHoldKey, @(holdDuration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    double rate = MAX(0.0, [gDateLyricsLocalAnchor[@"rate"] doubleValue]);
    DateLyricsDebugLog(@"MARQUEE sync line=%@ duration=%.3f overflow=%.1f rate=%.2f paused=%d anchorGeneration=%lu seek=%d",
                       payload[@"lineId"] ?: @"-", timelineDuration, overflow,
                       rate, rate <= 0.0, (unsigned long)gDateLyricsAnchorGeneration,
                       [gDateLyricsLocalAnchor[@"seek"] boolValue]);

    // the model stays parked at the end of the scroll (set above to -overflow,
    // which is xforphase(timelineduration)). the keyframe animation below carries
    // fillmode kcafillmodeboth and starts at entryphase, so it drives the display
    // from the phase the line has actually reached; the model is only what the
    // track rests at once that animation is gone, which is the finished position.
    NSTimeInterval remainingPhase = MAX(0.0, timelineDuration - entryPhase);
    NSDictionary *rejoin = objc_getAssociatedObject(label, kDateLyricsMarqueeWakeRejoinKey);
    BOOL rejoinAfterWake = rate > 0.0 && [rejoin[@"line"] isEqual:payload[@"lineId"]];
    // the wake animation already met the live curve. continue its normal
    // motion immediately; only blend again if a late callback left a gap.
    if (rejoinAfterWake && [rejoin[@"predicted"] boolValue] &&
        fabs([rejoin[@"startX"] doubleValue] - DateLyricsMarqueeXForPhase(entryPhase, timelineDuration, holdDuration, overflow)) < 0.5)
        rejoinAfterWake = NO;
    objc_setAssociatedObject(label, kDateLyricsMarqueeWakeRejoinKey, nil, OBJC_ASSOCIATION_ASSIGN);
    NSMutableArray *vals = [NSMutableArray array];
    const NSInteger kSteps = 60;
    for (NSInteger i = 0; i <= kSteps; i++) {
        NSTimeInterval p = entryPhase + remainingPhase * ((double)i / kSteps);
        CGFloat x = rejoinAfterWake ? (rejoin[@"velocity"]
            ? DateLyricsMarqueeHandoffWakeMotionX(p, entryPhase, timelineDuration, holdDuration, overflow, rate, [rejoin[@"startX"] doubleValue], [rejoin[@"velocity"] doubleValue], 0.35)
            : DateLyricsMarqueeWakeX(p, entryPhase, timelineDuration, holdDuration, overflow, rate, [rejoin[@"startX"] doubleValue]))
            : DateLyricsMarqueeXForPhase(p, timelineDuration, holdDuration, overflow);
        [vals addObject:@(x)];
    }
    if (rejoinAfterWake) DateLyricsDebugLog(@"[DISPLAY:MARQUEE] wake-rejoin line=%@ phase=%.3f", payload[@"lineId"], entryPhase);
    CAKeyframeAnimation *scroll = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    scroll.values = vals;
    scroll.calculationMode = kCAAnimationLinear;
    if (remainingPhase <= 0.0) {
        objc_setAssociatedObject(label, kDateLyricsMarqueeTrackKey, track, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(label, kDateLyricsMarqueeContentLabelKey, contentLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(label, kDateLyricsMarqueeContainerKey, container, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(label, kDateLyricsMarqueeActiveKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        gDateLyricsActiveMarqueeCount++;
        DateLyricsSynchronizeOwnerVisibility(label);
        return YES;
    }
    scroll.duration = rate > 0.0 ? remainingPhase / rate : remainingPhase;
    scroll.removedOnCompletion = NO;
    scroll.fillMode = kCAFillModeBoth;
    // use begintime offset instead of timeoffset to avoid local-time modulo wrap-to-zero.
    CFTimeInterval localNow = [track.layer convertTime:CACurrentMediaTime() fromLayer:nil];
    if (rate > 0.0) {
        scroll.speed = 1.0;
        scroll.timeOffset = 0.0;
        scroll.beginTime = localNow;
        [track.layer addAnimation:scroll forKey:@"DateLyricsMarquee"];
    } else {
        // park marquees built during pause at the current line phase and mark
        // them frozen, so playback resumes them instead of reusing a parked track.
        CGFloat parkedX = DateLyricsMarqueeXForPhase(entryPhase, timelineDuration, holdDuration, overflow);
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        track.layer.transform = CATransform3DMakeTranslation(parkedX, 0.0, 0.0);
        [CATransaction commit];
        objc_setAssociatedObject(label, kDateLyricsMarqueeFrozenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(label, kDateLyricsMarqueeFrozenSettledXKey, @(parkedX), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(label, kDateLyricsMarqueeFrozenSettledPhaseKey, @(MAX(0.0, entryPhase)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (rate > 0.0) {
        NSUInteger gen = [objc_getAssociatedObject(label, kDateLyricsMarqueeRunGenerationKey) unsignedIntegerValue] + 1;
        objc_setAssociatedObject(label, kDateLyricsMarqueeRunGenerationKey, @(gen), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        DateLyricsScheduleMarqueeProbe(label, track, payload, scroll.duration + 0.05, @"normal-end+50ms", gen);
    }

    objc_setAssociatedObject(label, kDateLyricsMarqueeContainerKey, container, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(label, kDateLyricsMarqueeContentLabelKey, contentLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(label, kDateLyricsMarqueeTrackKey, track, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(label, kDateLyricsMarqueeActiveKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gDateLyricsActiveMarqueeCount++;
    DateLyricsSynchronizeOwnerVisibility(label);

    DateLyricsDebugMarqueeState(label, @"new-started", payload);
    return YES;
}

static NSString *GetLyricsRootPath(void) {
    if (DateLyricsIsSpringBoardHost()) return DateLyricsStorageMusicDirectory(NSClassFromString(@"LSApplicationProxy"));
    // music's own container is stable for its process lifetime.
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        path = DateLyricsStorageLocalDirectory();
        if (path.length) [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    });
    return path;
}

@interface DateLyricsWordTTMLParserDelegate : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray<DateLyricsTimedLine *> *lines;
@property (nonatomic, strong) DateLyricsTimedLine *currentLine;
@property (nonatomic, strong) NSMutableArray<DateLyricsTimedWord *> *currentWords;
@property (nonatomic, strong) NSMutableString *pendingSeparator;
@property (nonatomic, strong) NSMutableString *currentSpanText;
@property (nonatomic, assign) BOOL insideParagraph;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *spanBackgroundStack;
@end

@implementation DateLyricsWordTTMLParserDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _lines = [NSMutableArray array];
        _pendingSeparator = [NSMutableString string];
        _spanBackgroundStack = [NSMutableArray array];
    }
    return self;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *,NSString *> *)attributeDict {
    if ([elementName isEqualToString:@"p"]) {
        self.insideParagraph = YES;
        self.currentLine = [DateLyricsTimedLine new];
        self.currentLine.begin = DateLyricsParseTimeString(attributeDict[@"begin"]);
        self.currentLine.end = DateLyricsParseTimeString(attributeDict[@"end"]);
        self.currentWords = [NSMutableArray array];
        [self.spanBackgroundStack removeAllObjects];
        [self.pendingSeparator setString:@""];
    } else if (self.insideParagraph && [elementName isEqualToString:@"span"]) {
        NSString *role = attributeDict[@"ttm:role"] ?: attributeDict[@"role"];
        BOOL isBackground = [role isEqualToString:@"x-bg"] || [[self.spanBackgroundStack lastObject] boolValue];
        [self.spanBackgroundStack addObject:@(isBackground)];
        BOOL hasTiming = attributeDict[@"begin"] != nil || attributeDict[@"end"] != nil;
        if (hasTiming) {
            DateLyricsTimedWord *word = [DateLyricsTimedWord new];
            word.begin = DateLyricsParseTimeString(attributeDict[@"begin"]);
            word.end = DateLyricsParseTimeString(attributeDict[@"end"]);
            word.separatorBefore = [self.pendingSeparator copy] ?: @"";
            word.background = isBackground;
            [self.currentWords addObject:word];
            self.currentSpanText = [NSMutableString string];
            [self.pendingSeparator setString:@""];
        }
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    if (!self.insideParagraph || string.length == 0) return;
    if (self.currentSpanText) {
        [self.currentSpanText appendString:string];
    } else {
        [self.pendingSeparator appendString:string];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    if ([elementName isEqualToString:@"span"]) {
        if (self.currentSpanText) {
            DateLyricsTimedWord *word = self.currentWords.lastObject;
            if (word && !word.text.length) {
                word.text = [self.currentSpanText copy];
            }
            self.currentSpanText = nil;
        }
        if (self.spanBackgroundStack.count > 0) {
            [self.spanBackgroundStack removeLastObject];
        }
    } else if ([elementName isEqualToString:@"p"] && self.currentLine) {
        NSMutableString *fullText = [NSMutableString string];
        for (DateLyricsTimedWord *word in self.currentWords) {
            if (word.separatorBefore.length > 0) {
                [fullText appendString:word.separatorBefore];
            }
            if (word.text.length > 0) {
                [fullText appendString:word.text];
            }
        }
        self.currentLine.text = [fullText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        self.currentLine.words = [self.currentWords copy];
        if (self.currentLine.text.length > 0 && self.currentLine.words.count > 0) {
            [self.lines addObject:self.currentLine];
        }
        self.currentLine = nil;
        self.currentWords = nil;
        self.insideParagraph = NO;
        [self.spanBackgroundStack removeAllObjects];
        [self.pendingSeparator setString:@""];
    }
}

@end

static void DateLyricsNormalizeWordLines(NSArray<DateLyricsTimedLine *> *lines) {
    for (DateLyricsTimedLine *line in lines) {
        if (line.words.count == 0) continue;

        NSMutableString *reconstructed = [NSMutableString string];
        for (NSUInteger i = 0; i < line.words.count; i++) {
            DateLyricsTimedWord *word = line.words[i];
            if (i == 0) word.separatorBefore = @"";
            [reconstructed appendString:word.separatorBefore ?: @""];
            [reconstructed appendString:word.text ?: @""];
        }

        line.text = [reconstructed copy];
    }
}

static NSArray<DateLyricsTimedLine *> *DateLyricsParseWordTimedLines(NSData *data) {
    if (!data.length) return nil;
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    DateLyricsWordTTMLParserDelegate *delegate = [DateLyricsWordTTMLParserDelegate new];
    parser.delegate = delegate;
    BOOL ok = [parser parse];

    if (!ok || delegate.lines.count == 0) return nil;

    NSMutableArray<DateLyricsTimedLine *> *parsedLines = [delegate.lines mutableCopy];
    [parsedLines sortUsingComparator:^NSComparisonResult(DateLyricsTimedLine *left, DateLyricsTimedLine *right) {
        return left.begin < right.begin ? NSOrderedAscending : (left.begin > right.begin ? NSOrderedDescending : NSOrderedSame);
    }];

    // bounds validation
    for (DateLyricsTimedLine *line in parsedLines) {
        if (line.begin < 0.0) line.begin = 0.0;
        if (line.end < line.begin) line.end = line.begin + 5.0;
        for (DateLyricsTimedWord *word in line.words) {
            if (word.begin < line.begin) word.begin = line.begin;
            if (word.end < word.begin) word.end = word.begin + 0.1;
        }
    }

    DateLyricsNormalizeWordLines(parsedLines);
    return [parsedLines copy];
}

static BOOL DateLyricsWordLinesHaveTiming(NSArray<DateLyricsTimedLine *> *lines) {
    if (lines.count == 0) return NO;
    BOOL hasTiming = NO;
    for (DateLyricsTimedLine *line in lines) {
        if (!isfinite(line.begin) || !isfinite(line.end)) return NO;
        for (DateLyricsTimedWord *word in line.words) {
            if (!isfinite(word.begin) || !isfinite(word.end)) return NO;
            if (word.end > word.begin) hasTiming = YES;
        }
    }
    return hasTiming;
}

static BOOL DateLyricsLineItemsHaveTiming(NSArray<MSVLyricsLine *> *lines) {
    if (lines.count == 0) return NO;
    BOOL hasTiming = NO;
    for (MSVLyricsLine *line in lines) {
        if (!isfinite(line.startTime) || !isfinite(line.endTime)) return NO;
        if (line.endTime > line.startTime) hasTiming = YES;
        // some line-synced responses provide only increasing start times.
        if (line.startTime > 0.001) hasTiming = YES;
    }
    return hasTiming;
}

static void DateLyricsTouchMemoryCacheLocked(NSNumber *storeID) {
    if (!storeID) return;
    [gLyricsCacheOrder removeObject:storeID];
    [gLyricsCacheOrder addObject:storeID];
    while (gLyricsCacheOrder.count > kDateLyricsMaxMemoryCacheEntries) {
        NSNumber *oldestStoreID = gLyricsCacheOrder.firstObject;
        [gLyricsCacheOrder removeObjectAtIndex:0];
        [gLyricsCache removeObjectForKey:oldestStoreID];
        [gWordLyricsCache removeObjectForKey:oldestStoreID];
    }
}

static void DateLyricsPruneDiskCacheAtPath(NSString *rootPath) {
    if (!rootPath.length) return;

    NSArray<NSString *> *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:rootPath error:nil];
    NSMutableArray<NSDictionary *> *files = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *scoreFiles = [NSMutableArray array];
    for (NSString *entry in entries) {
        BOOL isAppleLyrics = [entry hasPrefix:@"syllable-lyrics_"] && [entry hasSuffix:@".xml"];
        BOOL isScore = [entry hasPrefix:@"score-"] && [entry hasSuffix:@".json"];
        if (!isAppleLyrics && !isScore) continue;
        NSString *path = [rootPath stringByAppendingPathComponent:entry];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        NSMutableArray *destination = isScore ? scoreFiles : files;
        [destination addObject:@{ @"path": path, @"date": attributes[NSFileModificationDate] ?: [NSDate distantPast] }];
    }
    for (NSMutableArray<NSDictionary *> *cacheFiles in @[files, scoreFiles]) {
        [cacheFiles sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            return [left[@"date"] compare:right[@"date"]];
        }];
        while (cacheFiles.count > kDateLyricsMaxDiskCacheEntries) {
            NSDictionary *oldest = cacheFiles.firstObject;
            [[NSFileManager defaultManager] removeItemAtPath:oldest[@"path"] error:nil];
            [cacheFiles removeObjectAtIndex:0];
        }
    }
}

static NSString *DateLyricsScoreRootPath(NSInteger trackID) {
    if (!DateLyricsIsExternalTrack(trackID)) return GetLyricsRootPath();
    NSString *path = DateLyricsExternalScoreDirectory;
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}

static void DateLyricsPruneDiskCache(void) {
    static NSTimeInterval lastPruneTime = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - lastPruneTime < 3600.0) return;
    lastPruneTime = now;
    DateLyricsPruneDiskCacheAtPath(DateLyricsIsSpringBoardHost()
        ? DateLyricsExternalScoreDirectory : GetLyricsRootPath());
}

static NSString *DateLyricsAppleScorePath(NSInteger storeID) {
    return DateLyricsStorageScorePath(DateLyricsScoreRootPath(storeID), storeID, @"apple");
}

// the historical musixmatch filename holds the best score from any online provider.
static NSString *DateLyricsMusixmatchScorePath(NSInteger storeID) {
    return DateLyricsStorageScorePath(DateLyricsScoreRootPath(storeID), storeID, @"musixmatch");
}

static NSString *DateLyricsActiveScorePath(NSInteger storeID) {
    return DateLyricsStorageScorePath(DateLyricsScoreRootPath(storeID), storeID, @"");
}

static DateLyricsScore *DateLyricsScoreAtPath(NSString *path) {
    if (!path.length) return nil;
    NSData *data = DateLyricsStorageReadData(path);
    return data.length > 0 ? [[DateLyricsScore alloc] initWithJSONData:data] : nil;
}

// both paths are sibling files. posix rename replaces an existing destination
// atomically; failure leaves the old score intact for readers.
static BOOL DateLyricsAtomicReplaceFile(NSString *temporaryPath, NSString *destinationPath) {
    return rename(temporaryPath.fileSystemRepresentation, destinationPath.fileSystemRepresentation) == 0;
}

static BOOL DateLyricsPublishBestScore(NSInteger storeID) {
    if (storeID <= 0) return NO;
    DateLyricsScore *apple = DateLyricsScoreAtPath(DateLyricsAppleScorePath(storeID));
    DateLyricsScore *musixmatch = DateLyricsMusixmatchAllowedForTrack(storeID)
        ? DateLyricsScoreAtPath(DateLyricsMusixmatchScorePath(storeID)) : nil;
    if (!DateLyricsSourceAllowedForMatchMode(musixmatch.source, gDateLyricsRelaxedMatching)) musixmatch = nil;
    DateLyricsScore *best = nil;
    if (apple.hasWordTiming) best = apple;
    else if (musixmatch.hasWordTiming) best = musixmatch;
    else if (apple.lines.count > 0) best = apple;
    else if (musixmatch.lines.count > 0) best = musixmatch;

    NSString *activePath = DateLyricsActiveScorePath(storeID);
    if (!activePath.length) return NO;
    BOOL published = NO;
    if (!best) {
        [[NSFileManager defaultManager] removeItemAtPath:activePath error:nil];
        published = ![[NSFileManager defaultManager] fileExistsAtPath:activePath];
    } else {
        NSData *data = nil;
        // preserve the provider's original json so ranges and future fields are intact.
        NSString *sourcePath = [best.source hasPrefix:@"musixmatch"]
            ? DateLyricsMusixmatchScorePath(storeID) : DateLyricsAppleScorePath(storeID);
        data = DateLyricsStorageReadData(sourcePath);
        NSString *tmp = [NSString stringWithFormat:@"%@.%@.tmp", activePath, [NSUUID UUID].UUIDString];
        if (data && [data writeToFile:tmp atomically:YES]) {
            published = DateLyricsAtomicReplaceFile(tmp, activePath);
            if (!published) [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
        }
    }
    if (published) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.shalamand3r.datelyrics/score.changed"), NULL, NULL, YES);
    }
    return published;
}

static BOOL DateLyricsWriteScoreJSON(NSInteger storeID, NSArray<NSDictionary *> *linesArray, BOOL hasWordTiming, NSString *source) {
    if (storeID <= 0 || linesArray.count == 0) return NO;

    NSMutableDictionary *score = [NSMutableDictionary dictionary];
    score[@"protocol"] = @3;
    score[@"kind"] = @"score";
    score[@"trackId"] = @(storeID);
    score[@"generatedAt"] = @([NSDate timeIntervalSinceReferenceDate]);
    NSData *linesData = [NSJSONSerialization dataWithJSONObject:linesArray options:0 error:nil];
    score[@"revision"] = linesData ? [NSString stringWithFormat:@"%lu", (unsigned long)[linesData hash]] : [[NSUUID UUID] UUIDString];
    score[@"hasWordTiming"] = @(hasWordTiming);

    if (source.length > 0) score[@"source"] = source;
    score[@"lines"] = linesArray;

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:score options:0 error:nil];
    if (!jsonData) return NO;

    BOOL isLoading = [source isEqualToString:@"musixmatch-loading"];
    NSString *path = isLoading ? DateLyricsActiveScorePath(storeID)
        : ([source hasPrefix:@"musixmatch"] ? DateLyricsMusixmatchScorePath(storeID) : DateLyricsAppleScorePath(storeID));
    if (!path.length) return NO;
    NSString *tempPath = [NSString stringWithFormat:@"%@.%@.tmp", path, [NSUUID UUID].UUIDString];
    if (![jsonData writeToFile:tempPath atomically:YES]) return NO;
    BOOL moved = DateLyricsAtomicReplaceFile(tempPath, path);
    if (!moved) [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
    if (!moved) return NO;

    DateLyricsPruneDiskCache();
    DateLyricsDebugLog(@"[Score] wrote storeID=%ld lines=%lu wordTiming=%d source=%@",
                       (long)storeID, (unsigned long)linesArray.count, hasWordTiming, source ?: @"apple");

    if (!isLoading) return DateLyricsPublishBestScore(storeID);
    else CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.shalamand3r.datelyrics/score.changed"), NULL, NULL, YES);
    return YES;
}

static void DateLyricsSerializeScore(NSInteger storeID, NSArray<DateLyricsTimedLine *> *wordLines, NSArray<MSVLyricsLine *> *lyricLines) {
    if (wordLines.count == 0 && lyricLines.count == 0) return;

    NSMutableArray *linesArray = [NSMutableArray array];

    if (wordLines.count > 0) {
        for (DateLyricsTimedLine *line in wordLines) {
            NSMutableDictionary *lineDict = [NSMutableDictionary dictionary];
            lineDict[@"begin"] = @(line.begin);
            lineDict[@"end"] = @(line.end);
            lineDict[@"text"] = line.text ?: @"";

            NSMutableArray *wordsArray = [NSMutableArray array];
            for (DateLyricsTimedWord *word in line.words) {
                [wordsArray addObject:@{
                    @"b": @(word.begin),
                    @"e": @(word.end),
                    @"t": word.text ?: @"",
                    @"s": word.separatorBefore ?: @"",
                    @"bg": @(word.background)
                }];
            }
            lineDict[@"words"] = wordsArray;
            [linesArray addObject:lineDict];
        }
    } else {
        for (MSVLyricsLine *line in lyricLines) {
            NSMutableDictionary *lineDict = [NSMutableDictionary dictionary];
            lineDict[@"begin"] = @(line.startTime);
            lineDict[@"end"] = @(line.endTime);

            id lyricsText = [line respondsToSelector:@selector(lyricsText)] ? [line performSelector:@selector(lyricsText)] : nil;
            NSString *rawTitle = nil;
            if ([lyricsText isKindOfClass:[NSAttributedString class]]) {
                rawTitle = [lyricsText string];
            } else if ([lyricsText isKindOfClass:[NSString class]]) {
                rawTitle = (NSString *)lyricsText;
            }
            lineDict[@"text"] = rawTitle ?: @"";
            [linesArray addObject:lineDict];
        }
    }

    DateLyricsWriteScoreJSON(storeID, linesArray, wordLines.count > 0, @"apple");
}

#include "CoreLyrics/DateLyricsAdapter.inc"

static NSString *DateLyricsMetadataString(id metadata, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        SEL selector = NSSelectorFromString(key);
        if (![metadata respondsToSelector:selector]) continue;
        @try {
            id value = [metadata valueForKey:key];
            if ([value isKindOfClass:NSString.class] && [value length] > 0) return [value copy];
        } @catch (__unused NSException *exception) {
        }
    }
    return nil;
}

static NSTimeInterval DateLyricsMetadataDuration(id metadata) {
    for (NSString *key in @[@"duration", @"durationInSeconds", @"trackDuration", @"playbackDuration", @"totalTime"]) {
        if (![metadata respondsToSelector:NSSelectorFromString(key)]) continue;
        @try {
            id value = [metadata valueForKey:key];
            double duration = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.0;
            if (!isfinite(duration) || duration <= 0.0) continue;
            if ([key isEqualToString:@"totalTime"] && duration > 10000.0) duration /= 1000.0;
            return duration;
        } @catch (__unused NSException *exception) {
        }
    }
    return 0.0;
}

static void DateLyricsStartMusixmatchFallback(NSInteger storeID, NSString *title, NSString *artist,
                                              NSString *album, NSTimeInterval duration, DateLyricsSyncTier appleTier) {
    if (storeID <= 0 || !DateLyricsMusixmatchAllowedForTrack(storeID)) return;
    if (!DateLyricsIsExternalTrack(storeID) && !DateLyricsShouldFetchMusixmatch(appleTier)) return;
    if (title.length == 0 || artist.length == 0) {
        DateLyricsDebugLog(@"[Musixmatch] storeID=%ld skipped: title or artist missing", (long)storeID);
        return;
    }
    DateLyricsDebugLog(@"[Musixmatch] fallback start storeID=%ld title=%@ artist=%@ album=%@ duration=%.0f appleTier=%ld",
                       (long)storeID, title, artist, album ?: @"", duration, (long)appleTier);
    if (gMusixmatchPendingTaskIDs[@(storeID)] != nil) return;
    NSTimeInterval retryAfter = [gMusixmatchFailureRetryAfter[@(storeID)] doubleValue];
    if (retryAfter > [[NSDate date] timeIntervalSince1970]) {
        DateLyricsDebugLog(@"[Musixmatch] storeID=%ld skipped during failure cooldown", (long)storeID);
        return;
    }

    // a provider cache hit avoids repeating the network lookup offline.
    DateLyricsScore *cachedMusixmatch = DateLyricsScoreAtPath(DateLyricsMusixmatchScorePath(storeID));
    if (!DateLyricsSourceAllowedForMatchMode(cachedMusixmatch.source, gDateLyricsRelaxedMatching)) cachedMusixmatch = nil;
    if (DateLyricsMusixmatchScoreWins(cachedMusixmatch, appleTier)) {
        DateLyricsDebugLog(@"[Musixmatch] using cached score storeID=%ld source=%@ lines=%lu",
                           (long)storeID, cachedMusixmatch.source, (unsigned long)cachedMusixmatch.lines.count);
        DateLyricsPublishBestScore(storeID);
        DateLyricsShareCachedScore(storeID, title, artist, album, duration);
        if (cachedMusixmatch.hasWordTiming || !gDateLyricsWordHighlighting) return;
    }

    DateLyricsMusixmatchTask *task = [DateLyricsMusixmatchTask new];
    task.storeID = storeID;
    task.title = title;
    task.artist = artist;
    task.album = album;
    task.duration = duration;
    task.appleTier = appleTier;
    task.hasUsableLines = appleTier == DateLyricsSyncTierLine || cachedMusixmatch.lines.count > 0;

    task.cacheGeneration = gDateLyricsCacheGeneration;
    task.musixmatchGeneration = gDateLyricsMusixmatchGeneration;
    task.taskID = [NSUUID UUID].UUIDString;
    gMusixmatchPendingTaskIDs[@(storeID)] = task.taskID;

    NSArray<NSString *> *active = DateLyricsActiveProviders();
    task.totalProviders = active.count;
    task.currentProviderIndex = 1;

    if (!task.hasUsableLines) {
        DateLyricsScheduleMusixmatchLoadingScore(task);
    }
    DateLyricsBeginSharedLookup(task);
}

static NSDictionary *gDateLyricsSelectedExternalInfo;
static NSUInteger gDateLyricsExternalSelectionGeneration;
static void DateLyricsRefreshSharedLyrics(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(gLyricsQueue, ^{
        NSInteger selectedID = gDateLyricsSelectedExternalTrack;
        NSDictionary *info = gDateLyricsSelectedExternalInfo;
        if (!selectedID || !info || !gDateLyricsEnabled || !gDateLyricsExternalAppsEnabled) return;
        DLLyricsTrack *track = [DLLyricsTrack trackWithTitle:info[@"kMRMediaRemoteNowPlayingInfoTitle"] artist:info[@"kMRMediaRemoteNowPlayingInfoArtist"] duration:[DateLyricsJSONNumber(info[@"kMRMediaRemoteNowPlayingInfoDuration"]) doubleValue]];
        NSUInteger generation = gDateLyricsCacheGeneration, selectionGeneration = gDateLyricsExternalSelectionGeneration;
        [DLLyricsEngine.sharedEngine cachedTrack:track completion:^(DLLyricsResult *result) {
            dispatch_async(gLyricsQueue, ^{
                if (!gDateLyricsEnabled || !gDateLyricsExternalAppsEnabled || selectedID != gDateLyricsSelectedExternalTrack ||
                    generation != gDateLyricsCacheGeneration || selectionGeneration != gDateLyricsExternalSelectionGeneration ||
                    !result.lines.count || (result.relaxedMatch && !gDateLyricsRelaxedMatching)) return;
                DateLyricsScore *existing = DateLyricsScoreAtPath(DateLyricsMusixmatchScorePath(selectedID));
                if (!DateLyricsSourceAllowedForMatchMode(existing.source, gDateLyricsRelaxedMatching)) existing = nil;
                if (existing.hasWordTiming || (existing.lines.count && !result.hasWordTiming)) return;
                DateLyricsDebugLog(@"[CoreLyrics] adopted shared cache lines=%lu words=%d", (unsigned long)result.lines.count, result.hasWordTiming);
                DateLyricsWriteScoreJSON(selectedID, result.lines, result.hasWordTiming, result.relaxedMatch ? @"musixmatch-relaxed" : @"musixmatch");
            });
        }];
    });
}
static void DateLyricsSelectExternalTrack(NSInteger trackID, NSDictionary *info) {
    dispatch_async(gLyricsQueue, ^{
        NSInteger selectedID = gDateLyricsEnabled && gDateLyricsExternalAppsEnabled ? trackID : 0;
        BOOL sameTrack = selectedID == gDateLyricsSelectedExternalTrack;
        double oldDuration = [DateLyricsJSONNumber(gDateLyricsSelectedExternalInfo[@"kMRMediaRemoteNowPlayingInfoDuration"]) doubleValue];
        gDateLyricsSelectedExternalInfo = selectedID ? [info copy] : nil;
        double duration = [DateLyricsJSONNumber(info[@"kMRMediaRemoteNowPlayingInfoDuration"]) doubleValue];
        if (!isfinite(duration) || duration < 0) duration = 0;
        if (sameTrack && !(oldDuration <= 0 && duration > 0)) return;
        ++gDateLyricsExternalSelectionGeneration;
        NSInteger previous = gDateLyricsSelectedExternalTrack;
        gDateLyricsSelectedExternalTrack = selectedID;
        DateLyricsCancelProviderLookup(previous);
        if (!selectedID) return;
        if (sameTrack) [gMusixmatchFailureRetryAfter removeObjectForKey:@(selectedID)];
        id album = info[@"kMRMediaRemoteNowPlayingInfoAlbum"];
        DateLyricsStartMusixmatchFallback(selectedID, info[@"kMRMediaRemoteNowPlayingInfoTitle"],
            info[@"kMRMediaRemoteNowPlayingInfoArtist"], [album isKindOfClass:NSString.class] ? album : nil,
            duration, DateLyricsSyncTierNone);
        DateLyricsRefreshSharedLyrics(NULL, NULL, NULL, NULL, NULL);
    });
}

static void DateLyricsInvalidateAppleScore(NSInteger storeID) {
    if (storeID <= 0) return;
    NSNumber *storeIDKey = @(storeID);
    pthread_mutex_lock(&gLyricsCacheMutex);
    [gLyricsCache removeObjectForKey:storeIDKey];
    [gWordLyricsCache removeObjectForKey:storeIDKey];
    [gLyricsCacheOrder removeObject:storeIDKey];
    pthread_mutex_unlock(&gLyricsCacheMutex);

    [[NSFileManager defaultManager] removeItemAtPath:DateLyricsAppleScorePath(storeID) error:nil];
    DateLyricsPublishBestScore(storeID);
}

static BOOL DateLyricsXMLDeclaresNoTiming(NSData *data) {
    if (!data.length) return NO;

    NSString *xml = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (xml.length == 0) return NO;

    // apple marks transcript-only ttml explicitly.  check the document before
    // invoking either parser because the private parser still returns one line
    // per <p>, all at time zero, for this format.
    NSRange doubleQuoted = [xml rangeOfString:@"itunes:timing=\"None\"" options:NSCaseInsensitiveSearch];
    if (doubleQuoted.location != NSNotFound) return YES;
    NSRange singleQuoted = [xml rangeOfString:@"itunes:timing='None'" options:NSCaseInsensitiveSearch];
    return singleQuoted.location != NSNotFound;
}

typedef NS_ENUM(NSInteger, DateLyricsParseResult) {
    DateLyricsParseResultSuccess,
    DateLyricsParseResultNoTiming,
    DateLyricsParseResultMalformed,
    DateLyricsParseResultUnsupported
};





// attach custom/word spans onto apple's private line timeline. each word line
// may be used at most once, matches proceed in sorted order, and large internal
// unmatched gaps reject the merge so partial karaoke cannot mis-attach.
static NSArray<DateLyricsTimedLine *> *DateLyricsMergeWordTiming(NSArray<DateLyricsTimedLine *> *wordLines, NSArray<MSVLyricsLine *> *lyricLines) {
    if (wordLines.count == 0 || lyricLines.count == 0) return nil;

    static const NSTimeInterval kMatchTolerance = 0.25;
    static const NSUInteger kMaxInternalSkip = 2;

    NSMutableArray<DateLyricsTimedLine *> *merged = [NSMutableArray array];
    NSMutableIndexSet *usedWordIndexes = [NSMutableIndexSet indexSet];
    NSUInteger matchedWords = 0;
    NSUInteger searchStart = 0;
    NSInteger firstMatchedWordIndex = -1;
    NSInteger lastMatchedWordIndex = -1;

    NSInteger firstMeaningfulWordIndex = -1;
    NSInteger lastMeaningfulWordIndex = -1;
    for (NSUInteger i = 0; i < wordLines.count; i++) {
        DateLyricsTimedLine *wLine = wordLines[i];
        if (!DateLyricsLineHasWordTiming(wLine)) continue;
        if (firstMeaningfulWordIndex < 0) firstMeaningfulWordIndex = (NSInteger)i;
        lastMeaningfulWordIndex = (NSInteger)i;
    }
    if (firstMeaningfulWordIndex < 0) return nil;

    for (MSVLyricsLine *mLine in lyricLines) {
        DateLyricsTimedLine *line = [DateLyricsTimedLine new];
        line.begin = mLine.startTime;
        line.end = mLine.endTime;

        id lyricsText = [mLine respondsToSelector:@selector(lyricsText)] ? [mLine performSelector:@selector(lyricsText)] : nil;
        NSString *rawTitle = nil;
        if ([lyricsText isKindOfClass:[NSAttributedString class]]) {
            rawTitle = [(NSAttributedString *)lyricsText string];
        } else if ([lyricsText isKindOfClass:[NSString class]]) {
            rawTitle = (NSString *)lyricsText;
        }
        line.text = rawTitle ?: @"";
        if (line.text.length == 0) continue;

        DateLyricsTimedLine *bestMatch = nil;
        NSUInteger bestIndex = NSNotFound;
        NSTimeInterval bestDiff = kMatchTolerance;

        for (NSUInteger i = searchStart; i < wordLines.count; i++) {
            if ([usedWordIndexes containsIndex:i]) continue;
            DateLyricsTimedLine *wLine = wordLines[i];
            if (!DateLyricsLineHasWordTiming(wLine)) continue;

            NSTimeInterval diff = fabs(wLine.begin - line.begin);
            // past the ordered window: later word lines only grow farther away.
            if (wLine.begin - line.begin > kMatchTolerance) break;
            if (diff > kMatchTolerance) continue;
            if (!DateLyricsTextsAreSimilar(line.text, wLine.text)) continue;

            if (diff < bestDiff || bestMatch == nil) {
                bestDiff = diff;
                bestMatch = wLine;
                bestIndex = i;
            }
        }

        if (bestMatch && bestIndex != NSNotFound) {
            // reject large unmatched internal gaps between successive matches.
            if (lastMatchedWordIndex >= 0 &&
                bestIndex > (NSUInteger)lastMatchedWordIndex + 1 + kMaxInternalSkip) {
                DateLyricsDebugLog(@"[Parser] Rejecting word merge: internal gap %lu unused word lines",
                                   (unsigned long)(bestIndex - (NSUInteger)lastMatchedWordIndex - 1));
                return nil;
            }

            line.text = bestMatch.text;
            line.words = bestMatch.words;
            [usedWordIndexes addIndex:bestIndex];
            matchedWords++;
            if (firstMatchedWordIndex < 0) firstMatchedWordIndex = (NSInteger)bestIndex;
            lastMatchedWordIndex = (NSInteger)bestIndex;
            searchStart = bestIndex + 1;
        } else {
            line.words = @[];
        }
        DateLyricsAssignCharacterRanges(line);
        [merged addObject:line];
    }

    if (merged.count == 0 || matchedWords == 0) return nil;

    // first and last meaningful karaoke regions must be represented.
    if (firstMatchedWordIndex != firstMeaningfulWordIndex ||
        lastMatchedWordIndex != lastMeaningfulWordIndex) {
        DateLyricsDebugLog(@"[Parser] Rejecting word merge: first/last word regions unmatched");
        return nil;
    }

    // up to 10% line-only rows is acceptable once per-line timing is resolved.
    if ((double)matchedWords / (double)merged.count >= 0.9) {
        return [merged copy];
    }
    return nil;
}

static DateLyricsParseResult ParseLyricsData(NSData *data, NSInteger iTunesStoreID, __unused NSInteger lyricsAdamID,
                                             BOOL *wordTimingOut, BOOL allowMemoryShortCircuit) {
    if (wordTimingOut) *wordTimingOut = NO;
    if (!data.length || iTunesStoreID <= 0) return DateLyricsParseResultMalformed;

    NSNumber *storeIDKey = @(iTunesStoreID);

    // reparsing a known on-disk xml may reuse the memory cache. fresh network
    // responses must always reparse so higher-quality timing can upgrade the
    // score instead of being blocked by a prior line-timed cache entry.
    if (allowMemoryShortCircuit) {
        NSArray *cachedLineItems = nil;
        NSArray *cachedWordLines = nil;
        BOOL cachedLineTiming = NO;
        BOOL cachedWordTiming = NO;
        BOOL cacheHit = NO;

        pthread_mutex_lock(&gLyricsCacheMutex);
        cachedLineItems = [gLyricsCache[storeIDKey] copy];
        cachedWordLines = [gWordLyricsCache[storeIDKey] copy];
        cachedLineTiming = DateLyricsLineItemsHaveTiming(cachedLineItems);
        cachedWordTiming = DateLyricsWordLinesHaveTiming(cachedWordLines);
        if ((cachedLineItems.count > 0 && cachedLineTiming) || (cachedWordLines.count > 0 && cachedWordTiming)) {
            DateLyricsTouchMemoryCacheLocked(storeIDKey);
            cacheHit = YES;
        }
        pthread_mutex_unlock(&gLyricsCacheMutex);

        if (cacheHit) {
            if (wordTimingOut) *wordTimingOut = cachedWordTiming;
            // serialize outside the mutex — score writes are disk i/o.
            DateLyricsSerializeScore(iTunesStoreID, cachedWordLines, cachedLineItems);
            return DateLyricsParseResultSuccess;
        }
    }

    if (DateLyricsXMLDeclaresNoTiming(data)) {
        DateLyricsInvalidateAppleScore(iTunesStoreID);
        DateLyricsDebugLog(@"[Parser] Ignoring TTML transcript marked itunes:timing=None for storeID=%ld", (long)iTunesStoreID);
        return DateLyricsParseResultNoTiming;
    }

    NSArray<DateLyricsTimedLine *> *wordLines = DateLyricsParseWordTimedLines(data);
    NSError *parseError = nil;
    NSMutableArray<MSVLyricsLine *> *lyricLines = nil;
    Class parserClass = %c(MSVLyricsTTMLParser);
    if (parserClass) {
        MSVLyricsTTMLParser *parser = [[parserClass alloc] initWithTTMLData:data];
        [parser parseWithError:&parseError];
        if (!parseError) {
            lyricLines = [[parser lyricLines] mutableCopy];
        }
    }
    [lyricLines sortUsingComparator:^NSComparisonResult(MSVLyricsLine *line1, MSVLyricsLine *line2) {
        if (line1.startTime < line2.startTime) {
            return NSOrderedAscending;
        } else if (line1.startTime > line2.startTime) {
            return NSOrderedDescending;
        } else {
            return NSOrderedSame;
        }
    }];

    // a plain transcript has text but no timeline. treat it as no lyrics for
    // datelyrics purposes; displaying it would make one arbitrary line occupy
    // the date view for the entire song. prefer word timing when available, or
    // otherwise valid line timing from apple's parser.
    if (!DateLyricsWordLinesHaveTiming(wordLines)) wordLines = nil;
    if (!DateLyricsLineItemsHaveTiming(lyricLines)) lyricLines = nil;

    if (wordLines && lyricLines) {
        NSArray<DateLyricsTimedLine *> *merged = DateLyricsMergeWordTiming(wordLines, lyricLines);
        if (merged) {
            wordLines = merged;
        } else {
            wordLines = nil; // failed to merge 90%
        }
    }

    if (lyricLines.count == 0 && wordLines.count == 0) {
                DateLyricsInvalidateAppleScore(iTunesStoreID);
        DateLyricsDebugLog(@"[Parser] Ignoring unsupported lyrics format for storeID=%ld", (long)iTunesStoreID);
        return DateLyricsParseResultUnsupported;
    }

    pthread_mutex_lock(&gLyricsCacheMutex);
    [gLyricsCache removeObjectForKey:storeIDKey];
    [gWordLyricsCache removeObjectForKey:storeIDKey];
    if (lyricLines.count > 0) {
        gLyricsCache[storeIDKey] = [lyricLines copy];
    }
    if (wordLines.count > 0) {
        gWordLyricsCache[storeIDKey] = wordLines;
    }
    DateLyricsTouchMemoryCacheLocked(storeIDKey);
    pthread_mutex_unlock(&gLyricsCacheMutex);

    // publish the normalized timeline for springboard.
    DateLyricsSerializeScore(iTunesStoreID, wordLines, lyricLines);
    if (wordTimingOut) *wordTimingOut = wordLines.count > 0;


    return DateLyricsParseResultSuccess;
}

static BOOL DateLyricsAppleTaskIsCurrent(LyricsTask *task) {
    return gDateLyricsEnabled && task.cacheGeneration == gDateLyricsCacheGeneration &&
        task.selectionGeneration == gDateLyricsSelectionGeneration &&
        task.iTunesStoreID == gDateLyricsSelectedStoreID && task.lyricsAdamID == gDateLyricsSelectedAdamID;
}

static void DateLyricsSelectAppleTrack(NSInteger storeID, NSInteger adamID) {
    if (storeID == gDateLyricsSelectedStoreID && adamID == gDateLyricsSelectedAdamID) return;
    gDateLyricsSelectedStoreID = storeID; gDateLyricsSelectedAdamID = adamID;
    ++gDateLyricsSelectionGeneration;
    NSUInteger dropped = gLyricsTaskQueue.count;
    [gLyricsTaskQueue removeAllObjects];
    // ids belong to the current selection; obsolete callbacks never remove
    // reservations made by a later visit to the same song.
    [gPendingLyricsIDs removeAllObjects];
    DateLyricsDebugLog(@"[Apple] selected storeID=%ld adamID=%ld generation=%lu dropped=%lu active=%lu",
        (long)storeID, (long)adamID, (unsigned long)gDateLyricsSelectionGeneration,
        (unsigned long)dropped, (unsigned long)gActiveLyricsTasks.count);
}

static void DateLyricsFetchAppleTask(LyricsTask *task);
static void ProcessNextTask(void) {
    if (!gSession || !gRequestContext) return;
    while (gLyricsTaskQueue.count && gActiveLyricsTasks.count < 2) {
        LyricsTask *task = gLyricsTaskQueue.firstObject;
        [gLyricsTaskQueue removeObjectAtIndex:0];
        if (!DateLyricsAppleTaskIsCurrent(task)) continue;
        [gActiveLyricsTasks addObject:task];
        task.startedAt = CACurrentMediaTime();
        DateLyricsDebugLog(@"[Apple] request-start storeID=%ld adamID=%ld active=%lu",
            (long)task.iTunesStoreID, (long)task.lyricsAdamID, (unsigned long)gActiveLyricsTasks.count);
        DateLyricsFetchAppleTask(task);
    }
}

static void DateLyricsFetchAppleTask(LyricsTask *task) {
    ICMusicKitURLRequest *request = [[%c(ICMusicKitURLRequest) alloc] initWithURL:task.lyricURL requestContext:gRequestContext];
    [gSession enqueueDataRequest:request withCompletionHandler:^(ICURLResponse *response, NSError *error) {
        dispatch_async(gLyricsQueue, ^{
            [gActiveLyricsTasks removeObject:task];
            DateLyricsDebugLog(@"[Apple] request-complete storeID=%ld seconds=%.3f current=%d error=%@",
                (long)task.iTunesStoreID, CACurrentMediaTime() - task.startedAt,
                DateLyricsAppleTaskIsCurrent(task), error ? @"yes" : @"no");
            if (!DateLyricsAppleTaskIsCurrent(task)) {
                ProcessNextTask();
                return;
            }

            BOOL taskFailed = NO;

            if (error) {
                taskFailed = YES;
            } else if (![response.bodyData isKindOfClass:[NSData class]]) {
                taskFailed = YES;
            } else {
                id object = [NSJSONSerialization JSONObjectWithData:response.bodyData options:0 error:nil];
                if ([object isKindOfClass:[NSDictionary class]]) {
                    if (((NSDictionary *)object)[@"data"]) {
                        object = ((NSDictionary *)object)[@"data"];
                        if ([object isKindOfClass:[NSArray class]]) {
                            object = ((NSArray *)object).firstObject;
                            if ([object isKindOfClass:[NSDictionary class]]) {
                                object = ((NSDictionary *)object)[@"attributes"];
                                if ([object isKindOfClass:[NSDictionary class]]) {
                                    object = ((NSDictionary *)object)[@"ttml"];
                                }
                            }
                        }
                    } else if (((NSDictionary *)object)[@"ttml"]) {
                        object = ((NSDictionary *)object)[@"ttml"];
                    }
                }

                if (![object isKindOfClass:[NSString class]]) {
                    taskFailed = YES;
                } else {
                    NSData *data = [(NSString *)object dataUsingEncoding:NSUTF8StringEncoding];
                    BOOL hasWordTiming = NO;
                    // fresh network response: never short-circuit on memory cache.
                    DateLyricsParseResult result = data.length > 0
                        ? ParseLyricsData(data, task.iTunesStoreID, task.lyricsAdamID, &hasWordTiming, NO)
                        : DateLyricsParseResultMalformed;

                    if (result == DateLyricsParseResultSuccess) {
                        DateLyricsSetUnsynchronizedLyricsID(task.lyricsAdamID, NO);
                        if (![data writeToFile:task.lyricsFilePath atomically:YES]) {
                            taskFailed = YES;
                        } else {
                            DateLyricsPruneDiskCache();
                            if (!hasWordTiming) {
                                DateLyricsStartMusixmatchFallback(task.iTunesStoreID, task.fallbackTitle,
                                    task.fallbackArtist, task.fallbackAlbum, task.fallbackDuration, DateLyricsSyncTierLine);
                            }
                        }
                    } else {
                        taskFailed = (result != DateLyricsParseResultNoTiming);
                        if (result == DateLyricsParseResultNoTiming) {
                            DateLyricsSetUnsynchronizedLyricsID(task.lyricsAdamID, YES);
                            DateLyricsDebugLog(@"[Parser] Marked lyricsAdamID=%ld as transcript-only; skipping retries", (long)task.lyricsAdamID);
                            DateLyricsStartMusixmatchFallback(task.iTunesStoreID, task.fallbackTitle,
                                task.fallbackArtist, task.fallbackAlbum, task.fallbackDuration, DateLyricsSyncTierNone);
                        }
                        [[NSFileManager defaultManager] removeItemAtPath:task.lyricsFilePath error:nil];
                    }
                }
            }

            if (taskFailed) {
                task.retryCount++;
                if (task.retryCount < 3) {
                    NSTimeInterval retryDelay = 0.5 * (1 << (task.retryCount - 1));
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(retryDelay * NSEC_PER_SEC)), gLyricsQueue, ^{
                        if (!DateLyricsAppleTaskIsCurrent(task)) {
                            DateLyricsDebugLog(@"[Apple] Dropping stale retry storeID=%ld adamID=%ld",
                                               (long)task.iTunesStoreID, (long)task.lyricsAdamID);
                            return;
                        }
                        [gLyricsTaskQueue addObject:task];
                        ProcessNextTask();
                    });
                } else {
                    [gPendingLyricsIDs removeObject:@(task.lyricsAdamID)];
                }
            } else {
                [gPendingLyricsIDs removeObject:@(task.lyricsAdamID)];
            }

            if (task.retryCount >= 3) {
                DateLyricsStartMusixmatchFallback(task.iTunesStoreID, task.fallbackTitle,
                    task.fallbackArtist, task.fallbackAlbum, task.fallbackDuration, DateLyricsSyncTierNone);
            }

            ProcessNextTask();
        });
    }];
}

static void AddTaskToQueue(NSInteger iTunesStoreID, NSInteger lyricsAdamID, NSURL *lyricURL,
                           NSString *lyricsFilePath, NSString *fallbackTitle, NSString *fallbackArtist,
                           NSString *fallbackAlbum, NSTimeInterval fallbackDuration) {
    if (iTunesStoreID != gDateLyricsSelectedStoreID || lyricsAdamID != gDateLyricsSelectedAdamID) return;
    if ([gPendingLyricsIDs containsObject:@(lyricsAdamID)]) {
        return;
    }

    LyricsTask *task = [[LyricsTask alloc] init];
    task.iTunesStoreID = iTunesStoreID;
    task.lyricsAdamID = lyricsAdamID;
    task.retryCount = 0;
    task.lyricURL = lyricURL;
    task.lyricsFilePath = lyricsFilePath;
    task.fallbackTitle = fallbackTitle;
    task.fallbackArtist = fallbackArtist;
    task.fallbackAlbum = fallbackAlbum;
    task.fallbackDuration = fallbackDuration;

    task.cacheGeneration = gDateLyricsCacheGeneration;
    task.selectionGeneration = gDateLyricsSelectionGeneration;

    [gLyricsTaskQueue addObject:task];
    [gPendingLyricsIDs addObject:@(lyricsAdamID)];

    ProcessNextTask();
}

%group DateLyricsPrimary

%hook ICURLSession

- (void)enqueueDataRequest:(id)arg1 withCompletionHandler:(ICURLSessionCompletionHandler)arg2 {
    // music can replace its url session or refresh the request context after a
    // token/identity change.  keeping the first objects forever makes all later
    // lyric requests fail after that rotation.
    ICURLSession *session = nil;
    ICMusicKitRequestContext *requestContext = nil;
    if ([arg1 isKindOfClass:%c(ICMusicKitURLRequest)]) {
        ICMusicKitURLRequest *req = arg1;
        session = self;
        requestContext = [req requestContext];
    }
    dispatch_async(gLyricsQueue, ^{
        if (session) {
            gSession = session;
            gRequestContext = requestContext;
        }
        ProcessNextTask();
    });
    %orig;
}

%end

static void DateLyricsProcessNowPlayingClient(MRNowPlayingPlayerClient *client);

%hook MRNowPlayingPlayerClient

- (void)sendContentItemChanges:(NSArray<MRContentItem *> *)contentItems {
    %orig;
    DateLyricsProcessNowPlayingClient(self);
}

%end

static void DateLyricsProcessNowPlayingClient(MRNowPlayingPlayerClient *client) {
    gActivePlayerClient = client;
    if (!gDateLyricsEnabled) return;
    dispatch_async(gLyricsQueue, ^{

        MRContentItem *item = client.nowPlayingContentItem;
        if (!item || ![item respondsToSelector:@selector(metadata)] || !item.metadata) {
            return;
        }
        NSInteger iTunesStoreID = item.metadata.iTunesStoreIdentifier;
        BOOL lyricsAvailable = [item.metadata respondsToSelector:@selector(lyricsAvailable)] && item.metadata.lyricsAvailable;
        NSInteger adamID = [item.metadata respondsToSelector:@selector(lyricsAdamID)]
            ? item.metadata.lyricsAdamID : iTunesStoreID;
        if (iTunesStoreID != gDateLyricsSelectedStoreID) {
            for (NSNumber *track in [gMusixmatchPendingTaskIDs.allKeys copy]) {
                if (track.integerValue == iTunesStoreID) continue;
                DateLyricsCancelProviderLookup(track.integerValue);
            }
        }
        DateLyricsSelectAppleTrack(iTunesStoreID, lyricsAvailable ? adamID : 0);
        NSString *fallbackTitle = DateLyricsMetadataString(item.metadata, @[@"title", @"amLyricsTitle", @"name"]);
        NSString *fallbackArtist = DateLyricsMetadataString(item.metadata, @[@"trackArtistName", @"artist", @"artistName"]);
        NSString *fallbackAlbum = DateLyricsMetadataString(item.metadata, @[@"albumName", @"album", @"collectionName"]);
        NSTimeInterval fallbackDuration = DateLyricsMetadataDuration(item.metadata);

        static NSString *gLastHandledTitle = nil;
        static NSString *gLastHandledArtist = nil;

        if (iTunesStoreID == gLastHandledStoreID &&
            adamID == gLastHandledAdamID &&
            lyricsAvailable == gLastHandledLyricsAvailable &&
            (!fallbackTitle || (gLastHandledTitle && [fallbackTitle isEqualToString:gLastHandledTitle])) &&
            (!fallbackArtist || (gLastHandledArtist && [fallbackArtist isEqualToString:gLastHandledArtist]))) {
            return;
        }

        gLastHandledStoreID = iTunesStoreID;
        gLastHandledAdamID = adamID;
        gLastHandledLyricsAvailable = lyricsAvailable;
        gLastHandledTitle = [fallbackTitle copy];
        gLastHandledArtist = [fallbackArtist copy];

        if (!lyricsAvailable) {
            // a track can lose its lyrics flag while switching items.  remove
            // any score left from an earlier fetch so springboard cannot load
            // it when the new anchor arrives.
            if (iTunesStoreID > 0) {
                DateLyricsInvalidateAppleScore(iTunesStoreID);
                DateLyricsStartMusixmatchFallback(iTunesStoreID, fallbackTitle, fallbackArtist,
                    fallbackAlbum, fallbackDuration, DateLyricsSyncTierNone);
            }
            return;
        }

        if (iTunesStoreID <= 0) {
            return;
        }

        NSInteger lyricsAdamID;
        NSString *lyricURLString;
        NSString *storefront = DateLyricsStorefront();
        NSString *locale = DateLyricsPreferredLocale();
        if ([item.metadata respondsToSelector:@selector(lyricsAdamID)]) {
            lyricsAdamID = item.metadata.lyricsAdamID;
            lyricURLString = [NSString stringWithFormat:@"https://amp-api.music.apple.com/v1/catalog/%@/songs/%lld/syllable-lyrics?l=%@", storefront, (long long)lyricsAdamID, locale];
        } else {
            lyricsAdamID = iTunesStoreID;
            lyricURLString = [NSString stringWithFormat:@"https://se2.itunes.apple.com/WebObjects/MZStoreElements2.woa/wa/ttmlLyrics?id=%lld&l=%@", (long long)iTunesStoreID, locale];
        }
        if (lyricsAdamID <= 0) {
            DateLyricsStartMusixmatchFallback(iTunesStoreID, fallbackTitle, fallbackArtist,
                fallbackAlbum, fallbackDuration, DateLyricsSyncTierNone);
            return;
        }


        NSString *lyricsRoot = GetLyricsRootPath();
        NSString *lyricsFilePath = [lyricsRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"syllable-lyrics_%lld.xml", (long long)lyricsAdamID]];
        if (DateLyricsIsUnsynchronizedLyricsID(lyricsAdamID)) {
            DateLyricsStartMusixmatchFallback(iTunesStoreID, fallbackTitle, fallbackArtist,
                fallbackAlbum, fallbackDuration, DateLyricsSyncTierNone);
            return;
        }
        BOOL lyricsCacheExists = [[NSFileManager defaultManager] fileExistsAtPath:lyricsFilePath];
        if (lyricsCacheExists) {
            NSData *cachedData = DateLyricsStorageReadData(lyricsFilePath);
            BOOL hasWordTiming = NO;
            // existing xml may reuse the memory cache for speed.
            DateLyricsParseResult result = ParseLyricsData(cachedData, iTunesStoreID, lyricsAdamID, &hasWordTiming, YES);
            if (result == DateLyricsParseResultSuccess) {
                if (!hasWordTiming) {
                    DateLyricsStartMusixmatchFallback(iTunesStoreID, fallbackTitle, fallbackArtist,
                        fallbackAlbum, fallbackDuration, DateLyricsSyncTierLine);
                }
                return;
            }
            [[NSFileManager defaultManager] removeItemAtPath:lyricsFilePath error:nil];
            if (result == DateLyricsParseResultNoTiming) {
                DateLyricsSetUnsynchronizedLyricsID(lyricsAdamID, YES);
                DateLyricsDebugLog(@"[Parser] Marked cached lyricsAdamID=%ld as transcript-only; skipping fetch", (long)lyricsAdamID);
                DateLyricsStartMusixmatchFallback(iTunesStoreID, fallbackTitle, fallbackArtist,
                    fallbackAlbum, fallbackDuration, DateLyricsSyncTierNone);
                return;
            }
        }

        NSURL *lyricURL = [NSURL URLWithString:lyricURLString];
        if (lyricURL) {
            AddTaskToQueue(iTunesStoreID, lyricsAdamID, lyricURL, lyricsFilePath,
                fallbackTitle, fallbackArtist, fallbackAlbum, fallbackDuration);
        } else {
            DateLyricsStartMusixmatchFallback(iTunesStoreID, fallbackTitle, fallbackArtist,
                fallbackAlbum, fallbackDuration, DateLyricsSyncTierNone);
        }
    });
}

%end

%group DateLyricsSpringBoard

%hook SBScreenSleepCoordinatorBacklightEnvironment
- (instancetype)initWithCoordinator:(id)coordinator {
    id result = %orig;
    gDateLyricsBacklightEnvironment = result;
    return result;
}
- (void)willBeginRenderSession:(id)session {
    DateLyricsLogAODRender(self, @"begin", nil);
    %orig;
}
- (void)invalidateContentForReason:(id)reason {
    if (gDateLyricsDebugLogging) {
        DateLyricsDebugLog(@"[AOD:INVALIDATE] seq=%lu aod=%d wall=%@ presentation=%@ reason=%@",
            (unsigned long)gDateLyricsAODRefreshSequence, gDateLyricsAlwaysOnDisplay,
            DateLyricsAODDateDescription(NSDate.date), DateLyricsAODDateDescription(
                [self respondsToSelector:@selector(presentationDate)] ? self.presentationDate : nil), reason);
    }
    %orig;
}
- (void)willEndRenderSession:(id)session {
    DateLyricsLogAODRender(self, @"end", nil);
    %orig;
}
- (void)updateToDateSpecifier:(id)specifier sceneContentsUpdated:(id)completion {
    DateLyricsLogAODRender(self, @"update-before", specifier);
    %orig;
    DateLyricsLogAODRender(self, @"update-after", specifier);
}

%end

static _UIAnimatingLabel *DateLyricsSearchAnimatingLabel(UIView *view, Class labelClass) {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:labelClass]) {
            return (_UIAnimatingLabel *)subview;
        }
        _UIAnimatingLabel *nestedLabel = DateLyricsSearchAnimatingLabel(subview, labelClass);
        if (nestedLabel) return nestedLabel;
    }
    return nil;
}

// cache weakly on the host view; verify ancestry before reusing the label.
static _UIAnimatingLabel *DateLyricsFindAnimatingLabel(UIView *view) {
    if (![view isKindOfClass:UIView.class]) return nil;
    Class labelClass = NSClassFromString(@"_UIAnimatingLabel");
    if (!labelClass) return nil;

    DateLyricsWeakBox *box = objc_getAssociatedObject(view, kDateLyricsCachedLabelKey);
    _UIAnimatingLabel *cached = box.object;
    // only trust the cache while the label is still installed under this view.
    if ([cached isKindOfClass:labelClass] && [cached isDescendantOfView:view]) {
        objc_setAssociatedObject(cached, kDateLyricsIsDateLabelKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return cached;
    }
    if (box) box.object = nil;

    _UIAnimatingLabel *label = DateLyricsSearchAnimatingLabel(view, labelClass);
    if (label) {
        // let text hooks identify date labels without walking the view hierarchy.
        objc_setAssociatedObject(label, kDateLyricsIsDateLabelKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!box) {
            box = [DateLyricsWeakBox new];
            objc_setAssociatedObject(view, kDateLyricsCachedLabelKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        box.object = label;
    }
    return label;
}

static NSSet<_UIAnimatingLabel *> *DateLyricsAttachedDateLabels(void) {
    NSMutableSet *labels = [NSMutableSet set];
    for (UIView *view in gDateLyricsDateViews) {
        _UIAnimatingLabel *label = DateLyricsFindAnimatingLabel(view);
        if (label) [labels addObject:label];
    }
    for (UIView *view in gDateLyricsWidgetSlots) {
        _UIAnimatingLabel *label = DateLyricsFindAnimatingLabel(view);
        if (label) [labels addObject:label];
    }
    return labels;
}

static UIView *DateLyricsFindWidgetHostView(UIView *view) {
    if (![view isKindOfClass:UIView.class]) return nil;

    DateLyricsWeakBox *box = objc_getAssociatedObject(view, kDateLyricsCachedWidgetHostKey);
    UIView *cached = box.object;
    if ([cached isKindOfClass:UIView.class] && (cached == view || [cached isDescendantOfView:view])) {
        return cached;
    }

    UIView *host = nil;
    if ([NSStringFromClass(view.class) isEqualToString:@"CHUISWidgetHostViewControllerView"]) {
        host = view;
    } else {
        for (UIView *subview in view.subviews) {
            host = DateLyricsFindWidgetHostView(subview);
            if (host) break;
        }
    }

    if (host) {
        if (!box) {
            box = [DateLyricsWeakBox new];
            objc_setAssociatedObject(view, kDateLyricsCachedWidgetHostKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        box.object = host;
    } else {
        objc_setAssociatedObject(view, kDateLyricsCachedWidgetHostKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
    return host;
}

static CSProminentSubtitleDateView *DateLyricsFindSiblingDateView(UIView *view) {
    DateLyricsWeakBox *cachedBox = objc_getAssociatedObject(view, "DateLyricsCachedSiblingDateView");
    if (cachedBox && [cachedBox.object isKindOfClass:NSClassFromString(@"CSProminentSubtitleDateView")]) {
        return (CSProminentSubtitleDateView *)cachedBox.object;
    }

    UIView *containerView = view.superview;
    if (![containerView isKindOfClass:UIView.class]) return nil;

    Class dateClass = NSClassFromString(@"CSProminentSubtitleDateView");
    for (UIView *subview in containerView.subviews) {
        if ([subview isKindOfClass:dateClass]) {
            DateLyricsWeakBox *box = [DateLyricsWeakBox new];
            box.object = subview;
            objc_setAssociatedObject(view, "DateLyricsCachedSiblingDateView", box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return (CSProminentSubtitleDateView *)subview;
        }
    }

    objc_setAssociatedObject(view, "DateLyricsCachedSiblingDateView", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return nil;
}

static CSProminentSubtitleDateView *DateLyricsFindAncestorDateView(UIView *view) {
    Class dateClass = NSClassFromString(@"CSProminentSubtitleDateView");
    UIView *currentView = view;
    while ([currentView isKindOfClass:UIView.class]) {
        if ([currentView isKindOfClass:dateClass]) {
            return (CSProminentSubtitleDateView *)currentView;
        }
        currentView = currentView.superview;
    }
    return nil;
}

static BOOL DateLyricsWidgetSlotMatchesDateSlot(UIView *widgetSlot, UIView *dateView) {
    if (![widgetSlot isKindOfClass:UIView.class] || ![dateView isKindOfClass:UIView.class]) return NO;

    CGRect slotFrame = widgetSlot.frame;
    if (CGRectIsEmpty(slotFrame)) {
        return NO;
    }

    CGRect dateFrame = dateView.frame;
    if (CGRectIntersectsRect(slotFrame, dateFrame)) {
        return YES;
    }

    return CGRectGetMaxY(slotFrame) >= CGRectGetMinY(dateFrame) - 4.0 &&
           CGRectGetMinY(slotFrame) <= CGRectGetMaxY(dateFrame) + 4.0;
}

static UIView *DateLyricsFindMatchingWidgetSlotForDateView(UIView *dateView) {
    UIView *containerView = dateView.superview;
    if (![containerView isKindOfClass:UIView.class] || ![dateView isKindOfClass:UIView.class]) return nil;

    Class emptyElementClass = NSClassFromString(@"CSProminentEmptyElementView");
    for (UIView *subview in containerView.subviews) {
        if (![subview isKindOfClass:emptyElementClass]) continue;
        if (!DateLyricsFindWidgetHostView(subview)) continue;
        if (!DateLyricsWidgetSlotMatchesDateSlot(subview, dateView)) continue;
        return subview;
    }
    return nil;
}

static void DateLyricsSetWidgetDateSlotHidden(UIView *containerView, UIView *dateView, BOOL hidden) {
    if (![containerView isKindOfClass:UIView.class] || ![dateView isKindOfClass:UIView.class]) return;

    Class emptyElementClass = NSClassFromString(@"CSProminentEmptyElementView");
    for (UIView *subview in containerView.subviews) {
        if (![subview isKindOfClass:emptyElementClass]) continue;
        if (!DateLyricsFindWidgetHostView(subview)) continue;
        BOOL matchesDateSlot = DateLyricsWidgetSlotMatchesDateSlot(subview, dateView);
        if (hidden && !matchesDateSlot) continue;
        if (!hidden && !matchesDateSlot && !objc_getAssociatedObject(subview, kDateLyricsOriginalHiddenKey)) continue;

        if (hidden) {
            if (!objc_getAssociatedObject(subview, kDateLyricsOriginalHiddenKey)) {
                objc_setAssociatedObject(subview, kDateLyricsOriginalHiddenKey, @(subview.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (!subview.hidden) subview.hidden = YES;
        } else {
            NSNumber *originalHidden = objc_getAssociatedObject(subview, kDateLyricsOriginalHiddenKey);
            if (originalHidden) {
                BOOL shouldHide = originalHidden.boolValue;
                if (subview.hidden != shouldHide) subview.hidden = shouldHide;
                objc_setAssociatedObject(subview, kDateLyricsOriginalHiddenKey, nil, OBJC_ASSOCIATION_ASSIGN);
            }
        }
    }
}

static BOOL DateLyricsShouldSuppressStockDate(void) {
    if (!gDateLyricsEnabled || !gDateLyricsCurrentScore || !gDateLyricsLocalAnchor) return NO;
    if ([gDateLyricsLocalAnchor[@"rate"] floatValue] <= 0.0f) return NO;
    return DateLyricsHasRenderableLyricPayload();
}

static BOOL DateLyricsHasRenderableLyricPayload(void) {
    if (!gDateLyricsEnabled) return NO;
    NSString *text = gDateLyricsCurrentPayload[@"text"];
    return [text isKindOfClass:NSString.class] && text.length > 0;
}

static void DateLyricsInvalidateLabelRenderCache(_UIAnimatingLabel *label, DateLyricsCacheInvalidationReason reason) {
    if (![label isKindOfClass:UILabel.class]) return;
    objc_setAssociatedObject(label, kDateLyricsRenderCacheKey, nil, OBJC_ASSOCIATION_ASSIGN);

    gDateLyricsCacheForced++;
    switch (reason) {
        case DateLyricsCacheInvalidationReasonInitialAttach: gDateLyricsCacheReasonInitialAttach++; break;
        case DateLyricsCacheInvalidationReasonStockRestore: gDateLyricsCacheReasonStockRestore++; break;
        case DateLyricsCacheInvalidationReasonTransitionCompletion: gDateLyricsCacheReasonTransitionCompletion++; break;
        case DateLyricsCacheInvalidationReasonExternalContentChanged: gDateLyricsCacheReasonExternal++; break;
    }
}

static BOOL DateLyricsApplyDateLabel(_UIAnimatingLabel *label) {
    if (!label) return NO;
    BOOL layoutApplied = [label _amlApplyCurrentLyric];
    if (layoutApplied) gDateLyricsCacheLayoutApplies++;
    return layoutApplied;
}

static BOOL DateLyricsForceApplyDateLabel(_UIAnimatingLabel *label, DateLyricsCacheInvalidationReason reason) {
    if (!label) return NO;
    DateLyricsInvalidateLabelRenderCache(label, reason);
    BOOL layoutApplied = [label _amlApplyCurrentLyric];
    if (layoutApplied) gDateLyricsCacheLayoutApplies++;
    return layoutApplied;
}


static void DateLyricsResetHybridVisibilityIfNeeded(CSProminentSubtitleDateView *dateView) {
    if (![dateView isKindOfClass:UIView.class]) return;
    if (![objc_getAssociatedObject(dateView, kDateLyricsForcedWidgetDateVisibleKey) boolValue]) return;
    if (DateLyricsFindMatchingWidgetSlotForDateView(dateView)) return;

    NSNumber *originalHidden = objc_getAssociatedObject(dateView, kDateLyricsOriginalHiddenKey);
    dateView.hidden = originalHidden ? originalHidden.boolValue : NO;
    objc_setAssociatedObject(dateView, kDateLyricsOriginalHiddenKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(dateView, kDateLyricsForcedWidgetDateVisibleKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static BOOL DateLyricsLabelHasResidualLyricState(_UIAnimatingLabel *label) {
    return [objc_getAssociatedObject(label, kDateLyricsLabelShowingLyricKey) boolValue] ||
        objc_getAssociatedObject(label, kDateLyricsRenderCacheKey) ||
        objc_getAssociatedObject(label, kDateLyricsOriginalFontKey) ||
        objc_getAssociatedObject(label, kDateLyricsOriginalAttributedTextKey) ||
        objc_getAssociatedObject(label, kDateLyricsOriginalTextKey) ||
        objc_getAssociatedObject(label, kDateLyricsOriginalTextColorKey) ||
        objc_getAssociatedObject(label, kDateLyricsOriginalNumberOfLinesKey) ||
        objc_getAssociatedObject(label, kDateLyricsOriginalAdjustsFontSizeKey) ||
        objc_getAssociatedObject(label, kDateLyricsOriginalLineBreakModeKey) ||
        objc_getAssociatedObject(label, kDateLyricsOriginalTextAlignmentKey) ||
        objc_getAssociatedObject(label, kDateLyricsOriginalClipsToBoundsKey) ||
        objc_getAssociatedObject(label, kDateLyricsOutgoingSnapshotKey) ||
        objc_getAssociatedObject(label, kDateLyricsFrozenFrameKey) ||
        objc_getAssociatedObject(label, kDateLyricsAnimatingTransitionKey) ||
        objc_getAssociatedObject(label, kDateLyricsProgressSlotPoolKey) ||
        objc_getAssociatedObject(label, kDateLyricsDisplayMorphKey) ||
        objc_getAssociatedObject(label, kDateLyricsMarqueeContainerKey) ||
        objc_getAssociatedObject(label, kDateLyricsMarqueeTrackKey) ||
        objc_getAssociatedObject(label, kDateLyricsMarqueeActiveKey);
}

static void DateLyricsRestoreSystemDateLabel(_UIAnimatingLabel *label) {
    if (![label isKindOfClass:UILabel.class]) return;
    if (!DateLyricsLabelHasResidualLyricState(label)) return;
    DateLyricsCancelDisplayMorph(label);
    DateLyricsRemoveProgressOverlay(label);
    UIView *outgoingSnapshot = objc_getAssociatedObject(label, kDateLyricsOutgoingSnapshotKey);
    [outgoingSnapshot removeFromSuperview];
    objc_setAssociatedObject(label, kDateLyricsOutgoingSnapshotKey, nil, OBJC_ASSOCIATION_ASSIGN);
    DateLyricsStopMarquee(label);
    CSProminentSubtitleDateView *dateView = DateLyricsFindAncestorDateView(label);
    objc_setAssociatedObject(label, kDateLyricsLabelShowingLyricKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsLastRenderedAttrTextKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsLastRenderedTextKey, nil, OBJC_ASSOCIATION_ASSIGN);
    DateLyricsInvalidateLabelRenderCache(label, DateLyricsCacheInvalidationReasonStockRestore);
    objc_setAssociatedObject(label, @selector(_amlApplyCurrentLyric), nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, @selector(previousLineId), nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsAnimatingTransitionKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsSplitPlanKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsFrozenFrameKey, nil, OBJC_ASSOCIATION_ASSIGN);
    // bumping the generation invalidates any in-flight completion block, so it
    // cannot resurrect a lyric on top of the stock date after we restore.
    NSUInteger generation = [objc_getAssociatedObject(label, kDateLyricsTransitionGenerationKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(label, kDateLyricsTransitionGenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [label.layer removeAllAnimations];
    label.alpha = 1.0;
    label.transform = CGAffineTransformIdentity;

    NSNumber *origClips = objc_getAssociatedObject(label, kDateLyricsOriginalClipsToBoundsKey);
    if (origClips) {
        label.clipsToBounds = origClips.boolValue;
        objc_setAssociatedObject(label, kDateLyricsOriginalClipsToBoundsKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }

    UIFont *origFont = objc_getAssociatedObject(label, kDateLyricsOriginalFontKey);
    if (origFont) {
        label.font = origFont;
        objc_setAssociatedObject(label, kDateLyricsOriginalFontKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }

    UIColor *origColor = objc_getAssociatedObject(label, kDateLyricsOriginalTextColorKey);
    if (origColor) {
        label.textColor = origColor;
        objc_setAssociatedObject(label, kDateLyricsOriginalTextColorKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }

    id origNumLines = objc_getAssociatedObject(label, kDateLyricsOriginalNumberOfLinesKey);
    if (origNumLines) {
        label.numberOfLines = [origNumLines integerValue];
        objc_setAssociatedObject(label, kDateLyricsOriginalNumberOfLinesKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }

    id origAdjusts = objc_getAssociatedObject(label, kDateLyricsOriginalAdjustsFontSizeKey);
    if (origAdjusts) {
        label.adjustsFontSizeToFitWidth = [origAdjusts boolValue];
        objc_setAssociatedObject(label, kDateLyricsOriginalAdjustsFontSizeKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }



    NSNumber *origAlignment = objc_getAssociatedObject(label, kDateLyricsOriginalTextAlignmentKey);
    if (origAlignment) {
        label.textAlignment = (NSTextAlignment)origAlignment.integerValue;
        objc_setAssociatedObject(label, kDateLyricsOriginalTextAlignmentKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
    id origLineBreak = objc_getAssociatedObject(label, kDateLyricsOriginalLineBreakModeKey);
    if (origLineBreak) {
        label.lineBreakMode = (NSLineBreakMode)[origLineBreak integerValue];
        objc_setAssociatedObject(label, kDateLyricsOriginalLineBreakModeKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }

    if (!dateView) {
        objc_setAssociatedObject(label, kDateLyricsLabelShowingLyricKey, nil, OBJC_ASSOCIATION_ASSIGN);
        NSAttributedString *detachedAttr = objc_getAssociatedObject(label, kDateLyricsOriginalAttributedTextKey);
        NSString *detachedText = objc_getAssociatedObject(label, kDateLyricsOriginalTextKey);
        if (detachedAttr) label.attributedText = detachedAttr;
        else if (detachedText) label.text = detachedText;
        objc_setAssociatedObject(label, kDateLyricsOriginalAttributedTextKey, nil, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(label, kDateLyricsOriginalTextKey, nil, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(label, kDateLyricsIsDateLabelKey, nil, OBJC_ASSOCIATION_ASSIGN);
        return;
    }

    label.hidden = NO;
    if (![objc_getAssociatedObject(dateView, kDateLyricsForcedWidgetDateVisibleKey) boolValue]) dateView.hidden = NO;
    // the saved date is a formatting backup for detached labels, not the
    // current system date. avoid feeding old/nil/current strings through the
    // native animating label during the same restore.
    objc_setAssociatedObject(label, kDateLyricsOriginalAttributedTextKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(label, kDateLyricsOriginalTextKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(dateView, kDateLyricsRestoringStockDateKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [UIView performWithoutAnimation:^{
        if ([dateView respondsToSelector:@selector(_updateLabel)]) [dateView performSelector:@selector(_updateLabel)];
        [label setNeedsLayout]; [dateView setNeedsLayout]; [dateView layoutIfNeeded];
    }];
    [label.layer removeAllAnimations];
    objc_setAssociatedObject(dateView, kDateLyricsRestoringStockDateKey, nil, OBJC_ASSOCIATION_ASSIGN);
    DateLyricsDebugLog(@"[STOCK:RESTORE] label=%p text='%@' subviews=%lu parentViews=%lu",
        label, label.attributedText.string ?: label.text, (unsigned long)label.subviews.count,
        (unsigned long)label.superview.subviews.count);

}

static void DateLyricsUpdateWidgetDateView(UIView *widgetSlot) {
    if (!DateLyricsRenderingActive()) return;
    if (![widgetSlot isKindOfClass:UIView.class]) return;
    if (!DateLyricsFindWidgetHostView(widgetSlot)) return;

    CSProminentSubtitleDateView *dateView = DateLyricsFindSiblingDateView(widgetSlot);
    if (!dateView) return;

    NSDictionary *payload = DateLyricsCurrentRenderablePayload();
    BOOL hasLyric = [payload[@"text"] isKindOfClass:NSString.class];

    if (!gDateLyricsEnabled) hasLyric = NO;

    if (!hasLyric) {
        if ([objc_getAssociatedObject(dateView, kDateLyricsForcedWidgetDateVisibleKey) boolValue]) {
            NSNumber *originalHidden = objc_getAssociatedObject(dateView, kDateLyricsOriginalHiddenKey);
            if (originalHidden) {
                dateView.hidden = originalHidden.boolValue;
                objc_setAssociatedObject(dateView, kDateLyricsOriginalHiddenKey, nil, OBJC_ASSOCIATION_ASSIGN);
            }
            DateLyricsSetWidgetDateSlotHidden(widgetSlot.superview, dateView, NO);
            objc_setAssociatedObject(dateView, kDateLyricsForcedWidgetDateVisibleKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
        return;
    }

    BOOL wasForced = [objc_getAssociatedObject(dateView, kDateLyricsForcedWidgetDateVisibleKey) boolValue];
    if (wasForced && widgetSlot.hidden && !dateView.hidden) return;

    if (!wasForced && !objc_getAssociatedObject(dateView, kDateLyricsOriginalHiddenKey)) {
        objc_setAssociatedObject(dateView, kDateLyricsOriginalHiddenKey, @(dateView.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (dateView.hidden) dateView.hidden = NO;
    if (!wasForced || !widgetSlot.hidden) {
        DateLyricsSetWidgetDateSlotHidden(widgetSlot.superview, dateView, YES);
    }
    objc_setAssociatedObject(dateView, kDateLyricsForcedWidgetDateVisibleKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!wasForced) {
        DateLyricsForceApplyDateLabel(DateLyricsFindAnimatingLabel(dateView), DateLyricsCacheInvalidationReasonInitialAttach);
    }
    [dateView setNeedsLayout];
}

static void DateLyricsSetCoverSheetVisible(BOOL visible, NSString *reason) {
    if (gDateLyricsCoverSheetVisible == visible) return;
    gDateLyricsCoverSheetVisible = visible;
    ++gDateLyricsRenderGeneration;
    ++gDateLyricsDisplayModeRequestGeneration;
    DateLyricsDebugLog(@"[VISIBILITY] visible=%d screen=%d aod=%d reason=%@", visible, gDateLyricsScreenIsOn, gDateLyricsAlwaysOnDisplay, reason);
    // uikit may retire the interactive coversheet while native aod continues
    // displaying its cached scene. its disappearance is not a display-off event.
    if (!DateLyricsRenderingActive()) {
        DateLyricsCancelTicker();
        DateLyricsSuspendPauseHideTimer();
        DateLyricsClearEarlyLinePreview();
        for (_UIAnimatingLabel *label in DateLyricsAttachedDateLabels()) {
            DateLyricsCancelDisplayMorph(label);
            DateLyricsCancelLabelTransition(label);
            DateLyricsStopMarquee(label);
            DateLyricsRemoveProgressOverlay(label);
        }
        return;
    }
    gDateLyricsLastResolvedElapsed = -1.0;
    gDateLyricsLastResolvedAnchorGeneration = NSUIntegerMax;
    DateLyricsScheduleTicker();
    DateLyricsApplyCurrentLineToAllCoverSheets();
    DateLyricsRequestNowPlayingInfo();
}

%hook CSCoverSheetViewController
- (void)viewWillAppear:(BOOL)animated {
    // resume before uikit draws even the first sliver of an interactive reveal.
    DateLyricsSetCoverSheetVisible(YES, @"will appear");
    %orig;
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // a cancelled interactive dismissal also ends in didappear.
    DateLyricsSetCoverSheetVisible(YES, @"did appear");
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    // do not stop at willdisappear: its pixels are still visible while sliding
    // away, and an interactive gesture can be cancelled.
    DateLyricsSetCoverSheetVisible(NO, @"did disappear");
}
%end

%hook CSProminentSubtitleDateView

- (void)didMoveToWindow {
    %orig;
    if (!self.window) {
        if (gDateLyricsDateViews) [gDateLyricsDateViews removeObject:self];
        _UIAnimatingLabel *label = DateLyricsFindAnimatingLabel(self);
        DateLyricsCancelDisplayMorph(label);
        DateLyricsStopMarquee(label);
        DateLyricsRemoveProgressOverlay(label);
        if (gDateLyricsDateViews.count == 0 && gDateLyricsWidgetSlots.count == 0) {
            DateLyricsCancelTicker();
            DateLyricsSuspendPauseHideTimer();
        }
        return;
    }
    if (gDateLyricsDateViews) [gDateLyricsDateViews addObject:self];
    DateLyricsResetHybridVisibilityIfNeeded(self);
    DateLyricsForceApplyDateLabel(DateLyricsFindAnimatingLabel(self), DateLyricsCacheInvalidationReasonInitialAttach);
    DateLyricsScheduleTicker();
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    %orig;
    if (!DateLyricsRenderingActive()) return;

    _UIAnimatingLabel *label = DateLyricsFindAnimatingLabel(self);
    if (!label) return;

    DateLyricsResetHybridVisibilityIfNeeded(self);

    NSDictionary *payload = DateLyricsCurrentRenderablePayload();
    NSString *lyric = payload[@"text"];
    if (lyric.length > 0 && gDateLyricsEnabled) {
        label.hidden = NO;
        // while a transition runs, hold the label at the frame captured when it
        // started. uikit will otherwise re-size the label to its new (shorter or
        // longer) text mid-animation, which is what tears the outgoing and
        // incoming lines into each other.
        NSValue *frozen = objc_getAssociatedObject(label, kDateLyricsFrozenFrameKey);
        if (frozen) {
            CGRect frozenFrame = frozen.CGRectValue;
            if (!CGRectEqualToRect(label.frame, frozenFrame)) {
                label.frame = frozenFrame;
            }
            return;
        }

        CGRect frame = label.frame;
        frame.origin.x = 0.0;
        frame.size.width = self.bounds.size.width;
        if (!CGRectEqualToRect(frame, label.frame)) {
            label.frame = frame;
        }
        [label _amlApplyCurrentLyric];
    } else {
        DateLyricsRestoreSystemDateLabel(label);
        if (!DateLyricsShouldSuppressStockDate()) {
            label.hidden = NO;
        }
    }
}

- (void)_updateLabel {
    %orig;
    if ([objc_getAssociatedObject(self, kDateLyricsRestoringStockDateKey) boolValue]) return;
    _UIAnimatingLabel *label = DateLyricsFindAnimatingLabel(self);
    if (!label) return;
    BOOL lyricActive = DateLyricsHasRenderableLyricPayload() && [objc_getAssociatedObject(label, kDateLyricsLabelShowingLyricKey) boolValue];
    if (lyricActive) {
        DateLyricsApplyDateLabel(label);
    } else {
        DateLyricsForceApplyDateLabel(label, DateLyricsCacheInvalidationReasonInitialAttach);
    }
}

- (void)setDate:(id)date {
    if (gDateLyricsDebugLogging && gDateLyricsAlwaysOnDisplay) {
        DateLyricsDebugLog(@"[AOD:DATEVIEW] seq=%lu wall=%@ applied=%@ line=%@",
            (unsigned long)gDateLyricsAODRefreshSequence, DateLyricsAODDateDescription(NSDate.date),
            DateLyricsAODDateDescription(date), gDateLyricsCurrentPayload[@"lineId"] ?: @"-");
    }
    %orig;
    if ([objc_getAssociatedObject(self, kDateLyricsRestoringStockDateKey) boolValue]) return;
    _UIAnimatingLabel *label = DateLyricsFindAnimatingLabel(self);
    if (!label) return;
    BOOL lyricActive = DateLyricsHasRenderableLyricPayload() && [objc_getAssociatedObject(label, kDateLyricsLabelShowingLyricKey) boolValue];
    if (lyricActive) {
        DateLyricsApplyDateLabel(label);
    } else {
        DateLyricsForceApplyDateLabel(label, DateLyricsCacheInvalidationReasonInitialAttach);
    }
}

%end

%hook CSProminentEmptyElementView

- (void)didMoveToWindow {
    %orig;
    if (!self.window) {
        if (gDateLyricsWidgetSlots) [gDateLyricsWidgetSlots removeObject:self];
        return;
    }
    if (gDateLyricsWidgetSlots) [gDateLyricsWidgetSlots addObject:self];
    DateLyricsUpdateWidgetDateView(self);
}

- (void)layoutSubviews {
    %orig;
    if (!self.window) return;
    if (gDateLyricsWidgetSlots && ![gDateLyricsWidgetSlots containsObject:self]) [gDateLyricsWidgetSlots addObject:self];
    DateLyricsUpdateWidgetDateView(self);
}

%end

%hook _UIAnimatingLabel

// these setters fire for every _uianimatinglabel in springboard, not just ours, so
// the very first thing they must do is cheaply establish that this is our label.
// the tag is applied by datelyricsfindanimatinglabel when the date view adopts it.
- (void)didMoveToWindow {
    %orig;
    if (self.window) return;
    DateLyricsCancelDisplayMorph(self);
    DateLyricsStopMarquee(self);
    UIView *outgoingSnapshot = objc_getAssociatedObject(self, kDateLyricsOutgoingSnapshotKey);
    [outgoingSnapshot removeFromSuperview];
    objc_setAssociatedObject(self, kDateLyricsOutgoingSnapshotKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

- (void)didMoveToSuperview {
    %orig;
    if (![objc_getAssociatedObject(self, kDateLyricsIsDateLabelKey) boolValue]) return;

    CSProminentSubtitleDateView *dateView = DateLyricsFindAncestorDateView(self);
    if (!dateView || ![self isDescendantOfView:dateView]) {
        DateLyricsRestoreSystemDateLabel(self);
        objc_setAssociatedObject(self, kDateLyricsIsDateLabelKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
}

- (void)setText:(NSString *)text {
    if (![objc_getAssociatedObject(self, kDateLyricsIsDateLabelKey) boolValue]) {
        %orig;
        return;
    }
    if (![objc_getAssociatedObject(self, kDateLyricsApplyingLyricContentKey) boolValue] &&
        [objc_getAssociatedObject(self, kDateLyricsLabelShowingLyricKey) boolValue] &&
        DateLyricsHasRenderableLyricPayload()) {
        return;
    }
    if (text.length > 0 && [objc_getAssociatedObject(self, kDateLyricsLabelShowingLyricKey) boolValue]) {
        NSMutableAttributedString *cleanStr = [[NSMutableAttributedString alloc] initWithString:text];
        [cleanStr addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, cleanStr.length)];
        self.attributedText = cleanStr;
        return;
    }
    DateLyricsInvalidateLabelRenderCache(self, DateLyricsCacheInvalidationReasonExternalContentChanged);
    [UIView performWithoutAnimation:^{
        %orig;
    }];
}

- (void)setAttributedText:(NSAttributedString *)attributedText {
    if (![objc_getAssociatedObject(self, kDateLyricsIsDateLabelKey) boolValue]) {
        %orig;
        return;
    }
    if (![objc_getAssociatedObject(self, kDateLyricsApplyingLyricContentKey) boolValue] &&
        [objc_getAssociatedObject(self, kDateLyricsLabelShowingLyricKey) boolValue] &&
        DateLyricsHasRenderableLyricPayload()) {
        return;
    }
    if (attributedText.length > 0 && [objc_getAssociatedObject(self, kDateLyricsLabelShowingLyricKey) boolValue]) {
        NSMutableAttributedString *cleanStr = [attributedText mutableCopy];
        [cleanStr addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, cleanStr.length)];
        %orig(cleanStr);
        return;
    }
    DateLyricsInvalidateLabelRenderCache(self, DateLyricsCacheInvalidationReasonExternalContentChanged);
    [UIView performWithoutAnimation:^{
        %orig;
    }];
}

%new
- (BOOL)_amlApplyCurrentLyric {
    if (!DateLyricsRenderingActive()) {
        return YES;
    }
    if (!gDateLyricsEnabled) {
        DateLyricsRestoreSystemDateLabel(self);
        return YES;
    }
    NSDictionary *sourcePayload = DateLyricsCurrentRenderablePayload();
    NSDictionary *payload = sourcePayload;
    NSString *sourceLyric = payload[@"text"];
    if (sourceLyric.length == 0) {
        DateLyricsRestoreSystemDateLabel(self);
        return YES;
    }

    // widen the content-sized stock label before its first lyric render.
    // waiting for layoutsubviews creates a narrow frame and then a visible jump.
    // an active transition keeps its pinned geometry.
    if (!objc_getAssociatedObject(self, kDateLyricsFrozenFrameKey)) {
        CSProminentSubtitleDateView *hostDateView = DateLyricsFindAncestorDateView(self);
        if (hostDateView && self.superview == hostDateView && CGRectGetWidth(hostDateView.bounds) > 1.0) {
            CGRect widened = self.frame;
            widened.origin.x = 0.0;
            widened.size.width = CGRectGetWidth(hostDateView.bounds);
            if (!CGRectEqualToRect(widened, self.frame)) {
                self.frame = widened;
            }
        }
    }

    UIFont *configuredFont = DateLyricsConfiguredFontForLabel(self);
    BOOL isShowingLyric = [objc_getAssociatedObject(self, kDateLyricsLabelShowingLyricKey) boolValue];
    NSDictionary *renderCache = objc_getAssociatedObject(self, kDateLyricsRenderCacheKey);
    NSUInteger appliedStyleGeneration = [objc_getAssociatedObject(self, kDateLyricsAppliedStyleGenerationKey) unsignedIntegerValue];
    BOOL styleNeedsApply = appliedStyleGeneration != gDateLyricsStyleGeneration;
    UIFont *cachedFont = renderCache[@"font"];
    UITraitCollection *cachedTraits = renderCache[@"traits"];
    NSString *cachedDisplayText = renderCache[@"displayText"];
    // text equality alone is not line identity: a repeated chorus line renders
    // the same string, and without an explicit lineid term the cache would hit
    // and swallow the transition into the new line.  the old pointer-identity
    // check on the payload dictionary provided this implicitly.
    id cachedLineId = renderCache[@"lineId"];
    if (cachedLineId == (id)[NSNull null]) cachedLineId = nil;
    id sourceLineId = sourcePayload[@"lineId"];
    DateLyricsDisplayMorph *displayMorph = objc_getAssociatedObject(self, kDateLyricsDisplayMorphKey);
    CFTimeInterval continuingHandoffDeadline = 0;
    if (displayMorph && (![displayMorph.lineID isEqual:sourceLineId] ||
        (displayMorph.deadline > 0 && displayMorph.trackID != [gDateLyricsLocalAnchor[@"trackId"] integerValue]))) {
        if (DateLyricsDisplayMorphCanContinue(displayMorph)) continuingHandoffDeadline = displayMorph.deadline;
        DateLyricsCancelDisplayMorph(self);
        displayMorph = nil;
    }
    BOOL lineMatchesCache = (!cachedLineId && !sourceLineId) || [cachedLineId isEqual:sourceLineId];
    NSString *currentLabelText = self.attributedText.string ?: self.text ?: @"";
    BOOL labelMatchesCache = [cachedDisplayText isKindOfClass:NSString.class] && [currentLabelText isEqualToString:cachedDisplayText];
    BOOL sizingChanged = renderCache &&
        ([renderCache[@"splitLongLines"] boolValue] != gDateLyricsSplitLongLines ||
         [renderCache[@"showAdlibs"] boolValue] != gDateLyricsShowAdlibs ||
         [renderCache[@"marqueeEnabled"] boolValue] != DateLyricsMarqueeAvailableForLabel(self));
    BOOL cachedMarqueeNeeded = [renderCache[@"marqueeNeeded"] boolValue];
    id skippedLineId = objc_getAssociatedObject(self, kDateLyricsMarqueeSkippedLineIdKey);
    BOOL marqueeSkippedThisLine = skippedLineId && [skippedLineId isEqual:sourcePayload[@"lineId"]];
    BOOL marqueeReady = !cachedMarqueeNeeded || marqueeSkippedThisLine ||
        [objc_getAssociatedObject(self, kDateLyricsMarqueeActiveKey) boolValue];
    BOOL cacheMatches = isShowingLyric &&
        [renderCache[@"generation"] unsignedIntegerValue] == gDateLyricsRenderGeneration &&
        [renderCache[@"styleGeneration"] unsignedIntegerValue] == appliedStyleGeneration &&
        fabs([renderCache[@"width"] doubleValue] - CGRectGetWidth(self.bounds)) < 0.5 &&
        !styleNeedsApply && !sizingChanged && [cachedFont isEqual:configuredFont] &&
        [cachedTraits isEqual:self.traitCollection] && labelMatchesCache && lineMatchesCache && marqueeReady;

    if (!cacheMatches && gDateLyricsDebugLogging) {
        DateLyricsDebugLog(@"[CACHE] miss showing=%d gen=%d styleGen=%d width=%d style=%d "
                            "sizing=%d font=%d traits=%d labelText=%d line=%d marquee=%d",
            isShowingLyric,
            [renderCache[@"generation"] unsignedIntegerValue] == gDateLyricsRenderGeneration,
            [renderCache[@"styleGeneration"] unsignedIntegerValue] == appliedStyleGeneration,
            fabs([renderCache[@"width"] doubleValue] - CGRectGetWidth(self.bounds)) < 0.5,
            !styleNeedsApply, !sizingChanged,
            [cachedFont isEqual:configuredFont],
            [cachedTraits isEqual:self.traitCollection],
            labelMatchesCache, lineMatchesCache, marqueeReady);
    }
    if (cacheMatches) {
        gDateLyricsCacheHits++;
        return NO;
    }
    gDateLyricsCacheMisses++;
    BOOL layoutNeeded = NO;

    if (payload && !gDateLyricsShowAdlibs && ![payload[@"wordTimed"] boolValue]) {
        NSString *rawText = payload[@"text"];
        NSString *strippedText = DateLyricsStripParentheses(rawText) ?: @"";
        if (![strippedText isEqualToString:rawText]) {
            NSMutableDictionary *mutablePayload = [payload mutableCopy];
            mutablePayload[@"text"] = strippedText;

            NSUInteger strippedLen = strippedText.length;
            NSNumber *locNum = mutablePayload[@"loc"];
            NSNumber *lenNum = mutablePayload[@"len"];
            if (locNum && lenNum) {
                NSUInteger loc = locNum.unsignedIntegerValue;
                NSUInteger len = lenNum.unsignedIntegerValue;
                if (loc == NSNotFound || loc + len > strippedLen) {
                    [mutablePayload removeObjectForKey:@"loc"];
                    [mutablePayload removeObjectForKey:@"len"];
                }
            }

            NSNumber *bgLocNum = mutablePayload[@"bgLoc"];
            NSNumber *bgLenNum = mutablePayload[@"bgLen"];
            if (bgLocNum && bgLenNum) {
                NSUInteger bgLoc = bgLocNum.unsignedIntegerValue;
                NSUInteger bgLen = bgLenNum.unsignedIntegerValue;
                if (bgLoc == NSNotFound || bgLoc + bgLen > strippedLen) {
                    [mutablePayload removeObjectForKey:@"bgLoc"];
                    [mutablePayload removeObjectForKey:@"bgLen"];
                }
            }
            payload = [mutablePayload copy];
        }
    }
    if (gDateLyricsForceLowercase) payload = DateLyricsPayloadByApplyingLowercaseSafely(payload);
    NSDictionary *renderPayload = DateLyricsSplitPayloadForLabel(payload, self, configuredFont) ?: payload;
    NSString *lyric = renderPayload[@"text"];

    // a later split segment is a new visible lyric. retire the old handoff
    // before its frozen glyphs can overlap that segment's normal transition.
    if (displayMorph && gDateLyricsSplitLongLines && !gDateLyricsAlwaysOnDisplay &&
        !gDateLyricsDisplayWakeInProgress && ![displayMorph.text isEqualToString:lyric]) {
        if (DateLyricsDisplayMorphCanContinue(displayMorph)) continuingHandoffDeadline = displayMorph.deadline;
        DateLyricsCancelDisplayMorph(self);
        displayMorph = nil;
    }

    if (lyric.length == 0) {
        DateLyricsRestoreSystemDateLabel(self);
        return YES;
    }

    NSString *displayText = lyric;
    NSString *previousDisplayText = objc_getAssociatedObject(self, @selector(_amlApplyCurrentLyric));

    NSAttributedString *attrDisplayText = nil;
    NSNumber *locNum = renderPayload[@"loc"];
    NSNumber *lenNum = renderPayload[@"len"];
        NSNumber *bgLocNum = renderPayload[@"bgLoc"];
        NSNumber *bgLenNum = renderPayload[@"bgLen"];
        NSNumber *completedLocNum = renderPayload[@"completedLoc"];
        NSNumber *completedLenNum = renderPayload[@"completedLen"];
    BOOL hasWordTiming = [renderPayload[@"wordTimed"] boolValue];
    BOOL splitApplied = [renderPayload[@"splitApplied"] boolValue];

    // marquee is only needed when the line remains wider than the available
    // container even at the user's selected minimum scale.
    CGFloat _marqueeTextWidth = 0.0;
    CGFloat _marqueeContainerWidth = 0.0;
    BOOL _textOverflows = NO;
    if (DateLyricsMarqueeAvailableForLabel(self) && !splitApplied) {
        BOOL canReuseMarqueeGeometry =
            [renderCache[@"marqueeEnabled"] boolValue] &&
            [cachedDisplayText isEqualToString:lyric] &&
            [cachedFont isEqual:configuredFont] &&
            fabs([renderCache[@"width"] doubleValue] - CGRectGetWidth(self.bounds)) < 0.5 &&
            [renderCache[@"marqueeTextWidth"] isKindOfClass:NSNumber.class] &&
            [renderCache[@"marqueeContainerWidth"] isKindOfClass:NSNumber.class];
        if (canReuseMarqueeGeometry) {
            _marqueeTextWidth = [renderCache[@"marqueeTextWidth"] doubleValue];
            _marqueeContainerWidth = [renderCache[@"marqueeContainerWidth"] doubleValue];
        } else {
            _marqueeContainerWidth = DateLyricsSplitAvailableWidth(self);
            if (_marqueeContainerWidth > 0) {
                _marqueeTextWidth = DateLyricsMeasuredLineWidth(lyric, configuredFont);
            }
        }
    }
    if (_marqueeContainerWidth > 0 && _marqueeTextWidth > 0) {
        _textOverflows = _marqueeTextWidth > _marqueeContainerWidth + 0.5f;
    }

    // progressivemode: fill animation is available for this label context.
    BOOL progressiveMode = DateLyricsProgressiveFillAvailable() &&
        self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionLeftToRight;
    // progressiveactive: a segment is actually firing right now (drives overlay renderer).
    NSArray *progressSegmentsForEligibility = renderPayload[@"progressSegments"];
    BOOL progressiveActive = progressiveMode && hasWordTiming &&
        [progressSegmentsForEligibility isKindOfClass:NSArray.class] &&
        progressSegmentsForEligibility.count > 0;
    if (gDateLyricsWordHighlighting && hasWordTiming) {
        NSMutableAttributedString *mAttrStr = [[NSMutableAttributedString alloc] initWithString:lyric];

        UIColor *textColor = DateLyricsBaseTextColorForLabel(self);
        [mAttrStr addAttribute:NSStrokeWidthAttributeName value:@0 range:NSMakeRange(0, lyric.length)];

        NSUInteger loc = locNum ? locNum.unsignedIntegerValue : NSNotFound;
        NSUInteger len = lenNum ? lenNum.unsignedIntegerValue : 0;

        NSRange highlightRange = NSMakeRange(NSNotFound, 0);
        if (loc != NSNotFound && loc + len <= lyric.length) {
            highlightRange = NSMakeRange(loc, len);
        }

        NSRange backgroundHighlightRange = NSMakeRange(NSNotFound, 0);
        if (bgLocNum && bgLenNum) {
            NSUInteger bgLoc = bgLocNum.unsignedIntegerValue;
            NSUInteger bgLen = bgLenNum.unsignedIntegerValue;
            if (bgLoc != NSNotFound && bgLoc + bgLen <= lyric.length && bgLen > 0) {
                backgroundHighlightRange = NSMakeRange(bgLoc, bgLen);
            }
        }
        NSRange completedRange = NSMakeRange(NSNotFound, 0);
        if (completedLocNum && completedLenNum && completedLenNum.unsignedIntegerValue > 0 &&
            completedLocNum.unsignedIntegerValue + completedLenNum.unsignedIntegerValue <= lyric.length) {
            completedRange = NSMakeRange(completedLocNum.unsignedIntegerValue, completedLenNum.unsignedIntegerValue);
        }

        // opacity is the sole highlight style: dim upcoming syllables and retain
        // the normal colour for the spoken portion of the line.
        UIColor *dimmedColor = [textColor colorWithAlphaComponent:0.35];
        BOOL finished = [renderPayload[@"finished"] boolValue];
        BOOL started = renderPayload[@"started"] ? [renderPayload[@"started"] boolValue] : YES;
        if (finished) {
            [mAttrStr addAttribute:NSForegroundColorAttributeName value:textColor range:NSMakeRange(0, lyric.length)];
        } else if (!started) {
            [mAttrStr addAttribute:NSForegroundColorAttributeName value:dimmedColor range:NSMakeRange(0, lyric.length)];
        } else {
            [mAttrStr addAttribute:NSForegroundColorAttributeName value:dimmedColor range:NSMakeRange(0, lyric.length)];

            if (progressiveMode) {
                // progressive mode: the gradient overlay owns the active word.
                // only brighten words that have been fully sung — never the active one.
                if ([renderPayload[@"completedRanges"] isKindOfClass:NSArray.class]) {
                    for (NSDictionary *entry in renderPayload[@"completedRanges"]) {
                        NSRange completed = NSMakeRange([entry[@"loc"] unsignedIntegerValue], [entry[@"len"] unsignedIntegerValue]);
                        if (completed.length > 0 && NSMaxRange(completed) <= lyric.length) {
                            [mAttrStr addAttribute:NSForegroundColorAttributeName value:textColor range:completed];
                        }
                    }
                } else if (completedRange.location != NSNotFound && completedRange.length > 0) {
                    [mAttrStr addAttribute:NSForegroundColorAttributeName value:textColor range:completedRange];
                }
            } else {
                // non-progressive fallback: plain word-by-word highlight.
                if (highlightRange.location != NSNotFound && highlightRange.length > 0) {
                    [mAttrStr addAttribute:NSForegroundColorAttributeName value:textColor range:highlightRange];
                }
                if (backgroundHighlightRange.location != NSNotFound && backgroundHighlightRange.length > 0) {
                    [mAttrStr addAttribute:NSForegroundColorAttributeName value:textColor range:backgroundHighlightRange];
                }
            }
        }
        attrDisplayText = mAttrStr;
    }

    if (!isShowingLyric) {
        if (self.font) {
            objc_setAssociatedObject(self, kDateLyricsOriginalFontKey, self.font, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (self.textColor) {
            objc_setAssociatedObject(self, kDateLyricsOriginalTextColorKey, self.textColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        objc_setAssociatedObject(self, kDateLyricsOriginalNumberOfLinesKey, @(self.numberOfLines), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kDateLyricsOriginalAdjustsFontSizeKey, @(self.adjustsFontSizeToFitWidth), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kDateLyricsOriginalLineBreakModeKey, @(self.lineBreakMode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kDateLyricsOriginalTextAlignmentKey, @(self.textAlignment), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kDateLyricsOriginalClipsToBoundsKey, @(self.clipsToBounds), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        if (self.attributedText) {
            objc_setAssociatedObject(self, kDateLyricsOriginalAttributedTextKey, self.attributedText, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else if (self.text) {
            objc_setAssociatedObject(self, kDateLyricsOriginalTextKey, self.text, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
    }

    BOOL isTransitioning = [objc_getAssociatedObject(self, kDateLyricsAnimatingTransitionKey) boolValue];

    // reassigning these mid-flight dirties layout and fights the running animation,
    // so only touch them when the label is settled.
    if (!isTransitioning) {
        self.font = configuredFont;
        self.numberOfLines = 1;
        self.adjustsFontSizeToFitWidth = NO;
        NSNumber *originalAlignment = objc_getAssociatedObject(self, kDateLyricsOriginalTextAlignmentKey);
        // match the finished marquee viewport: the final glyph touches the
        // right edge, and the leading overflow is clipped with no ellipsis.
        // keep the same tail layout during wake backfill until marquee rejoins.
        BOOL anchorAODTail = DateLyricsAODTailMatchesCurrentLine() && (gDateLyricsAlwaysOnDisplay ||
            objc_getAssociatedObject(self, kDateLyricsDisplayMorphKey) != nil) && gDateLyricsMarqueeEnabled &&
            !gDateLyricsSplitLongLines &&
            self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionLeftToRight &&
            DateLyricsMeasuredLineWidth(lyric, configuredFont) > CGRectGetWidth(self.bounds) + 0.5;
        self.textAlignment = anchorAODTail ? NSTextAlignmentRight :
            (originalAlignment ? (NSTextAlignment)originalAlignment.integerValue : self.textAlignment);
        self.lineBreakMode = NSLineBreakByTruncatingTail;
        // the scrolling overlay is created after an incoming transition. keep
        // the stock label clipped in the meantime so marquee mode never exposes
        // uikit's temporary trailing ellipsis.
        self.lineBreakMode = (anchorAODTail || DateLyricsMarqueeAvailable())
            ? NSLineBreakByClipping
            : NSLineBreakByTruncatingTail;
        self.clipsToBounds = YES;
        objc_setAssociatedObject(self, kDateLyricsAppliedStyleGenerationKey,
                                 @(gDateLyricsStyleGeneration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        appliedStyleGeneration = gDateLyricsStyleGeneration;
        styleNeedsApply = NO;
    }

    BOOL contentChanged = NO;
    BOOL lineChanged = ![previousDisplayText isEqualToString:displayText];

    id currentLineId = renderPayload[@"lineId"];
    id previousLineId = objc_getAssociatedObject(self, @selector(previousLineId));
    BOOL reverseDirection = NO;
    if (currentLineId && previousLineId) {
        if (![currentLineId isEqual:previousLineId]) {
            lineChanged = YES;
            reverseDirection = DateLyricsCompareLineIdentity(currentLineId, previousLineId) == NSOrderedAscending;
        }
    }

    if (attrDisplayText) {
        NSAttributedString *lastAttrText = objc_getAssociatedObject(self, kDateLyricsLastRenderedAttrTextKey);
        contentChanged = ![lastAttrText isEqualToAttributedString:attrDisplayText];
    } else {
        NSString *lastText = objc_getAssociatedObject(self, kDateLyricsLastRenderedTextKey);
        contentChanged = lastText == nil || ![lastText isEqualToString:displayText];
    }
    contentChanged = contentChanged || sizingChanged || styleNeedsApply;

    // coalesce line changes during an active transition; completion renders the
    // newest payload once. keep bookkeeping on the visible line until then,
    // so stale updates and rapid seeks cannot create overlapping transitions.
    DateLyricsDebugLog(@"APPLY split=%d wordTimed=%d started=%d finished=%d w=%.1f frame=%.1f contentChg=%d lineChg=%d reverse=%d trans=%d loc=%@ len=%@ id=%@ prevId=%@ text='%@' prev='%@'",
                       [renderPayload[@"splitApplied"] boolValue],
                       [renderPayload[@"wordTimed"] boolValue],
                       renderPayload[@"started"] ? [renderPayload[@"started"] boolValue] : YES,
                       [renderPayload[@"finished"] boolValue],
                       CGRectGetWidth(self.bounds),
                       CGRectGetWidth(self.frame),
                       contentChanged, lineChanged, reverseDirection, isTransitioning,
                       renderPayload[@"loc"] ?: @"-", renderPayload[@"len"] ?: @"-",
                       currentLineId ?: @"-", previousLineId ?: @"-",
                       displayText, previousDisplayText ?: @"-");

    // same-line syllable changes are safe: the outgoing line is now a static
    // sibling snapshot, while this label is the live incoming line. applying
    // its new attributed string here keeps the first syllable on timestamp.
    if (contentChanged && isTransitioning && lineChanged) {
        return YES;
    }

    objc_setAssociatedObject(self, @selector(_amlApplyCurrentLyric), displayText, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (currentLineId) {
        objc_setAssociatedObject(self, @selector(previousLineId), currentLineId, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        objc_setAssociatedObject(self, @selector(previousLineId), nil, OBJC_ASSOCIATION_ASSIGN);
    }
    objc_setAssociatedObject(self, kDateLyricsLabelShowingLyricKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    BOOL marqueeViewportReady = _marqueeContainerWidth > 0.0 &&
        fabs(CGRectGetWidth(self.bounds) - _marqueeContainerWidth) < 0.5;
    BOOL willMarquee = marqueeViewportReady && DateLyricsMarqueeAvailableForLabel(self) && !splitApplied && _textOverflows;

    if (contentChanged) {
        if (attrDisplayText) {
            objc_setAssociatedObject(self, kDateLyricsLastRenderedAttrTextKey, attrDisplayText, OBJC_ASSOCIATION_COPY_NONATOMIC);
            objc_setAssociatedObject(self, kDateLyricsLastRenderedTextKey, nil, OBJC_ASSOCIATION_ASSIGN);
        } else {
            objc_setAssociatedObject(self, kDateLyricsLastRenderedAttrTextKey, nil, OBJC_ASSOCIATION_ASSIGN);
            objc_setAssociatedObject(self, kDateLyricsLastRenderedTextKey, displayText, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }

        if (lineChanged && continuingHandoffDeadline <= CACurrentMediaTime()) {
            CGFloat marqueeOverflow = willMarquee ? _marqueeTextWidth - _marqueeContainerWidth : 0.0;
            DateLyricsAnimateLabelTransition(self, previousDisplayText ?: @"", displayText, attrDisplayText, reverseDirection,
                                             willMarquee, marqueeOverflow, renderPayload, currentLineId);
            layoutNeeded = YES;
        } else {
            layoutNeeded = lineChanged || sizingChanged || styleNeedsApply;
            DateLyricsApplyLabelContent(self, displayText, attrDisplayText, layoutNeeded);
        }
    }
    DateLyricsRefreshMarqueeContent(self);
    BOOL heldAODTail = DateLyricsAODTailMatchesCurrentLine() && !gDateLyricsSplitLongLines &&
        gDateLyricsMarqueeEnabled && (gDateLyricsAlwaysOnDisplay || displayMorph) && DateLyricsHoldAODTail(self);

    // marquee scrolling: start when text overflows and split isn't handling it;
    // restart only on a new line so syllable highlights mid-line don't stutter-restart the scroll.
    CGFloat latchedWidth = _marqueeContainerWidth > 0.0 ? _marqueeContainerWidth
                                                        : DateLyricsSplitAvailableWidth(self);
    UIView *marqueeContainer = objc_getAssociatedObject(self, kDateLyricsMarqueeContainerKey);
    BOOL marqueeViewportChanged = marqueeContainer &&
        fabs(CGRectGetWidth(marqueeContainer.bounds) - latchedWidth) >= 0.5;
    if (marqueeViewportChanged) {
        DateLyricsStopMarquee(self);
    }

    marqueeViewportReady = _marqueeContainerWidth > 0.0 &&
        fabs(CGRectGetWidth(self.bounds) - _marqueeContainerWidth) < 0.5;
    BOOL transitionRunning = [objc_getAssociatedObject(self, kDateLyricsAnimatingTransitionKey) boolValue];
    if (!transitionRunning && marqueeViewportReady &&
        DateLyricsMarqueeAvailableForLabel(self) && !splitApplied && _textOverflows) {
        id marqueeLineId = objc_getAssociatedObject(self, kDateLyricsMarqueeLineIdKey);
        BOOL alreadyMarqueeingThisLine = marqueeLineId && currentLineId && [marqueeLineId isEqual:currentLineId];
        BOOL marqueeNeedsResync = [objc_getAssociatedObject(self, kDateLyricsMarqueeAnchorGenerationKey) unsignedIntegerValue] != gDateLyricsAnchorGeneration;
        if (!alreadyMarqueeingThisLine || marqueeNeedsResync) {
            CGFloat overflow = _marqueeTextWidth - _marqueeContainerWidth;
            BOOL didRebuild = NO;
            if (DateLyricsStartMarquee(self, overflow, renderPayload, &didRebuild)) {
                objc_setAssociatedObject(self, kDateLyricsMarqueeLineIdKey, currentLineId, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(self, kDateLyricsMarqueeAnchorGenerationKey, @(gDateLyricsAnchorGeneration), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                // log only for genuine rebuilds; reuse/paused-hold returns above.
                if (didRebuild) {
                    DateLyricsDebugLog(@"MARQUEE start viewport=%.1f text=%.1f line=%@",
                                       _marqueeContainerWidth, _marqueeTextWidth,
                                       currentLineId ?: @"-");
                }
            }
        }
    } else if (!heldAODTail && !_textOverflows && objc_getAssociatedObject(self, kDateLyricsMarqueeContainerKey)) {
        DateLyricsStopMarquee(self);
    }

    UILabel *progressTarget = objc_getAssociatedObject(self, kDateLyricsMarqueeContentLabelKey);
    if (![progressTarget isKindOfClass:UILabel.class]) progressTarget = self;
    DateLyricsUpdateProgressOverlay(self, progressTarget, renderPayload, lyric, configuredFont,
                                    DateLyricsBaseTextColorForLabel(self), progressiveActive);

    objc_setAssociatedObject(self, kDateLyricsRenderCacheKey, @{
        @"generation": @(gDateLyricsRenderGeneration),
        @"styleGeneration": @(appliedStyleGeneration),
        @"payload": sourcePayload,
        @"lineId": sourcePayload[@"lineId"] ?: [NSNull null],
        @"displayText": displayText,
        @"width": @(CGRectGetWidth(self.bounds)),

        @"splitLongLines": @(gDateLyricsSplitLongLines),
        @"showAdlibs": @(gDateLyricsShowAdlibs),
        @"marqueeEnabled": @(DateLyricsMarqueeAvailableForLabel(self)),
        @"marqueeNeeded": @(_textOverflows),
        @"marqueeTextWidth": @(_marqueeTextWidth),
        @"marqueeContainerWidth": @(_marqueeContainerWidth),
        @"font": configuredFont,
        @"traits": self.traitCollection ?: [NSNull null]
    }, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (continuingHandoffDeadline > CACurrentMediaTime()) DateLyricsContinueDisplayMorph(self, continuingHandoffDeadline);
    return layoutNeeded;
}

%end

%end



static void DateLyricsReloadPrefs(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    void (^reloadBlock)(void) = ^{
        BOOL wasEnabled = gDateLyricsEnabled;
        BOOL wasAODEnabled = gDateLyricsAODEnabled;
        BOOL wasMusixmatchEnabled = gDateLyricsMusixmatchEnabled;
        BOOL wasRelaxedMatching = gDateLyricsRelaxedMatching;
        NSTimeInterval previousPauseTimeout = gDateLyricsPauseTimeout;
        BOOL wasExternalAppsEnabled = gDateLyricsExternalAppsEnabled;
        CFPreferencesAppSynchronize((__bridge CFStringRef)@"com.shalamand3r.datelyrics");

        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.shalamand3r.datelyrics.plist"];
        if (!prefs) {
            prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.shalamand3r.datelyrics.plist"];
        }

        auto getPrefBool = ^BOOL(NSString *key) { return DateLyricsBoolPreference(key, prefs); };
        auto getPrefInteger = ^NSInteger(NSString *key) { return DateLyricsIntegerPreference(key, prefs); };
        auto getPrefDouble = ^double(NSString *key) { return DateLyricsDoublePreference(key, prefs); };
        auto getPrefString = ^NSString *(NSString *key) { return DateLyricsStringPreference(key, prefs); };

        gDateLyricsEnabled = getPrefBool(@"Enabled");
        gDateLyricsAODEnabled = getPrefBool(@"AODEnabled");
        gDateLyricsAODRefreshRetry = getPrefBool(@"AODRefreshRetry");
        gDateLyricsForceLowercase = getPrefBool(@"ForceLowercase");
        gDateLyricsWordHighlighting = getPrefBool(@"WordHighlighting");
        gDateLyricsProgressiveFill = getPrefBool(@"ProgressiveFill");
        gDateLyricsUseCustomFont = getPrefBool(@"UseCustomFont");
        NSString *customFont = getPrefString(@"CustomFontName");
        gDateLyricsCustomFontName = [customFont isKindOfClass:NSString.class] ? customFont : nil;
        gDateLyricsTransitionsEnabled = getPrefBool(@"TransitionsEnabled");

        NSInteger transitionStyle = getPrefInteger(@"TransitionStyle");
        if (transitionStyle < DateLyricsTransitionStyleFade || transitionStyle > DateLyricsTransitionStylePop) {
            transitionStyle = DateLyricsTransitionStyleSlideUp;
        }
        gDateLyricsTransitionStyle = transitionStyle;
        gDateLyricsTransitionDuration = MIN(MAX(getPrefDouble(@"TransitionDuration"), 0.0), 2.0);
        if (!gDateLyricsTransitionsEnabled) DateLyricsClearEarlyLinePreview();
        gDateLyricsSplitLongLines = getPrefBool(@"SplitLongLines");
        if (gDateLyricsSplitLongLines) {
            gDateLyricsShowAdlibs = NO;
        } else {
            gDateLyricsShowAdlibs = getPrefBool(@"ShowAdlibs");
        }

        gDateLyricsPauseTimeout = MIN(MAX(getPrefDouble(@"PauseTimeout"), 0.0), 60.0);
        gDateLyricsRelaxedMatching = getPrefBool(@"RelaxedMatching");
        gDateLyricsRequestTimeout = DateLyricsSanitizedRequestTimeout(@(getPrefDouble(@"LyricsRequestTimeout")));
        gDateLyricsMarqueeEnabled = getPrefBool(@"MarqueeEnabled");
        gDateLyricsMusixmatchEnabled = getPrefBool(@"MusixmatchEnabled");
        gDateLyricsLRCLIBEnabled = getPrefBool(@"LRCLIBEnabled");
        gDateLyricsMegalobizEnabled = getPrefBool(@"MegalobizEnabled");
        gDateLyricsNetEaseEnabled = getPrefBool(@"NetEaseEnabled");
        gDateLyricsQQMusicEnabled = getPrefBool(@"QQMusicEnabled");
        NSArray *savedOrder = (__bridge_transfer NSArray *)CFPreferencesCopyAppValue(
            CFSTR("LyricsProviderOrder"), CFSTR("com.shalamand3r.datelyrics"));
        gDateLyricsProviderOrder = DateLyricsSanitizedProviderOrder(savedOrder);
        gDateLyricsExternalAppsEnabled = getPrefBool(@"ExternalAppsEnabled");
        gDateLyricsDebugLogging = getPrefBool(@"DebugLogging");
        gDateLyricsNativeTransitionProbe = getPrefBool(@"NativeTransitionProbe");
        if (gDateLyricsNativeTransitionProbe) { gDateLyricsEnabled = NO; }
        gDateLyricsRenderGeneration++;
        gDateLyricsStyleGeneration++;

        if (wasRelaxedMatching != gDateLyricsRelaxedMatching && gLyricsQueue) {
            dispatch_async(gLyricsQueue, ^{
                DateLyricsCancelAllProviderRequests();
                NSArray *tracks = gMusixmatchPendingTaskIDs.allKeys;
                [gMusixmatchPendingTaskIDs removeAllObjects];
                [gMusixmatchFailureRetryAfter removeAllObjects];
                gDateLyricsSelectedExternalTrack = 0;
                ++gDateLyricsMusixmatchGeneration;
                for (NSNumber *track in tracks) DateLyricsRemoveMusixmatchLoadingScore(track.integerValue);
            });
        }

        if ((!DateLyricsMusixmatchServiceEnabled() || !gDateLyricsEnabled) && gLyricsQueue) {
            // pending fallback requests are best-effort.  they cannot be
            // allowed to repopulate a score after the user turns the feature
            // off, and clearing the pending ids lets a later re-enable retry
            // the current track cleanly.
            dispatch_async(gLyricsQueue, ^{
                NSArray<NSNumber *> *pendingStoreIDs = [gMusixmatchPendingTaskIDs.allKeys copy];
                DateLyricsCancelAllProviderRequests();
                [gMusixmatchPendingTaskIDs removeAllObjects];
                gDateLyricsMusixmatchGeneration++;
                gDateLyricsSelectedExternalTrack = 0;
                for (NSNumber *storeID in pendingStoreIDs) DateLyricsRemoveMusixmatchLoadingScore(storeID.integerValue);
                [gMusixmatchFailureRetryAfter removeAllObjects];
            });
        }

        if (DateLyricsMusixmatchServiceEnabled() && gDateLyricsEnabled && gLyricsQueue &&
            (wasMusixmatchEnabled != gDateLyricsMusixmatchEnabled ||
             wasExternalAppsEnabled != gDateLyricsExternalAppsEnabled)) {
            dispatch_async(gLyricsQueue, ^{
                // revoking either opt-in cancels only its requests. otherwise a
                // failed old callback could leave a reservation blocking re-enable.
                for (NSNumber *track in [gMusixmatchPendingTaskIDs.allKeys copy]) {
                    if (DateLyricsMusixmatchAllowedForTrack(track.integerValue)) continue;
                    DateLyricsCancelProviderLookup(track.integerValue);
                }
                if (!gDateLyricsExternalAppsEnabled) gDateLyricsSelectedExternalTrack = 0;
            });
        }

        if (!DateLyricsIsSpringBoardHost() && gLyricsQueue) {
            dispatch_async(gLyricsQueue, ^{
                gLastHandledStoreID = 0;
                if (gActivePlayerClient) {
                    DateLyricsProcessNowPlayingClient(gActivePlayerClient);
                }
            });
        }

        if (DateLyricsIsSpringBoardHost() && (wasMusixmatchEnabled != gDateLyricsMusixmatchEnabled || wasRelaxedMatching != gDateLyricsRelaxedMatching) && gDateLyricsLocalAnchor) {
            NSInteger publicationTrack = [gDateLyricsLocalAnchor[@"trackId"] integerValue];
            // provider selection parses cached scores too: keep this rare
            // preferences path off springboard's main queue as well.
            dispatch_async(gLyricsQueue, ^{ DateLyricsPublishBestScore(publicationTrack); });
            if ((!DateLyricsMusixmatchAllowedForTrack(publicationTrack) && [gDateLyricsCurrentScore.source hasPrefix:@"musixmatch"]) ||
                !DateLyricsSourceAllowedForMatchMode(gDateLyricsCurrentScore.source, gDateLyricsRelaxedMatching)) {
                gDateLyricsCurrentScore = nil;
                gDateLyricsCurrentPayload = nil;
                gDateLyricsResolverCursor = -1;
                DateLyricsClearEarlyLinePreview();
                gDateLyricsRenderGeneration++;
                DateLyricsApplyCurrentLineToAllCoverSheets();
            }
        }

        if (DateLyricsIsSpringBoardHost()) {
            if (wasEnabled != gDateLyricsEnabled || wasMusixmatchEnabled != gDateLyricsMusixmatchEnabled ||
                wasExternalAppsEnabled != gDateLyricsExternalAppsEnabled || wasRelaxedMatching != gDateLyricsRelaxedMatching)
                DateLyricsInvalidateScoreLoad();
            if (wasAODEnabled != gDateLyricsAODEnabled)
                DateLyricsRefreshDisplayState(gDateLyricsScreenIsOn);
            // preference changes can rearm the source, but only a timeout
            // change adjusts its original expiry; aod/debug toggles do not.
            if (gDateLyricsPauseHideDeadline > 0.0)
                gDateLyricsPauseHideDeadline += gDateLyricsPauseTimeout - previousPauseTimeout;
            DateLyricsSuspendPauseHideTimer();
            DateLyricsScheduleTicker();
        }
        if (DateLyricsIsSpringBoardHost() && ((!wasEnabled && gDateLyricsEnabled) ||
            wasExternalAppsEnabled != gDateLyricsExternalAppsEnabled || wasRelaxedMatching != gDateLyricsRelaxedMatching)) {
            DateLyricsRequestNowPlayingInfo();
        }
        if (!gDateLyricsEnabled) {
            if (DateLyricsIsSpringBoardHost()) {
                gDateLyricsCurrentPayload = nil;
                DateLyricsApplyCurrentLineToAllCoverSheets();
            }
        } else {
            if (DateLyricsIsSpringBoardHost()) {
                DateLyricsApplyCurrentLineToAllCoverSheets();
            }
        }
    };

    if ([NSThread isMainThread]) {
        reloadBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), reloadBlock);
    }
}

// each injected host cancels pending writes and clears its own sandboxed cache.
static void DateLyricsClearCaches(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    pthread_mutex_lock(&gLyricsCacheMutex);
    [gLyricsCache removeAllObjects];
    [gWordLyricsCache removeAllObjects];
    [gLyricsCacheOrder removeAllObjects];
    [gUnsynchronizedLyricsIDs removeAllObjects];
    pthread_mutex_unlock(&gLyricsCacheMutex);

    NSNumber *requestedGeneration = DateLyricsIsMusicHost() ? (__bridge_transfer id)CFPreferencesCopyAppValue(
        CFSTR("CacheGeneration"), CFSTR("com.shalamand3r.datelyrics")) : nil;
    if (![requestedGeneration isKindOfClass:NSNumber.class]) requestedGeneration = nil;

    if ((DateLyricsIsMusicHost() || DateLyricsIsSpringBoardHost()) && gLyricsQueue) {
        dispatch_async(gLyricsQueue, ^{
            gDateLyricsSelectedExternalTrack = 0;
            gDateLyricsCacheGeneration++;
            gDateLyricsMusixmatchGeneration++;
            [gLyricsTaskQueue removeAllObjects];
            [gPendingLyricsIDs removeAllObjects];

            NSString *rootPath = DateLyricsIsSpringBoardHost()
                ? DateLyricsExternalScoreDirectory : GetLyricsRootPath();
            DateLyricsRemoveCachedLyrics(rootPath, NSFileManager.defaultManager);

            // invalidate pending callbacks so they cannot repopulate the cleared cache.
            DateLyricsCancelAllProviderRequests();
            [gMusixmatchPendingTaskIDs removeAllObjects];
            [gMusixmatchFailureRetryAfter removeAllObjects];
            gLastHandledStoreID = 0;
            gLastHandledAdamID = 0;
            gLastHandledLyricsAvailable = NO;
            // a live wipe also acknowledges its generation, preserving newly fetched
            // lyrics on the next launch instead of clearing them a second time.
            if (DateLyricsIsMusicHost() && requestedGeneration) {
                CFPreferencesSetAppValue(CFSTR("MusicProcessedCacheGeneration"),
                    (__bridge CFPropertyListRef)requestedGeneration, CFSTR("com.shalamand3r.datelyrics"));
                CFPreferencesAppSynchronize(CFSTR("com.shalamand3r.datelyrics"));
            }
        });
    }

    if (DateLyricsIsSpringBoardHost()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DateLyricsClearNowPlaying();
        });
    }
}


static void DateLyricsClearNowPlaying(void) {
    DateLyricsSelectExternalTrack(0, nil);
    DateLyricsInvalidateScoreLoad();
    gDateLyricsLocalAnchor = nil;
    gDateLyricsCurrentScore = nil;
    gDateLyricsCurrentPayload = nil;
    gDateLyricsResolverCursor = -1;
    gDateLyricsLastResolvedTrackId = 0;
    gDateLyricsLastResolvedElapsed = -1.0;
    gDateLyricsLastResolutionWasBackwardSeek = NO;
    DateLyricsClearEarlyLinePreview();
    gDateLyricsRenderGeneration++;
    DateLyricsCancelPauseHideTimer();
    DateLyricsScheduleTicker();
    DateLyricsApplyCurrentLineToAllCoverSheets();
}


static void DateLyricsAdoptNowPlayingInfo(NSDictionary *info) {
    if (info.count == 0) { DateLyricsClearNowPlaying(); return; }

    if (!gDateLyricsEnabled) { DateLyricsClearNowPlaying(); return; }
    NSNumber *storeIdNum = info[@"kMRMediaRemoteNowPlayingInfoiTunesStoreIdentifier"];
    BOOL hasStoreID = [storeIdNum isKindOfClass:NSNumber.class] && isfinite(storeIdNum.doubleValue) &&
        storeIdNum.doubleValue > 0 && storeIdNum.doubleValue < kDateLyricsExternalTrackBase;
    NSInteger trackId = hasStoreID ? storeIdNum.integerValue
        : (gDateLyricsExternalAppsEnabled ? DateLyricsExternalTrackID(info) : 0);
    if (trackId <= 0) { DateLyricsClearNowPlaying(); return; }

    NSNumber *elapsedNum = info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"];
    NSInteger previousTrackID = [gDateLyricsLocalAnchor[@"trackId"] integerValue];
    if (![elapsedNum isKindOfClass:NSNumber.class] || !isfinite(elapsedNum.doubleValue)) {
        if (trackId != previousTrackID) DateLyricsClearNowPlaying();
        return;
    }

    NSDate *sampledAt = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
    id rateValue = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
    double rawRate = [rateValue isKindOfClass:NSNumber.class] ? [rateValue doubleValue] : 0.0;
    if ((rateValue && ![rateValue isKindOfClass:NSNumber.class]) || !isfinite(rawRate) || rawRate > FLT_MAX ||
        ([sampledAt isKindOfClass:NSDate.class] && !isfinite(sampledAt.timeIntervalSince1970))) {
        if (trackId != previousTrackID) DateLyricsClearNowPlaying();
        return;
    }
    float rate = (float)MAX(0.0, rawRate);

    NSTimeInterval sampleAge = [sampledAt isKindOfClass:NSDate.class] ? MAX(0.0, -[sampledAt timeIntervalSinceNow]) : 0.0;
    NSTimeInterval atHostTime = DateLyricsMonotonicTime() - sampleAge;
    if (!isfinite(sampleAge) || !isfinite(atHostTime) ||
        !isfinite(elapsedNum.doubleValue + sampleAge * rate)) {
        if (trackId != previousTrackID) DateLyricsClearNowPlaying();
        return;
    }
    DateLyricsSelectExternalTrack(DateLyricsIsExternalTrack(trackId) ? trackId : 0, info);
    NSTimeInterval sampleWall = [sampledAt isKindOfClass:NSDate.class] ? sampledAt.timeIntervalSince1970 : 0.0;
    NSTimeInterval previousSampleWall = [gDateLyricsLocalAnchor[@"sampleWall"] doubleValue];
    if (trackId == previousTrackID && sampleWall > 0.0 && previousSampleWall > 0.0 &&
        sampleWall < previousSampleWall - 0.05) {
        DateLyricsDebugLog(@"[CLOCK] event=ignore-stale track=%ld timestampBackwards=%.3f raw=%.3f rate=%.2f",
            (long)trackId, previousSampleWall - sampleWall, elapsedNum.doubleValue, rate);
        return;
    }

    NSTimeInterval visualBefore = DateLyricsCurrentRenderElapsed();
    NSTimeInterval anchorElapsed = elapsedNum.doubleValue;

    BOOL isSeek = NO;
    NSTimeInterval rawElapsed = anchorElapsed;
    NSTimeInterval appliedSlip = 0.0;
    NSTimeInterval expected = anchorElapsed;
    float previousRate = [gDateLyricsLocalAnchor[@"rate"] floatValue];

    if (gDateLyricsLocalAnchor && trackId == [gDateLyricsLocalAnchor[@"trackId"] integerValue]) {
        NSTimeInterval previousElapsed = [gDateLyricsLocalAnchor[@"elapsed"] doubleValue];
        NSTimeInterval previousHost = [gDateLyricsLocalAnchor[@"atHostTime"] doubleValue];

        // dedupe check
        // a playing sample is only a duplicate if it is the same sample; the same
        // elapsed value at a later timestamp is new (repeat/restart at 0:00).
        BOOL sameSample = rate <= 0.0f || sampleWall <= 0.0 || previousSampleWall <= 0.0 ||
                          fabs(sampleWall - previousSampleWall) < 0.002;
        if (sameSample &&
            fabs(anchorElapsed - previousElapsed) < 0.01 &&
            fabs(rate - previousRate) < 0.01) {
            return;
        }

        // while paused, later anchors differ from ours only by the boundary nudge.
        // without this the next repeat anchor snaps the playhead back.
        if (rate <= 0.0f && previousRate <= 0.0f &&
            anchorElapsed <= previousElapsed &&
            (previousElapsed - anchorElapsed) < 0.30) {
            return;
        }

        expected = previousElapsed + ((atHostTime - previousHost) * previousRate);
        isSeek = fabs(anchorElapsed - expected) > 0.35;
        BOOL normalPause = previousRate > 0.0f && rate <= 0.0f && !isSeek;

        BOOL atTransportBoundary = ((previousRate <= 0.0f) != (rate <= 0.0f));
        if (!isSeek && visualBefore >= 0.0) {
            NSTimeInterval candidate = anchorElapsed + (sampleAge * rate);
            NSTimeInterval rawSlip = visualBefore - candidate;
            NSTimeInterval limit = atTransportBoundary ? 0.30 : 0.15;
            appliedSlip = MAX(0.0, MIN(rawSlip, limit));
            anchorElapsed += appliedSlip;
        }

        if (normalPause) {
            DateLyricsFreezeAllMarquees();
            DateLyricsDebugLog(@"[PAUSE] marquee freeze raw=%.3f expected=%.3f correction=%.3f",
                               anchorElapsed, expected, anchorElapsed - expected);
        }
    }

    BOOL rateUnchanged = fabs(rate - previousRate) < 0.01;
    BOOL hadAnchorForThisTrack = gDateLyricsLocalAnchor && trackId == [gDateLyricsLocalAnchor[@"trackId"] integerValue];
    BOOL scoreReadyForThisTrack = gDateLyricsCurrentScore && gDateLyricsCurrentScore.trackId == trackId;
    if (hadAnchorForThisTrack && scoreReadyForThisTrack && !isSeek && rateUnchanged && fabs(anchorElapsed - expected) < 0.05) {
        // nothing to learn. refresh athosttime silently; do not bump the generation.
        gDateLyricsLocalAnchor = @{ @"trackId": @(trackId), @"elapsed": @(anchorElapsed),
                                    @"rate": @(rate), @"seek": @NO, @"atHostTime": @(atHostTime), @"sampleWall": @(sampleWall) };
        DateLyricsDebugLog(@"[CLOCK] event=anchor-noop track=%ld anchor=%.3f rate=%.2f slip=%.3f sampleAge=%.3f",
                           (long)trackId, anchorElapsed, rate, appliedSlip, sampleAge);
        return;
    }

    if (isSeek) {
        if (!gDateLyricsStagedAnchor || [gDateLyricsStagedAnchor[@"trackId"] integerValue] != trackId) {
            gDateLyricsStagedAnchor = @{
                @"trackId": @(trackId),
                @"elapsed": @(anchorElapsed),
                @"rate": @(rate),
                @"hostTime": @(atHostTime)
            };
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                DateLyricsRequestNowPlayingInfo();
            });
            DateLyricsDebugLog(@"[CLOCK] event=seek_stage track=%ld anchor=%.3f rate=%.2f",
                               (long)trackId, anchorElapsed, rate);
            return;
        } else {
            NSTimeInterval stagedElapsed = [gDateLyricsStagedAnchor[@"elapsed"] doubleValue];
            NSTimeInterval stagedHost = [gDateLyricsStagedAnchor[@"hostTime"] doubleValue];
            NSTimeInterval timeDiff = atHostTime - stagedHost;
            NSTimeInterval projectedStaged = stagedElapsed + (timeDiff * rate);

            if (fabs(anchorElapsed - projectedStaged) < 0.10) {
                DateLyricsDebugLog(@"[CLOCK] event=seek_confirm track=%ld anchor=%.3f", (long)trackId, anchorElapsed);
                gDateLyricsStagedAnchor = nil;
                DateLyricsClearAllFrozenMarquees();
                // scrubbing while paused is activity.  the hide timer deliberately ignores
                // repeated identical paused anchors, but without this the countdown kept
                // running from the original pause and the lyric vanished a second or so after
                // a scrub.  cancelling lets the ticker's paused branch arm a fresh one.
                if (rate <= 0.0f) DateLyricsCancelPauseHideTimer();
            } else {
                gDateLyricsStagedAnchor = @{
                    @"trackId": @(trackId),
                    @"elapsed": @(anchorElapsed),
                    @"rate": @(rate),
                    @"hostTime": @(atHostTime)
                };
                DateLyricsDebugLog(@"[CLOCK] event=seek_restage track=%ld anchor=%.3f", (long)trackId, anchorElapsed);
                return;
            }
        }
    } else {
        gDateLyricsStagedAnchor = nil;
    }

    NSString *event =
        isSeek ? @"seek" :
        (previousRate > 0.0f && rate <= 0.0f) ? @"pause" :
        (previousRate <= 0.0f && rate > 0.0f) ? @"resume" :
        @"anchor";

    DateLyricsDebugLog(
        @"[CLOCK] event=%@ gen=%lu track=%ld oldRate=%.2f newRate=%.2f "
         "raw=%.3f anchor=%.3f slip=%.3f expected=%.3f visualBefore=%.3f lastResolved=%.3f "
         "correction=%.3f sampleAge=%.3f seek=%d line=%@ focus=%@/%@",
        event,
        (unsigned long)gDateLyricsAnchorGeneration + 1,
        (long)trackId,
        previousRate,
        rate,
        rawElapsed,
        anchorElapsed,
        appliedSlip,
        expected,
        visualBefore,
        gDateLyricsLastResolvedElapsed,
        anchorElapsed - expected,
        sampleAge,
        isSeek,
        gDateLyricsCurrentPayload[@"lineId"] ?: @"-",
        gDateLyricsCurrentPayload[@"focusLoc"] ?: @"-",
        gDateLyricsCurrentPayload[@"focusLen"] ?: @"-"
    );

    gDateLyricsLocalAnchor = @{
        @"trackId": @(trackId),
        @"elapsed": @(anchorElapsed),
        @"rate": @(rate),
        @"seek": @(isSeek),
        @"atHostTime": @(atHostTime),
        @"sampleWall": @(sampleWall),
    };
    // a tiny pause correction is intentionally invisible to the render layer;
    // incrementing this generation would rebuild the marquee at the stale raw
    // anchor and undo the frozen presentation state.
    gDateLyricsAnchorGeneration++;

    BOOL cursorNeedsReset = isSeek;
    if (trackId != previousTrackID) {
        DateLyricsCancelPauseHideTimer();
        DateLyricsInvalidateScoreLoad();
        gDateLyricsCurrentScore = nil;
        gDateLyricsCurrentPayload = nil;
        ++gDateLyricsScoreGeneration;
        ++gDateLyricsRenderGeneration;
        cursorNeedsReset = YES;
        DateLyricsApplyCurrentLineToAllCoverSheets();
    }

    if (cursorNeedsReset) {
        gDateLyricsResolverCursor = -1;
        DateLyricsClearEarlyLinePreview();
    }

    DateLyricsScheduleTicker();

}

static void DateLyricsRequestScoreLoad(void) {
    // main queue owns selection/generations. a black screen remembers pending
    // invalidation without reading/parsing until its next wake.
    if (!DateLyricsRenderingActive() || !gDateLyricsEnabled || !gDateLyricsLocalAnchor ||
        gDateLyricsScoreLoadAttemptGeneration == gDateLyricsScoreLoadGeneration) return;
    NSInteger trackID = [gDateLyricsLocalAnchor[@"trackId"] integerValue];
    if (trackID <= 0) return;
    NSUInteger generation = gDateLyricsScoreLoadGeneration;
    gDateLyricsScoreLoadAttemptGeneration = generation;
    NSString *path = DateLyricsActiveScorePath(trackID);
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.shalamand3r.datelyrics.score-reader", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(queue, ^{
        @autoreleasepool {
            DateLyricsScore *score = DateLyricsScoreAtPath(path);
            dispatch_async(dispatch_get_main_queue(), ^{
                // ignore old tracks, a->b->a selections, resets and setting changes.
                if (generation != gDateLyricsScoreLoadGeneration || !gDateLyricsEnabled ||
                    trackID != [gDateLyricsLocalAnchor[@"trackId"] integerValue]) return;
                DateLyricsScore *newScore = score;
                if (!DateLyricsSourceAllowedForMatchMode(newScore.source, gDateLyricsRelaxedMatching) || newScore.trackId != trackID ||
                    ([newScore.source hasPrefix:@"musixmatch"] && !DateLyricsMusixmatchAllowedForTrack(trackID))) newScore = nil;
                if (newScore && gDateLyricsCurrentScore.trackId == trackID &&
                    newScore.revision && [newScore.revision isEqual:gDateLyricsCurrentScore.revision] &&
                    [newScore.source isEqual:gDateLyricsCurrentScore.source]) return;
                BOOL hadScore = gDateLyricsCurrentScore != nil || gDateLyricsCurrentPayload != nil;
                if (!newScore && !hadScore) return;
                gDateLyricsCurrentScore = newScore;
                ++gDateLyricsScoreGeneration;
                gDateLyricsResolverCursor = -1;
                DateLyricsClearEarlyLinePreview();
                gDateLyricsLastResolvedTrackId = trackID;
                gDateLyricsLastResolvedElapsed = -1.0;
                ++gDateLyricsRenderGeneration;
                if (!newScore) gDateLyricsCurrentPayload = nil;
                DateLyricsDebugLog(@"[SB:SCORE] loaded track=%ld lines=%lu valid=%d generation=%lu", (long)trackID,
                    (unsigned long)newScore.lines.count, newScore != nil, (unsigned long)generation);
                DateLyricsScheduleTicker();
                if (!newScore) DateLyricsApplyCurrentLineToAllCoverSheets();
            });
        }
    });
}

static void DateLyricsHandleScoreChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        DateLyricsInvalidateScoreLoad();
        DateLyricsRequestScoreLoad();
    });
}

@interface SBBacklightController : NSObject
+ (instancetype)sharedInstanceIfExists;
- (NSInteger)backlightState;
- (BOOL)screenIsOn;
- (void)addObserver:(id)observer;
@end

@interface SBAlwaysOnDefaults : NSObject
- (BOOL)enableAlwaysOn;
@end

static BOOL DateLyricsSystemAODEnabled(void) {
    Class cls = NSClassFromString(@"SBBacklightController");
    if ([cls respondsToSelector:@selector(sharedInstanceIfExists)]) {
        id controller = [cls sharedInstanceIfExists];
        // observed on ios 17.0: this is the live setting backing display &
        // brightness, rather than the hardware capability or our own toggle.
        Ivar ivar = class_getInstanceVariable([controller class], "_alwaysOnDefaults");
        const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
        if (type && type[0] == '@') {
            SBAlwaysOnDefaults *defaults = object_getIvar(controller, ivar);
            if ([defaults respondsToSelector:@selector(enableAlwaysOn)]) return defaults.enableAlwaysOn;
        }
    }
    // on an unrecognised system, trust the actual dim backlight state. never
    // turn a bright lock screen off based on an unavailable private setting.
    return YES;
}

// date views can stay attached to a window while the backlight is off. their
// presence alone is not permission to keep resolving/animating the lyric.
static void DateLyricsSetDisplayMode(BOOL awake, BOOL alwaysOn) {
    BOOL wasSuppressed = gDateLyricsAODSuppressed;
    BOOL systemAODEnabled = !alwaysOn || DateLyricsSystemAODEnabled();
    BOOL suppressAOD = alwaysOn && (!gDateLyricsAODEnabled || !systemAODEnabled);
    gDateLyricsAODSuppressed = suppressAOD;
    if (suppressAOD) { awake = NO; alwaysOn = NO; }
    // reverse immediately; capture the currently displayed handoff before
    // resolving the new mode. the association guards stale completion callbacks.
    if (gDateLyricsScreenIsOn == awake && gDateLyricsAlwaysOnDisplay == alwaysOn &&
        !(suppressAOD && !wasSuppressed)) return;
    DateLyricsDebugLog(@"[DISPLAY:POLICY] requestedAOD=%d systemAOD=%d tweakAOD=%d suppressed=%d", alwaysOn || suppressAOD, systemAODEnabled, gDateLyricsAODEnabled, suppressAOD);
    ++gDateLyricsDisplayModeRequestGeneration;
    DateLyricsUpdateAODTailMode(awake, alwaysOn);
    BOOL handoff = awake && DateLyricsRenderingActive() && alwaysOn != gDateLyricsAlwaysOnDisplay;
    NSMutableArray<DateLyricsDisplayMorph *> *morphs = [NSMutableArray array];
    NSSet *labels = DateLyricsAttachedDateLabels();
    for (_UIAnimatingLabel *label in labels) {
        DateLyricsDisplayMorph *morph = handoff ? DateLyricsCaptureDisplayMorph(label) : nil;
        if (morph) [morphs addObject:morph];
        else DateLyricsCancelDisplayMorph(label);
        // a line transition's outgoing copy and delayed completion must not
        // survive into aod or later reset a newer handoff's alpha/geometry.
        DateLyricsCancelLabelTransition(label);
        DateLyricsStopMarquee(label);
        DateLyricsRemoveProgressOverlay(label);
    }
    gDateLyricsScreenIsOn = awake;
    gDateLyricsAlwaysOnDisplay = alwaysOn;
    DateLyricsDebugLog(@"[DISPLAY] awake=%d aod=%d", awake, alwaysOn);
    DateLyricsCancelTicker();
    if (!awake) {
        DateLyricsSuspendPauseHideTimer();
        DateLyricsClearEarlyLinePreview();
        if (suppressAOD) {
            for (_UIAnimatingLabel *label in labels) DateLyricsRestoreSystemDateLabel(label);
            // restore the native date snapshot only for real, enabled aod.
            // an aod-capable/spoofed device can briefly dim on its way to black
            // even with the system switch off; never request a cache then.
            if (systemAODEnabled && [gDateLyricsBacklightEnvironment respondsToSelector:@selector(invalidateContentForReason:)])
                [gDateLyricsBacklightEnvironment invalidateContentForReason:@"DateLyrics AOD disabled"];
        }
        return;
    }
    if (!DateLyricsRenderingActive()) return;
    // arm the window before resolving: locking immediately before a new line
    // can replace the captured glyphs during the very first mode update.
    CFTimeInterval deadline = CACurrentMediaTime() + 0.85;
    for (DateLyricsDisplayMorph *morph in morphs) {
        morph.deadline = deadline; morph.enteringAOD = alwaysOn;
        morph.trackID = [gDateLyricsLocalAnchor[@"trackId"] integerValue];
    }
    // resolve the advancing clock immediately. the snapshots only bridge its
    // appearance; they never hold back the current line or word resolution.
    DateLyricsClearEarlyLinePreview();
    gDateLyricsLastResolvedElapsed = -1.0;
    gDateLyricsLastResolvedAnchorGeneration = NSUIntegerMax;
    gDateLyricsRenderGeneration++;
    gDateLyricsDisplayWakeInProgress = YES;
    DateLyricsScheduleTicker();
    DateLyricsApplyCurrentLineToAllCoverSheets();
    if (alwaysOn && !gDateLyricsCurrentPayload) DateLyricsRequestAODRefresh(@"display without lyrics");
    for (DateLyricsDisplayMorph *morph in morphs) DateLyricsStartDisplayMorph(morph, alwaysOn);
    gDateLyricsDisplayWakeInProgress = NO;
    DateLyricsRequestNowPlayingInfo();
}

// selectors and state values observed on ios 17.0. older systems retain the
// darwin notification fallback if their controller lacks these getters.


static NSTimeInterval gDateLyricsBacklightRampStarted = 0.0;
static NSInteger gDateLyricsPendingBacklightState = -1;
static NSUInteger gDateLyricsBacklightRampGeneration = 0;
static void DateLyricsRefreshDisplayState(BOOL fallbackAwake) {
    // darwin notifications can arrive before the controller commits its new
    // state. do not reverse a handoff using that old state during the ramp.
    if (gDateLyricsPendingBacklightState >= 0) return;
    Class cls = NSClassFromString(@"SBBacklightController");
    if ([cls respondsToSelector:@selector(sharedInstanceIfExists)]) {
        SBBacklightController *controller = [cls sharedInstanceIfExists];
        if ([controller respondsToSelector:@selector(backlightState)] &&
            [controller respondsToSelector:@selector(screenIsOn)]) {
            NSInteger state = controller.backlightState;
            BOOL alwaysOn = state == 3;
            // some devices pass through dim on the way to black even with
            // system aod disabled. keep the current pixels through that fade.
            if (alwaysOn && !DateLyricsSystemAODEnabled()) return;
            DateLyricsSetDisplayMode(state != 4 && (controller.screenIsOn || alwaysOn), alwaysOn);
            return;
        }
    }
    DateLyricsSetDisplayMode(fallbackAwake, NO);
}

static void DateLyricsBeginBacklightTransition(NSInteger state) {
    if (state == 1) DateLyricsSetDisplayMode(YES, NO);
    else if (state == 3 && gDateLyricsAODEnabled && DateLyricsSystemAODEnabled())
        DateLyricsSetDisplayMode(YES, YES);
    // a black/suppressed-aod destination is not black yet. leave the existing
    // glyphs and animations alone until the committed/blanked callback arrives.
}

static void DateLyricsCommitDisplayBlank(void) {
    // rapid lock/wake can deliver the old zero-factor/blanked notification
    // after will awake. it must not cancel the newer wake's handoff or timer.
    if (gDateLyricsPendingBacklightState == 1) return;
    // on native aod, factor zero and hasblankedscreen are normal: the bright
    // backlight is off while the dim scene remains visible. keep its ramp and
    // line timer alive. an explicit state-4 destination still means fully off.
    if (gDateLyricsPendingBacklightState == 3 && DateLyricsSystemAODEnabled()) return;
    if (gDateLyricsPendingBacklightState != 4 && DateLyricsSystemAODEnabled()) {
        Class cls = NSClassFromString(@"SBBacklightController");
        SBBacklightController *controller = [cls respondsToSelector:@selector(sharedInstanceIfExists)]
            ? [cls sharedInstanceIfExists] : nil;
        if ([controller respondsToSelector:@selector(backlightState)] && controller.backlightState == 3) {
            DateLyricsSetDisplayMode(YES, YES);
            return;
        }
    }
    gDateLyricsPendingBacklightState = -1;
    ++gDateLyricsBacklightRampGeneration;
    DateLyricsSetDisplayMode(NO, NO);
}

@interface DateLyricsBacklightObserver : NSObject
@end
@implementation DateLyricsBacklightObserver
- (void)backlightController:(id)controller willTransitionToBacklightState:(NSInteger)state source:(NSInteger)source {
    // begin during the backlight ramp, while the display can still show the
    // brief fill/unfill. waiting for the dim snapshot makes the handoff late.
    if (state != 1 && state != 3 && state != 4) return;
    void (^change)(void) = ^{
        DateLyricsDebugLog(@"[DISPLAY:RAMP] event=will state=%ld source=%ld", (long)state, (long)source);
        gDateLyricsBacklightRampStarted = DateLyricsMonotonicTime();
        gDateLyricsPendingBacklightState = state;
        NSUInteger generation = ++gDateLyricsBacklightRampGeneration;
        DateLyricsBeginBacklightTransition(state);
        // a cancelled ramp may omit its completion callback. reconcile once,
        // without letting an older ramp clear a newer pending transition.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation != gDateLyricsBacklightRampGeneration) return;
            gDateLyricsPendingBacklightState = -1;
            DateLyricsRefreshDisplayState(gDateLyricsScreenIsOn);
        });
    };
    if (NSThread.isMainThread) change(); else dispatch_async(dispatch_get_main_queue(), change);
}
- (void)backlightController:(id)controller didTransitionToBacklightState:(NSInteger)state source:(NSInteger)source {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gDateLyricsPendingBacklightState >= 0 && gDateLyricsPendingBacklightState != state) return;
        DateLyricsDebugLog(@"[DISPLAY:RAMP] event=did state=%ld duration=%.3f", (long)state, gDateLyricsBacklightRampStarted > 0 ? DateLyricsMonotonicTime() - gDateLyricsBacklightRampStarted : -1.0);
        gDateLyricsPendingBacklightState = -1;
        ++gDateLyricsBacklightRampGeneration;
        DateLyricsRefreshDisplayState(gDateLyricsScreenIsOn);
    });
}
- (void)backlightController:(id)controller didAnimateBacklightToFactor:(float)factor source:(NSInteger)source {
    dispatch_async(dispatch_get_main_queue(), ^{
        DateLyricsDebugLog(@"[DISPLAY:RAMP] event=animated factor=%.3f duration=%.3f", factor, gDateLyricsBacklightRampStarted > 0 ? DateLyricsMonotonicTime() - gDateLyricsBacklightRampStarted : -1.0);
        if (factor <= 0.0f) DateLyricsCommitDisplayBlank();
        else DateLyricsRefreshDisplayState(gDateLyricsScreenIsOn);
    });
}
@end


static void DateLyricsObserveDisplayState(void) {
    static int blankedToken = 0;
    static int awakeToken = 0;
    if (notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &blankedToken,
                                dispatch_get_main_queue(), ^(int token) {
        uint64_t blanked = 0;
        if (notify_get_state(token, &blanked) != NOTIFY_STATUS_OK) return;
        if (blanked) DateLyricsCommitDisplayBlank();
        else DateLyricsRefreshDisplayState(YES);
    }) == NOTIFY_STATUS_OK) {
        uint64_t blanked = 0;
        if (notify_get_state(blankedToken, &blanked) == NOTIFY_STATUS_OK) gDateLyricsScreenIsOn = blanked == 0;
    }
    notify_register_dispatch("com.apple.springboard.didTurnOnDisplay", &awakeToken,
                             dispatch_get_main_queue(), ^(__unused int token) {
        DateLyricsRefreshDisplayState(YES);
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        static DateLyricsBacklightObserver *observer;
        // native hardware capability, independent of the user's ios aod switch.
        Class provider = NSClassFromString(@"SBBacklightPlatformProvider");
        BOOL supported = [provider respondsToSelector:@selector(deviceSupportsAlwaysOn)] && [provider deviceSupportsAlwaysOn];
        CFPreferencesSetAppValue(CFSTR("AODDeviceSupported"), supported ? kCFBooleanTrue : kCFBooleanFalse, CFSTR("com.shalamand3r.datelyrics"));
        CFPreferencesAppSynchronize(CFSTR("com.shalamand3r.datelyrics"));
        DateLyricsDebugLog(@"[AOD:CAPABILITY] supported=%d", supported);
        Class cls = NSClassFromString(@"SBBacklightController");
        if ([cls respondsToSelector:@selector(sharedInstanceIfExists)]) {
            SBBacklightController *controller = [cls sharedInstanceIfExists];
            if ([controller respondsToSelector:@selector(addObserver:)]) {
                observer = [DateLyricsBacklightObserver new];
                [controller addObserver:observer];
            }
        }
        DateLyricsRefreshDisplayState(gDateLyricsScreenIsOn);
    });
}

typedef void (*MRGetNowPlayingInfoFn)(dispatch_queue_t queue, void (^handler)(NSDictionary *info));
typedef void (*MRRegisterForNotificationsFn)(dispatch_queue_t queue);

static MRGetNowPlayingInfoFn gDateLyricsGetNowPlayingInfo = NULL;
static BOOL gDateLyricsNowPlayingFetchInFlight = NO;
static BOOL gDateLyricsNowPlayingFetchPending = NO;

static void DateLyricsRequestNowPlayingInfo(void) {
    if (!gDateLyricsGetNowPlayingInfo) return;
    if (gDateLyricsNowPlayingFetchInFlight) { gDateLyricsNowPlayingFetchPending = YES; return; }
    gDateLyricsNowPlayingFetchInFlight = YES;
    gDateLyricsNowPlayingFetchPending = NO;
    gDateLyricsGetNowPlayingInfo(dispatch_get_main_queue(), ^(NSDictionary *info) {
        gDateLyricsNowPlayingFetchInFlight = NO;
        DateLyricsAdoptNowPlayingInfo(info);
        if (gDateLyricsNowPlayingFetchPending) {
            gDateLyricsNowPlayingFetchPending = NO;
            DateLyricsRequestNowPlayingInfo();
        }
    });
}


static const void *kDateLyricsDiagnosticLayerTagKey = &kDateLyricsDiagnosticLayerTagKey;
static NSUInteger gDateLyricsNativeEventID = 0;

static void DateLyricsLogHierarchy(UIView *view, NSString *role) {
    if (!view) return;
    NSMutableString *hier = [NSMutableString string];
    UIView *curr = view;
    int depth = 0;
    while (curr && depth < 10) {
        [hier appendFormat:@"parent%d=%p class=%@\n", depth, curr, NSStringFromClass(curr.class)];
        if ([curr isKindOfClass:NSClassFromString(@"CSProminentSubtitleDateView")]) break;
        curr = curr.superview;
        depth++;
    }
    DateLyricsDebugLog(@"[NATIVE:HIERARCHY] event=%lu mode=%@ role=%@ label=%p class=%@\n%@frame=%@ bounds=%@ alpha=%f hidden=%d",
                       (unsigned long)gDateLyricsNativeEventID,
                       DateLyricsFindMatchingWidgetSlotForDateView(DateLyricsFindAncestorDateView(view)) ? @"widget-hybrid" : @"stock",
                       role, view, NSStringFromClass(view.class), hier,
                       NSStringFromCGRect(view.frame), NSStringFromCGRect(view.bounds), view.alpha, view.hidden);
}

static void DateLyricsTagLayerTree(CALayer *layer, NSString *role, int depth) {
    if (!layer || depth > 15) return;
    objc_setAssociatedObject(layer, kDateLyricsDiagnosticLayerTagKey, role, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (CALayer *sub in layer.sublayers) {
        DateLyricsTagLayerTree(sub, role, depth + 1);
    }
}

static void DateLyricsProbeLogLayerStatePhase(CALayer *layer, NSString *phase, NSUInteger eventID) {
    if (!layer) return;
    CALayer *pres = layer.presentationLayer;
    DateLyricsDebugLog(@"[NATIVE:STATE] phase=%@ event=%lu layer=%p model=(op=%.2f pos=%@ bounds=%@ transform=%@) pres=%@",
                       phase, (unsigned long)eventID, layer, layer.opacity, NSStringFromCGPoint(layer.position),
                       NSStringFromCGRect(layer.bounds), NSStringFromCGAffineTransform(layer.affineTransform), pres ? [NSString stringWithFormat:@"(op=%.2f pos=%@ bounds=%@ transform=%@)", pres.opacity, NSStringFromCGPoint(pres.position), NSStringFromCGRect(pres.bounds), NSStringFromCGAffineTransform(pres.affineTransform)] : @"nil");
}

static void DateLyricsProbeDispatchStateSamples(CALayer *layer, NSUInteger eventID, NSTimeInterval duration) {
    if (!layer) return;
    __weak CALayer *weakLayer = layer;
    NSArray *delays = @[@0.0, @0.016, @0.050, @0.100, @0.250, @0.500, @(duration), @(duration + 0.050)];
    for (NSNumber *d in delays) {
        NSTimeInterval delay = d.doubleValue;
        if (delay < 0) continue;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            CALayer *strongLayer = weakLayer;
            if (strongLayer) {
                DateLyricsProbeLogLayerStatePhase(strongLayer, [NSString stringWithFormat:@"%.0fms", delay * 1000.0], eventID);
            }
        });
    }
}

static void DateLyricsDiagnosticInventoryMethods(void) {
    NSArray *classesToInspect = @[@"_UIAnimatingLabel", @"CSProminentSubtitleDateView", @"CSProminentEmptyElementView"];
    NSArray *keywords = @[@"anim", @"transition", @"text", @"label", @"date", @"update", @"content", @"appear", @"disappear"];

    for (NSString *className in classesToInspect) {
        Class cls = NSClassFromString(className);
        if (!cls) continue;

        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        if (!methods) continue;

        for (unsigned int i = 0; i < methodCount; i++) {
            SEL selector = method_getName(methods[i]);
            NSString *selectorName = NSStringFromSelector(selector);
            NSString *lowerName = [selectorName lowercaseString];

            for (NSString *keyword in keywords) {
                if ([lowerName containsString:keyword]) {
                    DateLyricsDebugLog(@"[NATIVE:INVENTORY] class=%@ selector=%@", className, selectorName);
                    break;
                }
            }
        }
        free(methods);
    }
}

%group DateLyricsDiagnostics
%hook CSProminentSubtitleDateView
- (void)_updateLabel {
    if (gDateLyricsDebugLogging && gDateLyricsNativeTransitionProbe) {
        gDateLyricsNativeEventID++;
        NSUInteger eventID = gDateLyricsNativeEventID;
        DateLyricsDebugLog(@"[NATIVE:ORIGIN] event=%lu origin=_updateLabel", (unsigned long)eventID);
        _UIAnimatingLabel *label = DateLyricsFindAnimatingLabel(self);
        DateLyricsProbeLogLayerStatePhase(label.layer, @"before", eventID);
        %orig;
        DateLyricsProbeLogLayerStatePhase(label.layer, @"after", eventID);
        DateLyricsProbeDispatchStateSamples(label.layer, eventID, 0.5);
    } else {
        %orig;
    }
}
- (void)setDate:(id)date {
    if (gDateLyricsDebugLogging && gDateLyricsNativeTransitionProbe) {
        gDateLyricsNativeEventID++;
        NSUInteger eventID = gDateLyricsNativeEventID;
        DateLyricsDebugLog(@"[NATIVE:ORIGIN] event=%lu origin=setDate:", (unsigned long)eventID);
        _UIAnimatingLabel *label = DateLyricsFindAnimatingLabel(self);
        DateLyricsProbeLogLayerStatePhase(label.layer, @"before", eventID);
        %orig;
        DateLyricsProbeLogLayerStatePhase(label.layer, @"after", eventID);
        DateLyricsProbeDispatchStateSamples(label.layer, eventID, 0.5);
    } else {
        %orig;
    }
}
- (void)didMoveToWindow {
    %orig;
    if (gDateLyricsDebugLogging && gDateLyricsNativeTransitionProbe && self.window) {
        _UIAnimatingLabel *label = DateLyricsFindAnimatingLabel(self);
        DateLyricsLogHierarchy(label, @"date-label");
        DateLyricsTagLayerTree(self.layer, @"date-view-tree", 0);
    }
}
%end

%hook _UIAnimatingLabel
- (void)setText:(NSString *)text {
    if (gDateLyricsDebugLogging && gDateLyricsNativeTransitionProbe) {
        NSString *oldText = self.text;
        BOOL equal = [oldText isEqualToString:text];
        DateLyricsDebugLog(@"[NATIVE:TEXT] event=%lu origin=setText: old=\"%@\" new=\"%@\" equal=%d UIViewAnimationsEnabled=%d",
            (unsigned long)gDateLyricsNativeEventID, oldText ?: @"", text ?: @"", equal, [UIView areAnimationsEnabled]);
        if (!equal) {
            DateLyricsDebugLog(@"[NATIVE:STACK] event=%lu \n%@", (unsigned long)gDateLyricsNativeEventID, [[NSThread callStackSymbols] subarrayWithRange:NSMakeRange(0, MIN(10, [NSThread callStackSymbols].count))]);
        }
        %orig;
    } else {
        %orig;
    }
}
- (void)setAttributedText:(NSAttributedString *)text {
    if (gDateLyricsDebugLogging && gDateLyricsNativeTransitionProbe) {
        NSString *oldText = self.attributedText.string;
        NSString *newText = text.string;
        BOOL equal = [oldText isEqualToString:newText];
        DateLyricsDebugLog(@"[NATIVE:TEXT] event=%lu origin=setAttributedText: old=\"%@\" new=\"%@\" equal=%d UIViewAnimationsEnabled=%d",
            (unsigned long)gDateLyricsNativeEventID, oldText ?: @"", newText ?: @"", equal, [UIView areAnimationsEnabled]);
        if (!equal) {
            DateLyricsDebugLog(@"[NATIVE:STACK] event=%lu \n%@", (unsigned long)gDateLyricsNativeEventID, [[NSThread callStackSymbols] subarrayWithRange:NSMakeRange(0, MIN(10, [NSThread callStackSymbols].count))]);
        }
        %orig;
    } else {
        %orig;
    }
}
%end

%hook CALayer
- (void)addAnimation:(CAAnimation *)anim forKey:(NSString *)key {
    NSString *role = objc_getAssociatedObject(self, kDateLyricsDiagnosticLayerTagKey);
    if (gDateLyricsDebugLogging && gDateLyricsNativeTransitionProbe && role) {
        DateLyricsDebugLog(@"[NATIVE:ANIM_ADD] event=%lu origin=unknown layer=%p role=%@ key=%@ class=%@ duration=%.3f",
            (unsigned long)gDateLyricsNativeEventID, self, role, key, NSStringFromClass(anim.class), anim.duration);
        if ([anim isKindOfClass:CATransition.class]) {
            CATransition *t = (CATransition *)anim;
            DateLyricsDebugLog(@"[NATIVE:ANIM_CATRANSITION] type=%@ subtype=%@ start=%.2f end=%.2f", t.type, t.subtype, t.startProgress, t.endProgress);
        } else if ([anim isKindOfClass:CABasicAnimation.class]) {
            CABasicAnimation *b = (CABasicAnimation *)anim;
            DateLyricsDebugLog(@"[NATIVE:ANIM_CABASIC] keyPath=%@ from=%@ to=%@ by=%@", b.keyPath, b.fromValue, b.toValue, b.byValue);
        }
        DateLyricsDebugLog(@"[NATIVE:STACK] \n%@", [[NSThread callStackSymbols] subarrayWithRange:NSMakeRange(0, MIN(10, [NSThread callStackSymbols].count))]);
        DateLyricsProbeDispatchStateSamples(self, gDateLyricsNativeEventID, anim.duration);
    }
    %orig;
}
- (void)removeAnimationForKey:(NSString *)key {
    NSString *role = objc_getAssociatedObject(self, kDateLyricsDiagnosticLayerTagKey);
    if (gDateLyricsDebugLogging && gDateLyricsNativeTransitionProbe && role) {
        DateLyricsDebugLog(@"[NATIVE:ANIM_REMOVE] event=%lu layer=%p role=%@ key=%@", (unsigned long)gDateLyricsNativeEventID, self, role, key);
    }
    %orig;
}
- (void)removeAllAnimations {
    NSString *role = objc_getAssociatedObject(self, kDateLyricsDiagnosticLayerTagKey);
    if (gDateLyricsDebugLogging && gDateLyricsNativeTransitionProbe && role) {
        DateLyricsDebugLog(@"[NATIVE:ANIM_REMOVE_ALL] event=%lu layer=%p role=%@", (unsigned long)gDateLyricsNativeEventID, self, role);
    }
    %orig;
}
%end
%end

%ctor {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gLyricsCache = [[NSMutableDictionary alloc] init];
        gWordLyricsCache = [[NSMutableDictionary alloc] init];
        gLyricsCacheOrder = [NSMutableArray array];
        gUnsynchronizedLyricsIDs = [NSMutableSet set];
        gMusixmatchPendingTaskIDs = [NSMutableDictionary dictionary];
        gMusixmatchFailureRetryAfter = [NSMutableDictionary dictionary];
        gLyricsQueue = dispatch_queue_create("com.shalamand3r.datelyrics.queue", DISPATCH_QUEUE_SERIAL);
        gLyricsTaskQueue = [NSMutableArray array];
        gActiveLyricsTasks = [NSMutableSet set];
        gPendingLyricsIDs = [NSMutableSet set];
    });

    DateLyricsReloadPrefs(NULL, NULL, NULL, NULL, NULL);
    if (DateLyricsIsMusicHost()) {
        NSNumber *requestedGeneration = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(
            CFSTR("CacheGeneration"), CFSTR("com.shalamand3r.datelyrics"));
        NSNumber *processedGeneration = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(
            CFSTR("MusicProcessedCacheGeneration"), CFSTR("com.shalamand3r.datelyrics"));
        NSUInteger requested = [requestedGeneration isKindOfClass:NSNumber.class] ? requestedGeneration.unsignedIntegerValue : 0;
        NSUInteger processed = [processedGeneration isKindOfClass:NSNumber.class] ? processedGeneration.unsignedIntegerValue : 0;
        if (requested != processed) DateLyricsClearCaches(NULL, NULL, NULL, NULL, NULL);
    }
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DateLyricsReloadPrefs, CFSTR("com.shalamand3r.datelyrics/ReloadPrefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DateLyricsClearCaches, CFSTR("com.shalamand3r.datelyrics/ClearCaches"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    BOOL isSpringBoardHost = DateLyricsIsSpringBoardHost();

    if (isSpringBoardHost) {
        dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_NOW);
        gDateLyricsDateViews = [NSHashTable weakObjectsHashTable];
        gDateLyricsWidgetSlots = [NSHashTable weakObjectsHashTable];
        gDateLyricsCurrentPayload = nil;
        DateLyricsObserveDisplayState();

        dispatch_async(dispatch_get_main_queue(), ^{
            void *mrHandle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
            if (mrHandle) {
                MRGetNowPlayingInfoFn getInfo = (MRGetNowPlayingInfoFn)dlsym(mrHandle, "MRMediaRemoteGetNowPlayingInfo");
                MRRegisterForNotificationsFn regNotifs = (MRRegisterForNotificationsFn)dlsym(mrHandle, "MRMediaRemoteRegisterForNowPlayingNotifications");
                if (getInfo && regNotifs) {
                    gDateLyricsGetNowPlayingInfo = getInfo;
                    regNotifs(dispatch_get_main_queue());
                    void (^observeBlock)(NSNotification *) = ^(__unused NSNotification *note) {
                        DateLyricsDebugLog(@"[MR] notification=%@", note.name);
                        DateLyricsRequestNowPlayingInfo();
                    };
                    [NSNotificationCenter.defaultCenter addObserverForName:@"kMRMediaRemoteNowPlayingInfoDidChangeNotification"
                                                                    object:nil queue:NSOperationQueue.mainQueue usingBlock:observeBlock];
                    [NSNotificationCenter.defaultCenter addObserverForName:@"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"
                                                                    object:nil queue:NSOperationQueue.mainQueue usingBlock:observeBlock];
                    [NSNotificationCenter.defaultCenter addObserverForName:@"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
                                                                    object:nil queue:NSOperationQueue.mainQueue usingBlock:observeBlock];
                    DateLyricsRequestNowPlayingInfo();
                }
            }
        });

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DateLyricsHandleScoreChanged, CFSTR("com.shalamand3r.datelyrics/score.changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DateLyricsRefreshSharedLyrics, CFSTR("com.shalamand3r.corelyrics/CacheUpdated"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

        %init(DateLyricsSpringBoard);
        if (gDateLyricsNativeTransitionProbe) {
            DateLyricsDiagnosticInventoryMethods();
            %init(DateLyricsDiagnostics);
        }
    } else if (DateLyricsIsMusicHost()) {
        dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_NOW);
        %init(DateLyricsPrimary);
        dispatch_async(dispatch_get_main_queue(), ^{
            DateLyricsRefreshStorefront();
        });


    }
}
