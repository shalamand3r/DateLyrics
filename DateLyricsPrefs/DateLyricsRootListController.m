#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <spawn.h>
#import "DateLyricsRootListController.h"
#import "DateLyricsPreviewView.h"
#import "DateLyricsPreviewFeed.h"
#import "DateLyricsPreviewSample.h"
#import "DateLyricsDiagnostics.h"
#import "../DateLyricsJSON.h"
#import "../DateLyricsStorage.h"
#import "../DateLyricsProviderOrder.h"
#import "../DateLyricsFetchSettings.h"
#import "../DateLyricsPreferences.h"
#import <Preferences/PSControlTableCell.h>
#import <Preferences/PSSliderTableCell.h>

extern char **environ;

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
    return DateLyricsPreferenceSnapshot();
}



@interface DateLyricsRootListController ()
@property (nonatomic, strong) UIImageView *headerImageView;
@property (nonatomic, strong) DateLyricsPreviewView *navPreview;
@property (nonatomic, strong) DateLyricsPreviewView *headerPreview;
@property (nonatomic, strong) DateLyricsPreviewFeed *previewFeed;
@property (nonatomic, assign) BOOL pillShown;
@property (nonatomic, assign) BOOL observingScroll;
@end

static void DateLyricsPerformWipeSavedLyrics(UIViewController *presenter);
static dispatch_queue_t DateLyricsCacheMaintenanceQueue(void);
static void DateLyricsWipeLyricsCaches(void);

@implementation DateLyricsRootListController

/// pushes the current preferences (plus the value that is changing right now, which the
/// defaults store may not have flushed yet) into both preview views.
- (void)amlRefreshMainPreviewWithKey:(NSString *)key value:(id)value {
	NSMutableDictionary *prefs = [DateLyricsCurrentPrefs() mutableCopy];
	if (key.length > 0 && value) prefs[key] = value;
	// split long lines forces ad-libs off (the tweak does the same), so reflect that at once.
	if ([key isEqualToString:@"SplitLongLines"] && [value boolValue]) prefs[@"ShowAdlibs"] = @NO;
	[self.navPreview applySettings:prefs];
	[self.headerPreview applySettings:prefs];
}

- (void)amlRefreshMainPreview {
	[self amlRefreshMainPreviewWithKey:nil value:nil];
}

/// replays a line transition in both previews so a style/duration change is visible at once.
- (void)amlPlayPreviewTransition {
	[self.navPreview playTransitionDemo];
	[self.headerPreview playTransitionDemo];
}

- (void)startPreviewAnimation {
	[self.previewFeed start];
	[self.navPreview start];
	[self.headerPreview start];
}

- (void)stopPreviewAnimation {
	[self.previewFeed stop];
	[self.navPreview stop];
	[self.headerPreview stop];
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *specs = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
		NSDictionary *prefs = DateLyricsCurrentPrefs();
		BOOL showsFontStyle = [prefs[@"UseCustomFont"] boolValue];
		BOOL transitionsEnabled = prefs[@"TransitionsEnabled"] ? [prefs[@"TransitionsEnabled"] boolValue] : YES;
		BOOL splitLongLinesEnabled = [prefs[@"SplitLongLines"] boolValue];
        BOOL onlineLyricsEnabled = prefs[@"MusixmatchEnabled"] ? [prefs[@"MusixmatchEnabled"] boolValue] : YES;

		NSIndexSet *fontIndexes = [specs indexesOfObjectsPassingTest:^BOOL(PSSpecifier *spec, NSUInteger idx, BOOL *stop) {
			return [[[spec propertyForKey:@"key"] description] isEqualToString:@"CustomFontName"] && !showsFontStyle;
		}];
		if (fontIndexes.count > 0) {
			[specs removeObjectsAtIndexes:fontIndexes];
		}

		NSIndexSet *visibilityIndexes = [specs indexesOfObjectsPassingTest:^BOOL(PSSpecifier *spec, NSUInteger idx, BOOL *stop) {
			NSString *key = [[spec propertyForKey:@"key"] description];
            if ([[spec propertyForKey:@"detail"] isEqualToString:@"DateLyricsProviderOrderController"]) return !onlineLyricsEnabled;
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

            if ([specifierKey isEqualToString:@"AODEnabled"]) {
                [spec setProperty:@([prefs[@"AODDeviceSupported"] boolValue]) forKey:@"enabled"];
            }
			if ([specifierKey isEqualToString:@"ShowAdlibs"]) {
				[spec setProperty:(splitLongLinesEnabled ? @NO : @YES) forKey:@"enabled"];
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

- (void)loadView {
	[super loadView];

	UITableView *tableView = [self table];
	tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
	self.navigationItem.backButtonTitle = @"Back";

	// a compact capsule in the navigation bar: it stays visible while you scroll through the
	// settings, so every change can be watched without scrolling back to the top.
	CGFloat pillWidth = MIN(250.0, [UIScreen mainScreen].bounds.size.width - 150.0);
	UIView *titleView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, pillWidth, 44)];
	titleView.backgroundColor = [UIColor clearColor];
	self.navPreview = [[DateLyricsPreviewView alloc] initWithFrame:CGRectMake(0, 5, pillWidth, 34) card:NO];
	self.navPreview.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[titleView addSubview:self.navPreview];
	// hidden until the header card has scrolled out of view (see amlupdatepillvisibility). the
	// capsule itself is faded, not the title view: the navigation bar drives the title view's own
	// alpha during appear/transition animations and would bring it back at the top.
	self.navPreview.alpha = 0.0;
	self.navigationItem.titleView = titleView;

	UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 306)];

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

	// the lock-screen card: a faithful, full-width miniature (same width the lyric line really
	// has), so marquee, split lines and the progressive fill read the way they will on device.
	self.headerPreview = [[DateLyricsPreviewView alloc] initWithFrame:CGRectMake(16, 186, MAX(tableView.bounds.size.width - 32, 100), 112) card:YES];
	// sized explicitly in viewdidlayoutsubviews from the real table width. the header is created
	// before the table has its final width, and autoresizing from that stale width left the
	// card running edge to edge with its text off-centre.
	self.headerPreview.autoresizingMask = UIViewAutoresizingNone;
	[headerView addSubview:self.headerPreview];

	// one feed drives both: the song that is actually playing when there is one, the sample otherwise.
	self.previewFeed = [DateLyricsPreviewFeed new];
	self.previewFeed.placeholderLines = DateLyricsSharedPreviewData();
	[self.previewFeed addView:self.navPreview];
	[self.previewFeed addView:self.headerPreview];

	tableView.tableHeaderView = headerView;
	[self amlRefreshMainPreview];
	[self amlUpdateHeaderArtwork];
}

/// the header card is the main preview. only once its bottom edge has scrolled completely above
/// the visible area does the compact capsule appear in the navigation bar, so there is always
/// exactly one preview in view and never two at once.
- (void)amlUpdatePillVisibility {
	UITableView *table = self.table;
	if (!table || !self.headerPreview) return;
	CGFloat visibleTop = table.contentOffset.y + table.adjustedContentInset.top;
	BOOL show = visibleTop >= CGRectGetMaxY(self.headerPreview.frame);
	if (show == self.pillShown) return;
	self.pillShown = show;
	DateLyricsPreviewView *pill = self.navPreview;
	[UIView animateWithDuration:0.22 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{
		pill.alpha = show ? 1.0 : 0.0;
	} completion:nil];
}

/// re-applies the capsule's state without animation. used after the screen has finished
/// appearing, in case a navigation transition touched the title view.
- (void)amlEnforcePillVisibility {
	UITableView *table = self.table;
	if (!table || !self.headerPreview) return;
	CGFloat visibleTop = table.contentOffset.y + table.adjustedContentInset.top;
	self.pillShown = visibleTop >= CGRectGetMaxY(self.headerPreview.frame);
	[self.navPreview.layer removeAllAnimations];
	self.navPreview.alpha = self.pillShown ? 1.0 : 0.0;
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self amlEnforcePillVisibility];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if ([keyPath isEqualToString:@"contentOffset"] && object == self.table) {
		[self amlUpdatePillVisibility];
		return;
	}
	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	CGFloat width = CGRectGetWidth(self.table.bounds);
	if (self.headerPreview && width > 1.0) {
		CGRect target = CGRectMake(16.0, 186.0, width - 32.0, 112.0);
		if (!CGRectEqualToRect(self.headerPreview.frame, target)) self.headerPreview.frame = target;
	}
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
	if (!self.observingScroll && self.table) {
		[self.table addObserver:self forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:NULL];
		self.observingScroll = YES;
	}
	[self amlUpdatePillVisibility];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self stopPreviewAnimation];
	if (self.observingScroll) {
		[self.table removeObserver:self forKeyPath:@"contentOffset"];
		self.observingScroll = NO;
	}
}

- (void)dealloc {
	if (self.observingScroll) {
		@try { [self.table removeObserver:self forKeyPath:@"contentOffset"]; } @catch (__unused NSException *e) {}
	}
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	[super traitCollectionDidChange:previousTraitCollection];
	[self amlUpdateHeaderArtwork];
}

- (void)reloadSettings {
    _specifiers = nil;
    [self reloadSpecifiers];
    [self amlRefreshMainPreview];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if ([key isEqualToString:@"AODEnabled"] || [key isEqualToString:@"AODRefreshRetry"])
        return @(DateLyricsBoolPreference(key, nil));
    return [super readPreferenceValue:specifier];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	[super setPreferenceValue:value specifier:specifier];

	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
	[haptic impactOccurred];

	NSString *key = [specifier propertyForKey:@"key"];
	if ([key isEqualToString:@"Enabled"]) {
		UIImage *respringImage = [UIImage systemImageNamed:@"arrow.clockwise"];
		UIBarButtonItem *respringButton = [[UIBarButtonItem alloc] initWithImage:respringImage style:UIBarButtonItemStylePlain target:self action:@selector(respring)];
		respringButton.tintColor = [UIColor systemBlueColor];
		self.navigationItem.rightBarButtonItem = respringButton;
	}

	if ([key isEqualToString:@"SplitLongLines"]) {
		if ([value boolValue]) {
			NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kDateLyricsPrefsSuite];
			[prefs setBool:NO forKey:@"ShowAdlibs"];
			[prefs synchronize];
		}
	}

	if ([key isEqualToString:@"WordHighlighting"] ||
	        [key isEqualToString:@"UseCustomFont"] ||
	        [key isEqualToString:@"TransitionsEnabled"] ||
	        [key isEqualToString:@"MinimumScale"] ||
	        [key isEqualToString:@"SplitLongLines"] ||
	        [key isEqualToString:@"ShowAdlibs"] ||
            [key isEqualToString:@"MusixmatchEnabled"]) {

	        _specifiers = nil;
	        [self reloadSpecifiers];

	}
	[self amlRefreshMainPreviewWithKey:key value:value];
	if ([key isEqualToString:@"TransitionStyle"] || [key isEqualToString:@"TransitionDuration"] ||
	    [key isEqualToString:@"TransitionsEnabled"]) {
		[self amlPlayPreviewTransition];
	}
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
		if (![[NSFileManager defaultManager] isExecutableFileAtPath:command.firstObject]) continue;
		pid_t pid;
		size_t argc = command.count;
		char *argv[argc + 1];
		for (size_t i = 0; i < argc; i++) {
			argv[i] = (char *)command[i].UTF8String;
		}
		argv[argc] = NULL;
		if (posix_spawn(&pid, command.firstObject.UTF8String, NULL, NULL, argv, environ) == 0) {
			break;
		}
	}
}


- (void)openGithub {
	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
	[haptic impactOccurred];
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/shalamand3r/DateLyrics"] options:@{} completionHandler:nil];
}

- (void)fetchGithubLogo {
	if (_cachedGithubIcon) return;
	NSURL *url = [NSURL URLWithString:@"https://github.com/shalamand3r/shalamand3r.github.io/blob/main/CydiaIcon.png?raw=true"];
	__weak typeof(self) weakSelf = self;
	[[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		if (!data || error) return;

		// everything below touches uikit (uiscreen, uigraphics, calayer rendering)
		// and mutates the shared _cachedgithubicon static. all of it must run on the
		// main thread; this block is on a urlsession worker.
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf || _cachedGithubIcon) return;

			UIImage *image = [UIImage imageWithData:data];
			if (!image) return;

			CGRect bounds = CGRectMake(0, 0, 29, 29);
			UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:bounds];
			UIImage *squircleImage = [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *ctx) {
				UIBezierPath *clip = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:7.0];
				[clip addClip];
				[image drawInRect:bounds];
			}];
			if (!squircleImage) return;

			_cachedGithubIcon = squircleImage;

			PSSpecifier *githubSpecifier = [strongSelf specifierForID:@"GitHubCell"];
			if (!githubSpecifier) return;

			[githubSpecifier setProperty:squircleImage forKey:@"iconImage"];
			[strongSelf reloadSpecifier:githubSpecifier];

			NSIndexPath *indexPath = [strongSelf indexPathForSpecifier:githubSpecifier];
			if (indexPath) {
				UITableViewCell *cell = [strongSelf.table cellForRowAtIndexPath:indexPath];
				UIView *spinner = [cell.imageView viewWithTag:1234];
				if (spinner) {
					[spinner removeFromSuperview];
				}
			}
		});
	}] resume];
}

@end

@interface DateLyricsFontListController ()
@property (nonatomic, strong) DateLyricsPreviewView *previewView;
@property (nonatomic, strong) DateLyricsPreviewFeed *previewFeed;
@end

@implementation DateLyricsFontListController

- (NSString *)amlSelectedFontName {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kDateLyricsPrefsSuite];
	NSString *fontName = [prefs objectForKey:@"CustomFontName"];
	return [fontName isKindOfClass:NSString.class] && fontName.length > 0 ? fontName : @"AvenirNext-DemiBold";
}

/// the font page previews the font being chosen, whatever the main "custom font" switch says.
- (void)amlUpdatePreviewLabel {
	NSMutableDictionary *prefs = [DateLyricsCurrentPrefs() mutableCopy];
	prefs[@"UseCustomFont"] = @YES;
	prefs[@"CustomFontName"] = [self amlSelectedFontName];
	[self.previewView applySettings:prefs];
}

- (void)startPreviewAnimation {
	[self.previewFeed start];
	[self.previewView start];
}

- (void)stopPreviewAnimation {
	[self.previewFeed stop];
	[self.previewView stop];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.rowHeight = 44.0;

	// the same text-only preview as the main page, driven by the same feed.
	CGFloat width = MIN(250.0, [UIScreen mainScreen].bounds.size.width - 150.0);
	UIView *titleView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 44)];
	titleView.backgroundColor = [UIColor clearColor];
	self.previewView = [[DateLyricsPreviewView alloc] initWithFrame:CGRectMake(0, 5, width, 34) card:NO];
	self.previewView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[titleView addSubview:self.previewView];
	self.navigationItem.titleView = titleView;

	self.previewFeed = [DateLyricsPreviewFeed new];
	self.previewFeed.placeholderLines = DateLyricsSharedPreviewData();
	[self.previewFeed addView:self.previewView];
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
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	cell.textLabel.numberOfLines = 1;
	cell.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	cell.detailTextLabel.text = nil;

	return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 44.0;
}

@end

static dispatch_queue_t DateLyricsCacheMaintenanceQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.shalamand3r.datelyrics.cache-maintenance", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

static unsigned long long DateLyricsTotalLyricsCacheSize(void) {
    unsigned long long total = 0;
    for (NSString *root in DateLyricsStorageCacheRoots(NSClassFromString(@"LSApplicationProxy")))
        total += DateLyricsGetPathSize(root, NSFileManager.defaultManager);
    return total;
}

static NSString *DateLyricsFormattedCacheSize(unsigned long long bytes) {
    if (bytes == 0) return @"0 KB";
    if (bytes < 1024) return @"1 KB";
    return [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile];
}

static void DateLyricsApplyRedColorToView(UIView *view) {
    if (!view) return;
    view.tintColor = UIColor.systemRedColor;
    if ([view isKindOfClass:UILabel.class]) {
        ((UILabel *)view).textColor = UIColor.systemRedColor;
    } else if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        button.tintColor = UIColor.systemRedColor;
        [button setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
        [button setTitleColor:UIColor.systemRedColor forState:UIControlStateHighlighted];
        [button setTitleColor:UIColor.systemRedColor forState:UIControlStateSelected];
    }
    for (UIView *sub in view.subviews) {
        DateLyricsApplyRedColorToView(sub);
    }
}

static void DateLyricsStyleDestructiveCell(UITableViewCell *cell, PSSpecifier *specifier) {
    if (!cell || ![[specifier propertyForKey:@"isDestructive"] boolValue]) return;
    cell.tintColor = UIColor.systemRedColor;
    cell.contentView.tintColor = UIColor.systemRedColor;
    cell.textLabel.textColor = UIColor.systemRedColor;
    if ([cell isKindOfClass:PSTableCell.class])
        ((PSTableCell *)cell).titleLabel.textColor = UIColor.systemRedColor;
    DateLyricsApplyRedColorToView(cell);
}

@implementation DateLyricsExperimentalListController
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if ([key isEqualToString:@"AODEnabled"] || [key isEqualToString:@"AODRefreshRetry"])
        return @(DateLyricsBoolPreference(key, nil));
    return [super readPreferenceValue:specifier];
}

- (NSArray *)specifiers {
    self.diagnosticsVisible = CFPreferencesGetAppBooleanValue(CFSTR("DiagnosticsVisible"), CFSTR("com.shalamand3r.datelyrics"), NULL);
	if (!_specifiers) {
        NSArray *loaded = [self loadSpecifiersFromPlistName:@"Experimental" target:self];
        NSMutableArray *specs = [NSMutableArray array];
        for (PSSpecifier *spec in loaded) {
            if ([[spec propertyForKey:@"DateLyricsInternalDiagnostics"] boolValue] && !self.diagnosticsVisible) continue;
            [specs addObject:spec];
        }
        BOOL supportsAOD = DateLyricsBoolPreference(@"AODEnabled", nil);

        for (PSSpecifier *spec in specs) {
            if ([[spec propertyForKey:@"key"] isEqualToString:@"AODRefreshRetry"])
                [spec setProperty:@(supportsAOD) forKey:@"enabled"];
            if ([[spec propertyForKey:@"id"] isEqualToString:@"WipeSavedLyrics"] ||
                [[spec propertyForKey:@"action"] isEqualToString:@"wipeSavedLyrics"]) {
                spec.name = @"Wipe Lyrics Cache";
            }
        }
        _specifiers = [specs mutableCopy];
	}
	return _specifiers;
}

- (void)updateWipeCacheSpecifier {
    NSUInteger request = ++self.cacheSizeRequest;
    __weak typeof(self) weakSelf = self;
    dispatch_async(DateLyricsCacheMaintenanceQueue(), ^{
        unsigned long long size = DateLyricsTotalLyricsCacheSize();
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) controller = weakSelf;
            if (!controller || request != controller.cacheSizeRequest) return;
            PSSpecifier *spec = [controller specifierForID:@"WipeSavedLyrics"];
            if (!spec) return;
            NSString *title = [NSString stringWithFormat:@"Wipe Lyrics Cache (%@)", DateLyricsFormattedCacheSize(size)];
            spec.name = title;
            [spec setProperty:title forKey:@"label"];
            [controller reloadSpecifier:spec animated:NO];

            PSTableCell *cached = [controller cachedCellForSpecifier:spec];
            DateLyricsStyleDestructiveCell(cached, spec);
            NSIndexPath *indexPath = [controller indexPathForSpecifier:spec];
            if (indexPath) {
                DateLyricsStyleDestructiveCell([controller.table cellForRowAtIndexPath:indexPath], spec);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                DateLyricsStyleDestructiveCell([controller cachedCellForSpecifier:spec], spec);
                NSIndexPath *ip = [controller indexPathForSpecifier:spec];
                if (ip) {
                    DateLyricsStyleDestructiveCell([controller.table cellForRowAtIndexPath:ip], spec);
                }
            });
        });
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _specifiers = nil;
    [self reloadSpecifiers];
    [self updateWipeCacheSpecifier];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIColor *tintColor = [UIColor colorWithRed:255/255.0 green:127/255.0 blue:189/255.0 alpha:1.0];
    [UISwitch appearanceWhenContainedInInstancesOfClasses:@[[self class]]].onTintColor = tintColor;
    self.view.tintColor = tintColor;
    UILabel *title = [UILabel new];
    title.text = @"Experimental";
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    title.textColor = UIColor.labelColor;
    title.userInteractionEnabled = YES;
    [title sizeToFit];
    UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(toggleDiagnostics:)];
    gesture.minimumPressDuration = 1.0;
    [title addGestureRecognizer:gesture];
    self.navigationItem.titleView = title;
}

- (void)toggleDiagnostics:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    self.diagnosticsVisible = !self.diagnosticsVisible;
    CFPreferencesSetAppValue(CFSTR("DiagnosticsVisible"), self.diagnosticsVisible ? kCFBooleanTrue : kCFBooleanFalse, CFSTR("com.shalamand3r.datelyrics"));
    CFPreferencesAppSynchronize(CFSTR("com.shalamand3r.datelyrics"));
    _specifiers = nil;
    [self reloadSpecifiers];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    DateLyricsStyleDestructiveCell(cell, specifier);
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    DateLyricsStyleDestructiveCell(cell, specifier);
}

- (void)showDebugLog {
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    NSString *logText = DateLyricsCombinedDebugLogText();
    DateLyricsLogViewController *controller = [DateLyricsLogViewController new];
    controller.logText = DateLyricsRecentLogText(logText);
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)copyDebugLog {
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    NSString *logText = DateLyricsRecentLogText(DateLyricsCombinedDebugLogText());
    NSString *title = @"No Debug Log";
    if (logText.length > 0) {
        UIPasteboard.generalPasteboard.string = logText;
        title = @"Debug Log Copied";
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                     message:nil
                                                               preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)clearDebugLog {
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    DateLyricsClearDebugLogs();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Debug Log Cleared"
                                                                     message:nil
                                                               preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

static void DateLyricsWipeLyricsCaches(void) {
    for (NSString *root in DateLyricsStorageCacheRoots(NSClassFromString(@"LSApplicationProxy"))) {
        DateLyricsRemoveCachedLyrics(root, NSFileManager.defaultManager);
        DateLyricsRemoveCachedLyrics([root stringByAppendingPathComponent:@"External"], NSFileManager.defaultManager);
    }

    // music may be closed when the notification is posted; clear on its next launch too.
    NSNumber *generation = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(
        CFSTR("CacheGeneration"), (__bridge CFStringRef)kDateLyricsPrefsSuite);
    NSUInteger nextGeneration = [generation isKindOfClass:NSNumber.class] ? generation.unsignedIntegerValue + 1 : 1;
    CFPreferencesSetAppValue(CFSTR("CacheGeneration"), (__bridge CFNumberRef)@(nextGeneration),
        (__bridge CFStringRef)kDateLyricsPrefsSuite);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDateLyricsPrefsSuite);

    // each injected host owns its cache and cancels in-flight writes when it
    // handles clearcaches. preferences.app cannot access those containers.
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.shalamand3r.datelyrics/ClearCaches"), NULL, NULL, YES);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.shalamand3r.datelyrics/ReloadPrefs"), NULL, NULL, YES);
}

static void DateLyricsPerformWipeSavedLyrics(UIViewController *presenter) {
    static BOOL inProgress = NO;
    if (inProgress) return;
    inProgress = YES;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy] impactOccurred];

    dispatch_async(DateLyricsCacheMaintenanceQueue(), ^{
        DateLyricsWipeLyricsCaches();
        dispatch_async(dispatch_get_main_queue(), ^{
            inProgress = NO;
            if ([presenter respondsToSelector:@selector(updateWipeCacheSpecifier)]) {
                [(DateLyricsExperimentalListController *)presenter updateWipeCacheSpecifier];
                __weak UIViewController *weakPresenter = presenter;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    [(DateLyricsExperimentalListController *)weakPresenter updateWipeCacheSpecifier];
                });
            }

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Cache Reset Requested"
                message:@"Resume playback in your music app to fetch fresh lyrics."
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [presenter presentViewController:alert animated:YES completion:nil];
        });
    });
}

- (void)resetSettings {
	if (self.resetInProgress) return;
	self.resetInProgress = YES;

	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
	[haptic impactOccurred];

    DateLyricsResetPreferenceValues();

    _specifiers = nil;
    [self reloadSpecifiers];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.shalamand3r.datelyrics/ReloadPrefs"), NULL, NULL, YES);
    for (UIViewController *controller in self.navigationController.viewControllers) {
        if ([controller isKindOfClass:DateLyricsRootListController.class]) {
            [(DateLyricsRootListController *)controller reloadSettings];
        }
    }
	self.resetInProgress = NO;
}

- (void)wipeSavedLyrics {
    DateLyricsPerformWipeSavedLyrics(self);
}
@end

@implementation DateLyricsProviderOrderController

- (NSArray *)specifiers {
    if (!_specifiers) {
        id saved = (__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("LyricsProviderOrder"), CFSTR("com.shalamand3r.datelyrics"));
        self.providerKeys = [DateLyricsSanitizedProviderOrder(saved) mutableCopy];
        NSMutableArray *specs = [[self loadSpecifiersFromPlistName:@"Services" target:self] mutableCopy];
        NSUInteger index = 1;
        for (NSString *key in self.providerKeys) {
            PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:DateLyricsProviderDefinition(key)[@"name"]
                target:self set:NULL get:NULL detail:Nil cell:PSTitleValueCell edit:Nil];
            specifier.identifier = key;
            [specs insertObject:specifier atIndex:index++];
        }
        _specifiers = specs;
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Lyric Services";
    UIColor *pink = [UIColor colorWithRed:255/255.0 green:127/255.0 blue:189/255.0 alpha:1.0];
    self.view.tintColor = pink;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.table setEditing:YES animated:NO];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    id value = [super readPreferenceValue:specifier];
    if ([[specifier propertyForKey:@"key"] isEqual:@"LyricsRequestTimeout"]) {
        return @(DateLyricsSanitizedRequestTimeout(value));
    }
    return value;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if ([key isEqual:@"LyricsRequestTimeout"]) {
        value = @(DateLyricsSanitizedRequestTimeout(value));
    } else if ([key isEqual:@"MusixmatchUserToken"] && [value isKindOfClass:NSString.class]) {
        value = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    [super setPreferenceValue:value specifier:specifier];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    return proposedDestinationIndexPath.section == 0 ? proposedDestinationIndexPath
        : [NSIndexPath indexPathForRow:self.providerKeys.count - 1 inSection:0];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (sourceIndexPath.section != 0 || destinationIndexPath.section != 0) return;
    if (sourceIndexPath.row == destinationIndexPath.row) return;

    NSString *movedKey = self.providerKeys[sourceIndexPath.row];
    [self.providerKeys removeObjectAtIndex:sourceIndexPath.row];
    [self.providerKeys insertObject:movedKey atIndex:destinationIndexPath.row];

    // keep preferences' specifier order in step with the table's row move.
    NSMutableArray *specs = self.specifiers;
    PSSpecifier *movedSpecifier = specs[sourceIndexPath.row + 1];
    [specs removeObjectAtIndex:sourceIndexPath.row + 1];
    [specs insertObject:movedSpecifier atIndex:destinationIndexPath.row + 1];

    CFPreferencesSetAppValue(CFSTR("LyricsProviderOrder"), (__bridge CFArrayRef)self.providerKeys, CFSTR("com.shalamand3r.datelyrics"));
    CFPreferencesAppSynchronize(CFSTR("com.shalamand3r.datelyrics"));

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (CFStringRef)@"com.shalamand3r.datelyrics/ReloadPrefs", NULL, NULL, YES);

    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return 60.0;
    return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        static NSString *cellId = @"DateLyricsProviderReorderCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
        if (!cell) {
            cell = [[PSTableCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId specifier:[self specifierAtIndexPath:indexPath]];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        ((PSTableCell *)cell).specifier = [self specifierAtIndexPath:indexPath];

        NSString *key = self.providerKeys[indexPath.row];
        NSDictionary *definition = DateLyricsProviderDefinition(key);
        cell.textLabel.text = definition[@"name"];
        cell.detailTextLabel.text = definition[@"detail"];
        cell.imageView.image = [UIImage systemImageNamed:definition[@"symbol"]];

        cell.imageView.tintColor = [UIColor colorWithRed:255/255.0 green:127/255.0 blue:189/255.0 alpha:1.0];
        cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.showsReorderControl = YES;

        return cell;
    }

    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    cell.showsReorderControl = NO;
    cell.tintColor = self.view.tintColor;
    if ([cell isKindOfClass:PSControlTableCell.class]) {
        UIControl *control = ((PSControlTableCell *)cell).control;
        control.tintColor = self.view.tintColor;
        if ([control isKindOfClass:UISlider.class]) ((UISlider *)control).minimumTrackTintColor = self.view.tintColor;
    }
    return cell;
}

@end
