#pragma once
#import <Foundation/Foundation.h>
#import "DateLyricsJSON.h"
#import "DateLyricsFetchSettings.h"
#import "DateLyricsProviderOrder.h"

static NSString *const kDateLyricsPrefsSuite = @"com.shalamand3r.datelyrics";

// editable defaults only. capability flags and cache generations survive resets.
static inline NSDictionary<NSString *, id> *DateLyricsPreferenceDefaults(void) {
    static NSDictionary *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        defaults = @{
            @"Enabled": @YES, @"AODEnabled": @YES, @"AODRefreshRetry": @YES,
            @"UseCustomFont": @NO, @"CustomFontName": @"AvenirNext-Regular",
            @"ForceLowercase": @NO, @"WordHighlighting": @YES, @"ProgressiveFill": @YES,
            @"TransitionsEnabled": @YES, @"TransitionStyle": @1, @"TransitionDuration": @0.33,
            @"SplitLongLines": @NO, @"MarqueeEnabled": @YES, @"ShowAdlibs": @YES,
            @"PauseTimeout": @5.0, @"MinimumScale": @0.55,
            @"MusixmatchEnabled": @YES, @"ExternalAppsEnabled": @YES,
            @"LRCLIBEnabled": @YES, @"MegalobizEnabled": @YES, @"NetEaseEnabled": @YES, @"QQMusicEnabled": @YES,
            @"LyricsProviderOrder": DateLyricsDefaultProviderOrder(),
            @"LyricsRequestTimeout": @(DateLyricsDefaultRequestTimeout), @"RelaxedMatching": @NO,
            @"MusixmatchUserToken": @"", @"DebugLogging": @NO, @"NativeTransitionProbe": @NO
        };
    });
    return defaults;
}

static inline id DateLyricsPreferenceValue(NSString *key, NSDictionary *legacy) {
    id value = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    return value ?: legacy[key];
}

static inline BOOL DateLyricsBoolPreference(NSString *key, NSDictionary *legacy) {
    if ([key isEqualToString:@"AODEnabled"] || [key isEqualToString:@"AODRefreshRetry"]) {
        id capability = DateLyricsPreferenceValue(@"AODDeviceSupported", legacy);
        if (![capability isKindOfClass:NSNumber.class] || ![capability boolValue]) return NO;
    }
    if ([key isEqualToString:@"AODRefreshRetry"] && !DateLyricsBoolPreference(@"AODEnabled", legacy)) return NO;
    id value = DateLyricsPreferenceValue(key, legacy);
    return [value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class]
        ? [value boolValue] : [DateLyricsPreferenceDefaults()[key] boolValue];
}

static inline NSInteger DateLyricsIntegerPreference(NSString *key, NSDictionary *legacy) {
    NSInteger fallback = [DateLyricsPreferenceDefaults()[key] integerValue];
    double value = DateLyricsJSONDouble(DateLyricsPreferenceValue(key, legacy), (double)fallback);
    return value > (double)NSIntegerMin && value < (double)NSIntegerMax ? (NSInteger)value : fallback;
}

static inline double DateLyricsDoublePreference(NSString *key, NSDictionary *legacy) {
    return DateLyricsJSONDouble(DateLyricsPreferenceValue(key, legacy), [DateLyricsPreferenceDefaults()[key] doubleValue]);
}

static inline NSString *DateLyricsStringPreference(NSString *key, NSDictionary *legacy) {
    return DateLyricsJSONString(DateLyricsPreferenceValue(key, legacy)) ?: DateLyricsPreferenceDefaults()[key];
}

static inline NSDictionary *DateLyricsPreferenceSnapshot(void) {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    NSDictionary *defaults = DateLyricsPreferenceDefaults();
    for (NSString *key in defaults) {
        id fallback = defaults[key];
        if ([fallback isKindOfClass:NSString.class]) values[key] = DateLyricsStringPreference(key, nil);
        else if ([fallback isKindOfClass:NSArray.class]) values[key] = DateLyricsSanitizedProviderOrder(DateLyricsPreferenceValue(key, nil));
        else if (CFGetTypeID((__bridge CFTypeRef)fallback) == CFBooleanGetTypeID()) values[key] = @(DateLyricsBoolPreference(key, nil));
        else if ([key isEqualToString:@"TransitionStyle"]) values[key] = @(DateLyricsIntegerPreference(key, nil));
        else if ([key isEqualToString:@"LyricsRequestTimeout"]) values[key] = @(DateLyricsSanitizedRequestTimeout(@(DateLyricsDoublePreference(key, nil))));
        else values[key] = @(DateLyricsDoublePreference(key, nil));
    }
    id capability = DateLyricsPreferenceValue(@"AODDeviceSupported", nil);
    values[@"AODDeviceSupported"] = @([capability isKindOfClass:NSNumber.class] && [capability boolValue]);
    return values;
}

static inline void DateLyricsResetPreferenceValues(void) {
    CFStringRef suite = (__bridge CFStringRef)kDateLyricsPrefsSuite;
    for (NSString *key in DateLyricsPreferenceDefaults())
        CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, suite);
    // remove retired controls without touching stored lyrics or host bookkeeping.
    for (NSString *key in @[@"HapticsEnabled", @"HapticStyleSyllable", @"HapticStyleLine"])
        CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, suite);
    CFPreferencesAppSynchronize(suite);
}
