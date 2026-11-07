#import <Foundation/Foundation.h>
NSString *probe(NSArray<NSString *> *a, NSMutableArray<NSString *> *m) {
    return a.lastObject.uppercaseString ?: a.firstObject.lowercaseString ?: [a objectAtIndex:0].capitalizedString ?: a[0].description ?: m[0].description;
}
