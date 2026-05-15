#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <spawn.h>
#import "DateLyricsRootListController.h"

extern char **environ;

static NSString *const kDateLyricsPrefsSuite = @"com.shalamand3r.datelyrics";
static NSString *const kDateLyricsBridgeFilePath = @"/var/mobile/Library/Preferences/com.shalamand3r.datelyrics.current-line.txt";
static NSString *const kDateLyricsLegacyBridgeFilePath = @"/var/mobile/Library/Preferences/com.82flex.amlyrics.current-line.txt";
static CFStringRef const kDateLyricsCurrentLineChangedNotification = CFSTR("com.shalamand3r.datelyrics.current-line.changed");
static CFStringRef const kDateLyricsLegacyCurrentLineChangedNotification = CFSTR("com.82flex.amlyrics.current-line.changed");
static UIImage *_cachedGithubIcon = nil;

static NSArray<NSDictionary<NSString *, NSString *> *> *DateLyricsFontOptions(void) {
	static NSArray<NSDictionary<NSString *, NSString *> *> *cachedOptions = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSArray<NSString *> *preferenceOrder = @[@"DemiBold", @"Semibold", @"SemiBold", @"Bold", @"Medium", @"Regular", @"Roman", @"Book", @"Light"];
		NSMutableArray<NSDictionary<NSString *, NSString *> *> *options = [NSMutableArray array];
		NSArray<NSString *> *families = [[UIFont familyNames] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

		for (NSString *family in families) {
			NSArray<NSString *> *fontNames = [[UIFont fontNamesForFamilyName:family] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
			if (fontNames.count == 0) continue;

			NSString *chosenFontName = fontNames.firstObject;
			NSInteger chosenRank = NSIntegerMax;
			for (NSString *fontName in fontNames) {
				NSString *lowerName = fontName.lowercaseString;
				NSInteger rank = preferenceOrder.count + 10;
				for (NSUInteger i = 0; i < preferenceOrder.count; i++) {
					if ([lowerName containsString:[preferenceOrder[i] lowercaseString]]) {
						rank = (NSInteger)i;
						break;
					}
				}
				if (rank < chosenRank) {
					chosenRank = rank;
					chosenFontName = fontName;
				}
			}

			[options addObject:@{
				@"title": family,
				@"value": chosenFontName
			}];
		}

		cachedOptions = [options copy];
	});
	return cachedOptions;
}

static NSArray<NSString *> *DateLyricsFontTitles(void) {
	NSMutableArray<NSString *> *titles = [NSMutableArray array];
	for (NSDictionary<NSString *, NSString *> *option in DateLyricsFontOptions()) {
		[titles addObject:option[@"title"] ?: option[@"value"]];
	}
	return [titles copy];
}

static NSArray<NSString *> *DateLyricsFontValues(void) {
	NSMutableArray<NSString *> *values = [NSMutableArray array];
	for (NSDictionary<NSString *, NSString *> *option in DateLyricsFontOptions()) {
		[values addObject:option[@"value"] ?: @""];
	}
	return [values copy];
}

static NSDictionary *DateLyricsCurrentPrefs(void) {
        NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kDateLyricsPrefsSuite];
        NSMutableDictionary *values = [NSMutableDictionary dictionary];
        values[@"ForceLowercase"] = @([prefs boolForKey:@"ForceLowercase"]);
        values[@"WordHighlighting"] = @([prefs objectForKey:@"WordHighlighting"] ? [prefs boolForKey:@"WordHighlighting"] : YES);
        values[@"HighlightTrail"] = @([prefs boolForKey:@"HighlightTrail"]);
        values[@"HighlightStyle"] = @((NSInteger)[prefs integerForKey:@"HighlightStyle"]);
        values[@"UseCustomFont"] = @([prefs boolForKey:@"UseCustomFont"]);
        values[@"TransitionsEnabled"] = @([prefs objectForKey:@"TransitionsEnabled"] ? [prefs boolForKey:@"TransitionsEnabled"] : YES);
        values[@"TransitionStyle"] = @((NSInteger)[prefs integerForKey:@"TransitionStyle"]);
        id transDuration = [prefs objectForKey:@"TransitionDuration"];
        values[@"TransitionDuration"] = transDuration ?: @0.28;
        id minScale = [prefs objectForKey:@"MinimumScale"];
        values[@"MinimumScale"] = minScale ?: @0.55;
        NSString *fontName = [prefs objectForKey:@"CustomFontName"];
        if ([fontName isKindOfClass:NSString.class]) values[@"CustomFontName"] = fontName;
        id strokeValue = [prefs objectForKey:@"StrokeWidth"];
        values[@"StrokeWidth"] = strokeValue ?: @3.0;
        return values;
}
@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSURL *dataContainerURL;
+ (id)applicationProxyForIdentifier:(id)arg1;
@end

@interface DateLyricsRootListController ()
@property (nonatomic, strong) UIImageView *headerImageView;
@property (nonatomic, strong) UILabel *mainTitleLabel;
@property (nonatomic, strong) UILabel *mainPreviewLabel;
@property (nonatomic, strong) NSTimer *previewAnimationTimer;
@property (nonatomic, assign) NSInteger previewLineIndex;
@property (nonatomic, assign) NSInteger previewWordIndex;
@end

@interface DateLyricsFontListController ()
@end

@implementation DateLyricsRootListController

- (void)amlAnimatePreview {
	NSDictionary *prefs = DateLyricsCurrentPrefs();
	BOOL transitionsEnabled = [prefs[@"TransitionsEnabled"] boolValue];
	
	NSInteger oldLineIndex = self.previewLineIndex;
	self.previewLineIndex = (self.previewLineIndex + 1) % 2;
	self.previewWordIndex = -1;

	if (!transitionsEnabled || !self.mainPreviewLabel) {
		[self amlRefreshMainPreview];
		return;
	}

	NSInteger style = [prefs[@"TransitionStyle"] integerValue];
	CGFloat duration = [prefs[@"TransitionDuration"] floatValue];
	
	UILabel *currentLabel = self.mainPreviewLabel;
	UILabel *nextLabel = [[UILabel alloc] initWithFrame:currentLabel.frame];
	
	NSInteger actualLine = self.previewLineIndex;
	NSInteger actualWord = self.previewWordIndex;
	
	self.previewLineIndex = actualLine;
	self.previewWordIndex = actualWord;
	[self amlRefreshMainPreview];
	nextLabel.attributedText = currentLabel.attributedText;
	
	self.previewLineIndex = oldLineIndex;
	self.previewWordIndex = 2;
	[self amlRefreshMainPreview];
	
	self.previewLineIndex = actualLine;
	self.previewWordIndex = actualWord;

	nextLabel.textAlignment = currentLabel.textAlignment;
	nextLabel.adjustsFontSizeToFitWidth = currentLabel.adjustsFontSizeToFitWidth;
	nextLabel.minimumScaleFactor = currentLabel.minimumScaleFactor;
	nextLabel.alpha = 0.0;
	[currentLabel.superview addSubview:nextLabel];

	if (style == 1) nextLabel.transform = CGAffineTransformMakeTranslation(0, 20);
	else if (style == 2) nextLabel.transform = CGAffineTransformMakeTranslation(0, -20);
	else if (style == 3) nextLabel.transform = CGAffineTransformMakeTranslation(currentLabel.bounds.size.width, 0);
	else if (style == 4) nextLabel.transform = CGAffineTransformMakeScale(0.5, 0.5);

	[UIView animateWithDuration:duration
						  delay:0
						options:UIViewAnimationOptionCurveEaseInOut
					 animations:^{
						 nextLabel.alpha = 1.0;
						 nextLabel.transform = CGAffineTransformIdentity;

						 if (style == 0) currentLabel.alpha = 0.0;
						 else if (style == 1) { currentLabel.transform = CGAffineTransformMakeTranslation(0, -20); currentLabel.alpha = 0.0; }
						 else if (style == 2) { currentLabel.transform = CGAffineTransformMakeTranslation(0, 20); currentLabel.alpha = 0.0; }
						 else if (style == 3) { currentLabel.transform = CGAffineTransformMakeTranslation(-currentLabel.bounds.size.width, 0); currentLabel.alpha = 0.0; }
						 else if (style == 4) { currentLabel.transform = CGAffineTransformMakeScale(1.5, 1.5); currentLabel.alpha = 0.0; }
					 }
					 completion:^(BOOL finished) {
						 [self amlRefreshMainPreview];
						 currentLabel.alpha = 1.0;
						 currentLabel.transform = CGAffineTransformIdentity;
						 [nextLabel removeFromSuperview];
					 }];
}

- (void)amlPreviewStep {
	self.previewWordIndex++;
	if (self.previewWordIndex > 2) {
		[self amlAnimatePreview];
	} else {
		[self amlRefreshMainPreview];
	}
}

- (void)startPreviewAnimation {
	[self stopPreviewAnimation];
	self.previewAnimationTimer = [NSTimer scheduledTimerWithTimeInterval:0.8 target:self selector:@selector(amlPreviewStep) userInfo:nil repeats:YES];
}

- (void)stopPreviewAnimation {
	[self.previewAnimationTimer invalidate];
	self.previewAnimationTimer = nil;
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *specs = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
		NSDictionary *prefs = DateLyricsCurrentPrefs();
		BOOL showsFontStyle = [prefs[@"UseCustomFont"] boolValue];
		BOOL highlightingEnabled = [prefs[@"WordHighlighting"] boolValue];
		BOOL showsStrokeSlider = highlightingEnabled && [prefs[@"HighlightStyle"] integerValue] == 0;
		BOOL transitionsEnabled = prefs[@"TransitionsEnabled"] ? [prefs[@"TransitionsEnabled"] boolValue] : YES;

		NSIndexSet *fontIndexes = [specs indexesOfObjectsPassingTest:^BOOL(PSSpecifier *spec, NSUInteger idx, BOOL *stop) {
			return [[[spec propertyForKey:@"key"] description] isEqualToString:@"CustomFontName"] && !showsFontStyle;
		}];
		if (fontIndexes.count > 0) {
			[specs removeObjectsAtIndexes:fontIndexes];
		}

		NSIndexSet *visibilityIndexes = [specs indexesOfObjectsPassingTest:^BOOL(PSSpecifier *spec, NSUInteger idx, BOOL *stop) {
			NSString *key = [[spec propertyForKey:@"key"] description];
			if ([key isEqualToString:@"HighlightStyle"] || [key isEqualToString:@"HighlightTrail"]) {
				return !highlightingEnabled;
			}
			if ([key isEqualToString:@"StrokeWidth"]) {
				return !showsStrokeSlider;
			}
			if ([key isEqualToString:@"TransitionStyle"] || [key isEqualToString:@"TransitionDuration"]) {
				return !transitionsEnabled;
			}
			return NO;
		}];
		if (visibilityIndexes.count > 0) {
			[specs removeObjectsAtIndexes:visibilityIndexes];
		}

		for (PSSpecifier *spec in specs) {
			NSString *specifierID = [spec propertyForKey:@"id"];
			NSString *specifierKey = [spec propertyForKey:@"key"];

			if ([specifierID isEqualToString:@"GitHubCell"]) {
				if (_cachedGithubIcon) {
					[spec setProperty:_cachedGithubIcon forKey:@"iconImage"];
				} else {
					UIGraphicsBeginImageContextWithOptions(CGSizeMake(29, 29), NO, 0);
					UIImage *blank = UIGraphicsGetImageFromCurrentImageContext();
					UIGraphicsEndImageContext();
					[spec setProperty:blank forKey:@"iconImage"];
				}
			}

			if ([specifierKey isEqualToString:@"CustomFontName"]) {
				[spec setProperty:@"titlesDataSource:" forKey:@"titlesDataSource"];
				[spec setProperty:@"valuesDataSource:" forKey:@"valuesDataSource"];
			}
		}

		_specifiers = [specs copy];
	}
	return _specifiers;
}

- (NSArray *)titlesDataSource:(PSSpecifier *)specifier {
	return DateLyricsFontTitles();
}

- (NSArray *)valuesDataSource:(PSSpecifier *)specifier {
	return DateLyricsFontValues();
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];

	if ([[specifier propertyForKey:@"id"] isEqualToString:@"GitHubCell"]) {
		if (!_cachedGithubIcon) {
			UIActivityIndicatorView *spinner = (UIActivityIndicatorView *)[cell.imageView viewWithTag:1234];
			if (!spinner) {
				spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
				spinner.tag = 1234;
				[cell.imageView addSubview:spinner];

				spinner.translatesAutoresizingMaskIntoConstraints = NO;
				[NSLayoutConstraint activateConstraints:@[
					[spinner.centerXAnchor constraintEqualToAnchor:cell.imageView.centerXAnchor],
					[spinner.centerYAnchor constraintEqualToAnchor:cell.imageView.centerYAnchor]
				]];
			}
			[spinner startAnimating];
		} else {
			UIView *spinner = [cell.imageView viewWithTag:1234];
			if (spinner) {
				[spinner removeFromSuperview];
			}
		}
	}

	return cell;
}

- (void)amlRefreshMainPreview {
        NSDictionary *prefs = DateLyricsCurrentPrefs();

        self.mainPreviewLabel.alpha = 1.0;

        BOOL forceLowercase = [prefs[@"ForceLowercase"] boolValue];
        BOOL wordHighlighting = [prefs[@"WordHighlighting"] boolValue];
        BOOL keepPastHighlighted = [prefs[@"HighlightTrail"] boolValue];
        NSInteger highlightStyle = [prefs[@"HighlightStyle"] integerValue];
        BOOL useCustomFont = [prefs[@"UseCustomFont"] boolValue];
        CGFloat strokeWidth = [prefs[@"StrokeWidth"] respondsToSelector:@selector(floatValue)] ? [prefs[@"StrokeWidth"] floatValue] : 3.0f;

        NSArray *lines = @[@"1 Test Lyric", @"Lyric Test 1"];
        NSString *baseText = lines[self.previewLineIndex % lines.count];
        if (forceLowercase) baseText = baseText.lowercaseString;

        NSArray *wordRanges;
        if (self.previewLineIndex % lines.count == 0) {
                wordRanges = @[
                        [NSValue valueWithRange:NSMakeRange(0, 1)],
                        [NSValue valueWithRange:NSMakeRange(2, 4)],
                        [NSValue valueWithRange:NSMakeRange(7, 5)]
                ];
        } else {
                wordRanges = @[
                        [NSValue valueWithRange:NSMakeRange(0, 5)],
                        [NSValue valueWithRange:NSMakeRange(6, 4)],
                        [NSValue valueWithRange:NSMakeRange(11, 1)]
                ];
        }

        NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:baseText];
        UIFont *font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold];
        NSString *fontName = prefs[@"CustomFontName"];
        if (useCustomFont && [fontName isKindOfClass:NSString.class] && fontName.length > 0) {
                UIFont *customFont = [UIFont fontWithName:fontName size:20.0];
                if (customFont) font = customFont;
        }
        [attributed addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, attributed.length)];
        [attributed addAttribute:NSForegroundColorAttributeName value:[UIColor labelColor] range:NSMakeRange(0, attributed.length)];

        if (wordHighlighting && self.previewWordIndex >= 0 && self.previewWordIndex < (NSInteger)wordRanges.count) {
                NSRange activeRange = [wordRanges[self.previewWordIndex] rangeValue];
                NSRange highlightRange = activeRange;

                if (keepPastHighlighted) {
                        highlightRange = NSMakeRange(0, activeRange.location + activeRange.length);
                }

                if (highlightStyle == 1) {
                        NSString *substring = [baseText substringWithRange:highlightRange];
                        [attributed replaceCharactersInRange:highlightRange withString:substring.uppercaseString];
                } else {
                        [attributed addAttribute:NSStrokeWidthAttributeName value:@(-strokeWidth) range:highlightRange];
                        [attributed addAttribute:NSStrokeColorAttributeName value:[UIColor labelColor] range:highlightRange];
                }
        }

        self.mainPreviewLabel.attributedText = attributed;
}
- (void)loadView {
	[super loadView];

	UITableView *tableView = [self table];
	tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
	self.navigationItem.backButtonTitle = @"Back";

	UIView *titleView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
	titleView.backgroundColor = [UIColor clearColor];
	UILabel *previewLabel = [[UILabel alloc] initWithFrame:titleView.bounds];
	previewLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	previewLabel.textAlignment = NSTextAlignmentCenter;
	previewLabel.numberOfLines = 1;
	previewLabel.adjustsFontSizeToFitWidth = YES;
	previewLabel.minimumScaleFactor = 0.55;
	previewLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[titleView addSubview:previewLabel];

	self.mainPreviewLabel = previewLabel;
	self.navigationItem.titleView = titleView;
	self.previewWordIndex = -1;
	[self amlRefreshMainPreview];

	UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 180)];

	self.headerImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 20, 100, 100)];
	self.headerImageView.contentMode = UIViewContentModeScaleAspectFit;
	self.headerImageView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
	self.headerImageView.center = CGPointMake(headerView.center.x, self.headerImageView.center.y);
	self.headerImageView.layer.cornerRadius = 22;
	self.headerImageView.layer.masksToBounds = YES;
	[headerView addSubview:self.headerImageView];

	UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 130, headerView.bounds.size.width, 40)];
	titleLabel.text = @"DateLyrics";
	titleLabel.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[headerView addSubview:titleLabel];

	tableView.tableHeaderView = headerView;
	[self amlUpdateHeaderArtwork];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];

	UIColor *tintColor = [UIColor colorWithRed:255/255.0 green:127/255.0 blue:189/255.0 alpha:1.0];
	[UISwitch appearanceWhenContainedInInstancesOfClasses:@[[self class]]].onTintColor = tintColor;
	self.view.tintColor = tintColor;
	[self amlUpdateHeaderArtwork];

	if (!_cachedGithubIcon) {
		[self fetchGithubLogo];
	}
	[self amlRefreshMainPreview];
	[self startPreviewAnimation];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self stopPreviewAnimation];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	[super traitCollectionDidChange:previousTraitCollection];
	[self amlUpdateHeaderArtwork];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	[super setPreferenceValue:value specifier:specifier];

	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
	[haptic impactOccurred];

	NSString *key = [specifier propertyForKey:@"key"];
	if ([key isEqualToString:@"HighlightStyle"] ||
	        [key isEqualToString:@"WordHighlighting"] ||
	        [key isEqualToString:@"UseCustomFont"] ||
	        [key isEqualToString:@"TransitionsEnabled"] ||
	        [key isEqualToString:@"MinimumScale"]) {

	        _specifiers = nil;
	        [self reloadSpecifiers];

	        if ([key isEqualToString:@"TransitionsEnabled"]) {
	                if ([value boolValue]) [self startPreviewAnimation];
	                else [self stopPreviewAnimation];
	        }
	}
	[self amlRefreshMainPreview];
	}
- (void)amlUpdateHeaderArtwork {
	if (!self.headerImageView) return;

	NSString *resourceName = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? @"DateLyricsIconDark" : @"DateLyricsIconLight";
	NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:resourceName ofType:@"png"];
	self.headerImageView.image = [UIImage imageWithContentsOfFile:path];
}

- (void)respring {
	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
	[haptic impactOccurred];

	NSArray<NSArray<NSString *> *> *commands = @[
		@[ @"/var/jb/usr/bin/sbreload" ],
		@[ @"/usr/bin/sbreload" ],
		@[ @"/usr/bin/killall", @"-9", @"SpringBoard" ],
		@[ @"/bin/killall", @"-9", @"SpringBoard" ]
	];

	for (NSArray<NSString *> *command in commands) {
		const char *path = command.firstObject.UTF8String;
		if (![[NSFileManager defaultManager] isExecutableFileAtPath:command.firstObject]) continue;

		pid_t pid;
		size_t argc = command.count;
		char *argv[argc + 1];
		for (size_t i = 0; i < argc; i++) {
			argv[i] = (char *)command[i].UTF8String;
		}
		argv[argc] = NULL;

		if (posix_spawn(&pid, path, NULL, NULL, argv, environ) == 0) {
			return;
		}
	}
}

- (void)resetSettings {
	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
	[haptic impactOccurred];

    CFPreferencesSetAppValue((__bridge CFStringRef)@"Enabled", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"ForceLowercase", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"WordHighlighting", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"HighlightTrail", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"HighlightStyle", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"UseCustomFont", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"CustomFontName", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"StrokeWidth", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"MinimumScale", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesSetAppValue((__bridge CFStringRef)@"PauseTimeout", NULL, (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDateLyricsPrefsSuite);

    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSString *libraryPath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    NSString *lyricsRoot = [libraryPath stringByAppendingPathComponent:@"DateLyrics"];
    if ([fileManager fileExistsAtPath:lyricsRoot]) {
        [fileManager removeItemAtPath:lyricsRoot error:nil];
    }

    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    if (proxyClass) {
        LSApplicationProxy *proxy = [proxyClass applicationProxyForIdentifier:@"com.apple.Music"];
        NSURL *containerURL = [proxy respondsToSelector:@selector(dataContainerURL)] ? proxy.dataContainerURL : nil;
        if (containerURL) {
            NSString *musicLyricsPath = [[containerURL.path stringByAppendingPathComponent:@"Library"] stringByAppendingPathComponent:@"DateLyrics"];
            if ([fileManager fileExistsAtPath:musicLyricsPath]) {
                [fileManager removeItemAtPath:musicLyricsPath error:nil];
            }
        }
    }

    NSArray *sharedPaths = @[
        kDateLyricsBridgeFilePath,
        kDateLyricsLegacyBridgeFilePath
    ];
    for (NSString *path in sharedPaths) {
        if ([fileManager fileExistsAtPath:path]) {
            [fileManager removeItemAtPath:path error:nil];
        }
    }

    [self reload];

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (CFStringRef)@"com.shalamand3r.datelyrics/ReloadPrefs", NULL, NULL, YES);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kDateLyricsCurrentLineChangedNotification, NULL, NULL, YES);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kDateLyricsLegacyCurrentLineChangedNotification, NULL, NULL, YES);
}

- (void)openGithub {
	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
	[haptic impactOccurred];
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/shalamand3r/DateLyrics"] options:@{} completionHandler:nil];
}

- (void)fetchGithubLogo {
	if (_cachedGithubIcon) return;
	NSURL *url = [NSURL URLWithString:@"https://github.com/shalamand3r/shalamand3r.github.io/blob/main/CydiaIcon.png?raw=true"];
	[[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		if (data && !error) {
			UIImage *image = [UIImage imageWithData:data];
			if (image) {
				UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 29, 29)];
				imageView.image = image;
				imageView.layer.cornerRadius = 7;
				imageView.layer.masksToBounds = YES;
				imageView.layer.contentsGravity = kCAGravityResizeAspectFill;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
				CGFloat scale = [UIScreen mainScreen].scale;
#pragma clang diagnostic pop
				UIGraphicsBeginImageContextWithOptions(imageView.bounds.size, NO, scale);
				[imageView.layer renderInContext:UIGraphicsGetCurrentContext()];
				UIImage *squircleImage = UIGraphicsGetImageFromCurrentImageContext();
				UIGraphicsEndImageContext();

				_cachedGithubIcon = squircleImage;
				dispatch_async(dispatch_get_main_queue(), ^{
					PSSpecifier *githubSpecifier = [self specifierForID:@"GitHubCell"];
					if (githubSpecifier) {
						[githubSpecifier setProperty:squircleImage forKey:@"iconImage"];
						[self reloadSpecifier:githubSpecifier];

						NSIndexPath *indexPath = [self indexPathForSpecifier:githubSpecifier];
						if (indexPath) {
							UITableViewCell *cell = [self.table cellForRowAtIndexPath:indexPath];
							if (cell) {
								UIView *spinner = [cell.imageView viewWithTag:1234];
								if (spinner) {
									[spinner removeFromSuperview];
								}
							}
						}
					}
				});
			}
		}
	}] resume];
}

@end

@interface DateLyricsFontListController ()
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) NSTimer *previewAnimationTimer;
@property (nonatomic, assign) NSInteger previewLineIndex;
@property (nonatomic, assign) NSInteger previewWordIndex;
@end

@implementation DateLyricsFontListController

- (NSString *)amlSelectedFontName {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kDateLyricsPrefsSuite];
	NSString *fontName = [prefs objectForKey:@"CustomFontName"];
	return [fontName isKindOfClass:NSString.class] && fontName.length > 0 ? fontName : @"AvenirNext-DemiBold";
}

- (void)amlUpdatePreviewLabel {
	NSDictionary *prefs = DateLyricsCurrentPrefs();
	BOOL forceLowercase = [prefs[@"ForceLowercase"] boolValue];
	BOOL wordHighlighting = [prefs[@"WordHighlighting"] boolValue];
	BOOL keepPastHighlighted = [prefs[@"HighlightTrail"] boolValue];
	NSInteger highlightStyle = [prefs[@"HighlightStyle"] integerValue];
	CGFloat strokeWidth = [prefs[@"StrokeWidth"] respondsToSelector:@selector(floatValue)] ? [prefs[@"StrokeWidth"] floatValue] : 3.0f;
	CGFloat minimumScale = [prefs[@"MinimumScale"] floatValue];

	NSArray *lines = @[@"1 Test Lyric", @"Lyric Test 1"];
	NSString *baseText = lines[self.previewLineIndex % lines.count];
	if (forceLowercase) baseText = baseText.lowercaseString;

	NSArray *wordRanges;
	if (self.previewLineIndex % lines.count == 0) {
		wordRanges = @[
			[NSValue valueWithRange:NSMakeRange(0, 1)],
			[NSValue valueWithRange:NSMakeRange(2, 4)],
			[NSValue valueWithRange:NSMakeRange(7, 5)]
		];
	} else {
		wordRanges = @[
			[NSValue valueWithRange:NSMakeRange(0, 5)],
			[NSValue valueWithRange:NSMakeRange(6, 4)],
			[NSValue valueWithRange:NSMakeRange(11, 1)]
		];
	}

	NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:baseText];
	NSString *fontName = [self amlSelectedFontName];
	UIFont *font = [UIFont fontWithName:fontName size:20.0] ?: [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold];
	
	[attributed addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, attributed.length)];
	[attributed addAttribute:NSForegroundColorAttributeName value:[UIColor labelColor] range:NSMakeRange(0, attributed.length)];

	if (wordHighlighting && self.previewWordIndex >= 0 && self.previewWordIndex < (NSInteger)wordRanges.count) {
		NSRange activeRange = [wordRanges[self.previewWordIndex] rangeValue];
		NSRange highlightRange = activeRange;
		if (keepPastHighlighted) highlightRange = NSMakeRange(0, activeRange.location + activeRange.length);

		if (highlightStyle == 1) {
			NSString *substring = [baseText substringWithRange:highlightRange];
			[attributed replaceCharactersInRange:highlightRange withString:substring.uppercaseString];
		} else {
			[attributed addAttribute:NSStrokeWidthAttributeName value:@(-strokeWidth) range:highlightRange];
			[attributed addAttribute:NSStrokeColorAttributeName value:[UIColor labelColor] range:highlightRange];
		}
	}

	self.previewLabel.minimumScaleFactor = minimumScale;
	self.previewLabel.attributedText = attributed;
}

- (void)amlAnimatePreview {
	NSDictionary *prefs = DateLyricsCurrentPrefs();
	BOOL transitionsEnabled = [prefs[@"TransitionsEnabled"] boolValue];
	
	NSInteger oldLineIndex = self.previewLineIndex;
	self.previewLineIndex = (self.previewLineIndex + 1) % 2;
	self.previewWordIndex = -1;

	if (!transitionsEnabled || !self.previewLabel) {
		[self amlUpdatePreviewLabel];
		return;
	}

	NSInteger style = [prefs[@"TransitionStyle"] integerValue];
	CGFloat duration = [prefs[@"TransitionDuration"] floatValue];
	
	UILabel *currentLabel = self.previewLabel;
	UILabel *nextLabel = [[UILabel alloc] initWithFrame:currentLabel.frame];
	nextLabel.minimumScaleFactor = currentLabel.minimumScaleFactor;
	nextLabel.adjustsFontSizeToFitWidth = currentLabel.adjustsFontSizeToFitWidth;
	
	NSInteger actualLine = self.previewLineIndex;
	NSInteger actualWord = self.previewWordIndex;
	
	self.previewLineIndex = actualLine;
	self.previewWordIndex = actualWord;
	[self amlUpdatePreviewLabel];
	nextLabel.attributedText = currentLabel.attributedText;
	
	self.previewLineIndex = oldLineIndex;
	self.previewWordIndex = 2;
	[self amlUpdatePreviewLabel];
	
	self.previewLineIndex = actualLine;
	self.previewWordIndex = actualWord;

	nextLabel.textAlignment = currentLabel.textAlignment;
	nextLabel.adjustsFontSizeToFitWidth = currentLabel.adjustsFontSizeToFitWidth;
	nextLabel.minimumScaleFactor = currentLabel.minimumScaleFactor;
	nextLabel.alpha = 0.0;
	[currentLabel.superview addSubview:nextLabel];

	if (style == 1) nextLabel.transform = CGAffineTransformMakeTranslation(0, 20);
	else if (style == 2) nextLabel.transform = CGAffineTransformMakeTranslation(0, -20);
	else if (style == 3) nextLabel.transform = CGAffineTransformMakeTranslation(currentLabel.bounds.size.width, 0);
	else if (style == 4) nextLabel.transform = CGAffineTransformMakeScale(0.5, 0.5);

	[UIView animateWithDuration:duration
						  delay:0
						options:UIViewAnimationOptionCurveEaseInOut
					 animations:^{
						 nextLabel.alpha = 1.0;
						 nextLabel.transform = CGAffineTransformIdentity;

						 if (style == 0) currentLabel.alpha = 0.0;
						 else if (style == 1) { currentLabel.transform = CGAffineTransformMakeTranslation(0, -20); currentLabel.alpha = 0.0; }
						 else if (style == 2) { currentLabel.transform = CGAffineTransformMakeTranslation(0, 20); currentLabel.alpha = 0.0; }
						 else if (style == 3) { currentLabel.transform = CGAffineTransformMakeTranslation(-currentLabel.bounds.size.width, 0); currentLabel.alpha = 0.0; }
						 else if (style == 4) { currentLabel.transform = CGAffineTransformMakeScale(1.5, 1.5); currentLabel.alpha = 0.0; }
					 }
					 completion:^(BOOL finished) {
						 [self amlUpdatePreviewLabel];
						 currentLabel.alpha = 1.0;
						 currentLabel.transform = CGAffineTransformIdentity;
						 [nextLabel removeFromSuperview];
					 }];
}

- (void)amlPreviewStep {
	self.previewWordIndex++;
	if (self.previewWordIndex > 2) {
		[self amlAnimatePreview];
	} else {
		[self amlUpdatePreviewLabel];
	}
}

- (void)startPreviewAnimation {
	[self stopPreviewAnimation];
	self.previewAnimationTimer = [NSTimer scheduledTimerWithTimeInterval:0.8 target:self selector:@selector(amlPreviewStep) userInfo:nil repeats:YES];
}

- (void)stopPreviewAnimation {
	[self.previewAnimationTimer invalidate];
	self.previewAnimationTimer = nil;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.rowHeight = 44.0;

	UIView *titleView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
	titleView.backgroundColor = [UIColor clearColor];

	UILabel *previewLabel = [[UILabel alloc] initWithFrame:titleView.bounds];
	previewLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	previewLabel.textAlignment = NSTextAlignmentCenter;
	previewLabel.numberOfLines = 1;
	previewLabel.adjustsFontSizeToFitWidth = YES;
	previewLabel.minimumScaleFactor = 0.55;
	previewLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[titleView addSubview:previewLabel];
	self.previewLabel = previewLabel;

	self.navigationItem.titleView = titleView;
	self.previewWordIndex = -1;
	[self amlUpdatePreviewLabel];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self amlUpdatePreviewLabel];
	[self startPreviewAnimation];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self stopPreviewAnimation];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[super tableView:tableView didSelectRowAtIndexPath:indexPath];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self amlUpdatePreviewLabel];
	});
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	if (!cell) return cell;
	cell.textLabel.numberOfLines = 1;
	cell.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	cell.detailTextLabel.text = nil;

	return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 44.0;
}

@end
