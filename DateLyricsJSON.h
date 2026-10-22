#pragma once
#import <Foundation/Foundation.h>
#import <math.h>

// json fields are untrusted, including fields inside an otherwise valid object.
static inline NSDictionary *DateLyricsJSONDictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static inline NSArray *DateLyricsJSONArray(id value) {
    return [value isKindOfClass:NSArray.class] ? value : nil;
}

static inline NSString *DateLyricsJSONString(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static inline NSNumber *DateLyricsJSONNumber(id value) {
    return [value isKindOfClass:NSNumber.class] ? value : nil;
}

static inline NSInteger DateLyricsJSONTrackID(id value) {
    NSNumber *number = DateLyricsJSONNumber(value);
    if (!number || CFGetTypeID((__bridge CFTypeRef)number) == CFBooleanGetTypeID()) return 0;
    double track = number.doubleValue;
    // track ids cross the json bridge as exact positive integers below 2^53.
    return isfinite(track) && track > 0.0 && track < 0x1p53 && floor(track) == track
        ? number.integerValue : 0;
}

static inline double DateLyricsJSONDouble(id value, double fallback) {
    double number;
    if ([value isKindOfClass:NSNumber.class]) {
        number = [value doubleValue];
    } else if ([value isKindOfClass:NSString.class]) {
        NSScanner *scanner = [NSScanner scannerWithString:value];
        scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        if (![scanner scanDouble:&number] || !scanner.isAtEnd) return fallback;
    } else {
        return fallback;
    }
    return isfinite(number) ? number : fallback;
}
