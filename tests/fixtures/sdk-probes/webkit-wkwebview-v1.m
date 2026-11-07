// weak: _OBJC_CLASS_$_WKWebView _OBJC_CLASS_$_WKWebsiteDataStore
#import <WebKit/WebKit.h>
WKWebView *probe(NSURLRequest *r) {
    WKWebViewConfiguration *c = [[NSClassFromString(@"WKWebViewConfiguration") alloc] init];
    c.applicationNameForUserAgent = @"iTerm2";
    WKPreferences *p = [[NSClassFromString(@"WKPreferences") alloc] init];
    p.javaEnabled = NO; p.javaScriptEnabled = YES; p.javaScriptCanOpenWindowsAutomatically = NO;
    c.preferences = p;
    c.processPool = [[NSClassFromString(@"WKProcessPool") alloc] init];
    c.userContentController = [[NSClassFromString(@"WKUserContentController") alloc] init];
    if ([WKWebsiteDataStore class]) { c.websiteDataStore = [WKWebsiteDataStore defaultDataStore]; }
    if (![WKWebView class]) { return nil; }
    WKWebView *v = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 1, 1) configuration:c];
    v.autoresizingMask = NSViewWidthSizable; [v loadRequest:r]; [v loadHTMLString:@"" baseURL:v.URL]; [v stopLoading];
    return v;
}
