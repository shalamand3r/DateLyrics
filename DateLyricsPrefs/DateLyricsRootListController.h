#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSListItemsController.h>
#import <Preferences/PSViewController.h>

@interface DateLyricsRootListController : PSListController
- (void)reloadSettings;
@end

@interface DateLyricsExperimentalListController : PSListController
@property (nonatomic) BOOL diagnosticsVisible;
@property (nonatomic) BOOL resetInProgress;
@property (nonatomic) NSUInteger cacheSizeRequest;
- (void)updateWipeCacheSpecifier;
@end

@interface DateLyricsFontListController : PSListItemsController
@end

@interface DateLyricsProviderOrderController : PSListController
@property (nonatomic, strong) NSMutableArray<NSString *> *providerKeys;
@end
