#import "DateLyricsPreviewSample.h"

@interface DateLyricsPreviewWord : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) BOOL isBackground;
@property (nonatomic, assign) double beginTime;
@property (nonatomic, assign) double endTime;
@end
@implementation DateLyricsPreviewWord
@end

@interface DateLyricsPreviewLine : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSArray<NSValue *> *wordRanges;
@property (nonatomic, copy) NSArray<NSNumber *> *wordIsBackground;
@property (nonatomic, assign) double beginTime;
@property (nonatomic, assign) double endTime;
@property (nonatomic, copy) NSArray<NSNumber *> *wordBeginTimes;
@property (nonatomic, copy) NSArray<NSNumber *> *wordEndTimes;
@end
@implementation DateLyricsPreviewLine
@end

@interface DateLyricsTTMLParser : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray<DateLyricsPreviewLine *> *lines;
@property (nonatomic, strong) NSMutableArray<DateLyricsPreviewWord *> *currentWords;
@property (nonatomic, assign) NSInteger backgroundDepth;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *spanIsBgStack;
@property (nonatomic, assign) BOOL insideP;
@property (nonatomic, assign) double currentPBegin;
@property (nonatomic, assign) double currentPEnd;
@property (nonatomic, assign) double currentSpanBegin;
@property (nonatomic, assign) double currentSpanEnd;
@end

@implementation DateLyricsTTMLParser

- (instancetype)init {
    self = [super init];
    if (self) {
        _lines = [NSMutableArray array];
        _currentWords = [NSMutableArray array];
        _backgroundDepth = 0;
        _spanIsBgStack = [NSMutableArray array];
        _insideP = NO;
        _currentPBegin = 0.0;
        _currentPEnd = 0.0;
        _currentSpanBegin = 0.0;
        _currentSpanEnd = 0.0;
    }
    return self;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *, NSString *> *)attributeDict {
    if ([elementName isEqualToString:@"p"]) {
        _insideP = YES;
        [_currentWords removeAllObjects];
        _backgroundDepth = 0;
        [_spanIsBgStack removeAllObjects];
        _currentPBegin = [attributeDict[@"begin"] doubleValue];
        _currentPEnd = [attributeDict[@"end"] doubleValue];
    } else if ([elementName isEqualToString:@"span"] && _insideP) {
        BOOL isThisSpanBg = NO;
        NSString *role = attributeDict[@"ttm:role"] ?: attributeDict[@"role"];
        if ([role isEqualToString:@"x-bg"]) {
            isThisSpanBg = YES;
            _backgroundDepth++;
        }
        [_spanIsBgStack addObject:@(isThisSpanBg)];

        if (attributeDict[@"begin"]) {
            _currentSpanBegin = [attributeDict[@"begin"] doubleValue];
        } else {
            _currentSpanBegin = 0.0;
        }
        if (attributeDict[@"end"]) {
            _currentSpanEnd = [attributeDict[@"end"] doubleValue];
        } else {
            _currentSpanEnd = 0.0;
        }
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    if (!_insideP) return;
    NSString *trimmed = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return;
    DateLyricsPreviewWord *word = [[DateLyricsPreviewWord alloc] init];
    word.text = trimmed;
    word.isBackground = (_backgroundDepth > 0);
    word.beginTime = _currentSpanBegin;
    word.endTime = _currentSpanEnd;
    [_currentWords addObject:word];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    if ([elementName isEqualToString:@"span"] && _insideP) {
        if (_spanIsBgStack.count > 0) {
            BOOL wasThisSpanBg = [[_spanIsBgStack lastObject] boolValue];
            [_spanIsBgStack removeLastObject];
            if (wasThisSpanBg && _backgroundDepth > 0) {
                _backgroundDepth--;
            }
        }
    } else if ([elementName isEqualToString:@"p"] && _insideP) {
        _insideP = NO;
        if (_currentWords.count == 0) return;

        NSMutableString *text = [NSMutableString string];
        NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
        NSMutableArray<NSNumber *> *bgFlags = [NSMutableArray array];
        NSMutableArray<NSNumber *> *wordBegins = [NSMutableArray array];
        NSMutableArray<NSNumber *> *wordEnds = [NSMutableArray array];
        for (DateLyricsPreviewWord *word in _currentWords) {
            if (text.length > 0) [text appendString:@" "];
            NSRange range = NSMakeRange(text.length, word.text.length);
            [text appendString:word.text];
            [ranges addObject:[NSValue valueWithRange:range]];
            [bgFlags addObject:@(word.isBackground)];
            [wordBegins addObject:@(word.beginTime)];
            [wordEnds addObject:@(word.endTime)];
        }

        DateLyricsPreviewLine *line = [[DateLyricsPreviewLine alloc] init];
        line.text = [text copy];
        line.wordRanges = [ranges copy];
        line.wordIsBackground = [bgFlags copy];
        line.beginTime = _currentPBegin;
        line.endTime = _currentPEnd;
        line.wordBeginTimes = [wordBegins copy];
        line.wordEndTimes = [wordEnds copy];
        [_lines addObject:line];
    }
}

@end

static NSArray<DateLyricsPreviewLine *> *DateLyricsLoadPreviewLines(void) {
    NSString *path = [[NSBundle bundleForClass:NSClassFromString(@"DateLyricsRootListController")] pathForResource:@"preview" ofType:@"xml"];
    if (!path) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    DateLyricsTTMLParser *delegate = [[DateLyricsTTMLParser alloc] init];
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    parser.delegate = delegate;
    [parser parse];
    return delegate.lines.count > 0 ? [delegate.lines copy] : nil;
}

static NSArray<NSDictionary *> *DateLyricsPreviewLineDictionaries(NSArray<DateLyricsPreviewLine *> *lines) {
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (DateLyricsPreviewLine *line in lines) {
        NSMutableArray<NSDictionary *> *words = [NSMutableArray array];
        for (NSUInteger i = 0; i < line.wordRanges.count; i++) {
            NSRange r = [line.wordRanges[i] rangeValue];
            if (NSMaxRange(r) > line.text.length) continue;
            [words addObject:@{@"text": [line.text substringWithRange:r],
                               @"begin": line.wordBeginTimes[i],
                               @"end": line.wordEndTimes[i],
                               @"bg": line.wordIsBackground[i]}];
        }
        [out addObject:@{@"begin": @(line.beginTime), @"end": @(line.endTime), @"words": words}];
    }
    return out;
}

/// the built-in sample shown when no song is playing. shared by the settings page and the font page.
NSArray<NSDictionary *> *DateLyricsSharedPreviewData(void) {
    static NSArray<NSDictionary *> *data = nil;
    if (data) return data;
    NSArray<DateLyricsPreviewLine *> *lines = DateLyricsLoadPreviewLines();
    if (lines.count > 0) {
        data = DateLyricsPreviewLineDictionaries(lines);
    } else {
        // preview.xml missing: a tiny built-in song so the preview still works.
        data = @[
            @{@"begin": @0.5, @"end": @4.0, @"words": @[
                @{@"text": @"Life's", @"begin": @0.5, @"end": @1.2, @"bg": @NO},
                @{@"text": @"better", @"begin": @1.2, @"end": @2.0, @"bg": @NO},
                @{@"text": @"on", @"begin": @2.0, @"end": @2.4, @"bg": @NO},
                @{@"text": @"Saturn", @"begin": @2.4, @"end": @4.0, @"bg": @NO}]},
            @{@"begin": @4.5, @"end": @8.5, @"words": @[
                @{@"text": @"Find", @"begin": @4.5, @"end": @5.2, @"bg": @NO},
                @{@"text": @"something", @"begin": @5.2, @"end": @6.2, @"bg": @NO},
                @{@"text": @"worth", @"begin": @6.2, @"end": @7.0, @"bg": @NO},
                @{@"text": @"saving", @"begin": @7.0, @"end": @8.5, @"bg": @NO}]},
        ];
    }
    return data;
}

