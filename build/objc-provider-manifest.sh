#!/bin/sh
# platform: host-agnostic
#   usage: objc-provider-manifest.sh header DECL OUT
#          objc-provider-manifest.sh manifest DECL ARCHIVE OUT ARCH ROLE SDK_SETTINGS COMPILER_RECEIPT SOURCE_RECEIPT
#          checks DECL against the providers Recaulk ships and against the encoding clang22 compiles for each
#          one's declaration, then writes the generated header or the provider manifest. Needs CC, TARGET_FLAGS, SDK and
#          LIPO in the environment (build/lib.sh recaulk_tools).
set -eu
die() { echo "objc-provider-manifest: $*" >&2; exit 1; }
[ "$#" -ge 3 ] || { sed -n 3,7p "$0" >&2; exit 2; }
mode=$1 decl=$2
: "${CC:?}" "${TARGET_FLAGS:?}" "${SDK:?}"

# spec: README.md "Objective-C methods" -- each provider Recaulk ships, one per line, tab-separated:
#       macro id class kind selector encoding implementation root frameworks(comma-separated)
providers() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    WORKSPACE recaulk.nsworkspace.open-urls.v1 NSWorkspace - \
    'openURLs:withApplicationAtURL:options:configuration:error:' '@56@0:8@16@24Q32@40^@48' \
    __recaulk_objc_workspace_open_urls __recaulk_objc_activate AppKit,Carbon \
    WORKSPACE_VOICEOVER recaulk.nsworkspace.is-voiceover-enabled.v1 NSWorkspace - isVoiceOverEnabled 'c16@0:8' \
    __recaulk_objc_workspace_is_voiceover_enabled __recaulk_objc_activate AppKit,Carbon \
    WORKSPACE_REDUCE_MOTION recaulk.nsworkspace.should-reduce-motion.v1 NSWorkspace - \
    accessibilityDisplayShouldReduceMotion 'c16@0:8' \
    __recaulk_objc_workspace_should_reduce_motion __recaulk_objc_activate AppKit,Carbon \
    TABLECOLUMN_TITLE recaulk.nstablecolumn.title.v1 NSTableColumn - title '@16@0:8' \
    __recaulk_objc_tablecolumn_title __recaulk_objc_activate AppKit,Carbon \
    TABLECOLUMN_SET_TITLE recaulk.nstablecolumn.set-title.v1 NSTableColumn - setTitle: \
    'v24@0:8@16' __recaulk_objc_tablecolumn_set_title __recaulk_objc_activate AppKit,Carbon \
    CONTROL_SINGLE_LINE recaulk.nscontrol.uses-single-line-mode.v1 NSControl - usesSingleLineMode 'c16@0:8' \
    __recaulk_objc_control_uses_single_line_mode __recaulk_objc_activate AppKit,Carbon \
    CONTROL_SET_SINGLE_LINE recaulk.nscontrol.set-uses-single-line-mode.v1 NSControl - setUsesSingleLineMode: \
    'v20@0:8c16' __recaulk_objc_control_set_uses_single_line_mode __recaulk_objc_activate AppKit,Carbon \
    WINDOW_TITLEBAR_TRANSPARENT recaulk.nswindow.titlebar-appears-transparent.v1 NSWindow - titlebarAppearsTransparent \
    'c16@0:8' __recaulk_objc_window_titlebar_appears_transparent __recaulk_objc_activate AppKit,Carbon \
    WINDOW_SET_TITLEBAR_TRANSPARENT recaulk.nswindow.set-titlebar-appears-transparent.v1 NSWindow - \
    setTitlebarAppearsTransparent: 'v20@0:8c16' __recaulk_objc_window_set_titlebar_appears_transparent \
    __recaulk_objc_activate AppKit,Carbon \
    LOCALE_LANGUAGE_CODE recaulk.nslocale.language-code.v1 NSLocale - languageCode '@16@0:8' \
    __recaulk_objc_locale_language_code __recaulk_objc_activate_foundation Foundation \
    LOCALE_COUNTRY_CODE recaulk.nslocale.country-code.v1 NSLocale - countryCode '@16@0:8' \
    __recaulk_objc_locale_country_code __recaulk_objc_activate_foundation Foundation \
    STRING_CONTAINS recaulk.nsstring.contains-string.v1 NSString - containsString: 'c24@0:8@16' \
    __recaulk_objc_string_contains_string __recaulk_objc_activate_foundation Foundation \
    STRING_CONTAINS_CI recaulk.nsstring.localized-case-insensitive-contains-string.v1 NSString - \
    localizedCaseInsensitiveContainsString: 'c24@0:8@16' \
    __recaulk_objc_string_localized_case_insensitive_contains_string __recaulk_objc_activate_foundation Foundation
}
# spec: README.md "Objective-C methods" -- each schema-2 group's members, in providers()'s columns: a group is the run
#       of rows sharing its id, with one class, one root and one framework list. Each group has a root of its own,
#       since Drydock credits a group only from a root that adds nothing but its members.
groups() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    TIMER_SCHEDULED_BLOCK recaulk.nstimer.block-timers.v1 NSTimer + 'scheduledTimerWithTimeInterval:repeats:block:' \
    '@36@0:8d16c24@?28' __recaulk_objc_timer_scheduled_with_interval_block __recaulk_objc_activate_timer Foundation \
    TIMER_BLOCK recaulk.nstimer.block-timers.v1 NSTimer + 'timerWithTimeInterval:repeats:block:' \
    '@36@0:8d16c24@?28' __recaulk_objc_timer_with_interval_block __recaulk_objc_activate_timer Foundation \
    COLOR_LABEL recaulk.nscolor.label-colors.v1 NSColor + labelColor '@16@0:8' \
    __recaulk_objc_color_label __recaulk_objc_activate_color AppKit \
    COLOR_LINK recaulk.nscolor.label-colors.v1 NSColor + linkColor '@16@0:8' \
    __recaulk_objc_color_link __recaulk_objc_activate_color AppKit \
    GRAPHICS_CONTEXT_CGCONTEXT recaulk.nsgraphicscontext.cgcontext.v1 NSGraphicsContext + \
    'graphicsContextWithCGContext:flipped:' '@28@0:8^{CGContext=}16c24' \
    __recaulk_objc_graphics_context_with_cgcontext __recaulk_objc_activate_graphics_context AppKit \
    VIEW_SET_AX_LABEL recaulk.nsview.accessibility.v1 NSView - setAccessibilityLabel: \
    'v24@0:8@16' __recaulk_objc_view_set_accessibility_label \
    __recaulk_objc_activate_view_accessibility AppKit \
    VIEW_AX_LABEL recaulk.nsview.accessibility.v1 NSView - accessibilityLabel \
    '@16@0:8' __recaulk_objc_view_accessibility_label \
    __recaulk_objc_activate_view_accessibility AppKit \
    VIEW_SET_AX_ROLE recaulk.nsview.accessibility.v1 NSView - setAccessibilityRole: \
    'v24@0:8@16' __recaulk_objc_view_set_accessibility_role \
    __recaulk_objc_activate_view_accessibility AppKit \
    VIEW_AX_ROLE recaulk.nsview.accessibility.v1 NSView - accessibilityRole \
    '@16@0:8' __recaulk_objc_view_accessibility_role \
    __recaulk_objc_activate_view_accessibility AppKit \
    VIEW_SET_AX_CHILDREN recaulk.nsview.accessibility.v1 NSView - setAccessibilityChildren: \
    'v24@0:8@16' __recaulk_objc_view_set_accessibility_children \
    __recaulk_objc_activate_view_accessibility AppKit \
    VIEW_AX_CHILDREN recaulk.nsview.accessibility.v1 NSView - accessibilityChildren \
    '@16@0:8' __recaulk_objc_view_accessibility_children \
    __recaulk_objc_activate_view_accessibility AppKit \
    VIEW_SET_AX_SELECTED_TEXT_RANGE recaulk.nsview.accessibility.v1 NSView - setAccessibilitySelectedTextRange: \
    'v32@0:8{_NSRange=QQ}16' __recaulk_objc_view_set_accessibility_selected_text_range \
    __recaulk_objc_activate_view_accessibility AppKit \
    VIEW_AX_SELECTED_TEXT_RANGE recaulk.nsview.accessibility.v1 NSView - accessibilitySelectedTextRange \
    '{_NSRange=QQ}16@0:8' __recaulk_objc_view_accessibility_selected_text_range \
    __recaulk_objc_activate_view_accessibility AppKit \
    VIEW_AX_FRAME recaulk.nsview.accessibility.v1 NSView - accessibilityFrame \
    '{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8' __recaulk_objc_view_accessibility_frame \
    __recaulk_objc_activate_view_accessibility AppKit \
    CELL_SET_AX_LABEL recaulk.nscell.accessibility.v1 NSCell - setAccessibilityLabel: \
    'v24@0:8@16' __recaulk_objc_cell_set_accessibility_label \
    __recaulk_objc_activate_cell_accessibility AppKit \
    CELL_AX_LABEL recaulk.nscell.accessibility.v1 NSCell - accessibilityLabel \
    '@16@0:8' __recaulk_objc_cell_accessibility_label \
    __recaulk_objc_activate_cell_accessibility AppKit \
    CELL_SET_AX_ROLE recaulk.nscell.accessibility.v1 NSCell - setAccessibilityRole: \
    'v24@0:8@16' __recaulk_objc_cell_set_accessibility_role \
    __recaulk_objc_activate_cell_accessibility AppKit \
    CELL_AX_ROLE recaulk.nscell.accessibility.v1 NSCell - accessibilityRole \
    '@16@0:8' __recaulk_objc_cell_accessibility_role \
    __recaulk_objc_activate_cell_accessibility AppKit \
    CELL_SET_AX_CHILDREN recaulk.nscell.accessibility.v1 NSCell - setAccessibilityChildren: \
    'v24@0:8@16' __recaulk_objc_cell_set_accessibility_children \
    __recaulk_objc_activate_cell_accessibility AppKit \
    CELL_AX_CHILDREN recaulk.nscell.accessibility.v1 NSCell - accessibilityChildren \
    '@16@0:8' __recaulk_objc_cell_accessibility_children \
    __recaulk_objc_activate_cell_accessibility AppKit \
    CELL_SET_AX_SELECTED_TEXT_RANGE recaulk.nscell.accessibility.v1 NSCell - setAccessibilitySelectedTextRange: \
    'v32@0:8{_NSRange=QQ}16' __recaulk_objc_cell_set_accessibility_selected_text_range \
    __recaulk_objc_activate_cell_accessibility AppKit \
    CELL_AX_SELECTED_TEXT_RANGE recaulk.nscell.accessibility.v1 NSCell - accessibilitySelectedTextRange \
    '{_NSRange=QQ}16@0:8' __recaulk_objc_cell_accessibility_selected_text_range \
    __recaulk_objc_activate_cell_accessibility AppKit \
    CELL_AX_FRAME recaulk.nscell.accessibility.v1 NSCell - accessibilityFrame \
    '{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8' __recaulk_objc_cell_accessibility_frame \
    __recaulk_objc_activate_cell_accessibility AppKit
}
# spec: README.md "Objective-C methods" -- each own-absent group (a bridge an app calls on a class of its own), one
#       row per member: id root class_table frameworks selector encoding(10.9's) implementation declaration. Every
#       member super-sends its own selector, so each has a super_fallbacks record. The declaration is what its encoding
#       probe compiles.
bridges() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    recaulk.accessibility.bridge.v1 recaulk_accessibility_bridge __recaulk_objc_axb_bridged AppKit \
    accessibilityAttributeNames '@16@0:8' __recaulk_objc_axb_attribute_names '- (NSArray *)accessibilityAttributeNames' \
    recaulk.accessibility.bridge.v1 recaulk_accessibility_bridge __recaulk_objc_axb_bridged AppKit \
    accessibilityAttributeValue: '@24@0:8@16' __recaulk_objc_axb_attribute_value \
    '- (id)accessibilityAttributeValue:(NSString *)attribute' \
    recaulk.accessibility.bridge.v1 recaulk_accessibility_bridge __recaulk_objc_axb_bridged AppKit \
    accessibilityIsAttributeSettable: 'c24@0:8@16' __recaulk_objc_axb_is_attribute_settable \
    '- (BOOL)accessibilityIsAttributeSettable:(NSString *)attribute' \
    recaulk.accessibility.bridge.v1 recaulk_accessibility_bridge __recaulk_objc_axb_bridged AppKit \
    accessibilitySetValue:forAttribute: 'v32@0:8@16@24' __recaulk_objc_axb_set_value \
    '- (void)accessibilitySetValue:(id)value forAttribute:(NSString *)attribute' \
    recaulk.accessibility.bridge.v1 recaulk_accessibility_bridge __recaulk_objc_axb_bridged AppKit \
    accessibilityParameterizedAttributeNames '@16@0:8' __recaulk_objc_axb_parameterized_names \
    '- (NSArray *)accessibilityParameterizedAttributeNames' \
    recaulk.accessibility.bridge.v1 recaulk_accessibility_bridge __recaulk_objc_axb_bridged AppKit \
    accessibilityAttributeValue:forParameter: '@32@0:8@16@24' __recaulk_objc_axb_parameterized_value \
    '- (id)accessibilityAttributeValue:(NSString *)attribute forParameter:(id)parameter' \
    recaulk.accessibility.bridge.v1 recaulk_accessibility_bridge __recaulk_objc_axb_bridged AppKit \
    accessibilityActionNames '@16@0:8' __recaulk_objc_axb_action_names '- (NSArray *)accessibilityActionNames' \
    recaulk.accessibility.bridge.v1 recaulk_accessibility_bridge __recaulk_objc_axb_bridged AppKit \
    accessibilityActionDescription: '@24@0:8@16' __recaulk_objc_axb_action_description \
    '- (NSString *)accessibilityActionDescription:(NSString *)action' \
    recaulk.accessibility.bridge.v1 recaulk_accessibility_bridge __recaulk_objc_axb_bridged AppKit \
    accessibilityPerformAction: 'v24@0:8@16' __recaulk_objc_axb_perform_action \
    '- (void)accessibilityPerformAction:(NSString *)action' \
    recaulk.accessibility.bridge.v1 recaulk_accessibility_bridge __recaulk_objc_axb_bridged AppKit \
    accessibilityIsIgnored 'c16@0:8' __recaulk_objc_axb_is_ignored '- (BOOL)accessibilityIsIgnored'
}
# spec: README.md "Objective-C methods" -- each provider's method declared, compiled to measure clang22's encoding for
#       it: a legacy provider by its id, a group's member by ID:SELECTOR
probe_source() {
  case "$1" in
    recaulk.nstimer.block-timers.v1:scheduledTimerWithTimeInterval:repeats:block:) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(NSTimer *timer))block;
@end
@implementation RecaulkProviderEncoding
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(NSTimer *timer))block { return nil; }
@end
EOF
    ;;
    recaulk.nstimer.block-timers.v1:timerWithTimeInterval:repeats:block:) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(NSTimer *timer))block;
@end
@implementation RecaulkProviderEncoding
+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(NSTimer *timer))block { return nil; }
@end
EOF
    ;;
    recaulk.nscolor.label-colors.v1:labelColor) cat <<'EOF'
#import <Foundation/Foundation.h>
@class NSColor;
@interface RecaulkProviderEncoding : NSObject
+ (NSColor *)labelColor;
@end
@implementation RecaulkProviderEncoding
+ (NSColor *)labelColor { return nil; }
@end
EOF
    ;;
    recaulk.nscolor.label-colors.v1:linkColor) cat <<'EOF'
#import <Foundation/Foundation.h>
@class NSColor;
@interface RecaulkProviderEncoding : NSObject
+ (NSColor *)linkColor;
@end
@implementation RecaulkProviderEncoding
+ (NSColor *)linkColor { return nil; }
@end
EOF
    ;;
    recaulk.nsgraphicscontext.cgcontext.v1:graphicsContextWithCGContext:flipped:) cat <<'EOF'
#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
@class NSGraphicsContext;
@interface RecaulkProviderEncoding : NSObject
+ (NSGraphicsContext *)graphicsContextWithCGContext:(CGContextRef)graphicsPort flipped:(BOOL)initialFlippedState;
@end
@implementation RecaulkProviderEncoding
+ (NSGraphicsContext *)graphicsContextWithCGContext:(CGContextRef)graphicsPort flipped:(BOOL)initialFlippedState { return nil; }
@end
EOF
    ;;
    recaulk.nsview.accessibility.v1:setAccessibilityLabel:) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (void)setAccessibilityLabel:(NSString *)label;
@end
@implementation RecaulkProviderEncoding
- (void)setAccessibilityLabel:(NSString *)label { (void)label; }
@end
EOF
    ;;
    recaulk.nsview.accessibility.v1:accessibilityLabel) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (NSString *)accessibilityLabel;
@end
@implementation RecaulkProviderEncoding
- (NSString *)accessibilityLabel { return nil; }
@end
EOF
    ;;
    recaulk.nsview.accessibility.v1:setAccessibilityRole:) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (void)setAccessibilityRole:(NSString *)role;
@end
@implementation RecaulkProviderEncoding
- (void)setAccessibilityRole:(NSString *)role { (void)role; }
@end
EOF
    ;;
    recaulk.nsview.accessibility.v1:accessibilityRole) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (NSString *)accessibilityRole;
@end
@implementation RecaulkProviderEncoding
- (NSString *)accessibilityRole { return nil; }
@end
EOF
    ;;
    recaulk.nsview.accessibility.v1:setAccessibilityChildren:) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (void)setAccessibilityChildren:(NSArray *)children;
@end
@implementation RecaulkProviderEncoding
- (void)setAccessibilityChildren:(NSArray *)children { (void)children; }
@end
EOF
    ;;
    recaulk.nsview.accessibility.v1:accessibilityChildren) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (NSArray *)accessibilityChildren;
@end
@implementation RecaulkProviderEncoding
- (NSArray *)accessibilityChildren { return nil; }
@end
EOF
    ;;
    recaulk.nsview.accessibility.v1:setAccessibilitySelectedTextRange:) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (void)setAccessibilitySelectedTextRange:(NSRange)range;
@end
@implementation RecaulkProviderEncoding
- (void)setAccessibilitySelectedTextRange:(NSRange)range { (void)range; }
@end
EOF
    ;;
    recaulk.nsview.accessibility.v1:accessibilitySelectedTextRange) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (NSRange)accessibilitySelectedTextRange;
@end
@implementation RecaulkProviderEncoding
- (NSRange)accessibilitySelectedTextRange { return NSMakeRange(NSNotFound, 0); }
@end
EOF
    ;;
    recaulk.nsview.accessibility.v1:accessibilityFrame) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (NSRect)accessibilityFrame;
@end
@implementation RecaulkProviderEncoding
- (NSRect)accessibilityFrame { return NSZeroRect; }
@end
EOF
    ;;
    recaulk.nscell.accessibility.v1:setAccessibilityLabel:) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (void)setAccessibilityLabel:(NSString *)label;
@end
@implementation RecaulkProviderEncoding
- (void)setAccessibilityLabel:(NSString *)label { (void)label; }
@end
EOF
    ;;
    recaulk.nscell.accessibility.v1:accessibilityLabel) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (NSString *)accessibilityLabel;
@end
@implementation RecaulkProviderEncoding
- (NSString *)accessibilityLabel { return nil; }
@end
EOF
    ;;
    recaulk.nscell.accessibility.v1:setAccessibilityRole:) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (void)setAccessibilityRole:(NSString *)role;
@end
@implementation RecaulkProviderEncoding
- (void)setAccessibilityRole:(NSString *)role { (void)role; }
@end
EOF
    ;;
    recaulk.nscell.accessibility.v1:accessibilityRole) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (NSString *)accessibilityRole;
@end
@implementation RecaulkProviderEncoding
- (NSString *)accessibilityRole { return nil; }
@end
EOF
    ;;
    recaulk.nscell.accessibility.v1:setAccessibilityChildren:) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (void)setAccessibilityChildren:(NSArray *)children;
@end
@implementation RecaulkProviderEncoding
- (void)setAccessibilityChildren:(NSArray *)children { (void)children; }
@end
EOF
    ;;
    recaulk.nscell.accessibility.v1:accessibilityChildren) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (NSArray *)accessibilityChildren;
@end
@implementation RecaulkProviderEncoding
- (NSArray *)accessibilityChildren { return nil; }
@end
EOF
    ;;
    recaulk.nscell.accessibility.v1:setAccessibilitySelectedTextRange:) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (void)setAccessibilitySelectedTextRange:(NSRange)range;
@end
@implementation RecaulkProviderEncoding
- (void)setAccessibilitySelectedTextRange:(NSRange)range { (void)range; }
@end
EOF
    ;;
    recaulk.nscell.accessibility.v1:accessibilitySelectedTextRange) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (NSRange)accessibilitySelectedTextRange;
@end
@implementation RecaulkProviderEncoding
- (NSRange)accessibilitySelectedTextRange { return NSMakeRange(NSNotFound, 0); }
@end
EOF
    ;;
    recaulk.nscell.accessibility.v1:accessibilityFrame) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (NSRect)accessibilityFrame;
@end
@implementation RecaulkProviderEncoding
- (NSRect)accessibilityFrame { return NSZeroRect; }
@end
EOF
    ;;
    recaulk.nsworkspace.open-urls.v1) cat <<'EOF'
#import <Foundation/Foundation.h>
@class NSRunningApplication;
@interface RecaulkProviderEncoding : NSObject
- (NSRunningApplication *)openURLs:(NSArray *)u withApplicationAtURL:(NSURL *)a options:(NSUInteger)o configuration:(NSDictionary *)c error:(NSError **)e;
@end
@implementation RecaulkProviderEncoding
- (NSRunningApplication *)openURLs:(NSArray *)u withApplicationAtURL:(NSURL *)a options:(NSUInteger)o configuration:(NSDictionary *)c error:(NSError **)e { return nil; }
@end
EOF
    ;;
    recaulk.nsworkspace.is-voiceover-enabled.v1) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (BOOL)isVoiceOverEnabled;
@end
@implementation RecaulkProviderEncoding
- (BOOL)isVoiceOverEnabled { return NO; }
@end
EOF
    ;;
    recaulk.nsworkspace.should-reduce-motion.v1) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (BOOL)accessibilityDisplayShouldReduceMotion;
@end
@implementation RecaulkProviderEncoding
- (BOOL)accessibilityDisplayShouldReduceMotion { return NO; }
@end
EOF
    ;;
    recaulk.nslocale.language-code.v1) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (NSString *)languageCode;
@end
@implementation RecaulkProviderEncoding
- (NSString *)languageCode { return nil; }
@end
EOF
    ;;
    recaulk.nslocale.country-code.v1) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (NSString *)countryCode;
@end
@implementation RecaulkProviderEncoding
- (NSString *)countryCode { return nil; }
@end
EOF
    ;;
    recaulk.nsstring.contains-string.v1) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (BOOL)containsString:(NSString *)str;
@end
@implementation RecaulkProviderEncoding
- (BOOL)containsString:(NSString *)str { return NO; }
@end
EOF
    ;;
    recaulk.nsstring.localized-case-insensitive-contains-string.v1) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (BOOL)localizedCaseInsensitiveContainsString:(NSString *)str;
@end
@implementation RecaulkProviderEncoding
- (BOOL)localizedCaseInsensitiveContainsString:(NSString *)str { return NO; }
@end
EOF
    ;;
    recaulk.nscontrol.uses-single-line-mode.v1) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (BOOL)usesSingleLineMode;
@end
@implementation RecaulkProviderEncoding
- (BOOL)usesSingleLineMode { return NO; }
@end
EOF
    ;;
    recaulk.nscontrol.set-uses-single-line-mode.v1) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (void)setUsesSingleLineMode:(BOOL)flag;
@end
@implementation RecaulkProviderEncoding
- (void)setUsesSingleLineMode:(BOOL)flag { (void)flag; }
@end
EOF
    ;;
    recaulk.nswindow.titlebar-appears-transparent.v1) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (BOOL)titlebarAppearsTransparent;
@end
@implementation RecaulkProviderEncoding
- (BOOL)titlebarAppearsTransparent { return NO; }
@end
EOF
    ;;
    recaulk.nswindow.set-titlebar-appears-transparent.v1) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (void)setTitlebarAppearsTransparent:(BOOL)flag;
@end
@implementation RecaulkProviderEncoding
- (void)setTitlebarAppearsTransparent:(BOOL)flag { (void)flag; }
@end
EOF
    ;;
    recaulk.nstablecolumn.title.v1) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (NSString *)title;
@end
@implementation RecaulkProviderEncoding
- (NSString *)title { return nil; }
@end
EOF
    ;;
    recaulk.nstablecolumn.set-title.v1) cat <<'EOF'
#import <Foundation/Foundation.h>
@interface RecaulkProviderEncoding : NSObject
- (void)setTitle:(NSString *)title;
@end
@implementation RecaulkProviderEncoding
- (void)setTitle:(NSString *)title { (void)title; }
@end
EOF
    ;;
    *) die "InvalidDeclaration: no encoding probe for provider $1" ;;
  esac
}
legacy=$(providers | awk -F'\t' '
  { split($9, f, ","); fw = ""; for (i = 1; i in f; i++) fw = fw (i > 1 ? "," : "") "\"" f[i] "\""
    printf "%s{\"provider_id\":\"%s\",\"class\":\"%s\",\"method_kind\":\"%s\",\"selector\":\"%s\",\"encoding\":\"%s\",\"implementation_symbol\":\"%s\",\"activation_root\":\"%s\",\"required_frameworks\":[%s],\"framework_policy\":\"strong-linked-before-root\"}", (NR > 1 ? "," : ""), $2, $3, $4, $5, $6, $7, $8, fw }')
# spec: README.md "Objective-C methods" -- a group's rows agree on its class, root and frameworks, and are adjacent
grouped=$(groups | awk -F'\t' '
  $2 != id { if (seen[$2]++) { print "group " $2 " is not one run of rows" > "/dev/stderr"; exit 1 }
             split($9, f, ","); fw = ""; for (i = 1; i in f; i++) fw = fw (i > 1 ? "," : "") "\"" f[i] "\""
             if (NR > 1) printf "]},"
             printf "{\"provider_id\":\"%s\",\"class\":\"%s\",\"guard\":\"absent-only\",\"activation_root\":\"%s\",\"required_frameworks\":[%s],\"framework_policy\":\"strong-linked-before-root\",\"methods\":[", $2, $3, $8, fw
             id = $2; cls = $3; root = $8; fws = $9; n = 0 }
  $3 != cls || $8 != root || $9 != fws { print "group " $2 " mixes classes, roots or frameworks" > "/dev/stderr"; exit 1 }
  { printf "%s{\"kind\":\"%s\",\"selector\":\"%s\",\"encoding\":\"%s\",\"implementation_symbol\":\"%s\"}", (n++ ? "," : ""), $4, $5, $6, $7 }
  END { if (NR) printf "]}" }') || die "InvalidDeclaration: build/objc-provider-manifest.sh's groups are malformed"
# spec: README.md "Objective-C methods" -- a bridge's rows agree on its root, class table and frameworks, and are adjacent
bridged=$(bridges | awk -F'\t' '
  function close_group() { printf "],\"super_fallbacks\":[%s]}", fb }
  $1 != id { if (seen[$1]++) { print "bridge " $1 " is not one run of rows" > "/dev/stderr"; exit 1 }
             split($4, f, ","); fw = ""; for (i = 1; i in f; i++) fw = fw (i > 1 ? "," : "") "\"" f[i] "\""
             if (NR > 1) close_group()
             printf "%s{\"provider_id\":\"%s\",\"guard\":\"own-absent\",\"activation_root\":\"%s\",\"required_frameworks\":[%s],\"framework_policy\":\"strong-linked-before-root\",\"class_table\":\"%s\",\"methods\":[", (NR > 1 ? "," : ""), $1, $2, fw, $3
             id = $1; root = $2; table = $3; fws = $4; n = 0; fb = "" }
  $2 != root || $3 != table || $4 != fws { print "bridge " $1 " mixes roots, tables or frameworks" > "/dev/stderr"; exit 1 }
  { printf "%s{\"kind\":\"-\",\"selector\":\"%s\",\"encoding\":\"%s\",\"implementation_symbol\":\"%s\"}", (n ? "," : ""), $5, $6, $7
    fb = fb (n++ ? "," : "") "{\"implementation_symbol\":\"" $7 "\",\"selector\":\"" $5 "\"}" }
  END { if (NR) close_group() }') || die "InvalidDeclaration: build/objc-provider-manifest.sh's bridges are malformed"
expected="{\"schema\":2,\"legacy_providers\":[$legacy],\"providers\":[$grouped${bridged:+,$bridged}]}"
[ -f "$decl" ] || die "InvalidDeclaration: $decl is missing"
[ "$(tr -d ' \t\r\n' < "$decl")" = "$expected" ] \
  || die "InvalidDeclaration: $decl is not the providers Recaulk ships (schema 2; build/objc-provider-manifest.sh lists them, each strong-linked-before-root)"

probe=$(mktemp -d "${TMPDIR:-/tmp}/objc-provider-manifest.XXXXXX")
trap 'rm -rf "$probe"' EXIT
providers > "$probe/providers.tsv"
groups > "$probe/groups.tsv"
n=0
while IFS='	' read -r macro id class kind selector encoding impl root frameworks; do
  n=$((n + 1)) key=$id
  probe_source "$key" > "$probe/$n.m"
  "$CC" $TARGET_FLAGS -isysroot "$SDK" -fno-objc-arc -fblocks -S -o "$probe/$n.s" "$probe/$n.m" \
    || die "CannotMeasure: clang22 could not compile the encoding probe for $key"
  compiled=$(awk '/^[ \t]*\.section[ \t]/ { m = ($0 ~ /__objc_methtype/) } m && /\.asciz/ { sub(/^[^"]*"/, ""); sub(/"[^"]*$/, ""); print }' "$probe/$n.s")
  [ "$compiled" = "$encoding" ] \
    || die "InvalidDeclaration: $key's declared encoding $encoding is not the compiled one, '$compiled'"
done < "$probe/providers.tsv"
while IFS='	' read -r macro id class kind selector encoding impl root frameworks; do
  n=$((n + 1))
  probe_source "$id:$selector" > "$probe/$n.m"
  "$CC" $TARGET_FLAGS -isysroot "$SDK" -fno-objc-arc -fblocks -S -o "$probe/$n.s" "$probe/$n.m" \
    || die "CannotMeasure: clang22 could not compile the encoding probe for $id:$selector"
  compiled=$(awk '/^[ \t]*\.section[ \t]/ { m = ($0 ~ /__objc_methtype/) } m && /\.asciz/ { sub(/^[^"]*"/, ""); sub(/"[^"]*$/, ""); print }' "$probe/$n.s")
  [ "$compiled" = "$encoding" ] \
    || die "InvalidDeclaration: $id:$selector's declared encoding $encoding is not the compiled one, '$compiled'"
done < "$probe/groups.tsv"
bridges > "$probe/bridges.tsv"
while IFS='	' read -r id root table frameworks selector encoding impl declaration; do
  n=$((n + 1))
  printf '#import <AppKit/AppKit.h>\n@interface RecaulkProviderEncoding : NSObject\n%s;\n@end\n@implementation RecaulkProviderEncoding\n%s { __builtin_trap(); }\n@end\n' \
    "$declaration" "$declaration" > "$probe/$n.m"
  "$CC" $TARGET_FLAGS -isysroot "$SDK" -fno-objc-arc -fblocks -S -o "$probe/$n.s" "$probe/$n.m" \
    || die "CannotMeasure: clang22 could not compile the encoding probe for $id:$selector"
  compiled=$(awk '/^[ \t]*\.section[ \t]/ { m = ($0 ~ /__objc_methtype/) } m && /\.asciz/ { sub(/^[^"]*"/, ""); sub(/"[^"]*$/, ""); print }' "$probe/$n.s")
  [ "$compiled" = "$encoding" ] \
    || die "InvalidDeclaration: $id:$selector's declared encoding $encoding is not the compiled one, '$compiled'"
done < "$probe/bridges.tsv"

sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
json_string() {
  awk 'BEGIN { ORS = "" }
       { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); gsub(/\r/, "\\r")
         if (NR > 1) print "\\n"; print }
       END { if (NR > 0) print "\\n" }' "$1"
}

bridge_fallbacks() {
  awk -F'\t' -v id="$1" '$1 == id { printf "%s        {\n          \"implementation_symbol\" : \"%s\",\n          \"selector\" : \"%s\"\n        }", (n++ ? ",\n" : ""), $7, $5 } END { print "" }' "$probe/bridges.tsv"
}

case "$mode:$#" in
  header:3)
    {
      printf '/* Generated from checked declaration; compiled ABI verified. */\n'
      while IFS='	' read -r macro id class kind selector encoding impl root frameworks; do
        printf '#define RECAULK_%s_CLASS "%s"\n' "$macro" "$class"
        printf '#define RECAULK_%s_SELECTOR "%s"\n' "$macro" "$selector"
        printf '#define RECAULK_%s_ENCODING "%s"\n' "$macro" "$encoding"
      done < "$probe/providers.tsv"
      while IFS='	' read -r macro id class kind selector encoding impl root frameworks; do
        printf '#define RECAULK_%s_CLASS "%s"\n' "$macro" "$class"
        printf '#define RECAULK_%s_SELECTOR "%s"\n' "$macro" "$selector"
        printf '#define RECAULK_%s_ENCODING "%s"\n' "$macro" "$encoding"
      done < "$probe/groups.tsv"
    } > "$3.tmp" && mv "$3.tmp" "$3"
    ;;
  manifest:9)
    archive=$3 out=$4 arch=$5 role=$6 settings=$7 compiler=$8 sources=$9
    : "${LIPO:?}"
    case "$arch:$role" in x86_64:shipping|x86_64:native-test-only|arm64:native-test-only) ;;
      *) die "CannotMeasure: arch $arch and role $role are not a combination Recaulk builds" ;; esac
    actual=$("$LIPO" -archs "$archive" 2>/dev/null) || die "CannotMeasure: cannot read $archive's architectures"
    [ "$actual" = "$arch" ] || die "CannotMeasure: $archive is '$actual', not $arch"
    [ -s "$compiler" ] && [ -s "$sources" ] && [ -f "$settings" ] || die "CannotMeasure: build evidence missing"
    case "$arch" in arm64) minimum=11.0 ;; *) minimum=10.9 ;; esac
    {
      # spec: README.md "Objective-C methods" -- schema 2: legacy_providers first, as schema 1 listed them (a reader
      #       taking the first implementation_symbol still finds openURLs), then the groups
      printf '{\n  "schema" : 2,\n  "legacy_providers" : [\n'
      n=0
      while IFS='	' read -r macro id class kind selector encoding impl root frameworks; do
        [ "$n" = 0 ] || printf '    },\n'
        n=$((n + 1))
        printf '    {\n      "provider_id" : "%s",\n' "$id"
        printf '      "class" : "%s",\n      "method_kind" : "%s",\n' "$class" "$kind"
        printf '      "selector" : "%s",\n      "encoding" : "%s",\n' "$selector" "$encoding"
        printf '      "implementation_symbol" : "%s",\n' "$impl"
        printf '      "activation_root" : "%s",\n' "$root"
        printf '      "required_frameworks" : [\n'
        printf '%s\n' "$frameworks" | tr ',' '\n' | awk '{ printf "%s        \"%s\"", (NR > 1 ? ",\n" : ""), $0 } END { print "" }'
        printf '      ],\n'
        printf '      "framework_policy" : "strong-linked-before-root"\n'
      done < "$probe/providers.tsv"
      printf '    }\n  ],\n  "providers" : [\n'
      gid=
      while IFS='	' read -r macro id class kind selector encoding impl root frameworks; do
        if [ "$id" != "$gid" ]; then
          [ -z "$gid" ] || printf '\n      ]\n    },\n'
          gid=$id
          printf '    {\n      "provider_id" : "%s",\n' "$id"
          printf '      "class" : "%s",\n      "guard" : "absent-only",\n' "$class"
          printf '      "activation_root" : "%s",\n' "$root"
          printf '      "required_frameworks" : [\n'
          printf '%s\n' "$frameworks" | tr ',' '\n' | awk '{ printf "%s        \"%s\"", (NR > 1 ? ",\n" : ""), $0 } END { print "" }'
          printf '      ],\n'
          printf '      "framework_policy" : "strong-linked-before-root",\n'
          printf '      "methods" : [\n'
        else
          printf ',\n'
        fi
        printf '        {\n          "kind" : "%s",\n          "selector" : "%s",\n' "$kind" "$selector"
        printf '          "encoding" : "%s",\n          "implementation_symbol" : "%s"\n        }' "$encoding" "$impl"
      done < "$probe/groups.tsv"
      [ -z "$gid" ] || printf '\n      ]\n    }'
      bid=
      while IFS='	' read -r id root table frameworks selector encoding impl declaration; do
        if [ "$id" != "$bid" ]; then
          [ -z "$bid" ] || { printf '\n      ],\n      "super_fallbacks" : [\n'; bridge_fallbacks "$bid"; printf '      ]\n    }'; }
          [ -z "$gid$bid" ] || printf ',\n'
          bid=$id
          printf '    {\n      "provider_id" : "%s",\n      "guard" : "own-absent",\n' "$id"
          printf '      "activation_root" : "%s",\n' "$root"
          printf '      "required_frameworks" : [\n'
          printf '%s\n' "$frameworks" | tr ',' '\n' | awk '{ printf "%s        \"%s\"", (NR > 1 ? ",\n" : ""), $0 } END { print "" }'
          printf '      ],\n'
          printf '      "framework_policy" : "strong-linked-before-root",\n'
          printf '      "class_table" : "%s",\n' "$table"
          printf '      "methods" : [\n'
        else
          printf ',\n'
        fi
        printf '        {\n          "kind" : "-",\n          "selector" : "%s",\n' "$selector"
        printf '          "encoding" : "%s",\n          "implementation_symbol" : "%s"\n        }' "$encoding" "$impl"
      done < "$probe/bridges.tsv"
      [ -z "$bid" ] || { printf '\n      ],\n      "super_fallbacks" : [\n'; bridge_fallbacks "$bid"; printf '      ]\n    }'; }
      [ -z "$gid$bid" ] || printf '\n'
      printf '  ],\n'
      printf '  "build" : {\n'
      printf '    "archive_path" : "lib/librecaulk-objc.a",\n'
      printf '    "archive_sha256" : "%s",\n' "$(sha256 "$archive")"
      printf '    "architecture" : "%s",\n' "$actual"
      printf '    "artifact_role" : "%s",\n' "$role"
      printf '    "minimum_macos" : "%s",\n' "$minimum"
      printf '    "sdk_settings_sha256" : "%s",\n' "$(sha256 "$settings")"
      printf '    "compiler_identity" : "%s",\n' "$(json_string "$compiler")"
      printf '    "source_inputs_receipt" : "%s",\n' "$(json_string "$sources")"
      printf '    "source_inputs_sha256" : "%s"\n' "$(sha256 "$sources")"
      printf '  }\n}\n'
    } > "$out.tmp" && mv "$out.tmp" "$out"
    ;;
  *) sed -n 3,7p "$0" >&2; exit 2 ;;
esac
