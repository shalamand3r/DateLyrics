@import Darwin;
@import Foundation;
@import MediaPlayer;
@import UIKit;
#import <objc/runtime.h>

@interface ICURLResponse : NSObject
@property (nonatomic, readonly) NSData *bodyData;
@end

typedef void (^ICURLSessionCompletionHandler)(ICURLResponse *, NSError *);

@interface MSVLyricsLine : NSObject
@property (assign, nonatomic) NSTimeInterval startTime;
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
@property (assign, nonatomic) BOOL hasITunesStoreIdentifier;
@property (copy, nonatomic) NSString *title;
@property (copy, nonatomic) NSString *trackArtistName;
@property (nonatomic, copy) NSString *amLyricsTitle;
@property (assign, nonatomic) NSTimeInterval elapsedTime;
@property (assign, nonatomic) BOOL lyricsAvailable;
@property (assign, nonatomic) BOOL hasLyricsAvailable;
@property (assign, nonatomic) NSInteger lyricsAdamID;
@property (assign, nonatomic) BOOL hasLyricsAdamID;
@end

@interface MRContentItem : NSObject
@property (nonatomic, copy) MRContentItemMetadata *metadata;
@end

@interface MPNowPlayingContentItem : MPContentItem
@property (assign, nonatomic) NSInteger storeID;
@property (nonatomic, strong) NSTimer *amlTimer;
@property (nonatomic, strong) NSTimer *amlPauseTimer;
@property (nonatomic, copy) NSString *amlCurrentLyricTitle;
@property (nonatomic, copy) NSString *amlCurrentPayloadSignature;
@property (assign, nonatomic) float playbackRate;
- (NSTimeInterval)calculatedElapsedTime;
- (void)setElapsedTime:(double)elapsedTime playbackRate:(float)arg2;
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

@interface MPNowPlayingInfoCenter (Private)
- (MPNowPlayingContentItem *)nowPlayingContentItem;
@end

@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
@property (nonatomic, readonly) NSURL *dataContainerURL;
@end

@interface CSProminentSubtitleDateView : UIView
@end

@interface CSProminentEmptyElementView : UIView
@end

@interface _UIAnimatingLabel : UILabel
@end

@interface _UIAnimatingLabel (DateLyrics)
- (void)_amlApplyCurrentLyric;
@end

@interface LyricsTask : NSObject
@property (nonatomic, assign) NSInteger iTunesStoreID;
@property (nonatomic, assign) NSInteger lyricsAdamID;
@property (nonatomic, assign) NSInteger retryCount;
@property (nonatomic, strong) NSURL *lyricURL;
@property (nonatomic, strong) NSString *lyricsFilePath;
@end

@interface DateLyricsTimedWord : NSObject
@property (nonatomic, assign) NSTimeInterval begin;
@property (nonatomic, assign) NSTimeInterval end;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *separatorBefore;
@end

@interface DateLyricsTimedLine : NSObject
@property (nonatomic, assign) NSTimeInterval begin;
@property (nonatomic, assign) NSTimeInterval end;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSArray<DateLyricsTimedWord *> *words;
@end

@implementation LyricsTask
@end

@implementation DateLyricsTimedWord
@end

@implementation DateLyricsTimedLine
@end

static dispatch_queue_t gLyricsQueue = nil;
static ICURLSession *gSession = nil;
static ICMusicKitRequestContext *gRequestContext = nil;
static NSMutableArray<LyricsTask *> *gLyricsTaskQueue = nil;
static NSMutableSet<NSNumber *> *gPendingLyricsIDs = nil;
static BOOL gIsProcessingQueue = NO;
static NSString *gLyricsRootPath = nil;
static NSInteger gLastLyricsAdamID = 0;
static NSMutableDictionary<NSNumber *, NSArray<MSVLyricsLine *> *> *gLyricsCache = nil;
static NSMutableDictionary<NSNumber *, NSArray<DateLyricsTimedLine *> *> *gWordLyricsCache = nil;
static pthread_mutex_t gLyricsCacheMutex = PTHREAD_MUTEX_INITIALIZER;
static MPNowPlayingInfoCenter *gNowPlayingInfoCenter = nil;

static BOOL gDateLyricsEnabled = YES;
static BOOL gDateLyricsForceLowercase = NO;
static BOOL gDateLyricsWordHighlighting = YES;
static NSInteger gDateLyricsHighlightStyle = 0;
static CGFloat gDateLyricsStrokeWidth = 3.0;
static CGFloat gDateLyricsMinimumScale = 0.55;
static NSTimeInterval gDateLyricsPauseTimeout = 7.0;

static NSHashTable<CSProminentSubtitleDateView *> *gDateLyricsDateViews = nil;
static NSHashTable<UIView *> *gDateLyricsWidgetSlots = nil;
static NSDictionary *gDateLyricsCurrentPayload = nil;

static void DateLyricsUpdateWidgetDateView(UIView *widgetSlot);
static const void *kDateLyricsForcedWidgetDateVisibleKey = &kDateLyricsForcedWidgetDateVisibleKey;
static const void *kDateLyricsOriginalHiddenKey = &kDateLyricsOriginalHiddenKey;

static NSString *const kDateLyricsPrefsSuite = @"com.82flex.amlyrics";
static NSString *const kDateLyricsCurrentLineKey = @"CurrentLyricLine";
static NSString *const kDateLyricsBridgeFilePath = @"/var/mobile/Library/Preferences/com.82flex.amlyrics.current-line.txt";
static CFStringRef const kDateLyricsCurrentLineChangedNotification = CFSTR("com.82flex.amlyrics.current-line.changed");
static NSString *GetLyricsRootPath(void);

static BOOL DateLyricsIsSpringBoardHost(void) {
    NSString *bundleIdentifier = [NSBundle mainBundle].bundleIdentifier;
    NSString *processName = [NSProcessInfo processInfo].processName;
    return [bundleIdentifier isEqualToString:@"com.apple.springboard"] ||
           [processName isEqualToString:@"SpringBoard"];
}

static BOOL DateLyricsIsMusicHost(void) {
    NSString *bundleIdentifier = [NSBundle mainBundle].bundleIdentifier;
    NSString *processName = [NSProcessInfo processInfo].processName;
    return [bundleIdentifier isEqualToString:@"com.apple.Music"] ||
           [processName isEqualToString:@"Music"];
}

static NSString *DateLyricsLocalCurrentLinePath(void) {
    return [GetLyricsRootPath() stringByAppendingPathComponent:@"current-line.txt"];
}

static NSString *DateLyricsMusicContainerCurrentLinePath(void) {
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    if (![proxyClass respondsToSelector:@selector(applicationProxyForIdentifier:)]) return nil;
    LSApplicationProxy *proxy = [proxyClass applicationProxyForIdentifier:@"com.apple.Music"];
    NSURL *containerURL = [proxy respondsToSelector:@selector(dataContainerURL)] ? proxy.dataContainerURL : nil;
    if (!containerURL) return nil;
    return [[containerURL.path stringByAppendingPathComponent:@"Library"] stringByAppendingPathComponent:@"DateLyrics/current-line.txt"];
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

static NSString *DateLyricsSerializePayload(NSDictionary *payload) {
    if (![payload isKindOfClass:NSDictionary.class] || ![payload[@"text"] isKindOfClass:NSString.class]) return @"";
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!json) return payload[@"text"];
    NSString *string = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    return string ?: payload[@"text"];
}

static NSDictionary *DateLyricsDeserializePayloadString(NSString *string) {
    if (![string isKindOfClass:NSString.class] || string.length == 0) return nil;
    NSData *json = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (json) {
        id object = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
        if ([object isKindOfClass:NSDictionary.class] && [object[@"text"] isKindOfClass:NSString.class]) {
            return object;
        }
    }
    return DateLyricsMakePayload(string, NSMakeRange(NSNotFound, 0));
}

static void DateLyricsApplyCurrentLineToAllCoverSheets(void) {
    if (gDateLyricsDateViews) {
        for (CSProminentSubtitleDateView *dateView in gDateLyricsDateViews) {
            if (![dateView isKindOfClass:UIView.class]) continue;
            
            BOOL didForceUpdate = NO;
            if ([dateView respondsToSelector:@selector(setDate:)] && [dateView respondsToSelector:@selector(date)]) {
                id realDate = [dateView performSelector:@selector(date)];
                if (realDate) {
                    NSDate *dummyDate = [NSDate dateWithTimeIntervalSince1970:0];
                    [dateView performSelector:@selector(setDate:) withObject:dummyDate];
                    [dateView performSelector:@selector(setDate:) withObject:realDate];
                    didForceUpdate = YES;
                }
            }
            
            if (!didForceUpdate) {
                if ([dateView respondsToSelector:@selector(_updateLabel)]) {
                    [dateView performSelector:@selector(_updateLabel)];
                } else {
                    [dateView setNeedsLayout];
                }
            }
        }
    }
    if (gDateLyricsWidgetSlots) {
        for (UIView *widgetSlot in gDateLyricsWidgetSlots) {
            if (![widgetSlot isKindOfClass:UIView.class]) continue;
            DateLyricsUpdateWidgetDateView(widgetSlot);
        }
    }
}

static NSDictionary *DateLyricsReadPayloadFromBridgeFile(void) {
    NSString *line = [NSString stringWithContentsOfFile:kDateLyricsBridgeFilePath encoding:NSUTF8StringEncoding error:nil];
    return DateLyricsDeserializePayloadString(line);
}

static NSDictionary *DateLyricsReadPayloadFromMusicContainer(void) {
    NSString *path = DateLyricsMusicContainerCurrentLinePath();
    if (path.length == 0) return nil;
    NSString *line = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    return DateLyricsDeserializePayloadString(line);
}

static void DateLyricsPersistCurrentLineSharedState(NSDictionary *payload) {
    NSString *publishedLine = DateLyricsSerializePayload(payload);
    [publishedLine writeToFile:kDateLyricsBridgeFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    CFPreferencesSetAppValue((__bridge CFStringRef)kDateLyricsCurrentLineKey, (__bridge CFPropertyListRef)publishedLine, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDateLyricsPrefsSuite);
}

static void DateLyricsPublishPayload(NSDictionary *payload) {
    NSString *publishedLine = DateLyricsSerializePayload(payload);
    if (DateLyricsIsSpringBoardHost()) {
        DateLyricsPersistCurrentLineSharedState(payload);
    } else {
        [publishedLine writeToFile:DateLyricsLocalCurrentLinePath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kDateLyricsCurrentLineChangedNotification, NULL, NULL, YES);
}

static NSDictionary *DateLyricsStoredPayload(void) {
    NSDictionary *musicContainerPayload = DateLyricsReadPayloadFromMusicContainer();
    if (musicContainerPayload) {
        return musicContainerPayload;
    }
    NSDictionary *filePayload = DateLyricsReadPayloadFromBridgeFile();
    if (filePayload) {
        return filePayload;
    }
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)kDateLyricsCurrentLineKey, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    return DateLyricsDeserializePayloadString(CFBridgingRelease(value));
}

static void DateLyricsCurrentLineChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        gDateLyricsCurrentPayload = [(DateLyricsStoredPayload() ?: @{}) copy];
        DateLyricsApplyCurrentLineToAllCoverSheets();
    });
}


static NSString *GetLyricsRootPath(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gLyricsRootPath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
        gLyricsRootPath = [gLyricsRootPath stringByAppendingPathComponent:@"DateLyrics"];
        [[NSFileManager defaultManager] createDirectoryAtPath:gLyricsRootPath withIntermediateDirectories:YES attributes:nil error:nil];
    });
    return gLyricsRootPath;
}

@interface DateLyricsWordTTMLParserDelegate : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray<DateLyricsTimedLine *> *lines;
@property (nonatomic, strong) DateLyricsTimedLine *currentLine;
@property (nonatomic, strong) NSMutableArray<DateLyricsTimedWord *> *currentWords;
@property (nonatomic, strong) NSMutableString *pendingSeparator;
@property (nonatomic, strong) NSMutableString *currentSpanText;
@property (nonatomic, assign) BOOL insideParagraph;
@end

@implementation DateLyricsWordTTMLParserDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _lines = [NSMutableArray array];
        _pendingSeparator = [NSMutableString string];
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
        [self.pendingSeparator setString:@""];
    } else if (self.insideParagraph && [elementName isEqualToString:@"span"]) {
        BOOL hasTiming = attributeDict[@"begin"] != nil || attributeDict[@"end"] != nil;
        if (hasTiming) {
            DateLyricsTimedWord *word = [DateLyricsTimedWord new];
            word.begin = DateLyricsParseTimeString(attributeDict[@"begin"]);
            word.end = DateLyricsParseTimeString(attributeDict[@"end"]);
            word.separatorBefore = [self.pendingSeparator copy] ?: @"";
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
        [self.pendingSeparator setString:@""];
    }
}

@end

static NSArray<DateLyricsTimedLine *> *DateLyricsParseWordTimedLines(NSData *data) {
    if (!data.length) return nil;
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    DateLyricsWordTTMLParserDelegate *delegate = [DateLyricsWordTTMLParserDelegate new];
    parser.delegate = delegate;
    BOOL ok = [parser parse];
    if (!ok || delegate.lines.count == 0) return nil;
    return [delegate.lines copy];
}

static void ParseLyricsData(NSData *data, NSInteger iTunesStoreID, NSInteger lyricsAdamID) {
    if (!data || gLastLyricsAdamID == lyricsAdamID) {
        return;
    }
    pthread_mutex_lock(&gLyricsCacheMutex);
    if (gLyricsCache[@(iTunesStoreID)]) {
        pthread_mutex_unlock(&gLyricsCacheMutex);
        return;
    }
    pthread_mutex_unlock(&gLyricsCacheMutex);
    NSError *parseError = nil;
    MSVLyricsTTMLParser *parser = [[%c(MSVLyricsTTMLParser) alloc] initWithTTMLData:data];
    [parser parseWithError:&parseError];
    if (parseError) {
        return;
    }
    NSMutableArray<MSVLyricsLine *> *lyricLines = [[parser lyricLines] mutableCopy];
    [lyricLines sortUsingComparator:^NSComparisonResult(MSVLyricsLine *line1, MSVLyricsLine *line2) {
        if (line1.startTime < line2.startTime) {
            return NSOrderedAscending;
        } else if (line1.startTime > line2.startTime) {
            return NSOrderedDescending;
        } else {
            return NSOrderedSame;
        }
    }];
    pthread_mutex_lock(&gLyricsCacheMutex);
    gLyricsCache[@(iTunesStoreID)] = [lyricLines copy];
    NSArray<DateLyricsTimedLine *> *wordLines = DateLyricsParseWordTimedLines(data);
    if (wordLines.count > 0) {
        gWordLyricsCache[@(iTunesStoreID)] = wordLines;
    }
    pthread_mutex_unlock(&gLyricsCacheMutex);
    gLastLyricsAdamID = lyricsAdamID;
}

static void ProcessNextTask(void) {
    if (!gSession || !gRequestContext || [gLyricsTaskQueue count] == 0) {
        gIsProcessingQueue = NO;
        return;
    }
    
    gIsProcessingQueue = YES;
    LyricsTask *task = [gLyricsTaskQueue firstObject];
    [gLyricsTaskQueue removeObjectAtIndex:0];
    
    ICMusicKitURLRequest *request = [[%c(ICMusicKitURLRequest) alloc] initWithURL:task.lyricURL requestContext:gRequestContext];
    [gSession enqueueDataRequest:request withCompletionHandler:^(ICURLResponse *response, NSError *error) {
        dispatch_async(gLyricsQueue, ^{
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
                    if (data) {
                        [data writeToFile:task.lyricsFilePath atomically:YES];
                        ParseLyricsData(data, task.iTunesStoreID, task.lyricsAdamID);
                    } else {
                        taskFailed = YES;
                    }
                }
            }
            
            if (taskFailed) {
                task.retryCount++;
                if (task.retryCount < 3) {
                    [gLyricsTaskQueue addObject:task];
                } else {
                    [gPendingLyricsIDs removeObject:@(task.lyricsAdamID)];
                }
            } else {
                [gPendingLyricsIDs removeObject:@(task.lyricsAdamID)];
            }
            
            ProcessNextTask();
        });
    }];
}

static void AddTaskToQueue(NSInteger iTunesStoreID, NSInteger lyricsAdamID, NSURL *lyricURL, NSString *lyricsFilePath) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gLyricsTaskQueue = [NSMutableArray array];
        gPendingLyricsIDs = [NSMutableSet set];
    });
    
    if ([gPendingLyricsIDs containsObject:@(lyricsAdamID)]) {
        return;
    }
    
    LyricsTask *task = [[LyricsTask alloc] init];
    task.iTunesStoreID = iTunesStoreID;
    task.lyricsAdamID = lyricsAdamID;
    task.retryCount = 0;
    task.lyricURL = lyricURL;
    task.lyricsFilePath = lyricsFilePath;
    
    [gLyricsTaskQueue addObject:task];
    [gPendingLyricsIDs addObject:@(lyricsAdamID)];
    
    if (!gIsProcessingQueue) {
        ProcessNextTask();
    }
}

%group DateLyricsPrimary

%hook ICURLSession

- (void)enqueueDataRequest:(id)arg1 withCompletionHandler:(ICURLSessionCompletionHandler)arg2 {
    if (!gSession) {
        gSession = self;
    }
    if (!gRequestContext) {
        if ([arg1 isKindOfClass:%c(ICMusicKitURLRequest)]) {
            ICMusicKitURLRequest *req = arg1;
            gRequestContext = [req requestContext];
        }
    }
    %orig;
}

%end

%hook MRNowPlayingPlayerClient

- (void)sendContentItemChanges:(NSArray<MRContentItem *> *)contentItems {
    %orig;
    if (!gDateLyricsEnabled) return;
    dispatch_async(gLyricsQueue, ^{
        
        MRContentItem *item = self.nowPlayingContentItem;
        NSInteger iTunesStoreID = item.metadata.iTunesStoreIdentifier;

        if (!item.metadata.lyricsAvailable) {
            DateLyricsPublishPayload(nil);
            return;
        }

        if (iTunesStoreID <= 0) {
            DateLyricsPublishPayload(nil);
            return;
        }
        
        NSInteger lyricsAdamID;
        NSString *lyricURLString;
        if ([item.metadata respondsToSelector:@selector(lyricsAdamID)]) {
            lyricsAdamID = item.metadata.lyricsAdamID;
            lyricURLString = [NSString stringWithFormat:@"https://amp-api.music.apple.com/v1/catalog/us/songs/%lld/syllable-lyrics?l=en-US", (long long)lyricsAdamID];
        } else {
            lyricsAdamID = iTunesStoreID;
            lyricURLString = [NSString stringWithFormat:@"https://se2.itunes.apple.com/WebObjects/MZStoreElements2.woa/wa/ttmlLyrics?id=%lld&l=en-US", (long long)iTunesStoreID];
        }
        if (lyricsAdamID <= 0) {
            DateLyricsPublishPayload(nil);
            return;
        }
        
        NSString *lyricsRoot = GetLyricsRootPath();
        NSString *lyricsFilePath = [lyricsRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"syllable-lyrics_%lld.xml", (long long)lyricsAdamID]];
        BOOL lyricsCacheExists = [[NSFileManager defaultManager] fileExistsAtPath:lyricsFilePath];
        if (lyricsCacheExists) {
            NSData *cachedData = [NSData dataWithContentsOfFile:lyricsFilePath];
            ParseLyricsData(cachedData, iTunesStoreID, lyricsAdamID);
            return;
        }

        if (!gSession || !gRequestContext) {
            return;
        }
        
        NSURL *lyricURL = [NSURL URLWithString:lyricURLString];
        AddTaskToQueue(iTunesStoreID, lyricsAdamID, lyricURL, lyricsFilePath);
    });
}

%end

%hook MPNowPlayingInfoCenter

- (MPNowPlayingContentItem *)nowPlayingContentItem {
    if (!gNowPlayingInfoCenter) {
        gNowPlayingInfoCenter = self;
    }
    return %orig;
}

%end

%hook MPNowPlayingContentItem

%property (nonatomic, strong) NSTimer *amlTimer;
%property (nonatomic, strong) NSTimer *amlPauseTimer;
%property (nonatomic, copy) NSString *amlCurrentLyricTitle;
%property (nonatomic, copy) NSString *amlCurrentPayloadSignature;

- (void)dealloc {
    [self.amlTimer invalidate];
    self.amlTimer = nil;
    [self.amlPauseTimer invalidate];
    self.amlPauseTimer = nil;
    %orig;
}

%new
- (void)amlPauseTimerFired:(NSTimer *)timer {
    self.amlCurrentLyricTitle = nil;
    self.amlCurrentPayloadSignature = nil;
    DateLyricsPublishPayload(nil);
}

%new
- (NSTimeInterval)calculatedElapsedTime {
    NSTimeInterval et = 0;
    if ([self respondsToSelector:@selector(elapsedTime)]) {
        et = [(id)self elapsedTime];
    } else if ([self respondsToSelector:@selector(metadata)]) {
        id metadata = [self performSelector:@selector(metadata)];
        if ([metadata respondsToSelector:@selector(elapsedTime)]) {
            et = (NSTimeInterval)[(NSNumber *)[metadata performSelector:@selector(elapsedTime)] doubleValue];
        }
    }
    return et;
}

%new
- (void)amlTimerFired:(NSTimer *)timer {
    NSInteger storeID = 0;
    if ([self respondsToSelector:@selector(storeID)]) {
        storeID = self.storeID;
    } else if ([self respondsToSelector:@selector(metadata)]) {
        id metadata = [self performSelector:@selector(metadata)];
        if ([metadata respondsToSelector:@selector(iTunesStoreIdentifier)]) {
            storeID = (NSInteger)[metadata performSelector:@selector(iTunesStoreIdentifier)];
        }
    }

    NSInteger currentStoreID = 0;
    MPNowPlayingContentItem *currentItem = gNowPlayingInfoCenter.nowPlayingContentItem;
    if ([currentItem respondsToSelector:@selector(storeID)]) {
        currentStoreID = currentItem.storeID;
    } else if ([currentItem respondsToSelector:@selector(metadata)]) {
        id metadata = [currentItem performSelector:@selector(metadata)];
        if ([metadata respondsToSelector:@selector(iTunesStoreIdentifier)]) {
            currentStoreID = (NSInteger)[metadata performSelector:@selector(iTunesStoreIdentifier)];
        }
    }

    if (!storeID || (gNowPlayingInfoCenter && currentStoreID != storeID)) {
        [timer invalidate];
        self.amlTimer = nil;
        return;
    }
    float rate = 1.0f;
    if ([self respondsToSelector:@selector(playbackRate)]) {
        rate = self.playbackRate;
    }
    double elapsedTime = [self calculatedElapsedTime];
    [self setElapsedTime:MAX(0, elapsedTime) playbackRate:rate];
}

- (void)setElapsedTime:(double)elapsedTime playbackRate:(float)playbackRate {
    %orig;
    [self.amlTimer invalidate];
    self.amlTimer = nil;
    [self.amlPauseTimer invalidate];
    self.amlPauseTimer = nil;

    NSInteger storeID = 0;
    if ([self respondsToSelector:@selector(storeID)]) {
        storeID = self.storeID;
    } else if ([self respondsToSelector:@selector(metadata)]) {
        id metadata = [self performSelector:@selector(metadata)];
        if ([metadata respondsToSelector:@selector(iTunesStoreIdentifier)]) {
            storeID = (NSInteger)[metadata performSelector:@selector(iTunesStoreIdentifier)];
        }
    }

    if (!storeID) {
        if (self.amlCurrentLyricTitle) {
            self.amlCurrentLyricTitle = nil;
            self.amlCurrentPayloadSignature = nil;
            DateLyricsPublishPayload(nil);
        }
        return;
    }

    NSString *title = nil;
    NSTimeInterval nextWordStart = -1.0;
    NSDictionary *wordPayload = nil;

    pthread_mutex_lock(&gLyricsCacheMutex);
    
    NSArray<DateLyricsTimedLine *> *wordLines = gWordLyricsCache[@(storeID)];
    for (DateLyricsTimedLine *line in [wordLines reverseObjectEnumerator]) {
        if (elapsedTime >= line.begin) {
            title = line.text;
            NSRange activeRange = NSMakeRange(NSNotFound, 0);
            NSUInteger cursor = 0;
            for (DateLyricsTimedWord *word in line.words) {
                cursor += word.separatorBefore.length;
                if (activeRange.location == NSNotFound && elapsedTime >= word.begin && elapsedTime < word.end) {
                    activeRange = NSMakeRange(cursor, word.text.length);
                    nextWordStart = word.end;
                } else if (word.begin > elapsedTime) {
                    if (nextWordStart < 0 || word.begin < nextWordStart) {
                        nextWordStart = word.begin;
                    }
                    break;
                }
                cursor += word.text.length;
            }
            wordPayload = DateLyricsMakePayload(line.text, activeRange);
            break;
        } else if (line.begin > elapsedTime) {
            if (nextWordStart < 0 || line.begin < nextWordStart) {
                nextWordStart = line.begin;
            }
        }
    }

    NSTimeInterval nextLineStart = -1.0;
    NSArray<MSVLyricsLine *> *lyricLines = gLyricsCache[@(storeID)];
    
    for (MSVLyricsLine *line in [lyricLines reverseObjectEnumerator]) {
        if (elapsedTime >= line.startTime) {
            if (!title.length) {
                id lyricsText = [line respondsToSelector:@selector(lyricsText)] ? [line performSelector:@selector(lyricsText)] : nil;
                if ([lyricsText isKindOfClass:[NSAttributedString class]]) {
                    title = [lyricsText string];
                } else if ([lyricsText isKindOfClass:[NSString class]]) {
                    title = (NSString *)lyricsText;
                }
            }
            break;
        } else {
            if (nextLineStart < 0 || line.startTime < nextLineStart) {
                nextLineStart = line.startTime;
            }
        }
    }
    pthread_mutex_unlock(&gLyricsCacheMutex);

    if (playbackRate == 0.0) {
        self.amlPauseTimer = [NSTimer scheduledTimerWithTimeInterval:gDateLyricsPauseTimeout target:self selector:@selector(amlPauseTimerFired:) userInfo:nil repeats:NO];
    } else {
        float timerRate = playbackRate;
        NSTimeInterval nextTrigger = -1.0;
        if (nextWordStart > elapsedTime) {
            nextTrigger = nextWordStart;
        }
        if (nextLineStart > elapsedTime) {
            if (nextTrigger < 0 || nextLineStart < nextTrigger) {
                nextTrigger = nextLineStart;
            }
        }

        if (nextTrigger > elapsedTime) {
            self.amlTimer = [NSTimer scheduledTimerWithTimeInterval:(nextTrigger - elapsedTime) / timerRate
                                                             target:self selector:@selector(amlTimerFired:)
                                                           userInfo:nil repeats:NO];
        } else {
            self.amlTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(amlTimerFired:)
                                                           userInfo:nil repeats:NO];
        }
    }

    NSDictionary *payload = wordPayload ?: DateLyricsMakePayload(title, NSMakeRange(NSNotFound, 0));
    NSString *payloadSignature = DateLyricsSerializePayload(payload);
    if (![payloadSignature isEqualToString:self.amlCurrentPayloadSignature]) {
        self.amlCurrentLyricTitle = title;
        self.amlCurrentPayloadSignature = payloadSignature;
        DateLyricsPublishPayload(payload);
    }
}

%end

%end

%group DateLyricsSpringBoard

static _UIAnimatingLabel *DateLyricsFindAnimatingLabel(UIView *view) {
    Class labelClass = NSClassFromString(@"_UIAnimatingLabel");
    if (!labelClass) return nil;
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:labelClass]) {
            return (_UIAnimatingLabel *)subview;
        }
        _UIAnimatingLabel *nestedLabel = DateLyricsFindAnimatingLabel(subview);
        if (nestedLabel) return nestedLabel;
    }
    return nil;
}

static BOOL DateLyricsViewContainsClassNamed(UIView *view, NSString *className) {
    if (![view isKindOfClass:UIView.class] || className.length == 0) return NO;
    if ([NSStringFromClass(view.class) isEqualToString:className]) return YES;

    for (UIView *subview in view.subviews) {
        if (DateLyricsViewContainsClassNamed(subview, className)) {
            return YES;
        }
    }
    return NO;
}

static CSProminentSubtitleDateView *DateLyricsFindSiblingDateView(UIView *view) {
    UIView *containerView = view.superview;
    if (![containerView isKindOfClass:UIView.class]) return nil;

    Class dateClass = NSClassFromString(@"CSProminentSubtitleDateView");
    for (UIView *subview in containerView.subviews) {
        if ([subview isKindOfClass:dateClass]) {
            return (CSProminentSubtitleDateView *)subview;
        }
    }
    return nil;
}

static BOOL DateLyricsWidgetSlotMatchesDateSlot(UIView *widgetSlot, UIView *dateView) {
    if (![widgetSlot isKindOfClass:UIView.class] || ![dateView isKindOfClass:UIView.class]) return NO;

    CGRect slotFrame = widgetSlot.frame;
    if (CGRectIsEmpty(slotFrame)) {
        return YES;
    }

    CGRect dateFrame = dateView.frame;
    if (CGRectIntersectsRect(slotFrame, dateFrame)) {
        return YES;
    }

    return CGRectGetMinY(slotFrame) <= CGRectGetMaxY(dateFrame) + 4.0 &&
           CGRectGetHeight(slotFrame) <= CGRectGetHeight(dateFrame) + 12.0;
}

static void DateLyricsSetWidgetDateSlotHidden(UIView *containerView, UIView *dateView, BOOL hidden) {
    if (![containerView isKindOfClass:UIView.class] || ![dateView isKindOfClass:UIView.class]) return;

    Class emptyElementClass = NSClassFromString(@"CSProminentEmptyElementView");
    for (UIView *subview in containerView.subviews) {
        if (![subview isKindOfClass:emptyElementClass]) continue;
        if (!DateLyricsViewContainsClassNamed(subview, @"CHUISWidgetHostViewControllerView")) continue;
        if (!DateLyricsWidgetSlotMatchesDateSlot(subview, dateView)) continue;

        subview.hidden = hidden;
    }
}

static void DateLyricsPrepareAndApplyDateLabel(_UIAnimatingLabel *label) {
    if (!label) return;
    [label _amlApplyCurrentLyric];
}

static void DateLyricsUpdateWidgetDateView(UIView *widgetSlot) {
    if (![widgetSlot isKindOfClass:UIView.class]) return;
    if (!DateLyricsViewContainsClassNamed(widgetSlot, @"CHUISWidgetHostViewControllerView")) return;

    CSProminentSubtitleDateView *dateView = DateLyricsFindSiblingDateView(widgetSlot);
    if (!dateView) return;

    NSDictionary *payload = gDateLyricsCurrentPayload ?: DateLyricsStoredPayload();
    BOOL hasLyric = [payload[@"text"] isKindOfClass:NSString.class];

    if (!gDateLyricsEnabled) hasLyric = NO;

    if (!hasLyric) {
        if ([objc_getAssociatedObject(dateView, kDateLyricsForcedWidgetDateVisibleKey) boolValue]) {
            dateView.hidden = YES;
            DateLyricsSetWidgetDateSlotHidden(widgetSlot.superview, dateView, NO);
            objc_setAssociatedObject(dateView, kDateLyricsForcedWidgetDateVisibleKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
        return;
    }

    dateView.hidden = NO;
    DateLyricsSetWidgetDateSlotHidden(widgetSlot.superview, dateView, YES);
    objc_setAssociatedObject(dateView, kDateLyricsForcedWidgetDateVisibleKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DateLyricsPrepareAndApplyDateLabel(DateLyricsFindAnimatingLabel(dateView));
    [dateView setNeedsLayout];
}

%hook CSProminentSubtitleDateView

- (void)didMoveToWindow {
    %orig;
    if (gDateLyricsDateViews) [gDateLyricsDateViews addObject:self];
    DateLyricsPrepareAndApplyDateLabel(DateLyricsFindAnimatingLabel(self));
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    %orig;

    _UIAnimatingLabel *label = DateLyricsFindAnimatingLabel(self);
    if (!label) return;

    NSDictionary *payload = gDateLyricsCurrentPayload ?: DateLyricsStoredPayload();
    NSString *lyric = payload[@"text"];
    if (lyric.length > 0 && gDateLyricsEnabled) {
        CGRect bounds = self.bounds;
        CGRect frame = label.frame;
        frame.origin.x = 0.0;
        frame.size.width = bounds.size.width;
        label.frame = frame;
        [label _amlApplyCurrentLyric];
    }
}

- (void)_updateLabel {
    %orig;
    DateLyricsPrepareAndApplyDateLabel(DateLyricsFindAnimatingLabel(self));
}

- (void)setDate:(id)date {
    %orig;
    DateLyricsPrepareAndApplyDateLabel(DateLyricsFindAnimatingLabel(self));
}

%end

%hook CSProminentEmptyElementView

- (void)didMoveToWindow {
    %orig;
    if (gDateLyricsWidgetSlots) [gDateLyricsWidgetSlots addObject:self];
    DateLyricsUpdateWidgetDateView(self);
}

- (void)layoutSubviews {
    %orig;
    if (gDateLyricsWidgetSlots) [gDateLyricsWidgetSlots addObject:self];
    DateLyricsUpdateWidgetDateView(self);
}

%end

%hook _UIAnimatingLabel

%new
- (void)_amlApplyCurrentLyric {
    if (!gDateLyricsEnabled) {
        return;
    }
    NSDictionary *payload = gDateLyricsCurrentPayload ?: DateLyricsStoredPayload();
    NSString *lyric = payload[@"text"];
    
    if (lyric.length == 0) return;

    if (gDateLyricsForceLowercase) {
        lyric = [lyric lowercaseString];
    }

    NSString *displayText = lyric;

    NSAttributedString *attrDisplayText = nil;
    NSNumber *locNum = payload[@"loc"];
    NSNumber *lenNum = payload[@"len"];
    if (gDateLyricsWordHighlighting && locNum && lenNum) {
        NSUInteger loc = locNum.unsignedIntegerValue;
        NSUInteger len = lenNum.unsignedIntegerValue;
        if (loc != NSNotFound && loc + len <= lyric.length) {
            NSMutableAttributedString *mAttrStr = [[NSMutableAttributedString alloc] initWithString:lyric];
            if (gDateLyricsHighlightStyle == 1) {  
                NSString *syllable = [lyric substringWithRange:NSMakeRange(loc, len)];
                [mAttrStr replaceCharactersInRange:NSMakeRange(loc, len) withString:[syllable uppercaseString]];
            } else {  
                UIColor *textColor = self.textColor ?: [UIColor whiteColor];
                [mAttrStr addAttribute:NSStrokeWidthAttributeName value:@(-gDateLyricsStrokeWidth) range:NSMakeRange(loc, len)];
                [mAttrStr addAttribute:NSStrokeColorAttributeName value:textColor range:NSMakeRange(loc, len)];
            }
            attrDisplayText = mAttrStr;
        }
    }

    self.numberOfLines = 1;
    self.adjustsFontSizeToFitWidth = YES;
    self.minimumScaleFactor = gDateLyricsMinimumScale;
    self.lineBreakMode = NSLineBreakByTruncatingTail;

    BOOL contentChanged = NO;
    if (attrDisplayText) {
        contentChanged = ![self.attributedText isEqualToAttributedString:attrDisplayText];
    } else {
        contentChanged = ![self.text isEqualToString:displayText];
    }

    static const void *kDateLyricsLastPlainTextKey = &kDateLyricsLastPlainTextKey;
    objc_setAssociatedObject(self, kDateLyricsLastPlainTextKey, displayText, OBJC_ASSOCIATION_COPY_NONATOMIC);

    if (contentChanged) {
        if (attrDisplayText) self.attributedText = attrDisplayText;
        else self.text = displayText;
    }
}

%end

%end



%group AMCrashPatcher

%hook VSSubscriptionRegistrationCenter

- (void)registerSubscription:(id)arg1 {
    return;
}

%end

%end

static void DateLyricsReloadPrefs(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)@"com.shalamand3r.datelyrics");

    NSNumber *valEnabled = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("Enabled"), CFSTR("com.shalamand3r.datelyrics"));
    NSNumber *valForceLowercase = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("ForceLowercase"), CFSTR("com.shalamand3r.datelyrics"));
    NSNumber *valWord = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("WordHighlighting"), CFSTR("com.shalamand3r.datelyrics"));
    NSNumber *valStyle = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("HighlightStyle"), CFSTR("com.shalamand3r.datelyrics"));
    NSNumber *valStroke = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("StrokeWidth"), CFSTR("com.shalamand3r.datelyrics"));
    NSNumber *valScale = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("MinimumScale"), CFSTR("com.shalamand3r.datelyrics"));
    NSNumber *valPause = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("PauseTimeout"), CFSTR("com.shalamand3r.datelyrics"));

    if (!valEnabled || !valPause) {
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.shalamand3r.datelyrics.plist"];
        if (!prefs) {
            prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.shalamand3r.datelyrics.plist"];
        }
        if (prefs) {
            if (!valEnabled) valEnabled = prefs[@"Enabled"];
            if (!valForceLowercase) valForceLowercase = prefs[@"ForceLowercase"];
            if (!valWord) valWord = prefs[@"WordHighlighting"];
            if (!valStyle) valStyle = prefs[@"HighlightStyle"];
            if (!valStroke) valStroke = prefs[@"StrokeWidth"];
            if (!valScale) valScale = prefs[@"MinimumScale"];
            if (!valPause) valPause = prefs[@"PauseTimeout"];
        }
    }

    gDateLyricsEnabled = valEnabled ? [valEnabled boolValue] : YES;
    gDateLyricsForceLowercase = valForceLowercase ? [valForceLowercase boolValue] : NO;
    gDateLyricsWordHighlighting = valWord ? [valWord boolValue] : YES;
    gDateLyricsHighlightStyle = valStyle ? [valStyle integerValue] : 0;
    gDateLyricsStrokeWidth = valStroke ? [valStroke floatValue] : 3.0;
    gDateLyricsMinimumScale = valScale ? [valScale floatValue] : 0.55;
    gDateLyricsPauseTimeout = valPause ? [valPause doubleValue] : 7.0;

    if (!gDateLyricsEnabled) {
        if (DateLyricsIsSpringBoardHost()) {
            gDateLyricsCurrentPayload = nil;
            DateLyricsApplyCurrentLineToAllCoverSheets();
        } else if (DateLyricsIsMusicHost()) {
            DateLyricsPublishPayload(nil);
        }
    }
}

%ctor {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gLyricsCache = [[NSMutableDictionary alloc] init];
        gWordLyricsCache = [[NSMutableDictionary alloc] init];
        gLyricsQueue = dispatch_queue_create("com.82flex.amlyrics.queue", DISPATCH_QUEUE_SERIAL);
        gLyricsTaskQueue = [NSMutableArray array];
        gPendingLyricsIDs = [NSMutableSet set];
    });

    DateLyricsReloadPrefs(NULL, NULL, NULL, NULL, NULL);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DateLyricsReloadPrefs, CFSTR("com.shalamand3r.datelyrics/ReloadPrefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    BOOL isSpringBoardHost = DateLyricsIsSpringBoardHost();

    if (isSpringBoardHost) {
        dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_NOW);
        gDateLyricsDateViews = [NSHashTable weakObjectsHashTable];
        gDateLyricsWidgetSlots = [NSHashTable weakObjectsHashTable];
        DateLyricsPersistCurrentLineSharedState(nil);
        gDateLyricsCurrentPayload = nil;
        
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DateLyricsCurrentLineChanged, kDateLyricsCurrentLineChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        
        %init(DateLyricsSpringBoard);
    } else if (DateLyricsIsMusicHost()) {
        dlopen("/System/Library/Frameworks/VideoSubscriberAccount.framework/VideoSubscriberAccount", RTLD_NOW);
        dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_NOW);
        %init(AMCrashPatcher);
        %init(DateLyricsPrimary);
    }
}
