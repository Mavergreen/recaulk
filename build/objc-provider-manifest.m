/* Host Foundation-only declaration/typed-ABI checker and metadata generator. */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <CommonCrypto/CommonDigest.h>
#include <stdio.h>
#include <string.h>
@class NSRunningApplication;
@interface RecaulkProviderEncoding : NSObject
- (NSRunningApplication *)openURLs:(NSArray *)u withApplicationAtURL:(NSURL *)a options:(NSUInteger)o configuration:(NSDictionary *)c error:(NSError **)e;
@end
@implementation RecaulkProviderEncoding
- (NSRunningApplication *)openURLs:(NSArray *)u withApplicationAtURL:(NSURL *)a options:(NSUInteger)o configuration:(NSDictionary *)c error:(NSError **)e { return nil; }
@end
static NSString *digest(NSString *path) {
    NSData *data=[NSData dataWithContentsOfFile:path]; if (!data) return nil;
    CC_SHA256_CTX state; CC_SHA256_Init(&state);
    const unsigned char *p=data.bytes; NSUInteger remaining=data.length;
    while (remaining) { CC_LONG n=(CC_LONG)MIN(remaining,(NSUInteger)1048576); CC_SHA256_Update(&state,p,n); p+=n; remaining-=n; }
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(bytes,&state);
    NSMutableString *value=[NSMutableString string];
    for (unsigned i=0;i<sizeof(bytes);i++) [value appendFormat:@"%02x",bytes[i]];
    return value;
}
static NSDictionary *declaration(NSString *path) {
    NSData *data=[NSData dataWithContentsOfFile:path];
    id root=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![root isKindOfClass:[NSDictionary class]] || [root count]!=2) return nil;
    id schema=[root objectForKey:@"schema"];
    if (![schema isKindOfClass:[NSNumber class]] || CFGetTypeID((CFTypeRef)schema)==CFBooleanGetTypeID() ||
        CFNumberIsFloatType((CFNumberRef)schema) || ![schema isEqual:@1]) return nil;
    id providers=[root objectForKey:@"providers"];
    if (![providers isKindOfClass:[NSArray class]] || [providers count]!=1) return nil;
    id p=[providers objectAtIndex:0];
    NSDictionary *expected=@{@"provider_id":@"recaulk.nsworkspace.open-urls.v1",@"class":@"NSWorkspace",@"method_kind":@"-",
        @"selector":@"openURLs:withApplicationAtURL:options:configuration:error:",@"encoding":@"@56@0:8@16@24Q32@40^@48",
        @"implementation_symbol":@"__recaulk_objc_workspace_open_urls",@"activation_root":@"__recaulk_objc_activate",
        @"required_frameworks":@[@"AppKit",@"Carbon"],@"framework_policy":@"strong-linked-before-root"};
    if (![p isKindOfClass:[NSDictionary class]] || ![p isEqual:expected]) return nil;
    Method method=class_getInstanceMethod(objc_getClass("RecaulkProviderEncoding"),sel_registerName("openURLs:withApplicationAtURL:options:configuration:error:"));
    if (!method || ![[p objectForKey:@"encoding"] isEqual:[NSString stringWithUTF8String:method_getTypeEncoding(method)]]) return nil;
    return root;
}
static NSString *architecture(NSString *archive) {
    NSTask *task=[[[NSTask alloc] init] autorelease]; NSPipe *output=[NSPipe pipe];
    task.launchPath=@"/usr/bin/lipo"; task.arguments=@[@"-info",archive]; task.standardOutput=output;
    [task launch]; NSData *data=[[output fileHandleForReading] readDataToEndOfFile]; [task waitUntilExit];
    if (task.terminationStatus) return nil;
    NSString *info=[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    NSRange marker=[info rangeOfString:@" is architecture: " options:NSBackwardsSearch];
    if (!info || [info rangeOfString:@"Non-fat file: "].location==NSNotFound || marker.location==NSNotFound) return nil;
    return [[info substringFromIndex:NSMaxRange(marker)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}
int main(int argc,char **argv) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new]; int result=1;
    @try {
        if (argc<4) { fprintf(stderr,"usage: objc-provider-manifest header DECL OUT | manifest DECL ARCHIVE OUT ARCH ROLE SDK_SETTINGS COMPILER_RECEIPT SOURCE_RECEIPT\n"); return 2; }
        NSString *mode=[NSString stringWithUTF8String:argv[1]];
        NSDictionary *root=declaration([NSString stringWithUTF8String:argv[2]]);
        if (!root) [NSException raise:@"InvalidDeclaration" format:@"provider schema/identity/strong policy/compiled ABI mismatch"];
        if ([mode isEqual:@"header"] && argc==4) {
            NSDictionary *p=[[root objectForKey:@"providers"] objectAtIndex:0];
            NSString *text=[NSString stringWithFormat:@"/* Generated from checked declaration; host compiled ABI verified. */\n#define RECAULK_WORKSPACE_CLASS \"%@\"\n#define RECAULK_WORKSPACE_SELECTOR \"%@\"\n#define RECAULK_WORKSPACE_ENCODING \"%@\"\n",[p objectForKey:@"class"],[p objectForKey:@"selector"],[p objectForKey:@"encoding"]];
            result=[text writeToFile:[NSString stringWithUTF8String:argv[3]] atomically:YES encoding:NSUTF8StringEncoding error:NULL] ? 0:1;
        } else if ([mode isEqual:@"manifest"] && argc==10) {
            NSString *archive=[NSString stringWithUTF8String:argv[3]], *arch=[NSString stringWithUTF8String:argv[5]], *role=[NSString stringWithUTF8String:argv[6]];
            NSString *actual=architecture(archive), *hash=digest(archive), *sdk=digest([NSString stringWithUTF8String:argv[7]]);
            NSString *compiler=[NSString stringWithContentsOfFile:[NSString stringWithUTF8String:argv[8]] encoding:NSUTF8StringEncoding error:NULL];
            NSString *sources=[NSString stringWithContentsOfFile:[NSString stringWithUTF8String:argv[9]] encoding:NSUTF8StringEncoding error:NULL];
            if (!actual || ![actual isEqual:arch] || !hash || !sdk || !compiler.length || !sources.length ||
                ![@[@"x86_64",@"arm64"] containsObject:arch] || ![@[@"shipping",@"native-test-only"] containsObject:role] ||
                ([role isEqual:@"shipping"] && ![arch isEqual:@"x86_64"])) [NSException raise:@"CannotMeasure" format:@"archive slice or build evidence invalid"];
            NSMutableDictionary *manifest=[[root mutableCopy] autorelease];
            [manifest setObject:@{@"archive_path":@"lib/librecaulk-objc.a",@"archive_sha256":hash,@"architecture":actual,
                @"artifact_role":role,@"minimum_macos":[arch isEqual:@"arm64"] ? @"11.0":@"10.9",@"sdk_settings_sha256":sdk,
                @"compiler_identity":compiler,@"source_inputs_receipt":sources,@"source_inputs_sha256":digest([NSString stringWithUTF8String:argv[9]])} forKey:@"build"];
            NSData *json=[NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:NULL];
            result=json && [json writeToFile:[NSString stringWithUTF8String:argv[4]] atomically:YES] ? 0:1;
        } else result=2;
    } @catch (NSException *error) { fprintf(stderr,"objc-provider-manifest: %s: %s\n",error.name.UTF8String,error.reason.UTF8String); result=1; }
    [pool drain]; return result;
}
