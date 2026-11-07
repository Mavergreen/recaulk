#import <Cocoa/Cocoa.h>
void probe(NSTextField *t) {
    t.editable = t.bordered; t.bordered = t.selectable; t.selectable = t.editable;
    if ([t respondsToSelector:@selector(setPlaceholderString:)]) { t.placeholderString = @"x"; }
}
