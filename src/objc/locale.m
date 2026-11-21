/* -[NSLocale languageCode] and -countryCode (10.12): the same answers 10.9 gives through objectForKey:. self is typed
   NSLocale *, so a consumer's strict guard can close the send (tests/objc-source-receipt.sh). */
#import "foundation-private.h"
NSString *__recaulk_objc_locale_language_code(NSLocale *self, SEL _cmd) {
    (void)_cmd;
    /* platform: 10.9 has no language for a locale such as "" or "_US"; Apple declares languageCode nonnull. */
    NSString *code=[self objectForKey:NSLocaleLanguageCode];
    return code ? [[code retain] autorelease] : @"";
}
NSString *__recaulk_objc_locale_country_code(NSLocale *self, SEL _cmd) {
    (void)_cmd;
    NSString *code=[self objectForKey:NSLocaleCountryCode];
    return [[code retain] autorelease];
}
