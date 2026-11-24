#ifndef RECAULK_FOUNDATION_PRIVATE_H
#define RECAULK_FOUNDATION_PRIVATE_H
#import <Foundation/Foundation.h>
NSString *__recaulk_objc_locale_language_code(NSLocale *, SEL);
NSString *__recaulk_objc_locale_country_code(NSLocale *, SEL);
BOOL __recaulk_objc_string_contains_string(NSString *, SEL, NSString *);
BOOL __recaulk_objc_string_localized_case_insensitive_contains_string(NSString *, SEL, NSString *);
void __recaulk_objc_activate_foundation(void);
NSTimer *__recaulk_objc_timer_with_interval_block(Class, SEL, NSTimeInterval, BOOL, void (^)(NSTimer *));
NSTimer *__recaulk_objc_timer_scheduled_with_interval_block(Class, SEL, NSTimeInterval, BOOL, void (^)(NSTimer *));
void __recaulk_objc_activate_timer(void);
#endif
