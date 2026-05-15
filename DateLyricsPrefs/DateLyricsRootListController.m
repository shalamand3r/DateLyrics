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

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSURL *dataContainerURL;
+ (id)applicationProxyForIdentifier:(id)arg1;
@end

@interface DateLyricsRootListController ()
@property (nonatomic, strong) UIImageView *headerImageView;
@end

@interface DateLyricsFontListController ()
@property (nonatomic, strong) UILabel *previewLabel;
@end

@implementation DateLyricsRootListController

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *specs = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
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
				[spec setProperty:@"titlesDataSource" forKey:@"titlesDataSource"];
				[spec setProperty:@"valuesDataSource" forKey:@"valuesDataSource"];
			}
		}

		_specifiers = [specs copy];
	}
	return _specifiers;
}

- (NSArray *)titlesDataSource {
	return DateLyricsFontTitles();
}

- (NSArray *)valuesDataSource {
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
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	[super traitCollectionDidChange:previousTraitCollection];
	[self amlUpdateHeaderArtwork];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	[super setPreferenceValue:value specifier:specifier];

	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
	[haptic impactOccurred];
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

@implementation DateLyricsFontListController

- (NSString *)amlSelectedFontName {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kDateLyricsPrefsSuite];
	NSString *fontName = [prefs objectForKey:@"CustomFontName"];
	return [fontName isKindOfClass:NSString.class] && fontName.length > 0 ? fontName : @"AvenirNext-DemiBold";
}

- (void)amlUpdatePreviewLabel {
	NSString *fontName = [self amlSelectedFontName];
	UIFont *previewFont = [UIFont fontWithName:fontName size:28.0] ?: [UIFont boldSystemFontOfSize:28.0];
	self.previewLabel.font = previewFont;
	self.previewLabel.text = @"I'm working late, cause I'm a singer";
	self.previewLabel.textColor = [UIColor labelColor];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Font Style";
	self.table.rowHeight = 44.0;

	UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.table.bounds.size.width, 108)];
	headerView.backgroundColor = [UIColor clearColor];

	UIView *previewCard = [[UIView alloc] initWithFrame:CGRectInset(headerView.bounds, 16.0, 10.0)];
	previewCard.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	previewCard.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
	previewCard.layer.cornerRadius = 12.0;
	previewCard.layer.masksToBounds = YES;
	[headerView addSubview:previewCard];

	UILabel *previewLabel = [[UILabel alloc] initWithFrame:CGRectInset(previewCard.bounds, 16.0, 14.0)];
	previewLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	previewLabel.textAlignment = NSTextAlignmentCenter;
	previewLabel.numberOfLines = 2;
	previewLabel.adjustsFontSizeToFitWidth = YES;
	previewLabel.minimumScaleFactor = 0.5;
	previewLabel.lineBreakMode = NSLineBreakByWordWrapping;
	[previewCard addSubview:previewLabel];
	self.previewLabel = previewLabel;
	self.table.tableHeaderView = headerView;
	[self amlUpdatePreviewLabel];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	UIView *headerView = self.table.tableHeaderView;
	if (!headerView) return;
	CGRect frame = headerView.frame;
	CGFloat width = CGRectGetWidth(self.table.bounds);
	if (fabs(frame.size.width - width) > 0.5) {
		frame.size.width = width;
		headerView.frame = frame;
		self.table.tableHeaderView = headerView;
	}
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self amlUpdatePreviewLabel];
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
