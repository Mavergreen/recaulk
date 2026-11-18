/* -[NSLocale languageCode] and -countryCode (10.12): the same answers 10.9 gives through objectForKey:. */
#import "foundation-private.h"
NSString *__recaulk_objc_locale_language_code(id self, SEL _cmd) {
    (void)_cmd;
    /* platform: 10.9 has no language for a locale such as "" or "_US"; Apple declares languageCode nonnull. */
    NSString *code=[self objectForKey:NSLocaleLanguageCode];
    return code ? [[code retain] autorelease] : @"";
}
NSString *__recaulk_objc_locale_country_code(id self, SEL _cmd) {
    (void)_cmd;
    return [[[self objectForKey:NSLocaleCountryCode] retain] autorelease];
}
