#import <Foundation/Foundation.h>
BOOL probe(NSURL *u) { return u.fileURL && [u isFileURL]; }
