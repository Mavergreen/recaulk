/* -[NSWorkspace isVoiceOverEnabled] (10.13), from the state VoiceOver itself records. CoreFoundation only. */
#import "workspace-private.h"

/* platform: VoiceOver records whether it is on in universal access's voiceOverOnOffKey; measured on
   10.9.5, the key is set as VoiceOver starts and cleared as it stops (before its process exits), and is
   not set while its welcome dialog is up or when that dialog is cancelled. */
__attribute__((visibility("hidden")))
BOOL __recaulk_objc_voiceover_enabled_in(CFStringRef domain) {
    CFPreferencesAppSynchronize(domain);
    return CFPreferencesGetAppBooleanValue(CFSTR("voiceOverOnOffKey"), domain, NULL) ? YES : NO;
}

BOOL __recaulk_objc_workspace_is_voiceover_enabled(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    return __recaulk_objc_voiceover_enabled_in(CFSTR("com.apple.universalaccess"));
}
