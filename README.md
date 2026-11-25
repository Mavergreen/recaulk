# Recaulk

Modern C library functions for Mac OS X 10.9 Mavericks.

Programs built for newer macOS often call functions 10.9's `libSystem.B.dylib` doesn't have.
Recaulk supplies them:

- `librecaulk.a` for source code
- `libRecaulkSystem.dylib` for binaries
- `librecaulk-cxxabi-exports.a` for one consumer only, libcxx22's `libc++abi.1.dylib` (see C++ exceptions)
- `librecaulk-objc.a` for Objective-C methods 10.9's frameworks lack (see Objective-C methods)

When running on newer macOS and a system-provided version of a Recaulk function exists, the system's version is preferred, with a few exceptions.

## How to use

Given source code:

```sh
cc -isystem /usr/local/mavergreen/recaulk/include/recaulk \
   myprogram.c /usr/local/mavergreen/recaulk/lib/librecaulk.a
```

Each member of `librecaulk.a` names the frameworks and libraries it needs (CoreFoundation, Security,
CoreServices, CoreGraphics, `-lobjc`, `-lc++abi`) in its own object file, and the linker adds them when it uses
that member. So the link needs no flags for Recaulk's sake: a program gains only what the members it uses need,
and one that force-loads the whole archive (`-Wl,-force_load`) gets everything any member needs.

(When you're building a dylib, also pass
`-Wl,-unexported_symbols_list,/usr/local/mavergreen/recaulk/share/recaulk/unexported-symbols.txt`. It names
every global `librecaulk.a` defines, the `___recaulk_` internals and the back-fills alike, so your dylib doesn't
export `clock_gettime` or `aligned_alloc` to its own clients. It also hides a function of your own by one of
those names.)

If you link only some members of `librecaulk.a`, refusing ones that define names 10.9 already exports, allow
the pairs `/usr/local/mavergreen/recaulk/share/recaulk/image-local-shadows.txt` lists (`<member> <symbol>
<reason>`, `#` comments). Each is a deliberate, hidden fix to a 10.9 function that binds only inside your image,
and some come with the member that needs them: `dispatch_activate` is correct only when the same image's
`dispatch_resume` and `dispatch_queue_create` are Recaulk's too. The list is exact; no other member defines a
10.9 export.

Every global `librecaulk.a` and `librecaulk-cxxabi-exports.a` define, as `nm` lists them, is a named API or
starts `___recaulk_`, so a consumer can pick members by the names it asks for. MacPorts' private helpers
(the names `build/forward-exclude.txt` classes private, such as `___mpls_best_fchdir`) and clang's block
helpers are renamed `___recaulk_<name>` in the archive. `libRecaulkSystem.dylib` still exports MacPorts'
names unrenamed, as libSystemWrapper.dylib did.

(Recaulk fills in the C++ runtime entry points 10.9's libc++abi lacks; those members bring `-lc++abi` with them, since they call the rest of it.)

### Objective-C methods

`librecaulk-objc.a` adds framework methods 10.9 lacks, such as NSWorkspace's
`openURLs:withApplicationAtURL:options:configuration:error:` and `isVoiceOverEnabled`. The latter reads the
state VoiceOver records (`voiceOverOnOffKey` in `com.apple.universalaccess`) each time it is asked; unlike
Apple's 10.13 property, it posts no key-value observing change when VoiceOver turns on or off.
`accessibilityDisplayShouldReduceMotion` answers NO: 10.9 has no reduce-motion setting (it arrived in 10.12).
`NSControl`'s `usesSingleLineMode` and its setter (10.10) are the control's cell's, which 10.9 has; a control with no
cell reads NO. `NSTableColumn`'s `title` and `setTitle:` (10.10) are its header cell's string; a nil title is stored
as `@""`, since 10.10 declares it non-null. `NSWindow`'s `titlebarAppearsTransparent` (10.10) reads NO and its
setter changes nothing, as 10.9 draws no transparent titlebar. It is separate from
`librecaulk.a` and does nothing unless you ask for it: link it and keep its
activation root, and AppKit and Carbon strong-linked:

```sh
cc myprogram.m /usr/local/mavergreen/recaulk/lib/librecaulk-objc.a \
   -Wl,-u,___recaulk_objc_activate -framework AppKit -framework Carbon
```

Foundation's methods have a root of their own, which needs Foundation alone:
`NSLocale`'s `languageCode` and `countryCode` (10.12), the answers
`objectForKey:` gives for `NSLocaleLanguageCode` and `NSLocaleCountryCode`, except
that `languageCode`, which Apple declares non-null, is `@""` where 10.9 has no
language (`""`, `_US`); and `NSString`'s `containsString:` and
`localizedCaseInsensitiveContainsString:` (10.10), through `rangeOfString:` (the second with
`NSCaseInsensitiveSearch` in the current locale), so like 10.10's neither finds the empty string.

```sh
cc myprogram.m /usr/local/mavergreen/recaulk/lib/librecaulk-objc.a \
   -Wl,-u,___recaulk_objc_activate_foundation -framework Foundation
```

Five groups each have a root of their own, three of class methods and two of instance methods:

- `___recaulk_objc_activate_timer` (Foundation): `NSTimer`'s `scheduledTimerWithTimeInterval:repeats:block:` and
  `timerWithTimeInterval:repeats:block:` (10.12), as 10.9's `CFRunLoopTimerCreateWithHandler` timers, which are
  `NSTimer`s whose block is passed the timer. An interval of 0 or less is 0.0001 s, as `NSTimer` documents, and the
  scheduled one runs in the current run loop's default mode.
- `___recaulk_objc_activate_color` (AppKit): `NSColor`'s `labelColor` (10.10), which is 10.9's
  `controlTextColor`, and `linkColor` (10.10), sRGB 0, 0.408, 0.855.
- `___recaulk_objc_activate_graphics_context` (AppKit): `NSGraphicsContext`'s
  `graphicsContextWithCGContext:flipped:` (10.10), through 10.9's `graphicsContextWithGraphicsPort:flipped:`.
- `___recaulk_objc_activate_view_accessibility` and `___recaulk_objc_activate_cell_accessibility` (AppKit):
  `NSView`'s and `NSCell`'s 10.10 accessibility properties `accessibilityLabel`, `accessibilityRole`,
  `accessibilityChildren` and `accessibilitySelectedTextRange` (each getter and setter) and `accessibilityFrame`.
  10.9's VoiceOver reads the attribute API, so a setter overrides the attribute (`AXDescription`, `AXRole`,
  `AXChildren`, `AXSelectedTextRange`) with 10.9's `accessibilitySetOverrideValue:forAttribute:`, and a getter
  returns the override, else 10.9's value of the attribute, else nil (10.9 throws for an attribute the element lacks);
  an absent text range is `{NSNotFound, 0}`, and the frame is 10.9's `AXPosition` and `AXSize` in screen coordinates,
  or `NSZeroRect`. A control's (`NSControl`'s) properties are its cell's, the element 10.9 exposes, as 10.10's
  `NSControl` forwards them. A program that subclasses with its own getters (10.10's way of being accessible) is
  not seen by 10.9's VoiceOver through these: 10.9 asks `accessibilityAttributeValue:`, which only the
  accessibility bridge (below) answers from them.

A group is added whole or not at all: if its class already has any of its methods, none of them is added.

#### The accessibility bridge

10.9's VoiceOver asks an element only through the old attribute API (`accessibilityAttributeNames`,
`accessibilityAttributeValue:` and their kin). A class written for 10.10 or later may implement only the
`NSAccessibility` protocol's getters (`accessibilityRole`, `accessibilityLabel`, `accessibilityValue`, the text ranges,
`accessibilityStringForRange:` and so on), and is then silent on 10.9. Call the bridge once for each such class of
yours, an `NSView` or `NSCell` subclass, before any of its instances is on screen, with the class named literally:

```objc
#include <recaulk/accessibility.h>
recaulk_accessibility_bridge(objc_getClass("PTYTextView"));
recaulk_accessibility_bridge([PSMTabBarControl class]);
```

and link `librecaulk-objc.a` with AppKit (the call pulls the bridge in; there is no root to keep with `-u`). Bridge a
class or a subclass of it, not both: the subclass's old API would reach the bridged superclass's, which Drydock refuses. The
class then answers each old attribute from the 10.10 getter it implements, boxed as 10.9 boxes it (a range, point,
size or rectangle as an `NSValue`, a count or flag as an `NSNumber`; `AXDescription` from `accessibilityLabel`,
`AXPosition` and `AXSize` from `accessibilityFrame`, `AXBoundsForRange` from `accessibilityFrameForRange:`), lists those
attributes and the parameterized ones it implements beside 10.9's, sets an attribute through the 10.10 setter it
implements (`setAccessibilityValue:`, the focus, selection and expansion flags, the selected text and ranges, the
visible character range), and offers each action whose `accessibilityPerform...` method it implements. What its
getters don't answer, 10.9 answers, as for any view or cell. A view 10.9 would ignore (any plain `NSView` subclass, and
a control, whose cell 10.9 exposes instead) is not ignored if it says it is an element (`isAccessibilityElement`) or its
`accessibilityRole` answers a role.

The bridge adds the old methods to the class you pass and to nothing else. Pass only a class of your own that neither
implements any of them itself nor inherits one from a class of yours; its subclasses inherit the bridge. Nil does
nothing. It is not an Objective-C method provider in the declaration (Drydock verifies the call sites from 0.8.0).

```sh
cc myprogram.m /usr/local/mavergreen/recaulk/lib/librecaulk-objc.a \
   -Wl,-u,___recaulk_objc_activate_timer -Wl,-u,___recaulk_objc_activate_color \
   -Wl,-u,___recaulk_objc_activate_graphics_context -Wl,-u,___recaulk_objc_activate_view_accessibility \
   -Wl,-u,___recaulk_objc_activate_cell_accessibility -framework AppKit
```

shipyard's `objc-provider-link-args.sh` prints the roots and frameworks of every
provider the declaration lists, so a link made with it activates every root and
links AppKit and Carbon; link by hand, as above, to take some roots alone.

Don't use `-force_load`; `-u` is enough, and survives `-dead_strip` and LTO. At
load, each method is added only where the class doesn't already have it, so a
native or inherited implementation on newer macOS is left alone.
`share/recaulk/objc-providers.json` lists the methods, their ABI encodings and
the build that produced the archive (source hashes, archive hash, compiler, SDK). It is Drydock's schema 2: the
instance methods registered before groups existed, one per entry as schema 1 had them, under `legacy_providers`, and
the groups under `providers`. Reading it takes Drydock 0.7.0 or later, which shipyard pins from 1.0.888 (`@v1` has
it); an older Drydock refuses the file rather than skip it. Crediting the NSView and NSCell accessibility groups, whose
members a newer SDK declares through the protocol the class adopts, takes Drydock 0.7.1; 0.7.0 still credits the
others. Drydock credits a group only from a root that registers its
members and nothing else, every member looked up before any is added, which is why each group has its own root.

#### Stand-in classes

Some 10.10 classes are meant to be subclassed, and a subclass of a class 10.9 lacks never realizes there: its superclass
is missing. `lib/stand-in/libRecaulkAppKit.dylib` holds a stand-in for each such class `build/standins.txt` lists,
today `RecaulkAccessibilityElement` for `NSAccessibilityElement`. It keeps 10.10's API (the factory
`+accessibilityElementWithRole:frame:label:parent:`, `-accessibilityAddChildElement:`, `accessibilityFrameInParentSpace`
and the protocol properties it stores), and answers 10.9's attribute API from the 10.10 getters, a subclass's overrides
first, as the accessibility bridge does. The dylib exports its class and metaclass under AppKit's names
(`_OBJC_CLASS_$_NSAccessibilityElement`); its runtime name stays `RecaulkAccessibilityElement`, so it never collides
with AppKit's, and `NSClassFromString(@"NSAccessibilityElement")` still returns nil on 10.9.

Link `lib/stub/libRecaulkAppKit.dylib`, never the stand-in itself: the stub has the same install name,
`@rpath/libRecaulkAppKit.dylib`, and exports no class, so the class stays unbound until launch. Bind the class flat
and weak, after AppKit, and ship the stand-in in your app's `Contents/Frameworks`:

```sh
cc myapp.m -framework AppKit \
   -Wl,-weak_library,/usr/local/mavergreen/recaulk/lib/stub/libRecaulkAppKit.dylib \
   -Wl,-U,'_OBJC_CLASS_$_NSAccessibilityElement' -Wl,-U,'_OBJC_METACLASS_$_NSAccessibilityElement' \
   -Wl,-rpath,@executable_path/../Frameworks
cp /usr/local/mavergreen/recaulk/lib/stand-in/libRecaulkAppKit.dylib MyApp.app/Contents/Frameworks/
```

(10.9's dyld expands `@executable_path` or `@loader_path` in an rpath only when a slash follows it: write
`@loader_path/.`, never a bare `@loader_path`.) dyld's flat lookup then takes AppKit's class on 10.10 and later, and
the stand-in's on 10.9. Declare the class
`weak_import` in your source (10.9's SDK lacks it): without the stand-in the app still launches, and only the
subclasses are missing, as before. Never put a stand-in in the executable, where it would win over AppKit's on every
macOS.

Given a binary, relink it with [drydock-macho-rewrite](https://github.com/Mavergreen/drydock):

```
dylib  replace  /usr/lib/libSystem.B.dylib  /usr/local/mavergreen/recaulk/lib/libRecaulkSystem.dylib
```

The source headers also adapt two Mavericks API defects: numeric port-zero
`getaddrinfo` requests no longer crash with `AI_NUMERICSERV`, and `fdopendir`
accepts already-open readable directories without requiring search permission.
MacPorts headers remain intact. Where Recaulk wraps a header MacPorts also
provides, MacPorts' copy is staged unmodified beside it as `_recaulk_macports_<name>`, and
Recaulk's header includes it before adding its own declarations. Beside, not in a subdirectory, so its
`#include_next` is in a file directly in a search directory, which is the only place `zig translate-c`'s
C front end continues one from.
The directory repair uses libc-owned stream state for both inode ABIs and retains
the original failure for union mounts, whose duplicate filtering needs a separate
implementation. Modern systems still use the forwarded native `fdopendir` first.

Source event loops can include `<recaulk/udp_wait.h>` and use
`__recaulk_kevent_wait_udp` after submitting their normal kqueue changes. Supply
an immutable snapshot of enabled, level-triggered UDP readers and zero-initialized
per-loop fairness state. This wait supplements Mavericks' missing empty-datagram
notifications using `select`, without consuming packets or retaining descriptors.
Other filters remain native. Synthetic UDP events report readiness with `data=0`;
receive the datagram to determine its length. The caller owns descriptor lifetime
and must refresh the snapshot when registrations change.

## Fixes to functions 10.9 has

When Recaulk fixes a defect in a function 10.9's libSystem already exports, the fix reaches both
products. `libRecaulkSystem.dylib` exports it publicly (its source is in `src/overrides/`), and
`librecaulk.a` carries it weak and hidden (`src/backfills/`), so it binds only inside the program or
dylib that links the archive and yields to the dylib's in the one link that has both. Each such name is
listed with its reason in `build/image-local-shadows.txt`, and `tests/rule-backfills-add-only.sh`
holds that list exact. Recaulk's C++ exception rules, its `posix_spawn`, its `pselect`, its `close` and
`dup2`, its `pthread_get_stacksize_np`, and its `fma`, `fmal` and `truncl` are fixes of this kind.

A back-fill that works only through such a fix is hidden in `librecaulk.a` with it
(`build/image-local-backfills.txt`): `posix_spawn_file_actions_addchdir_np` and `addfchdir_np` record actions only
Recaulk's `posix_spawn` and `posix_spawnp` carry out. So a dylib built from the archive exports both or neither, and
a program that looks the builders up with `dlsym` (as Rust's standard library does) does not find them, and takes its
own way to the directory rather than one libSystem's `posix_spawn` would silently ignore.

`/usr/local/mavergreen/recaulk/share/recaulk/system-overrides.txt` lists, one `<member> <symbol>` per line
(`#` comments), every name `librecaulk.a` defines that 10.9 already exports: those fixes, among them
`pthread_get_stacksize_np`, and MacPorts' public `sysconf`. Each takes effect only where it binds before the system's copy, so a
binary that imports one of these names from a system library has missed Recaulk's fix, usually through link order
(an explicit `-lSystem` ahead of `librecaulk.a`). A product's conformance check can read the list to catch that.

`pthread_get_stacksize_np` gives the main thread the stack the kernel gave it, which 10.9 reports as 512 KiB: the
`LC_MAIN` stacksize rounded up to a page when the program carries one (Apple ld's `-stack_size`), otherwise
`RLIMIT_STACK`'s soft limit rounded up to a page. It replaces MacPorts' fix, which returned the soft limit as is;
`build/macports-superseded.txt` names each MacPorts member Recaulk leaves out for one of its own.

A hidden definition in an archive binds only when nothing earlier in the link defines the name, and
`-lm`, `-ldl`, `-lpthread` and `-lc` each name libSystem itself. So a program built from source against
Recaulk's headers reaches each C fix by a name of Recaulk's own, whatever its link order: `math.h` and
`spawn.h` declare the 10.9 names first with Recaulk's symbol as their asm label, and `sys/select.h`
renames `pselect`, whose 10.9 declaration picks one of five labelled variants, so the label it picks is
the same variant of Recaulk's. `libRecaulkSystem.dylib` exports those names too, the only `___recaulk_` names
it exports (`build/header-entries.txt`), so the same program linked against it finds them.
`tests/shadow-renames.sh` holds each listed C function to that. Two cases
still depend on link order, besides `close` and `dup2` (see Closing a socket): code compiled against Apple's
headers (a prebuilt object), and C++ that
reaches `fmal` or `truncl` through libc++'s `long double` overloads, which call the compiler builtin and
so the plain name. The C++ exception rules are vtables the compiler references, which no header can
rename.

## Declarations

Every public function `librecaulk.a` defines is declared by Recaulk's headers, in the header and under
the condition the 11.3 SDK (shipyard's `fetch_sdk.sh --arch arm64`) declares it, or in a header of
Recaulk's own where no Apple SDK has it. A definition without a declaration is a trap: an autoconf link
test finds the function, the program drops its own fallback, and a C99 compiler then refuses the call
(LibreSSL's `timingsafe_bcmp`). Two kinds stay undeclared, each listed with its reason: an entry point no
source calls by name (one the compiler emits, an SPI its callers declare themselves, a call a later SDK's
macro makes), and a stub that only reports failure on 10.9, such as `SecKeyCreateRandomKey`, which a
declaration would make a feature check choose over the 10.9 path that works. `build/declarations.txt`
lists every one, and `tests/declarations.sh` holds that list exact and each header declaring its names.

Constants a later SDK names for a function 10.9 has are defined the same way: `<sys/clonefile.h>`
defines `CLONE_NOOWNERCOPY` (0x0002, from the 10.13 SDK), which changes nothing on 10.9, where the
`clonefile` family fails with `ENOTSUP` whatever the flags.

`<sys/mman.h>` names `MAP_ANONYMOUS` (10.11's name for `MAP_ANON`) exactly where 10.9 names `MAP_ANON`: by
default, or with `_DARWIN_C_SOURCE`. Under a bare `_POSIX_C_SOURCE` neither is defined, so a strict-POSIX
`#ifdef MAP_ANONYMOUS` takes its other branch rather than one that names an undeclared `MAP_ANON`.

`LSCopyApplicationURLsForBundleIdentifier` (10.10), declared through `<CoreServices/CoreServices.h>`, returns
the one application 10.9's LaunchServices would launch for the bundle identifier (`LSFindApplicationForInfo`),
not every copy, or NULL and an OSStatus-domain error such as `kLSApplicationNotFoundErr`.

`<sys/_endian.h>`, and so `<arpa/inet.h>`, `<netinet/in.h>` and `<machine/endian.h>`, defines the 10.10 SDK's
`ntohll`, `htonll`, `NTOHLL` and `HTONLL` beside `ntohl`, under the same conditions. `<dispatch/dispatch.h>`
defines its `dispatch_cancel` and `dispatch_testcancel`, the macros that pick a block's or a source's call; the
function 10.10 also exports under that name stays undeclared, since no call through the macros reaches it.

## C++ exceptions

C++ code linked with `librecaulk.a` catches pointers and member pointers by the current rules on
10.9 too: a thrown `nullptr` as a member pointer, an `int**` as a `const int* const*`, and a null
derived pointer as a null base pointer, which 10.9's libc++abi gets wrong. The rules hold for the
`catch` clauses of the program or dylib that links Recaulk; other libraries, the system's among
them, keep their own.

`librecaulk-cxxabi-exports.a` is the one archive that deliberately exports names the system
exports: the same two C++ ABI vtables, public. Its one intended consumer is libcxx22's
`libc++abi.1.dylib`, which exports them, so every program that reaches the C++ ABI through libcxx22
gets these rules as well. Link it into nothing else.

## OS version

`os_system_version_get_current_version`, which Swift's runtime calls for `if #available`, is
declared by `<os/system_version.h>` through `include/recaulk`. On 10.9 it reads the version from
`/System/Library/CoreServices/SystemVersion.plist` and returns 0. If it cannot read that file it returns
an `errno` and leaves the version untouched, as it does when the file holds no version it can read. Newer macOS uses its own.

## Security

`SecKeyCreateSignature` takes Apple's `SecKeyAlgorithm` constants and signs on 10.9 with RSA
PKCS#1 v1.5 or X9.62 ECDSA over a SHA-1, SHA-224, SHA-256, SHA-384 or SHA-512 digest. As Apple's
does for a 10.9 key, it signs RSA input no longer than the digest, and refuses ECDSA input that is
not the digest's length. It refuses RSA-PSS, for which 10.9's Security has no primitive, and every
other algorithm, with `errSecParam`, as Apple's does for an algorithm a key does not support.
`SecTrustEvaluateWithError` reports a failure as Apple's does, in `kCFErrorDomainOSStatus` with
codes such as `errSecNotTrusted` and `errSecCertificateExpired`, and `SecTrustCopyCertificateChain`
returns `NULL` for a chain without certificates. Through `include/recaulk`, `<Security/Security.h>`
declares these and the signing constants where the SDK does not. `SSLSetSessionTicketsEnabled`
succeeds in turning session tickets off, which 10.9's SecureTransport never uses, and reports
`errSecUnimplemented` for a request to turn them on, leaving the context unchanged; it is exported
but not declared, like the ALPN stubs. Newer macOS uses its own implementations.

## AppKit data

`librecaulk.a` defines `NSPasteboardTypeFileURL` (AppKit, 10.13) as `"public.file-url"`, the string
`kUTTypeFileURL` names on 10.9, using CoreFoundation only: linking it never loads AppKit. It is a data
symbol, so it is not forwarded: on 10.13 and later a program still gets Recaulk's copy, an equal string at
a different address from AppKit's. Compare it with `isEqual:` (or `CFEqual`), never `==`. Through
`include/recaulk`, `<AppKit/NSPasteboard.h>` declares it where the SDK does not.

The same way, it defines the appearance names `NSAppearanceNameVibrantDark` and `NSAppearanceNameVibrantLight`
(10.10), `NSAppearanceNameDarkAqua` and the four `NSAppearanceNameAccessibilityHighContrast` names (10.14), each
its own name as a string, as AppKit's are. 10.9 has none of those appearances, so `+[NSAppearance
appearanceNamed:]` still returns nil for each: a program can compare names with them, not draw with them.
`<AppKit/NSAppearance.h>` declares them. And it defines `NSEdgeInsetsZero` (10.10, Foundation's there), which
`<AppKit/NSLayoutConstraint.h>`, the 10.9 home of `NSEdgeInsets`, declares.

## Empty collection literals

A newer SDK's clang compiles `@{}` and `@[]` to the address of CoreFoundation's shared empty collections,
`___NSDictionary0__struct` and `___NSArray0__struct`, which 10.9's CoreFoundation lacks. `libRecaulkSystem.dylib`
defines both; `librecaulk.a` does not, since a member there may not run code at load
(`build/dylib-only-backfills.txt`), and a program built against the 10.9 SDK never references them. At load, a constructor builds in each an instance of the class 10.9's own
empty `NSDictionary` or `NSArray` has (`objc_constructInstance`), so each is an immutable empty collection that
nothing owns and nothing frees. A binary built against a newer SDK reaches them with Drydock:

```
import  redirect  ___NSDictionary0__struct  /System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation  /usr/local/mavergreen/recaulk/lib/libRecaulkSystem.dylib
```

They are data, so they are not forwarded: on newer macOS a program still gets Recaulk's empty collection, an
equal one at a different address from CoreFoundation's. Compare with `isEqual:` or `count`, never `==`.

## Core Graphics

`CGColorCreateSRGB` makes its color in the named `kCGColorSpaceSRGB` space, which 10.9 has, with
`CGColorCreate`. That space is not extended-range, so on 10.9 each component is kept within 0 to 1; whether
newer macOS's own `CGColorCreateSRGB` keeps an out-of-range component is not yet measured. Through
`include/recaulk`, `<CoreGraphics/CGColor.h>` declares it where the SDK does not. Newer macOS uses its
own implementation.

## Child processes

`posix_spawn_file_actions_addchdir_np` and `posix_spawn_file_actions_addfchdir_np` work on 10.9: the
child starts in the directory they name, and its program path and relative open actions resolve there.
Only the spawning thread's directory changes, and only during the spawn. On 10.9 every chdir action is
taken before the other file actions, wherever it was added among them. To carry them out, programs
linking `librecaulk.a` get Recaulk's `posix_spawn`, `posix_spawnp` and `posix_spawn_file_actions_init`,
`_destroy`, `_addopen`, `_adddup2`, `_addclose` and `_addinherit_np` in place of the system's, inside that program or dylib only; they call
the system's. Newer macOS uses its own chdir actions.

## Vector I/O at an offset

`preadv` and `pwritev` read and write at an offset without moving the file offset, as on macOS 11 and
later, which use their own. On 10.9, a transfer of several buffers over 1 MiB is not atomic: another
writer to the same range can interleave with it.

## Waiting with pselect

10.9's `pselect` sets the signal mask, calls `select`, then restores the mask, as three steps, so a signal
it unblocks that is already pending, or arrives before `select` starts, runs its handler and the wait then
sleeps on. Recaulk's `pselect`, all five of 10.9's symbols for it, never loses such a signal: it returns
`EINTR`, the handler run, as an atomic `pselect` does. Each thread keeps a kqueue that records every signal
posted to the process, from when the image loads (the main thread), the fork (a child) or its first wait
(any other thread); 10.11 and later use their own atomic `pselect`.

Limits on 10.9: a signal handled outside any wait can end the thread's next wait at once with `EINTR`; a
signal sent to one thread (`pthread_kill`) is no better covered than by 10.9's own; one that another
thread handles can end the wait with `EINTR`; one under way as a thread's first wait begins (the main thread's too, in a program linking
`librecaulk.a`: `libRecaulkSystem.dylib` registers it as it loads), or as a fork's child registers its
kqueue, is not seen; and a signal can end a wait a moment before its handler
runs, which it then does as the caller next unblocks it. xnu tells the kqueue of a signal before it picks
the thread that takes it, so in a program with other threads a wait that signal ends stays one it can be
delivered to for up to 10 ms more (ending as the handler runs); a signal xnu picks a thread for later than
that, with every other thread blocking it, waits on the first thread until that one unblocks it. Where no kqueue can be had (descriptors or
memory exhausted), a wait falls back to 10.9's own `pselect` rather than fail. A program may close the
kqueue's descriptor, as sshd's `closefrom` does: the next wait notices and registers another. Callers
already loop on `EINTR`. `librecaulk.a` must come before libSystem in the link, as clang
puts it; after libSystem, libSystem's `pselect` binds instead.

## Closing a socket

`close` and `dup2` never hang on a socket another thread is entering a `read`, `accept` or `recv` on.
10.9's can wait for seconds, or for ever: closing a descriptor in use wakes its users and waits for them to
leave, and a thread that took the descriptor but had not yet gone to sleep misses that wakeup. Its kernel
looks again only when some other descriptor in the process is released. So while a close or `dup2` of a socket
is under way, Recaulk keeps a helper thread releasing a descriptor of its own (it makes and closes a kqueue)
every 200 microseconds after the first millisecond, and after a second every 10 ms, until the close returns.
The helper starts at the first such close, which should not be one in a signal handler. Any other descriptor
costs one `fstat`. This applies on every macOS: macOS 11's `accept` has the same window.

No header renames `close` or `dup2` (a macro would rename C++'s `stream.close()` too), so a program reaches
Recaulk's by link order: `librecaulk.a` ahead of libSystem, as clang22 links. `tests/socket-close-race.sh`
holds both products to this.

## Floating point

`fma` and `fmal` round `a*b+c` once, in the current rounding mode, as C requires; 10.9's do not.
Its `fma` gets the sign wrong when the product and the addend nearly cancel (`fma(1+ε, ε-1, 1)` is
`-ε²`, not `ε²`), and its `fmal` misrounds in the directed modes and near the denormals, overflows
whenever the product alone would, and loses products too small to be a denormal. `truncl` keeps the
sign of a zero result: 10.9's, given a value between -1 and 1, takes the sign of its zero from whatever
its caller left in a register, so `truncl(-0.5)` can be `+0` and `truncl(0.5)` `-0`. `fmaf`, `trunc` and
`truncf` are 10.9's own, which are right.

Recaulk's three are used on every macOS, not only 10.9: Apple's published Libm source ends with 10.9's,
and no later x86_64 macOS has been tested, so no version is known to be right. `fma` uses the CPU's FMA
instruction, one correct rounding by definition, wherever the CPU has it and the OS saves the AVX state
it needs; elsewhere, 10.9's own Macs among them, it computes in software. `fmal` and `truncl` compute in
software everywhere. `fma` and `fmal` raise inexact, underflow (a tiny result, judged after rounding, as
x86 does), overflow and invalid as IEEE 754 does; `truncl` raises nothing.

## Compiler builtins

`__extendhfsf2` and `__truncsfhf2`, which clang calls to widen and narrow a `_Float16`, convert exactly,
rounding to nearest, ties to even. They are compiler-rt's, which 10.9's libSystem predates. Recaulk's are
weak and not forwarded, so a program that brings its own compiler-rt (Zig's `compiler_rt.c.o`) links with
`librecaulk.a` in either order, and its own win.

## Queue assertions

`dispatch_assert_queue`, as the `dispatch_assert_queue$V2` a modern SDK binds (Swift's
`MainActor.assumeIsolated` and `preconditionIsolated` call it), is the system's on 10.12 and later. On
10.9 to 10.11 Recaulk's returns when the calling thread is running a block for the queue or for a queue
that targets it, and for the main queue whenever it is called on the main thread. It traps, with
libdispatch's message, only when the thread is provably off the queue:

- a thread other than the main thread that is running no dispatch block at all (a thread of its own); or
- the queue is the main queue, the thread is not the main thread, and the main thread is still running,
  so the main queue can only run there.

Everywhere else it returns. 10.9's libdispatch shows a thread only the innermost queue it is running a
block for. The queue that called `dispatch_sync` or `dispatch_apply` is hidden, and the newer system counts
it as one the thread is on. So a thread running a block for some other queue may still be on the asserted
one, and Recaulk returns rather than trap falsely. That covers:

- the main thread asserting any queue but the main queue, inside a main-queue block or outside any block:
  10.9 reports the main queue as the main thread's current queue in both, so it cannot tell either from a
  main-queue block running inside a `dispatch_sync` to the asserted queue;
- any other thread asserting a queue while it runs a block of an unrelated queue;
- asserting the main queue off the main thread once `dispatch_main` has ended the main thread.

10.12 and later trap in each of these when the thread is in fact off the queue. To see a queue's place in a
thread's queues, Recaulk sets one queue-specific value of its own on each queue it is asked about and on
the default overcommit root queue.

## Dispatch on 10.9

The libdispatch calls 10.10 to 10.12 added, as Recaulk gives them on 10.9 (the system's own on a later macOS):

- `dispatch_get_global_queue` given a QoS class returns the global queue of the priority 10.10's `queue.h` pairs it
  with: user-interactive and user-initiated the high-priority queue, default the default one, utility the
  low-priority one, background the background one. 10.9's returns NULL for a class. It is a fix to a function 10.9
  has (see "Fixes to functions 10.9 has"): `<dispatch/dispatch.h>` binds a program built from source to it by asm
  label, whatever its link order, and `libRecaulkSystem.dylib` exports it for a program relinked onto it.
- `DISPATCH_APPLY_AUTO` (10.12) names the default-priority global queue, since 10.9's `dispatch_apply` needs a
  real queue; 10.12's chooses one by the caller's QoS. `dispatch_queue_global_t` (10.12) is `dispatch_queue_t`.
  Both are header-only.
- `dispatch_queue_attr_make_initially_inactive` gives an attribute with which `dispatch_queue_create` (and
  `dispatch_queue_create_with_target`, `dispatch_workloop_create_inactive`) creates the queue suspended.
  The attribute is an Objective-C object, as the system's are, so Swift and ARC code can retain and release it.
  It is a dispatch object every copy of Recaulk in the process shares. Recaulk makes no class for it, so Drydock's
  strict guard has nothing it cannot model; attributes from earlier Recaulks are still honoured.
  `dispatch_activate` starts such a queue, and a source, once; a second call, or a call on any other object,
  does nothing, as on 10.12. A `dispatch_resume` of such a queue or source is its activation, so a
  `dispatch_activate` after it does nothing too. A source suspended and resumed before it ever started counts as
  started: 10.9 cannot tell the two apart. `dispatch_queue_create` and `dispatch_resume` are fixes to functions
  10.9 has, bound as `dispatch_get_global_queue` is.
- `dispatch_queue_create_with_target` sets the target queue it is given.
- `dispatch_queue_attr_make_with_qos_class` keeps the class and relative priority on the attribute, with its
  inactivity and concurrency in either order, and `dispatch_queue_get_qos_class` reports them for a queue made from
  it; any other queue reports `QOS_CLASS_UNSPECIFIED` and 0. On 10.9 the class schedules nothing: 10.9 has none.
  On 10.10 and 10.11, where the system has QoS but not inactivity, `dispatch_queue_attr_make_with_qos_class` is
  Recaulk's, applying the system's to the attribute the queue is made from, so each keeps what the other set.
  Recaulk's attributes are interned: the same settings give the same object, in every copy of Recaulk.
- `dispatch_queue_attr_make_with_autorelease_frequency` returns the attribute it is given: 10.9's queues drain no
  autorelease pool of their own.
- `dispatch_assert_queue_not` traps, with libdispatch's message, only where the thread is provably on the queue
  (running a block for it or for a queue that targets it, or on the main thread for the main queue), and returns
  where 10.9 cannot tell, the converse of `dispatch_assert_queue` (see "Queue assertions").
- `dispatch_assert_queue_barrier` is `dispatch_assert_queue`: 10.9 cannot tell a barrier block of a concurrent
  queue from any other.
- `dispatch_block_wait` and `dispatch_block_notify` work on a block `dispatch_block_create` made: a wait returns 0
  once the block has finished and non-zero when its timeout passes first; a notification is submitted once it has
  finished, at once if it already has. A cancelled block that has not begun does nothing when it runs, and
  finishes then. A block released without running never notifies, as with libdispatch.
- A block's cancelled and finished state is shared by every copy of Recaulk in the process -- a program's own and
  one a library such as Swift's Dispatch links -- from release 20261120 on: a copy from before then sees only
  the blocks it made.

`<dispatch/dispatch.h>` declares them, `dispatch_queue_create_with_target` and the assertions with the `$V2` labels
the 11.3 SDK gives them, and `dispatch_block_flags_t` as its flag enum.

## Swift's Dispatch

Swift's Dispatch overlay wants dispatch's objects as classes (`DispatchQueue`, `DispatchGroup` and the rest), and
the 10.9 SDK declares them as protocol types. So under `__swift__` (Swift's importer, never C or Objective-C),
`<dispatch/dispatch.h>` declares them as the 11.3 SDK does under `OS_OBJECT_SWIFT3`: `OS_object : NSObject`,
`OS_dispatch_object : OS_object`, each dispatch type a subclass of `OS_dispatch_object` except `OS_dispatch_data`,
an `NSObject`. They are `objc_runtime_visible` declarations of the classes 10.9's libdispatch already registers,
whose ancestry matches (`tests/dispatch-swift-classes.sh` checks it on 10.9); nothing new is defined.
`dispatch_retain` and `dispatch_release` stay functions, as 11.3 has them for Swift. The source class adopts
11.3's per-type protocols (`OS_dispatch_source_timer` and the rest) in the declarations only: 10.9's runtime has
none of them, so in Swift a static upcast to `DispatchSourceTimer` works and a dynamic `as?` does not.

With a newer SDK, which declares the classes itself, nothing is added.

## The kernel back-fill kext

`RecaulkKPI.kext` (`dev.mavergreen.recaulk.kpi`) is a library kext for 10.9. It supplies the 7 kernel
functions macFUSE 5.5.0's kext imports and 10.9's public KPIs lack:

- `__memcpy_chk` and `__strncpy_chk`: panic when the copy is longer than its destination, as macOS 12 does.
- `ubc_upl_map_range`, `buf_map_range` and `buf_unmap_range`, over 10.9's `ubc_upl_map`, `buf_map` and
  `buf_unmap`. Each returns the address of the same byte as on macOS 12. Two deviations: `ubc_upl_map_range` maps
  the whole UPL, ignoring `size`, and always maps it read-write, ignoring `prot`.
- `vfs_get_notify_attributes`, reimplemented.
- `vnode_notify`. 10.9's kernel has it, but exports it only to Apple's kexts. Recaulk's forwards to the
  kernel's own function. On its first call, once root is mounted, a kernel thread of its own finds that function
  in `/mach_kernel`'s symbol table, so the caller's sandbox or chroot cannot decide the outcome. It accepts the result only when three other symbols agree on the KASLR slide, and the running
  kernel's UUID matches the file's. If any check fails, it delivers nothing and returns 0, so kqueue and
  FSEvents see no change.

Its log lines, through the kernel's `printf`, begin `RecaulkKPI: `. A consumer may test for them:

- `vnode_notify: forwarding to kernel ...` once the first call has resolved the kernel's function;
- `vnode_notify: FALLBACK, delivering nothing (<reason>, error <n>)` when it could not;
- `not starting: this kernel is Darwin <n> ...` on anything but 10.9.

The kext starts only on Darwin 13 (10.9). Elsewhere it refuses to start, because macOS 12 and later export these
functions themselves. `debug.recaulk_kpi.vnode_notify_forwarded` counts forwarded calls.

What a consumer relies on is the bundle id, `OSBundleCompatibleVersion` 1.0.0 (kept while the 7 signatures
hold) and its dependence only on `com.apple.kpi.bsd`, `com.apple.kpi.libkern` and `com.apple.kpi.mach` 13.0.0. `CFBundleVersion`
is the release, as `YYMM.DD.N`: `OSKext` parses at most 4, 2 and 2 digits, and that order matches the releases'.

Recaulk's pkg installs it at `/Library/Extensions/RecaulkKPI.kext`, root:wheel, and its postinstall runs
`kextcache -system-caches` on the boot volume, so a consumer's first load is immediate. Uninstalling Recaulk
removes it; a kext that depends on it then fails to load.

`sh build/build-kext.sh OUT` compiles it with clang22 and links it on any host. The kernel's loader on 10.9
accepts only `MH_KEXT_BUNDLE`, which needs ld64's `-kext`: clang22's lld writes no such file. So the link uses
Mavergreen cctools' ld64, pinned in `components/cctools/version` and fetched into `OUT/tools`; `RECAULK_KEXT_LD`
names another. Two builds are byte-identical, `LC_UUID` included.

## The kernel-fixes kext

`RecaulkKernelFixes.kext` (`dev.mavergreen.recaulk.kernelfixes`) fixes panics in the 10.9.5 kernel. It fixes
exactly one kernel, 13F1911 (xnu-2422.115.15, `LC_UUID` 8926E512-6714-34FC-B27C-6AE90EB51D5E), the last 10.9.5
security update. On any other 10.9 kernel it applies nothing and logs `no fixes for this kernel (UUID <hex>)`.
On any other Darwin it refuses to start.

It finds each site through `/mach_kernel`'s symbol table, read on a kernel thread of its own. It trusts the
result only when the live addresses of `printf` and `panic` agree on the KASLR slide and the running kernel's
UUID matches the file's. It writes only over the bytes it expects, with every CPU parked in a rendezvous, and
`CR0.WP` lifted only for the write.

### Its fixes

- **`kqueue_scan_restart`**: `kqueue_scan_continue` panics `invalid wait_result (3)` when a `kevent` wait ends
  `THREAD_RESTART` (`bsd/kern/kern_event.c`, line 2167 in 13F1911). Chromium Legacy's helpers hit it
  (blueboxd/chromium-legacy#44). The fix returns `EBADF` instead, as 10.12 and later do. The program that called
  `kevent` sees `EBADF` and must cope with it: Chromium treats it as fatal, so the helper exits where the kernel
  used to panic (blueboxd/chromium-legacy#44, comment 1066959291). This fix is ported from Wowfunhappy's KQueueScanContinuePatch,
  made with krackers and declared CC-0 (gist 8212f5bea4c601ac9a6297789f232321, comment 6488041). With
  `wait_result_prepost` applied it should never fire, so it is a backstop: where the kernel would have panicked it
  prints the panic's own message, `"kqueue_scan_continue: - invalid wait_result (3)"@...kern_event.c:2167` (with no
  newline, so the system log joins it to the line after), and returns `EBADF`. His kext's silent replacement counts
  as this fix already applied.
- **`wait_result_prepost`**: the cause of that panic. `wait_queue_assert_wait64_locked` returns `THREAD_AWAKENED`
  for a wait queue set that already has a post, without storing it in the thread's `wait_result`
  (`osfmk/kern/wait_queue.c`, line 1199). `kqueue_scan` ignores the return and blocks; `thread_block`, finding
  the thread still runnable, runs `kqueue_scan_continue` with whatever the thread's previous wait left there. A
  leftover `THREAD_RESTART` (a Mach receive on a port another thread destroyed) is the panic above; a leftover
  `THREAD_TIMED_OUT` makes a `kevent` with no timeout return 0 events, and `THREAD_INTERRUPTED` makes it fail
  `EINTR`, with no signal. It takes a kqueue watching a Mach port set (`EVFILT_MACHPORT`) whose message lands
  while `kevent` is between its scan and its wait. The fix stores `THREAD_AWAKENED` before returning it, as 10.10
  does (xnu-2782.1.97). The function has no symbol, so the site is `_wait_queue_set_unlink_one+0x13e`; the 43
  bytes it rewrites test the same bits, in one comparison, to make room for the store. Found by Wowfunhappy and
  krackers (gist 8212f5bea4c601ac9a6297789f232321, comment 6490893). `tests/kfix-wait-result-kit.sh` builds the
  kit that proves it on a disposable guest: the bug reproduced without the fix, the panic turned to `EBADF` by
  the backstop alone, and neither with both. Its silent race needs no privileges: on a 12-core 10.9.5 Mac with
  only the backstop, about 25 of 14,600 untimed `kevent`s in 20 seconds returned 0 events.
- **`signal_target_exit`**: `psignal_internal` picks a thread to signal without a reference, then calls
  `thread_abort_safely` on it (`bsd/kern/kern_sig.c`). If the thread exits and is freed in between, the
  kernel panics `trying to interlock destroyed mutex`. It takes a thread asleep in the kernel, picked for a
  signal (say, a child's `SIGCHLD`) just as another thread's `exit` tears the process down; Go programs such as
  `docker`, run often, hit it every few days. The fix makes an exiting thread wait out any signal in
  flight to its process before its state is torn down. It hooks the one call to `uthread_cleanup` in
  `thread_terminate_self`: the call is retargeted, in one store, to a jump placed in the unused padding before
  `timer_call_init`. A thread in `vfork`, the one its child's signals pick, also waits out the child's. If
  DTrace's fbt could mistake a byte of that jump for a function return, which depends on where the kext lands,
  it refuses with a reason, and loading it again places it elsewhere.

### Reading and controlling it

Its log lines begin `RecaulkKernelFixes: `:

- `<fix>: applied`;
- `<fix>: already applied (by another kext)`;
- `<fix>: refused (<reason>)`;
- `<fix>: disabled (boot-arg)`;
- `no fixes for this kernel (UUID <hex>)`;
- `not starting: this kernel is Darwin <n> ...`.

`sysctl debug.recaulk_kfix.<fix>` reports each fix (`kqueue_scan_restart`, `wait_result_prepost`,
`signal_target_exit`): 0 not applied, 1 applied, and 2 applied by another kext (`kqueue_scan_restart` only).

The boot-arg `recaulk_kfix=0` turns every fix off. `recaulk_kfix=-<fix>[,-<fix>]` turns off the fixes named.
A Safe Boot (hold Shift) never loads it, and if something loads it anyway it applies nothing.

Once it has applied a fix it refuses to unload, because the kernel's patched code depends on it. Uninstalling
Recaulk removes it, and the kernel is unpatched at the next boot.

### Installation

Recaulk's pkg installs it at `/Library/Extensions/RecaulkKernelFixes.kext`. The LaunchDaemon
`dev.mavergreen.recaulk.kernelfixes` loads it at every boot, except a Safe Boot. On the boot volume the
postinstall loads that daemon at once. The postinstall also retires Wowfunhappy's KQueueScanContinuePatch: it
unloads `wowfunhappy.KQueueScanContinuePatch-loader` and removes that daemon and
`/Library/Extensions/KQueueScanContinuePatch.kext`. A kernel his kext already patched stays patched until
reboot, and RecaulkKernelFixes reports that fix as state 2 meanwhile.

10.9 loads an unsigned kext from `/Library/Extensions` only when its bundle id is in `OSKextSigExceptionList`, in
`/System/Library/Extensions/AppleKextExcludeList.kext/Contents/Info.plist`. Otherwise kextd logs `invalid
signature ... will not load`, unless the Mac boots with `kext-dev-mode=1`. So the package declares
`dev.mavergreen.recaulk.kernelfixes` with shipyard's `stage_product.sh --boot-kext`: shipyard's postinstall adds it
there at the installed version and restarts kextd so it reads the list again, and uninstalling Recaulk removes the
entry. This is Wowfunhappy's mechanism (gist ee66f57e5e7a04e42a7a5e2b98a10874).

`KEXT_SRC=src/kfix KEXT_NAME=RecaulkKernelFixes sh build/build-kext.sh OUT` builds it like RecaulkKPI.
`tests/kfix-engine-test.sh` checks the engine on synthetic bytes, and on 13F1911 checks the pinned sites in
`/mach_kernel` by reading the file. `tests/kfix-runtime-test.sh` loads the kext on the disposable 10.9.5 guest
only. There it checks that all three fixes apply, `kevent` still works, and the kext refuses to unload. For
`signal_target_exit` it loads a test-only kext, `tests/kext/widen`, that delays the abort 5 ms, then classifies the
thread it would abort and skips the abort if that thread is already freed; `tests/c/kfix_exit_race.c`, the race's minimal shape, then makes 200 such
picks. Unfixed, most picked threads are already freed (182 of 200 on 13F1911); fixed, none are. It needs two or more CPUs: on one,
the exiting thread is never freed in the window, so an unfixed kernel would pass too. In its mode 1 the
widener calls through, and an unfixed kernel panics within seconds, the same panic as the field's; that check
is run by hand, never in CI. `RECAULK_KFIX_ROUND=foreign`, on a fresh boot, also
checks that a kernel with another UUID gets no fixes, and that the kext stands down after Wowfunhappy's kext.

## Licences

Recaulk's own code is under the ISC licence in `LICENSE`. Some MacPorts members of `librecaulk.a` are
built from Apple sources under the Apple Public Source License 2.0, whose section 2.3 asks object code
to say, in the code itself, where its source is. Each such member carries that notice as a string in
the section `__TEXT,__recaulk_apsl`, under a local symbol, `_recaulk_apsl_notice`. Nothing exports
it, and `-dead_strip` keeps it whenever the member is linked. `libRecaulkSystem.dylib` carries every
member's notice. MacPorts' sources stay unmodified: the build compiles those members a second time,
with a header holding the notice. A member is Apple-derived when anything clang22 reads to compile it,
other than the SDK and the compiler's own headers, carries Apple's licence mark. Any such licence other
than APSL 2.0, or a file the build cannot read, stops the build until its notice is decided.
`build/apsl-declaration-only.txt` exempts MacPorts headers that hold declarations only, each at the
sha256 it was reviewed at, so a changed one counts again.

`share/recaulk/notices.tsv` lists the notices, one tab-separated line per artifact and member:
artifact (`librecaulk.a` or `libRecaulkSystem.dylib`), member, licence, the Apple-licensed files,
their Apple copyright lines (not their other authors'), those files' URLs at the pinned MacPorts commit, and the notice text. Lines
starting `#` are comments. Each release attaches the same file as `recaulk-notices.tsv`. A consumer
that links `librecaulk.a` can take the members its link pulls in (ld64's `-why_load`, or the
`__recaulk_apsl` strings in its output) and assemble its own NOTICE from those lines.

`src/kfix/kqueue_scan_restart.c` is ported from Wowfunhappy's KQueueScanContinuePatch, which he declared CC-0
(`src/kfix/NOTICE.md`). `tests/kext/wowfunhappy/` holds an unchanged copy of it, which the guest test builds.

## SDK declaration metadata

`share/sdk-metadata/recipes.json` is data, not code: recipes that let an Objective-C target built
against the pinned 10.9 SDK see declarations a later SDK added, without changing the SDK. Recaulk owns
what each recipe means; shipyard's `MavericksSDKMetadata.cmake` checks a recipe against the SDK's bytes,
writes the edited headers to a scratch overlay, and opts one target into it; `recaulk-materialize` (below) does
the same without CMake. Nothing here is linked.

The file is one JSON object, schema 1:

- `schema` (`1`), `sdk` (`MacOSX10.9`) and `sdk_archive_sha256`, the SHA-256 of the SDK archive the
  recipes were written against.
- `recipes`, each with a unique `id` (lowercase letters, digits, `.` and `-`; a changed recipe takes a new
  id), the SDK-relative `header` and its exact `sha256`, `aliases` (other SDK-relative paths that reach the
  same header, such as a framework's `Headers` link) and `replacements`, `{old, new}` pairs of literal text.
  Each `old` must occur exactly once in the header; shipyard refuses the recipe otherwise.

`foundation-array-generics-v1` gives `NSArray` and `NSMutableArray` their lightweight generic
parameters, so `NSArray<NSString *> *` compiles against the 10.9 SDK. It adds no method signatures and
no other classes. The other Foundation recipes do the same, one header each, with the type parameters
the 10.11 SDK declares:

- `foundation-dictionary-generics-v1`: `NSDictionary<KeyType, ObjectType>` and `NSMutableDictionary`;
- `foundation-set-generics-v1`: `NSSet`, `NSMutableSet` and `NSCountedSet`;
- `foundation-orderedset-generics-v1`: `NSOrderedSet` and `NSMutableOrderedSet`;
- `foundation-maptable-generics-v1`: `NSMapTable<KeyType, ObjectType>`;
- `foundation-enumerator-generics-v1`: `NSEnumerator`;
- `foundation-directoryenumerator-generics-v1`: `NSDirectoryEnumerator` (with the enumerator recipe).

`foundation-objcruntime-macros-v1` defines, where the SDK does not, `NS_DESIGNATED_INITIALIZER` and
`NS_ASSUME_NONNULL_BEGIN`/`END` as the 10.10 and 10.11 SDKs do. These are compile-time annotations: the
compiler checks with them and emits the same code.

`foundation-objcruntime-macros-v2` is v1 plus the annotations the 10.11 to 10.13 SDKs added to the same header:
`NS_NOESCAPE`, `NS_SWIFT_NAME`, `NS_SWIFT_UNAVAILABLE`, `NS_REFINED_FOR_SWIFT`, `NS_SWIFT_NOTHROW`, and
`NS_STRING_ENUM`, `NS_EXTENSIBLE_STRING_ENUM`, `NS_TYPED_ENUM` and `NS_TYPED_EXTENSIBLE_ENUM`, each the attribute
those SDKs use where clang has it. A target selects one or the other.

`corefoundation-availability-v1` adds the availability spellings later SDKs use, as attributes clang checks
the same way: `__NSi_` and `__NSd_` for 10.10 to 10.15 and their point releases (behind
`NS_AVAILABLE_MAC`, `NS_CLASS_AVAILABLE`, `NS_ENUM_AVAILABLE_MAC` and `NS_DEPRECATED_MAC`), and
`API_AVAILABLE`, `API_UNAVAILABLE`, `API_DEPRECATED` and `API_DEPRECATED_WITH_REPLACEMENT` for up to six
platforms each. Like the SDK's own, they make a use of something newer than the deployment target a warning
(`-Wunguarded-availability`) and its reference weak; they supply nothing at run time. A file that includes
`<os/availability.h>` itself still finds no such header on 10.9's SDK.

`foundation-array-generics-v2` is `foundation-array-generics-v1` plus element-typed `objectAtIndex:`,
`firstObject`, `lastObject` and subscripting, as the 10.11 SDK declares them, so `array.lastObject.name`
compiles. It edits the same header, so a target selects one or the other.

The AppKit recipes re-declare as properties the accessors the 10.10 SDK turned into properties
(`NSView.hidden`, `NSControl.enabled` and `continuous`, `NSCell.highlighted`, `NSTextField.editable`,
`bordered` and `selectable`, `NSWindowController.windowLoaded`). Each uses the 10.9 method as its getter,
so the code compiled is the same. They also add the newer names of existing constants and types
(`NSTextAlignmentRight`, `NSRectEdgeMinY`, `NSWindowStyleMask`) and the `NSSearchFieldDelegate`
protocol.

The 10.12 SDK renamed many AppKit constants; these recipes add the new names with the 10.9 values, so the
code compiled is the same:

- `appkit-event-v2`: `appkit-event-stage-v1` plus `NSEventType*`, `NSEventMask*` (with `NSEventMaskAny`),
  `NSEventModifierFlags` and `NSEventModifierFlag*`;
- `appkit-window-v2`: `appkit-window-v1` plus `NSWindowStyleMask*`, including the panel masks, and
  `NSWindowTabbingMode` with `tabbingMode` at its 10.12 availability (a caller checks
  `respondsToSelector:@selector(setTabbingMode:)` first);
- `appkit-window-v3`: `appkit-window-v2` plus `NSWindowCollectionBehaviorFullScreenNone` (`1 << 9`), which
  later SDKs give 10.7 and 10.9's omits;
- `appkit-window-v4`: `appkit-window-v3` plus the 10.12 typedef `NSWindowLevel` (`NSInteger`), `isVisible`
  as `@property (readonly, getter=isVisible) BOOL visible`, and `sheetParent` as a readonly property (`assign`,
  where 11.3 says `weak`, since 10.9 consumers build without ARC);
- `appkit-alert-v2`: `appkit-alert-style-v1` plus `-[NSAlert window]` typed `NSWindow *`, so `[sender window]` on
  an `id` is an `NSWindow`;
- `appkit-textattachment-v1`: 10.11's `NSTextAttachment` `image` property, marked 10.11, so each use needs a
  guard; 10.9 has no such accessor;
- `appkit-tabview-v1`: `tabViewItems` as 10.11's `NSArray<__kindof NSTabViewItem *>` property; select it with
  `foundation-array-v3` (or the `swift-foundation` profile), which makes `NSArray` generic;
- `appkit-application-v1`: `NSApp` typed `NSApplication *`, as later SDKs type it, so `NSApp.keyWindow` compiles;
- `appkit-tabviewitem-v1`: `-[NSTabViewItem view]` typed `NSView *`;
- `appkit-nib-v1`: the 10.12 typedef `NSNibName` (`NSString *`);
- `appkit-accessibility-v4`: `appkit-accessibility-v3` plus the 10.12 typedef `NSAccessibilityRole` (`NSString *`);
- `appkit-attributedstring-v1`: the 10.11 typedef `NSUnderlineStyle` (`NSInteger`) and `NSUnderlineByWord`
  (`0x8000`, the value of 10.9's variable `NSUnderlineByWordMask`);
- `appkit-cell-properties-v2`: `appkit-cell-properties-v1` plus `NSControlSize*`;
- `appkit-cell-properties-v3`: `appkit-cell-properties-v2` plus the 10.14 names `NSBackgroundStyleNormal` and
  `NSBackgroundStyleEmphasized` (10.9's `Light` and `Dark`);
- `appkit-cell-properties-v4`: `appkit-cell-properties-v3` plus the accessibility properties below;
- `appkit-cell-properties-v5`: `appkit-cell-properties-v4` plus the 10.13 names `NSControlStateValue`,
  `NSControlStateValueOff`, `NSControlStateValueOn` and `NSControlStateValueMixed` (10.9's `NSOffState` and kin);
- `appkit-view-properties-v2`: `appkit-view-properties-v1` plus the accessibility properties below;
- `appkit-view-v3`: `appkit-view-properties-v2` plus 10.10's `NSVisualEffectView`, declared in `NSView.h`
  because 10.9 has no `NSVisualEffectView.h`. It includes its material, blending-mode and state enums, with
  the 10.11 and 10.14 materials marked as such, and `allowsVibrancy`. 10.9 has no such class, so references to
  it are weak: check `[NSVisualEffectView class]` before using it. `allowsVibrancy` is declared on the class,
  not on `NSView` as 10.10 has it, because 10.9's `NSView` does not answer it. It also adds the 10.12 typedef
  `NSAutoresizingMaskOptions` (`NSUInteger`);
- `appkit-control-v2`: `appkit-control-properties-v1` and `appkit-control-single-line-v1` together;
- `appkit-compositing-v1`: `NSCompositingOperation*`;
- `appkit-alert-style-v1`: `NSAlertStyle*`;
- `appkit-buttoncell-names-v1`: `NSButtonType*` and `NSBezelStyle*`, as members of their enumerations, so
  they keep the enumeration's type.

Each later version edits the same header as the ones before it and includes them, so a target selects one.

`appkit-accessibility-protocols-v1` declares the 10.10 role protocols (`NSAccessibilityElement`,
`NSAccessibilityGroup`, `NSAccessibilityButton`, `NSAccessibilitySwitch`, `NSAccessibilityRadioButton`,
`NSAccessibilityCheckBox`, `NSAccessibilityStaticText` and `NSAccessibilityNavigableStaticText`), so a class can
declare that it adopts them. They are compile-time only: 10.9's accessibility never asks through them, so a class
must still answer through `accessibilityAttributeValue:` and its kin to be accessible on 10.9.
`appkit-accessibility-v2` is v1 plus the 10.10 `NSAccessibilityElement` class, weak-imported: on 10.9 the class
is nil, so a caller checks `[NSAccessibilityElement class]` first, and a subclass of it does not load there.
`appkit-accessibility-v3`, `appkit-view-properties-v2` and `appkit-cell-properties-v4` declare 10.10's
`accessibilityLabel`, `accessibilityRole` and `accessibilityChildren` properties on `NSAccessibilityElement`, `NSView`
and `NSCell`. 10.9 has no such methods: a subclass's override compiles and runs where it is called, but calling
`super`'s, or setting one on a plain view or cell, needs `respondsToSelector:` first on 10.9.

`appkit-viewcontroller-lifecycle-v1` declares `NSViewController`'s 10.10 lifecycle methods (`viewDidLoad`,
`viewWillAppear`, `viewDidAppear`, `viewWillDisappear`, `viewDidDisappear`, `viewWillLayout` and `viewDidLayout`)
at their availability, so an override that calls `super` compiles. Nothing provides them on 10.9, whose AppKit
never sends them: an override there never runs, so work it does must also be reached another way on 10.9.
`appkit-viewcontroller-v2` is `appkit-titlebar-accessory-v1` and `appkit-viewcontroller-lifecycle-v1` together,
for a target that needs both. `appkit-control-single-line-v1` declares `NSControl`'s `usesSingleLineMode` (10.10),
which `librecaulk-objc.a`'s AppKit root provides. `appkit-color-separator-v1` declares `+[NSColor separatorColor]`
at 10.14: nothing provides it on 10.9, so a caller checks `@available` first. `appkit-appearance-name-v1` and
`appkit-menuitem-identifier-v1` declare `NSAppearance`'s `name` and `NSMenuItem`'s `identifier` as properties: 10.9
answers both, and its SDK does not declare them. `appkit-tablecolumn-title-v1` declares `NSTableColumn`'s `title`
(10.10), which `librecaulk-objc.a`'s AppKit root provides. `appkit-appearance-name-v2` is `appkit-appearance-name-v1`
with `-[NSAppearance bestMatchFromAppearancesWithNames:]` at 10.14, which nothing provides on 10.9.
`appkit-window-v5` (in the `swift-appkit` profile) declares `NSWindow`'s `titlebarAppearsTransparent` with no
availability, as `librecaulk-objc.a`'s AppKit root provides it.

`foundation-filemanager-keys-v1` adds the 10.12 typedefs `NSFileAttributeKey` and `NSFileAttributeType`
(`NSString *`); `foundation-filemanager-v2` is it and `foundation-directoryenumerator-generics-v1` together.
`foundation-kvo-change-key-v1` adds the 10.12 typedef `NSKeyValueChangeKey` and gives the change dictionary's
keys that type; `foundation-attributed-string-key-v1` adds 10.13's `NSAttributedStringKey` the same way.
`foundation-url-file-url-v1` declares `NSURL`'s `fileURL` property, whose getter is 10.9's `isFileURL`.
`foundation-filecoordinator-v1` adds `NSFileCoordinatorReadingImmediatelyAvailableMetadataOnly`
and `NSFileCoordinatorReadingForUploading` at their 10.10 availability; 10.9's `NSFileCoordinator` does not know
them, so a caller checks `@available` first.

APIs 10.9 does not have at all are declared with their availability, so references to them are weak
and a binary using them still loads on 10.9. A caller must check that they exist before using them:
`NSEvent.stage`, `NSTextField.placeholderString`, `NSTitlebarAccessoryViewController` and
`-[NSWindow addTitlebarAccessoryViewController:]` (`appkit-*`), the WebKit2 classes a caller looks up at
run time (`webkit-wkwebview-v1`), and `LSCopyDefaultApplicationURLForURL`
(`launchservices-default-app-v1`). Linking such a reference needs the linker told that the symbol may
stay undefined, since 10.9's frameworks do not export it.

`foundation-string-contains-v1` declares the two `NSString` methods with their 10.10 availability, which
that root provides on 10.9.

`foundation-locale-codes-v1` declares `NSLocale`'s `languageCode` and `countryCode` with their 10.12
availability; `librecaulk-objc.a`'s Foundation root provides them on 10.9 (see Objective-C methods).

`foundation-processinfo-version-v1` declares `NSOperatingSystemVersion`, `-[NSProcessInfo
operatingSystemVersion]` and `-isOperatingSystemAtLeastVersion:` plainly, with no availability and no
back-fill: the 10.10 SDK was the first to declare them, but 10.9.5's Foundation already implements both,
which `tests/foundation-os-version-test.sh` holds it to.

`launchservices-default-app-v2` declares `LSCopyDefaultApplicationURLForURL` plainly instead, with no
availability: Recaulk back-fills it in `librecaulk.a`, which clang22 links into every program, so callers
need no presence check and the reference is an ordinary one. v1's comment told callers to check first;
v1 stays for the consumers that pinned it, and new ones use v2.

`tests/sdk-metadata-compile.sh` proves each recipe with its probe in `tests/fixtures/sdk-probes/<id>.m`:
the probe compiles with `-Werror` through the recipe's overlay, made by shipyard's own module, and fails
to compile without it. A probe's `// weak:` symbols must be weak references in its object file. A
`// ast: FILTER REGEX` line proves what compiling cannot, such as a getter redeclared as a property or a
bridged CF type. The line holds when clang's AST dump of the declarations named FILTER matches REGEX
through the overlay but not on the SDK alone. A probe with such lines may compile without its recipe. The
probes run `SDK_METADATA_JOBS` at a time (4 by default), and `SDK_METADATA_ONLY` names the ids to run
(`consumer` names the consumer probes). A consumer probe in `tests/fixtures/sdk-probes-consumer/` names a
profile (`// profile: NAME`) and compiles with `-Werror -Wall` through that whole profile, the way an
Objective-C consumer selecting it would.

`build/stage-sdk-metadata.sh` validates the file (`build/sdk-metadata-validate.cmake`, through
`shipyard-cmake -P`) and stages it, with `profiles.json` (below); malformed data stages nothing.

### Profiles

`share/sdk-metadata/profiles.json` names fixed sets of recipe ids. A toolchain and every client of what it
builds must see the same SDK view, so they select a profile by name instead of picking recipes one by one:

```json
{"schema": 1, "profiles": {"swift-foundation": {"description": "...", "recipes": ["foundation-url-v2", "..."]}}}
```

Every id in a profile is in `recipes.json`, and no two of them edit one header; staging refuses anything
else (`build/sdk-metadata-profiles-validate.cmake`). A profile's list is fixed for a Recaulk version. A
consumer that also selects recipes of its own may select only recipes on headers the profile does not touch.
If it needs more on such a header, it asks for a v-next of the profile's recipe.

A profile may name a `base`: another profile whose every recipe id it carries too, as `swift-appkit` does
`swift-foundation`. Staging refuses a base that is not a profile, a chain of bases that loops, and a profile
missing any of its base's ids, and `recaulk-materialize` checks the same before it reads the SDK, so a client of
the larger view always sees the smaller one's headers unchanged. No recipe edits `usr/include/dispatch/` or
`usr/include/pthread/qos.h`: toolchains map those through overlays of their own.

`swift-foundation` is Foundation as swift-5.4's Foundation overlay needs it on 10.9. It covers 144 headers
in Foundation, CoreFoundation, `objc/NSObject.h` and `objc/runtime.h`:
- 10.9's getters redeclared as the properties the macOS 11.3 SDK declares, keeping 10.9's types and adding
  no nullability; a setter that 10.9 declares on a subclass (`NSMutableURLRequest`'s) becomes the readwrite
  property 11.3 redeclares there;
- `nonnull` where swift's overlay depends on it: `-[NSObject init]`, `description`, `debugDescription`,
  `-[NSError localizedDescription]` (without it the overlay's `Error.localizedDescription` calls itself),
  `-[NSScanner string]`, `+[NSString availableStringEncodings]` and
  `-[NSIndexSet indexesInRange:options:passingTest:]`;
- the typed string enums, such as `NSURLResourceKey` and `NSNotificationName`, with 10.9's constants and
  the methods the overlay calls retyped to them, `NSKeyValueChangeKey` as `NS_STRING_ENUM`, `CFLocaleKey` as
  `CF_STRING_ENUM`, and `NSErrorDomain` and `NSErrorUserInfoKey` as plain typedefs, as 11.3 has them;
- `NSPropertyListReadOptions` as 11.3's `NSPropertyListMutabilityOptions`;
- CF toll-free bridging annotations;
- generic result types where swift's overlay needs them;
- `NS_ENUM`/`NS_OPTIONS` shapes for `NSEnumerationOptions`, `NSURLRequestCachePolicy`,
  `NSURLRequestNetworkServiceType`, `NSRectEdge` and `objc_AssociationPolicy`.

Each of its recipes contains the earlier recipe on its header, so an Objective-C consumer can switch to it too,
together with the recipes its probe's `// needs:` line names: the generics recipes (`foundation-array-v3`,
`foundation-dictionary-v2`, `foundation-set-v2`, `foundation-orderedset-v2`, `foundation-enumerator-v2`,
`foundation-maptable-v2`, `foundation-filemanager-v3`), whose type parameters the generic results name, and
`corefoundation-base-v1`. A CoreFoundation recipe without `corefoundation-base-v1` still compiles, but its types
are not bridged.

These recipes are generated, not written by hand:
- `build/extract-swift-foundation-facts.py` reads clang's AST of the pinned 10.9 SDK and of the family's
  macOS 11.3 SDK (the `sdk113` product). Together with `sdk-metadata/swift-foundation-hand.json` (the string
  enums, members, anchors and enum shapes to take), it writes `sdk-metadata/swift-foundation-facts.json`.
  Each fact is a 10.9 declaration, its byte offset, and its later form.
- `build/gen-swift-foundation-recipes.py` turns the facts into one recipe per header, a probe for each, and
  the profile. Pass it the newest release tag's `recipes.json` as `--released`:
  - an unchanged recipe keeps its id;
  - a changed one that no release shipped is rewritten in place;
  - a changed released one becomes `-vN+1`.

  It records every id it has made in `sdk-metadata/swift-foundation-generated.json` (`--generated`), so a
  chained recipe is built on the hand-written recipe beneath its lineage, never on its own predecessor.

  A hand-written v-next on one of these headers is folded in only if it does not already contain the
  generated edits.

`tests/swift-foundation-facts.sh` and `tests/swift-foundation-recipes.sh` prove both scripts on fixtures and
check that the committed facts, recipes, probes and profile are current.

`swift-appkit` is AppKit as swift-5.4's AppKit overlay needs it on 10.9, and it contains all of `swift-foundation`,
so a Swift compile that uses AppKit selects this one profile. It covers the 33 AppKit headers of swift-gg's table
(`sdk-metadata/swift-appkit-rows.tsv`), in the same ways as above, plus:
- `NS_OPTIONS`/`NS_ENUM` types where 10.9 has a plain typedef or none: `NSWindowStyleMask`, `NSEventModifierFlags`,
  `NSAutoresizingMaskOptions`, `NSTrackingAreaOptions` (one type for 10.9's three anonymous enums),
  `NSFontDescriptorSymbolicTraits`, `NSTextAlignment`, `NSCompositingOperation`, `NSBackingStoreType`,
  `NSWindowOrderingMode` and `NSLineBreakMode`, with 10.9's values. The one later value,
  `NSWindowStyleMaskFullSizeContentView` (10.10), carries 10.10 availability;
- `NSImageName` and `NSNibName` as `NS_SWIFT_BRIDGED_TYPEDEF`, and `NSFontDescriptorAttributeName` and
  `NSUserInterfaceItemIdentifier` as extensible string enums;
- `NS_DESIGNATED_INITIALIZER` on `NSView`'s and `NSViewController`'s initializers, and `controlTextDidChange:` and
  its siblings as optional methods of `NSControlTextEditingDelegate`, with NSObject's informal category of them
  hidden from Swift 4.2 and later as 11.3 hides it;
- `-[NSTableView makeViewWithIdentifier:owner:]` taking `NSUserInterfaceItemIdentifier`;
- `+[NSApplication sharedApplication]` as a class property, so Swift writes `NSApplication.shared`
  (`appkit-application-v2`, which is `appkit-application-v1` plus it and `NSNotificationName`-typed notification names).
  Only that one of NSApplication's later properties: the others would retype getters an `NSApplication` subclass
  overrides;
- the class methods `librecaulk-objc.a`'s groups provide, with no availability: `NSColor`'s `labelColor` and
  `linkColor` (`appkit-color-v3`, beside `secondaryLabelColor` at 10.10 and `unemphasizedSelectedTextColor` and
  `separatorColor` at 10.14, which nothing provides), `+[NSGraphicsContext graphicsContextWithCGContext:flipped:]`
  (`appkit-graphicscontext-v2`) and, in swift-foundation too, `NSTimer`'s block timers (`foundation-timer-v2`).

A property whose name is a C++ keyword (`NSImage`'s `template`) is declared as the 11.3 SDK declares it: Objective-C
sees the property, Objective-C++ the accessor methods (`appkit-image-v2`), so a `.mm` that imports Cocoa compiles
through either profile's view.

No recipe carries `NS_SWIFT_NAME`: swift's own AppKit apinotes name things. Its recipes on headers that already had
recipes contain them, so an Objective-C consumer can switch to them. Two changes reach such a consumer: an override
of a getter whose type is now one of these types must use that type, as with the 10.12 and later SDKs
(`- (NSWindowStyleMask)styleMask`), and an `NSView` or `NSViewController` subclass's initializers are checked
against the designated ones.

The same two scripts make it: `extract-swift-foundation-facts.py --import AppKit/AppKit.h --files <those headers>
--hand sdk-metadata/swift-appkit-hand.json`, then `gen-swift-foundation-recipes.py --profile swift-appkit
--base-profile swift-foundation --generated sdk-metadata/swift-appkit-generated.json`, after swift-foundation's
run. The hand file's `base_edits` rewrite exact text of a header's existing recipe (a plain typedef into a tagged
type) before the facts are combined. `tests/swift-appkit-facts.sh` checks the facts are current and that every row
of the table has one; `tests/swift-appkit-recipes.sh` checks the recipes and both profiles are current;
`tests/swift-appkit-availability.sh` checks `NSWindowStyleMaskFullSizeContentView`'s availability.

### Materializing an SDK view

`bin/recaulk-materialize` applies a profile's recipes to your own copy of the 10.9 SDK. Apple's headers are never
shipped, so the edited copies are made on your machine, from your SDK, and the SDK itself is never written:

```sh
recaulk-materialize --sdk /usr/local/mavergreen/sdk109/SDKs/MacOSX10.9.sdk --out ~/Library/Caches/me/view \
  --profile swift-foundation
```

`--out` must not exist; its parent must. Into it go:

- `sdk/MacOSX10.9.sdk/`, links to each of the SDK's top-level entries plus an `SDKSettings.json` made from the
  SDK's own `SDKSettings.plist` (unless the SDK has one). Pass this as `-isysroot` or swift's `-sdk`: swiftc reads
  the SDK version only from `SDKSettings.json` on disk.
- `headers/`, each rewritten header, and `overlay.json`, a clang VFS overlay (`-ivfsoverlay`) mapping each header's
  paths under `sdk/MacOSX10.9.sdk`, under the SDK as you gave it, and under its real path, so it works whichever of
  the three your sysroot is. It is case-sensitive on every host.
- `stamp.json`: the profile, the recipe ids, a SHA-256 of the selected recipes, the SDK's real path, the output
  format and every file's SHA-256.

On Linux, unpack the release's `recaulk-<version>-linux-x86_64.tar.gz` (listed in its `SHA256SUMS`) and run
`opt/mavergreen/recaulk/bin/recaulk-materialize`, a static binary; the tarball also carries the `.pkg`'s `lib/`,
`include/` and `share/`, all but `librecaulk-cxxabi-exports.a`.

It runs on 10.9.5 without the Command Line Tools, on a modern Mac and on Linux, with nothing else installed, and
reads `recipes.json` and `profiles.json` from `../share/sdk-metadata/` beside itself (`--recipes`, `--profiles`
override them). `--recipe ID` (repeatable) selects recipes instead of a profile.

A second run on a complete `--out` with the same profile, recipes, SDK and format reads only `stamp.json` and exits
0; `--verify` also re-hashes every file. An `--out` made for anything else is refused, never replaced: remove it,
or keep one `--out` per cache key. `--print-stamp --profile NAME` prints that key's Recaulk half on one line, without
the SDK: format, profile, ids and recipes, but not Recaulk's release, so a release that leaves a profile alone keeps
every cache. The tree is built beside `--out` and renamed into place, so concurrent runs never see half of one.

It exits 0 when `--out` is complete, 1 with one line on stderr naming the header, recipe, path or stamp key at
fault, and 2 on a usage error. The output for the same inputs and `--out` is byte-identical; a change to any output
byte bumps the format (`tests/materialize-publish.sh` holds a golden tree).

## Tests

`sh build/build-lib.sh` builds Recaulk with clang22 (`components/clang22/version`, fetched by
`build/fetch-clang22.sh`) on Linux, a modern Mac or 10.9 alike, and `sh "$SHIPYARD_SCRIPTS/run-repo-tests.sh"`
runs its tests.
A test that runs an x86_64 program has two halves, and `RECAULK_TEST_PHASE` says which a run does:

- `build`: compile the programs into the build tree's `test-bin/` with clang22 and check them
  (`llvm-nm`, `llvm-otool`, and that each loads only what stock 10.9 has), then stop. Linux and a modern
  Mac do this, and never run an x86_64 program: Rosetta is not a test platform.
- `run`: on 10.9, with no compiler, shipyard or SDK, run the programs `build` made and judge them.
  `RECAULK_BUILD` names the build tree; `RECAULK_INSTALLED`, when set, names the installed Recaulk the
  tests use instead of the build tree's stage, whose libraries must be the same bytes. `tests/guest/run-runtime-tests.sh` runs every such test this
  way, each bounded at 300 s; a hang, a failure or a skip fails.
- `both`: both halves in one run, natively on a 10.9 machine with the Command Line Tools.

Unset, it is `both` on 10.9 and `build` elsewhere. CI builds on Linux, installs the pkg on a real 10.9.5
guest through [mavericks-vm](https://github.com/Mavergreen/mavericks-vm), and runs the `run` half there
against the installed Recaulk.

Launch Services launches apps only in a logged-in (Aqua) session, which `objc-workspace-backfill.sh` (the
Objective-C provider's real delivery) and `objc-workspace-context-test.sh` need. The guest job asks
mavericks-vm for one (`aqua-session: true`) and runs the tests through its `guest-macosx-aqua`, so they
run in that session. Run anywhere without one, those two skip (77), and the guest runner counts a skip
as a failure.
