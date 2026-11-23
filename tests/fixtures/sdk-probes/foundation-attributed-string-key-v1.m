#import <Foundation/Foundation.h>
id probe(NSAttributedString *s, NSAttributedStringKey key) { return [s attribute:key atIndex:0 effectiveRange:NULL]; }
