/* No messages, framework loading or dynamic method resolution here.
 * Foundation must already be strongly linked; it is the only framework this root needs. */
#import "foundation-private.h"
#import "register-common.h"
#include "providers-generated.h"
void __recaulk_objc_activate_foundation(void) {
    Class locale=objc_getClass(RECAULK_LOCALE_LANGUAGE_CODE_CLASS);
    __recaulk_objc_add_method(locale,sel_registerName(RECAULK_LOCALE_LANGUAGE_CODE_SELECTOR),(IMP)__recaulk_objc_locale_language_code,RECAULK_LOCALE_LANGUAGE_CODE_ENCODING);
    __recaulk_objc_add_method(locale,sel_registerName(RECAULK_LOCALE_COUNTRY_CODE_SELECTOR),(IMP)__recaulk_objc_locale_country_code,RECAULK_LOCALE_COUNTRY_CODE_ENCODING);
    Class string=objc_getClass(RECAULK_STRING_CONTAINS_CLASS);
    __recaulk_objc_add_method(string,sel_registerName(RECAULK_STRING_CONTAINS_SELECTOR),(IMP)__recaulk_objc_string_contains_string,RECAULK_STRING_CONTAINS_ENCODING);
    __recaulk_objc_add_method(string,sel_registerName(RECAULK_STRING_CONTAINS_CI_SELECTOR),(IMP)__recaulk_objc_string_localized_case_insensitive_contains_string,RECAULK_STRING_CONTAINS_CI_ENCODING);
}
__attribute__((constructor)) static void activateAtLoad(void) { __recaulk_objc_activate_foundation(); }
