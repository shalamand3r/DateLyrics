#import "DateLyricsPreviewFeed.h"
#import <notify.h>
#import "../DateLyricsStorage.h"
#import "../DateLyricsExternalTrack.h"
#import "../DateLyricsJSON.h"
#import "../DateLyricsFetchSettings.h"

static NSArray<NSString *> *PVFeedNowPlayingPaths(void) {
    return DateLyricsStorageNowPlayingPaths();
}

static NSString *PVFeedScoreDirectory(NSInteger track) {
    if (DateLyricsIsExternalTrack(track)) return DateLyricsExternalScoreDirectory;
    return DateLyricsStorageMusicDirectory(NSClassFromString(@"LSApplicationProxy"));
}

/// converts a cached score into the preview view's line format. a line without word timing (a
/// line-synced score) becomes a single always-lit word, which is how the tweak shows such lines.
static NSArray<NSDictionary *> *PVFeedLinesFromScore(NSData *data) {
    if (data.length == 0) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if ([json isKindOfClass:NSDictionary.class] && [json[@"source"] isEqual:@"musixmatch-loading"]) return nil;
    if ([json isKindOfClass:NSDictionary.class] && [json[@"source"] isEqual:@"musixmatch-relaxed"]) {
        id relaxed = (__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("RelaxedMatching"), CFSTR("com.shalamand3r.datelyrics"));
        if (![relaxed isKindOfClass:NSNumber.class] || ![relaxed boolValue]) return nil;
    }
    NSArray *lines = [json isKindOfClass:NSDictionary.class] ? json[@"lines"] : nil;
    if (![lines isKindOfClass:NSArray.class]) return nil;

    NSMutableArray<NSDictionary *> *out = [NSMutableArray arrayWithCapacity:lines.count];
    for (NSDictionary *line in lines) {
        if (![line isKindOfClass:NSDictionary.class]) continue;
        NSString *text = DateLyricsJSONString(line[@"text"]);
        double begin = DateLyricsJSONDouble(line[@"begin"], NAN);
        double end = DateLyricsJSONDouble(line[@"end"], NAN);
        if (!isfinite(begin) || !isfinite(end) || begin < 0 || end <= begin) continue;
        NSMutableArray<NSDictionary *> *words = [NSMutableArray array];
        for (id rawWord in DateLyricsJSONArray(line[@"words"])) {
            NSDictionary *word = DateLyricsJSONDictionary(rawWord);
            NSString *t = DateLyricsJSONString(word[@"t"]);
            double wordBegin = DateLyricsJSONDouble(word[@"b"], NAN);
            double wordEnd = DateLyricsJSONDouble(word[@"e"], NAN);
            if (t.length == 0 || !isfinite(wordBegin) || !isfinite(wordEnd) ||
                wordBegin < begin || wordEnd <= wordBegin || wordEnd > end) continue;
            [words addObject:@{@"text": t, @"sep": DateLyricsJSONString(word[@"s"]) ?: @"",
                               @"begin": @(wordBegin), @"end": @(wordEnd),
                               @"bg": @(DateLyricsJSONNumber(word[@"bg"]).boolValue)}];
        }
        if (words.count == 0) {
            if (![text isKindOfClass:NSString.class] || text.length == 0) continue;
            [words addObject:@{@"text": text, @"begin": @(-1.0e6), @"end": @(-1.0e6 + 1.0), @"bg": @NO}];
        }
        [out addObject:@{@"begin": @(begin), @"end": @(end), @"words": words}];
    }
    return out;
}

@implementation DateLyricsPreviewFeed {
    NSMutableArray<DateLyricsPreviewView *> *_views;
    NSTimer *_timer;
    BOOL _running;
    int _scoreNotificationToken;
    NSUInteger _loadGeneration;

    // latest now-playing note.
    NSInteger _track;
    double _elapsed, _rate, _wall;

    // cache of the most recently loaded score, so a finished/stale song doesn't reload every poll.
    NSInteger _cacheTrack;
    NSArray<NSDictionary *> *_cacheLines;
    double _cacheEnd;
    NSInteger _loadingTrack;

    // what the views currently show.
    NSInteger _shownTrack;       // 0 = placeholder
    BOOL _placeholderApplied;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _views = [NSMutableArray array];
        _scoreNotificationToken = -1;
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
    if (_scoreNotificationToken >= 0) notify_cancel(_scoreNotificationToken);
}

#pragma mark - Public

- (void)addView:(DateLyricsPreviewView *)view {
    if (!view) return;
    [_views addObject:view];
    [self applyStateToView:view];
}

- (void)start {
    if (_timer) return;
    _running = YES;
    __weak typeof(self) weakSelf = self;
    int token;
    if (notify_register_dispatch("com.shalamand3r.datelyrics/score.changed", &token,
        dispatch_get_main_queue(), ^(__unused int unusedToken) { [weakSelf scoreDidChange]; }) == NOTIFY_STATUS_OK)
        _scoreNotificationToken = token;
    // a provider may have upgraded the cached score while settings was closed.
    [self readNowPlaying];
    if (_track > 0) [self loadScoreForTrack:_track];
    [self poll];
    _timer = [NSTimer timerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) { [weakSelf poll]; }];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)stop {
    _running = NO;
    if (_scoreNotificationToken >= 0) {
        notify_cancel(_scoreNotificationToken);
        _scoreNotificationToken = -1;
    }
    _loadGeneration++;
    _loadingTrack = 0;
    [_timer invalidate];
    _timer = nil;
}

#pragma mark - State

- (double)currentElapsed {
    double age = MAX(0.0, [NSDate date].timeIntervalSince1970 - _wall);
    return _elapsed + (_rate > 0.0 ? age * _rate : 0.0);
}

- (void)readNowPlaying {
    for (NSString *path in PVFeedNowPlayingPaths()) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (data.length == 0) continue;
        NSDictionary *note = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![note isKindOfClass:NSDictionary.class]) continue;
        _track = DateLyricsJSONTrackID(note[@"trackId"]);
        _elapsed = DateLyricsJSONDouble(note[@"elapsed"], NAN);
        _rate = DateLyricsJSONDouble(note[@"rate"], NAN);
        _wall = DateLyricsJSONDouble(note[@"wall"], NAN);
        if (!isfinite(_elapsed) || !isfinite(_rate) || !isfinite(_wall) || _elapsed < 0 || _wall <= 0) _track = 0;
        return;
    }
    _track = 0;
}

- (void)poll {
    if (!_running) return;
    [self readNowPlaying];

    BOOL live = NO;
    if (_track > 0) {
        if (_cacheTrack == _track && _cacheLines.count > 0) {
            // a song that finished (or a note left behind by a crash) shouldn't keep driving the preview.
            live = [self currentElapsed] <= _cacheEnd + 20.0;
        } else if (_loadingTrack != _track) {
            [self loadScoreForTrack:_track];
        }
    }

    if (live) {
        if (_shownTrack != _track) [self applyLive];
    } else if (_shownTrack != 0 || !_placeholderApplied) {
        [self applyPlaceholder];
    }
}

- (void)scoreDidChange {
    if (!_running || _track <= 0) return;
    // replacing an apple score with musixmatch does not change the track id.
    // retain the displayed timeline until the new asynchronous read completes.
    [self loadScoreForTrack:_track];
}

- (void)loadScoreForTrack:(NSInteger)track {
    _loadingTrack = track;
    NSUInteger generation = ++_loadGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *dir = PVFeedScoreDirectory(track);
        NSData *data = DateLyricsStorageReadData(DateLyricsStorageScorePath(dir, track, @""));
        NSArray<NSDictionary *> *lines = PVFeedLinesFromScore(data);
        dispatch_async(dispatch_get_main_queue(), ^{
            DateLyricsPreviewFeed *feed = weakSelf;
            if (!feed || !feed->_running || generation != feed->_loadGeneration) return;
            feed->_loadingTrack = 0;
            feed->_cacheTrack = track;
            // loading is identified by its source; a real one-line score is valid.
            feed->_cacheLines = lines.count > 0 ? lines : nil;
            feed->_cacheEnd = [feed->_cacheLines.lastObject[@"end"] doubleValue];
            // missing/inaccessible/loading scores retry on the 1 hz timer. polling
            // immediately on failure recursively launches unbounded disk/json work.
            if (feed->_cacheLines) {
                // force adoption even when a provider update kept the same id.
                feed->_shownTrack = 0;
                [feed poll];
            }
        });
    });
}

- (void)applyLive {
    _shownTrack = _track;
    _placeholderApplied = NO;
    for (DateLyricsPreviewView *view in _views) [self applyStateToView:view];
}

- (void)applyPlaceholder {
    _shownTrack = 0;
    _placeholderApplied = YES;
    for (DateLyricsPreviewView *view in _views) [self applyStateToView:view];
}

- (void)applyStateToView:(DateLyricsPreviewView *)view {
    if (_shownTrack != 0 && _cacheTrack == _shownTrack && _cacheLines.count > 0) {
        __weak typeof(self) weakSelf = self;
        view.timeProvider = ^double{ return weakSelf ? [weakSelf currentElapsed] : 0.0; };
        view.lines = _cacheLines;
    } else {
        view.timeProvider = nil;
        view.lines = _placeholderLines;
    }
}

@end
