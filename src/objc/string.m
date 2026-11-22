/* -[NSString containsString:] and -localizedCaseInsensitiveContainsString: (10.10): what 10.10 answers, through
   rangeOfString:, which 10.9 has. self is typed NSString *, so a consumer's strict guard can close each send. */
#import "foundation-private.h"
BOOL __recaulk_objc_string_contains_string(NSString *self, SEL _cmd, NSString *str) {
    (void)_cmd;
    return [self rangeOfString:str].location != NSNotFound;
}
BOOL __recaulk_objc_string_localized_case_insensitive_contains_string(NSString *self, SEL _cmd, NSString *str) {
    (void)_cmd;
    return [self rangeOfString:str options:NSCaseInsensitiveSearch range:NSMakeRange(0, [self length])
                        locale:[NSLocale currentLocale]].location != NSNotFound;
}
