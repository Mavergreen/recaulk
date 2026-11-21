#ifndef RECAULK_FOUNDATION_PRIVATE_H
#define RECAULK_FOUNDATION_PRIVATE_H
#import <Foundation/Foundation.h>
NSString *__recaulk_objc_locale_language_code(NSLocale *, SEL);
NSString *__recaulk_objc_locale_country_code(NSLocale *, SEL);
void __recaulk_objc_activate_foundation(void);
#endif
