#pragma once
#import <Foundation/Foundation.h>

// the same line/word dictionaries used by the on-disk score format.
FOUNDATION_EXPORT NSArray<NSDictionary *> *DateLyricsQQWordLines(id encrypted, NSTimeInterval duration);
FOUNDATION_EXPORT NSArray<NSDictionary *> *DateLyricsNetEaseWordLines(id body, NSTimeInterval duration);
FOUNDATION_EXPORT NSString *DateLyricsQQWordURL(NSString *songMID);
FOUNDATION_EXPORT NSString *DateLyricsNetEaseWordURL(NSString *trackID);
FOUNDATION_EXPORT NSMutableURLRequest *DateLyricsProviderURLRequest(NSURL *url);
