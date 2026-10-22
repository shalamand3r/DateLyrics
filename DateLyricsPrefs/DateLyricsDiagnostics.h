#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSString *DateLyricsCombinedDebugLogText(void);
FOUNDATION_EXPORT NSString *DateLyricsRecentLogText(NSString *text);
FOUNDATION_EXPORT void DateLyricsClearDebugLogs(void);

@interface DateLyricsLogViewController : UIViewController
@property (nonatomic, copy) NSString *logText;
@end
