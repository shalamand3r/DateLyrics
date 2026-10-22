#import "DateLyricsProviderTiming.h"
#import "vendor/qrc/DateLyricsQRCDes.h"
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonDigest.h>
#import <zlib.h>
#import <math.h>

static const NSUInteger DateLyricsMaximumTimingBytes = 2 * 1024 * 1024;

static NSString *DateLyricsDecodeQRC(NSString *hex) {
    if (hex.length == 0 || hex.length > 512 * 1024 || hex.length % 16 != 0) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:hex.length / 2];
    uint8_t *bytes = data.mutableBytes;
    for (NSUInteger i = 0; i < hex.length; i++) {
        unichar c = [hex characterAtIndex:i];
        int digit = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
        if (digit < 0) return nil;
        if (i % 2 == 0) bytes[i / 2] = (uint8_t)(digit << 4);
        else bytes[i / 2] |= digit;
    }
    static const uint8_t key[] = "!@#)(*$%123ZXC!@!@#)(NHL";
    uint8_t schedule[3][16][6];
    DateLyricsQRCKeySetup(key, schedule, DateLyricsQRCDecrypt);
    for (NSUInteger i = 0; i < data.length; i += 8) {
        uint8_t block[8];
        DateLyricsQRCDecryptBlock(bytes + i, block, schedule);
        memcpy(bytes + i, block, 8);
    }
    NSMutableData *inflated = [NSMutableData dataWithLength:DateLyricsMaximumTimingBytes];
    uLongf length = inflated.length;
    if (uncompress(inflated.mutableBytes, &length, data.bytes, data.length) != Z_OK) return nil;
    inflated.length = length;
    return [[NSString alloc] initWithData:inflated encoding:NSUTF8StringEncoding];
}

static NSArray<NSDictionary *> *DateLyricsParseProviderWordText(NSString *body, NSTimeInterval duration, BOOL netease) {
    if (body.length == 0 || body.length > DateLyricsMaximumTimingBytes) return nil;
    static NSRegularExpression *linePattern, *qrcWordPattern, *yrcWordPattern;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        linePattern = [NSRegularExpression regularExpressionWithPattern:@"\\[(\\d+),(\\d+)\\]([\\s\\S]*?)(?=\\[\\d+,\\d+\\]|$)" options:0 error:nil];
        qrcWordPattern = [NSRegularExpression regularExpressionWithPattern:@"(.*?)\\((\\d+),(\\d+)\\)" options:0 error:nil];
        yrcWordPattern = [NSRegularExpression regularExpressionWithPattern:@"\\((\\d+),(\\d+),\\d+\\)(.*?)(?=\\(\\d+,\\d+,\\d+\\)|$)" options:0 error:nil];
    });
    NSMutableArray *lines = [NSMutableArray array];
    for (NSTextCheckingResult *match in [linePattern matchesInString:body options:0 range:NSMakeRange(0, body.length)]) {
        double begin = [[body substringWithRange:[match rangeAtIndex:1]] doubleValue] / 1000.0;
        double end = begin + [[body substringWithRange:[match rangeAtIndex:2]] doubleValue] / 1000.0;
        if (!isfinite(begin) || !isfinite(end) || begin < 0 || end <= begin ||
            (isfinite(duration) && duration > 0 && begin >= duration)) continue;
        if (isfinite(duration) && duration > 0) end = MIN(end, duration);
        NSString *raw = [body substringWithRange:[match rangeAtIndex:3]];
        raw = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (raw.length > 8192) return nil;
        NSRegularExpression *pattern = netease ? yrcWordPattern : qrcWordPattern;
        NSMutableArray *words = [NSMutableArray array];
        NSMutableString *text = [NSMutableString string];
        NSMutableString *separator = [NSMutableString string];
        BOOL valid = YES;
        NSUInteger cursor = 0;
        double previousEnd = begin;
        for (NSTextCheckingResult *token in [pattern matchesInString:raw options:0 range:NSMakeRange(0, raw.length)]) {
            if (token.range.location != cursor) { valid = NO; break; }
            cursor = NSMaxRange(token.range);
            NSString *fragment = [raw substringWithRange:[token rangeAtIndex:netease ? 3 : 1]];
            double wordBegin = [[raw substringWithRange:[token rangeAtIndex:netease ? 1 : 2]] doubleValue] / 1000.0;
            double wordEnd = wordBegin + [[raw substringWithRange:[token rangeAtIndex:netease ? 2 : 3]] doubleValue] / 1000.0;
            // netease emits punctuation as zero-duration tokens. attach it to
            // the adjacent word rather than inventing a sung-word duration.
            if (wordEnd == wordBegin && fragment.length &&
                [[fragment stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] rangeOfCharacterFromSet:NSCharacterSet.punctuationCharacterSet.invertedSet].location == NSNotFound &&
                wordBegin >= begin && wordBegin <= end) {
                if (words.count) {
                    NSMutableDictionary *last = [words.lastObject mutableCopy];
                    last[@"t"] = [last[@"t"] stringByAppendingString:fragment];
                    words[words.count - 1] = last;
                    [text appendString:fragment];
                } else [separator appendString:fragment];
                continue;
            }
            if (!isfinite(wordBegin) || !isfinite(wordEnd) || wordBegin < begin - 0.001 ||
                wordBegin < previousEnd - 0.02 || wordEnd > end + 0.001 || wordEnd <= wordBegin) { valid = NO; break; }
            previousEnd = wordEnd;
            if ([fragment stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) {
                [separator appendString:fragment];
                continue;
            }
            NSRange first = [fragment rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet.invertedSet];
            [separator appendString:[fragment substringToIndex:first.location]];
            NSString *word = [fragment substringFromIndex:first.location];
            [text appendString:separator];
            [text appendString:word];
            [words addObject:@{@"b": @(MAX(begin, wordBegin)), @"e": @(MIN(end, wordEnd)), @"t": word, @"s": [separator copy], @"bg": @NO}];
            [separator setString:@""];
        }
        // preserve untimed credit lines, but reject partial word maps as a whole.
        if (words.count == 0 && cursor == 0 && ![raw containsString:@"("]) {
            if (raw.length) [lines addObject:@{@"begin": @(begin), @"end": @(end), @"text": raw}];
            continue;
        }
        if (!valid || cursor != raw.length || words.count == 0) return nil;
        if (separator.length) {
            NSMutableDictionary *last = [words.lastObject mutableCopy];
            last[@"t"] = [last[@"t"] stringByAppendingString:separator];
            words[words.count - 1] = last;
            [text appendString:separator];
        }
        [lines addObject:@{@"begin": @(begin), @"end": @(end), @"text": text, @"words": words}];
    }
    [lines sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"begin"] compare:b[@"begin"]]; }];
    return lines.count ? lines : nil;
}

NSArray<NSDictionary *> *DateLyricsQQWordLines(id encrypted, NSTimeInterval duration) {
    if (![encrypted isKindOfClass:NSString.class]) return nil;
    NSString *xml = DateLyricsDecodeQRC(encrypted);
    if (!xml.length || [xml rangeOfString:@"<!DOCTYPE" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [xml rangeOfString:@"<!ENTITY" options:NSCaseInsensitiveSearch].location != NSNotFound) return nil;
    // qq's xml-like wrapper can contain unescaped quotation marks in lyrics.
    // read only its delimited lyric attribute; never resolve xml entities.
    if (![xml containsString:@"<QrcInfos"] || ![xml containsString:@"</QrcInfos>"]) return nil;
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"<Lyric_\\d+\\b[^>]*\\bLyricContent=([\"'])([\\s\\S]*?)\\1\\s*/>" options:0 error:nil];
    NSArray<NSTextCheckingResult *> *matches = [pattern matchesInString:xml options:0 range:NSMakeRange(0, xml.length)];
    if (matches.count != 1) return nil;
    NSString *content = [xml substringWithRange:[matches[0] rangeAtIndex:2]];
    for (NSArray *entity in @[@[@"&quot;", @"\""], @[@"&apos;", @"'"], @[@"&lt;", @"<"], @[@"&gt;", @">"], @[@"&amp;", @"&"]])
        content = [content stringByReplacingOccurrencesOfString:entity[0] withString:entity[1]];
    return DateLyricsParseProviderWordText(content, duration, NO);
}

NSArray<NSDictionary *> *DateLyricsNetEaseWordLines(id body, NSTimeInterval duration) {
    return [body isKindOfClass:NSString.class] ? DateLyricsParseProviderWordText(body, duration, YES) : nil;
}

NSString *DateLyricsQQWordURL(NSString *songMID) {
    if (!songMID.length || songMID.length > 32 || [songMID rangeOfCharacterFromSet:NSCharacterSet.alphanumericCharacterSet.invertedSet].location != NSNotFound) return nil;
    NSDictionary *payload = @{@"comm": @{@"ct": @19, @"cv": @0, @"tmeAppID": @"qqmusiclight"},
        @"req_0": @{@"module": @"music.musichallSong.PlayLyricInfo", @"method": @"GetPlayLyricInfo",
            @"param": @{@"songMID": songMID, @"platform": @0, @"needNew": @1, @"crypt": @1, @"qrc": @1, @"trans": @0, @"roma": @0}}};
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSCharacterSet *safe = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [@"https://u.y.qq.com/cgi-bin/musicu.fcg?data=" stringByAppendingString:[json stringByAddingPercentEncodingWithAllowedCharacters:safe]];
}

NSString *DateLyricsNetEaseWordURL(NSString *trackID) {
    if (trackID.length == 0 || trackID.length > 16 || [trackID rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound) return nil;
    NSDictionary *parameters = @{@"id": trackID, @"cp": @NO, @"tv": @0, @"lv": @0, @"rv": @0, @"kv": @0, @"yv": @0, @"ytv": @0, @"yrv": @0, @"e_r": @NO};
    NSData *json = [NSJSONSerialization dataWithJSONObject:parameters options:0 error:nil];
    NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    NSString *path = @"/api/song/lyric/v1";
    NSData *message = [[NSString stringWithFormat:@"nobody%@use%@md5forencrypt", path, text] dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CC_MD5(message.bytes, (CC_LONG)message.length, digest);
#pragma clang diagnostic pop
    NSMutableString *hash = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [hash appendFormat:@"%02x", digest[i]];
    NSData *plain = [[NSString stringWithFormat:@"%@-36cd479b6b5-%@-36cd479b6b5-%@", path, text, hash] dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *encrypted = [NSMutableData dataWithLength:plain.length + kCCBlockSizeAES128];
    size_t written = 0;
    if (CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionECBMode | kCCOptionPKCS7Padding,
        "e82ckenh8dichen8", kCCKeySizeAES128, NULL, plain.bytes, plain.length, encrypted.mutableBytes, encrypted.length, &written) != kCCSuccess) return nil;
    NSMutableString *hex = [NSMutableString stringWithCapacity:written * 2];
    const uint8_t *bytes = encrypted.bytes;
    for (NSUInteger i = 0; i < written; i++) [hex appendFormat:@"%02X", bytes[i]];
    return [@"https://interface3.music.163.com/eapi/song/lyric/v1?params=" stringByAppendingString:hex];
}

NSMutableURLRequest *DateLyricsProviderURLRequest(NSURL *url) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    if ([url.host isEqualToString:@"interface3.music.163.com"] && [url.path isEqualToString:@"/eapi/song/lyric/v1"] && [url.query hasPrefix:@"params="]) {
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [components.percentEncodedQuery dataUsingEncoding:NSUTF8StringEncoding];
        components.query = nil;
        request.URL = components.URL;
        [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    }
    return request;
}
