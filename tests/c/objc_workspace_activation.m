/* No direct references to provider symbols: -u must cause extraction itself. */
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static const char *selectorName="openURLs:withApplicationAtURL:options:configuration:error:";
static IMP before;
static BOOL ownerBefore;
static char beforeTypes[256];
static int initialized;
static Method metadata(Class c, SEL s) {
    for (;c;c=class_getSuperclass(c)) {
        unsigned n=0; Method *list=class_copyMethodList(c,&n); Method found=NULL;
        for (unsigned i=0;i<n;i++) if (method_getName(list[i])==s) { found=list[i]; break; }
        free(list); if (found) return found;
    }
    return NULL;
}
@interface ActivationSnapshot : NSObject @end
@implementation ActivationSnapshot
+ (void)load {
    Class owner=objc_getClass("NSWorkspace"); ownerBefore=owner!=Nil;
    Method m=metadata(owner,sel_registerName(selectorName));
    if (m) { before=method_getImplementation(m); strlcpy(beforeTypes,method_getTypeEncoding(m),sizeof(beforeTypes)); }
}
@end
@interface ActivationCarrier : NSObject
- (NSRunningApplication *)openURLs:(NSArray *)u withApplicationAtURL:(NSURL *)a options:(NSWorkspaceLaunchOptions)o configuration:(NSDictionary *)c error:(NSError **)e;
@end
@implementation ActivationCarrier
- (NSRunningApplication *)openURLs:(NSArray *)u withApplicationAtURL:(NSURL *)a options:(NSWorkspaceLaunchOptions)o configuration:(NSDictionary *)c error:(NSError **)e { return nil; }
@end
static NSRunningApplication *existing(id self,SEL cmd,NSArray *u,NSURL *a,NSWorkspaceLaunchOptions o,NSDictionary *c,NSError **e) { return nil; }
static void initialize(id self,SEL cmd) { initialized++; }
int main(int argc,char **argv) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    if (argc!=2) return 2; BOOL rooted=atoi(argv[1])!=0; int failures=0;
    SEL sel=sel_registerName(selectorName); Class owner=objc_getClass("NSWorkspace");
    Method current=metadata(owner,sel); IMP after=current ? method_getImplementation(current) : NULL;
    void (*activate)(void)=dlsym(RTLD_DEFAULT,"__recaulk_objc_activate");
    IMP body=(IMP)dlsym(RTLD_DEFAULT,"__recaulk_objc_workspace_open_urls");
    if (!ownerBefore || (body && before==body)) failures++; /* reject a late/contaminated baseline */
    if (!rooted) {
        if (activate || body || before!=after || (current && strcmp(beforeTypes,method_getTypeEncoding(current)))) failures++;
    } else {
        if (!activate || !body || !current) failures++;
        const char *types=method_getTypeEncoding(metadata(objc_getClass("ActivationCarrier"),sel));
        if (!types || strcmp(types,"@56@0:8@16@24Q32@40^@48") || (current && strcmp(types,method_getTypeEncoding(current)))) failures++;
        if (before ? after!=before : after!=body) failures++;
        if (before && strcmp(beforeTypes,method_getTypeEncoding(current))) failures++;
        if (activate) { activate(); if (method_getImplementation(metadata(owner,sel))!=after) failures++; }
        void (*registerClass)(Class)=dlsym(RTLD_DEFAULT,"__recaulk_objc_register_workspace_class");
        if (!registerClass) failures++;
        else {
            Class parent=objc_allocateClassPair([NSObject class],"ActivationParent",0);
            class_addMethod(parent,sel,(IMP)existing,types);
            class_addMethod(object_getClass(parent),sel_registerName("initialize"),(IMP)initialize,"v16@0:8");
            objc_registerClassPair(parent);
            Class child=objc_allocateClassPair(parent,"ActivationChild",0); objc_registerClassPair(child);
            registerClass(child);
            unsigned n=0; Method *methods=class_copyMethodList(child,&n);
            for (unsigned i=0;i<n;i++) if (method_getName(methods[i])==sel) failures++;
            free(methods);
            if (method_getImplementation(metadata(child,sel))!=(IMP)existing || initialized) failures++;
            Class missing=objc_allocateClassPair([NSObject class],"ActivationMissing",0); objc_registerClassPair(missing);
            registerClass(missing); IMP installed=method_getImplementation(metadata(missing,sel));
            registerClass(missing);
            if (installed!=body || method_getImplementation(metadata(missing,sel))!=installed) failures++;
        }
    }
    printf("%s: %s archive; startup/native/inherited/ABI/repeat metadata checks (no app launch)\n",failures ? "FAIL":"PASS",rooted ? "rooted":"unrooted");
    [pool drain]; return failures ? 1:0;
}
