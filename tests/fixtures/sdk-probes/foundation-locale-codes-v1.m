#import <Foundation/Foundation.h>
NSString *probe(NSLocale *l) { return l.countryCode ?: l.languageCode; }
