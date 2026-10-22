#import "CoreLyrics/CoreLyricsStorage.h"
#pragma once
#import <Foundation/Foundation.h>

// keep existing locations and filenames so upgrades retain offline lyrics.
static NSString *const DateLyricsSharedDirectory = @"/var/mobile/Library/DateLyrics";
static NSString *const DateLyricsLegacySharedDirectory = @"/var/jb/var/mobile/Library/DateLyrics";
static NSString *const DateLyricsExternalScoreDirectory = @"/var/mobile/Library/DateLyrics/External";
static NSString *const DateLyricsTokenFilename = @"musixmatch-token.json";

@protocol DateLyricsStorageApplicationProxy <NSObject>
+ (id)applicationProxyForIdentifier:(NSString *)identifier;
- (NSURL *)dataContainerURL;
- (BOOL)isInstalled;
@end

static inline NSString *DateLyricsStorageLocalDirectory(void) {
    NSString *library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    return library.length ? [library stringByAppendingPathComponent:@"DateLyrics"] : nil;
}

static inline NSString *DateLyricsStorageMusicDirectory(Class proxyClass) {
    if (![proxyClass respondsToSelector:@selector(applicationProxyForIdentifier:)]) return nil;
    id<DateLyricsStorageApplicationProxy> proxy = [proxyClass performSelector:@selector(applicationProxyForIdentifier:) withObject:@"com.apple.Music"];
    if ([proxy respondsToSelector:@selector(isInstalled)] && ![proxy isInstalled]) return nil;
    NSURL *container = [proxy respondsToSelector:@selector(dataContainerURL)] ? [proxy dataContainerURL] : nil;
    if (![container isKindOfClass:NSURL.class] || !container.isFileURL || !container.path.length) return nil;
    // resolve the current container on demand: reinstalling music changes its url.
    return [container.path stringByAppendingPathComponent:@"Library/DateLyrics"];
}

static inline NSData *DateLyricsStorageReadData(NSString *path) {
    return path.length ? [NSData dataWithContentsOfFile:path] : nil;
}

static inline NSString *DateLyricsStorageScorePath(NSString *directory, NSInteger track, NSString *source) {
    if (!directory.length || track <= 0) return nil;
    NSString *suffix = source.length ? [@"-" stringByAppendingString:source] : @"";
    return [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"score-%ld%@.json", (long)track, suffix]];
}

static inline NSArray<NSString *> *DateLyricsStorageCacheRoots(Class proxyClass) {
    NSMutableArray *roots = [NSMutableArray array];
    NSMutableArray *candidates = [NSMutableArray arrayWithArray:@[DateLyricsSharedDirectory,
        DateLyricsLegacySharedDirectory, DateLyricsStorageMusicDirectory(proxyClass) ?: @"",
        DateLyricsStorageLocalDirectory() ?: @"", @"/var/mobile/Library/CoreLyrics",
        @"/var/jb/var/mobile/Library/CoreLyrics"]];
    NSString *music = DateLyricsStorageMusicDirectory(proxyClass);
    if (music.length) {
        NSString *library = music.stringByDeletingLastPathComponent;
        [candidates addObject:[library stringByAppendingPathComponent:@"CoreLyrics"]];
    }
    for (NSString *path in candidates) {
        if (!path.length) continue;
        NSString *resolved = path.stringByResolvingSymlinksInPath;
        BOOL duplicate = NO;
        for (NSString *root in roots) {
            if ([root.stringByResolvingSymlinksInPath isEqualToString:resolved]) { duplicate = YES; break; }
        }
        if (!duplicate) [roots addObject:path];
    }
    return roots;
}

static inline NSArray<NSString *> *DateLyricsStorageNowPlayingPaths(void) {
    return @[[DateLyricsSharedDirectory stringByAppendingPathComponent:@"nowplaying.json"],
             [DateLyricsLegacySharedDirectory stringByAppendingPathComponent:@"nowplaying.json"]];
}

static inline NSArray<NSString *> *DateLyricsStorageDebugLogPaths(Class proxyClass) {
    NSMutableArray *paths = [@[[DateLyricsSharedDirectory stringByAppendingPathComponent:@"tweak-debug.log"],
                              [DateLyricsLegacySharedDirectory stringByAppendingPathComponent:@"tweak-debug.log"]] mutableCopy];
    NSString *music = DateLyricsStorageMusicDirectory(proxyClass);
    if (music.length) [paths addObject:[music stringByAppendingPathComponent:@"tweak-debug.log"]];
    return paths;
}

static inline BOOL DateLyricsIsLyricCacheFile(NSString *filename, NSString *directory) {
    (void)directory;
    return DLLyricsIsCacheFilename(filename);
}

static inline void DateLyricsRemoveCachedLyrics(NSString *directory, NSFileManager *fm) {
    if (!directory.length) return;
    NSDictionary *attributes = [fm attributesOfItemAtPath:directory error:nil];
    if (![attributes.fileType isEqualToString:NSFileTypeDirectory]) return;
    for (NSString *file in [fm contentsOfDirectoryAtPath:directory error:nil]) {
        if (!DateLyricsIsLyricCacheFile(file, directory)) continue;
        NSString *path = [directory stringByAppendingPathComponent:file];
        if ([[fm attributesOfItemAtPath:path error:nil].fileType isEqualToString:NSFileTypeRegular])
            [fm removeItemAtPath:path error:nil];
    }
}

static inline unsigned long long DateLyricsGetPathSize(NSString *path, NSFileManager *fm) {
    if (!path.length) return 0;
    NSDictionary *attributes = [fm attributesOfItemAtPath:path error:nil];
    if ([attributes.fileType isEqualToString:NSFileTypeRegular])
        return DateLyricsIsLyricCacheFile(path.lastPathComponent, path.stringByDeletingLastPathComponent) ? attributes.fileSize : 0;
    if (![attributes.fileType isEqualToString:NSFileTypeDirectory]) return 0;
    unsigned long long total = 0;
    for (NSString *entry in [fm contentsOfDirectoryAtPath:path error:nil])
        total += DateLyricsGetPathSize([path stringByAppendingPathComponent:entry], fm);
    return total;
}
