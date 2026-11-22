#import <Foundation/Foundation.h>
NSFileCoordinatorReadingOptions probe(void) {
    if (@available(macOS 10.10, *)) return NSFileCoordinatorReadingForUploading | NSFileCoordinatorReadingImmediatelyAvailableMetadataOnly;
    return NSFileCoordinatorReadingWithoutChanges;
}
