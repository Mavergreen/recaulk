#import <Foundation/Foundation.h>
id probe(NSDictionary *change) {
    NSKeyValueChangeKey key = NSKeyValueChangeNewKey;
    return [change objectForKey:key];
}
