#import <Foundation/Foundation.h>
#import "DateLyricsPreviewView.h"

/// decides what the preview views show: the song that is actually playing, in step with the lock
/// screen, or the built-in placeholder sample when nothing is playing.
///
/// the tweak (in springboard) publishes the playing track and position to
/// /var/mobile/library/datelyrics/nowplaying.json whenever playback changes, and the lyric scores
/// it already caches live in the music app's container. this object polls that note once a second,
/// loads the matching score on a background queue, and hands the views real lines plus a time
/// source. nothing about any song is stored in the repo or the package.
@interface DateLyricsPreviewFeed : NSObject

/// shown whenever there is no usable live song.
@property (nonatomic, copy) NSArray<NSDictionary *> *placeholderLines;

/// adds a view to drive. it is switched to the current state immediately.
- (void)addView:(DateLyricsPreviewView *)view;

- (void)start;
- (void)stop;

@end
