// needs: foundation-enumerator-generics-v1
#import <Foundation/Foundation.h>
NSFileAttributeType probe(NSDictionary *attributes) {
    NSFileAttributeKey key = NSFileType;
    return [attributes objectForKey:key];
}
void probeEnumerator(NSDirectoryEnumerator<NSString *> *e);
