#import <Foundation/Foundation.h>
NSFileAttributeType probe(NSDictionary *attributes) {
    NSFileAttributeKey key = NSFileType;
    return [attributes objectForKey:key];
}
