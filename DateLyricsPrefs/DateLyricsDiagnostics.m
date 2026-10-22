#import "DateLyricsDiagnostics.h"
#import "../DateLyricsStorage.h"

static NSArray<NSString *> *DateLyricsDebugLogPaths(void) {
    return DateLyricsStorageDebugLogPaths(NSClassFromString(@"LSApplicationProxy"));
}

// keep multiline payloads attached to their timestamped sb or music entry.
static double DateLyricsLogEntryTimestamp(NSString *line) {
    if (![line hasPrefix:@"[DateLyrics "]) return -1.0;
    NSRange close = [line rangeOfString:@"] "];
    if (close.location == NSNotFound) return -1.0;
    return [[line substringFromIndex:NSMaxRange(close)] doubleValue];
}

static NSArray<NSString *> *DateLyricsDiagnosticLogPaths(void) {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSString *path in DateLyricsDebugLogPaths()) {
        for (NSString *candidate in @[[path stringByAppendingString:@".1"], path]) {
            NSString *resolved = [candidate stringByResolvingSymlinksInPath];
            if ([seen containsObject:resolved]) continue;
            [seen addObject:resolved];
            [paths addObject:candidate];
        }
    }

    return paths;
}

void DateLyricsClearDebugLogs(void) {
    for (NSString *path in DateLyricsDiagnosticLogPaths())
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

NSString *DateLyricsCombinedDebugLogText(void) {
    // merge both hosts and their rotated files in timestamp order.
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    NSUInteger order = 0;
    for (NSString *path in DateLyricsDiagnosticLogPaths()) {
        NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if (text.length == 0) continue;
        NSMutableString *current = nil;
        double currentTime = -1.0;
        for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
            double ts = DateLyricsLogEntryTimestamp(line);
            if (ts >= 0.0 || !current) {
                if (current) [entries addObject:@{@"t": @(currentTime), @"o": @(order++), @"s": current}];
                current = [line mutableCopy];
                currentTime = ts;
            } else {
                [current appendFormat:@"\n%@", line];
            }
        }
        if (current.length > 0) [entries addObject:@{@"t": @(currentTime), @"o": @(order++), @"s": current}];
    }
    if (entries.count == 0) return nil;

    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        double ta = [a[@"t"] doubleValue], tb = [b[@"t"] doubleValue];
        if (ta < tb) return NSOrderedAscending;
        if (ta > tb) return NSOrderedDescending;
        return [a[@"o"] compare:b[@"o"]];
    }];
    NSMutableArray<NSString *> *ordered = [NSMutableArray arrayWithCapacity:entries.count];
    for (NSDictionary *entry in entries) [ordered addObject:entry[@"s"]];
    return [ordered componentsJoinedByString:@"\n"];
}

NSString *DateLyricsRecentLogText(NSString *text) {
    if (text.length == 0) return nil;
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    NSUInteger maximumLines = 5000;
    if (lines.count <= maximumLines) return text;
    return [[lines subarrayWithRange:NSMakeRange(lines.count - maximumLines, maximumLines)] componentsJoinedByString:@"\n"];
}

@interface DateLyricsLogViewController ()
@property (nonatomic, strong) UITextView *textView;
@end

@implementation DateLyricsLogViewController

- (void)loadView {
    self.textView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.textView.editable = NO;
    self.textView.selectable = YES;
    self.textView.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    self.textView.alwaysBounceVertical = YES;
    self.textView.backgroundColor = [UIColor systemBackgroundColor];
    self.textView.textColor = [UIColor labelColor];
    self.view = self.textView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Debug Log";
    self.textView.text = self.logText.length > 0 ? self.logText : @"No log entries yet.";
    UIBarButtonItem *copyButton = [[UIBarButtonItem alloc] initWithTitle:@"Copy"
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self
                                                                   action:@selector(copyLog)];
    UIBarButtonItem *clearButton = [[UIBarButtonItem alloc] initWithTitle:@"Clear"
                                                                     style:UIBarButtonItemStylePlain
                                                                    target:self
                                                                    action:@selector(clearLog)];
    self.navigationItem.rightBarButtonItems = @[copyButton, clearButton];
}

- (void)copyLog {
    if (self.logText.length == 0) return;
    UIPasteboard.generalPasteboard.string = self.logText;
    self.navigationItem.rightBarButtonItems.firstObject.title = @"Copied";
}

- (void)clearLog {
    DateLyricsClearDebugLogs();
    self.logText = nil;
    self.textView.text = @"No log entries yet.";
}

@end

