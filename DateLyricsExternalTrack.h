#import <Foundation/Foundation.h>

// exact integers below 2^53 survive the json bridge. keep metadata-derived ids
// in their own namespace so external caches cannot replace apple music scores.
static const NSInteger kDateLyricsExternalTrackBase = (NSInteger)1 << 52;

static inline BOOL DateLyricsIsExternalTrack(NSInteger trackID) {
    return trackID >= kDateLyricsExternalTrackBase;
}

static inline NSInteger DateLyricsExternalTrackID(NSDictionary *info) {
    id title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
    id artist = info[@"kMRMediaRemoteNowPlayingInfoArtist"];
    id advertisement = info[@"kMRMediaRemoteNowPlayingInfoIsAdvertisement"];
    if (![title isKindOfClass:NSString.class] || ![artist isKindOfClass:NSString.class] ||
        ([advertisement isKindOfClass:NSNumber.class] && [advertisement boolValue])) return 0;
    NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    title = [[title stringByTrimmingCharactersInSet:whitespace] precomposedStringWithCanonicalMapping];
    artist = [[artist stringByTrimmingCharactersInSet:whitespace] precomposedStringWithCanonicalMapping];
    if (![title length] || ![artist length]) return 0;
    // length-delimited json avoids ambiguity from punctuation in either field.
    // do not include elapsed time, duration or album: apps may update/omit them
    // between transport notifications for the same song.
    NSData *identity = [NSJSONSerialization dataWithJSONObject:@[title, artist] options:0 error:nil];
    uint64_t hash = UINT64_C(14695981039346656037);
    const uint8_t *bytes = (const uint8_t *)identity.bytes;
    for (NSUInteger i = 0; i < identity.length; ++i) {
        hash ^= bytes[i];
        hash *= UINT64_C(1099511628211);
    }
    return kDateLyricsExternalTrackBase | (hash & (kDateLyricsExternalTrackBase - 1));
}
