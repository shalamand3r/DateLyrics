#import <Foundation/Foundation.h>
#include <grp.h>
#include <unistd.h>

static BOOL DateLyricsResetDiagnosticPreferences(CFStringRef domain) {
    CFPreferencesSetAppValue(CFSTR("DebugLogging"), kCFBooleanFalse, domain);
    CFPreferencesSetAppValue(CFSTR("NativeTransitionProbe"), kCFBooleanFalse, domain);
    return CFPreferencesAppSynchronize(domain);
}

int main(void) {
    // use mobile's preference service; root has a separate preference domain.
    if (geteuid() == 0 && (initgroups("mobile", 501) != 0 || setgid(501) != 0 || setuid(501) != 0)) return 1;
    if (geteuid() != 501) return 1;
    @autoreleasepool {
        return DateLyricsResetDiagnosticPreferences(CFSTR("com.shalamand3r.datelyrics")) ? 0 : 1;
    }
}
