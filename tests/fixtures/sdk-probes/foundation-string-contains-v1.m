#import <Foundation/Foundation.h>
BOOL probe(NSString *s) { return [s containsString:@"a"] || [s localizedCaseInsensitiveContainsString:@"B"]; }
